import CryptoKit
import DesignSystem
import Foundation
import Library
import MidiIO
import MusicCore
import Observation
import Sketch
import Sound
import Practice
import SwiftUI
import Synchronization

/// App-wide state: connected keyboards, the piano sound, and which keys are down.
@MainActor
@Observable
final class AppModel {
    enum SoundStatus: Equatable {
        case loading
        case ready(SoundBank)
        case failed(String)
    }

    let devices = DeviceManager()
    var section = AppSection.today {
        didSet {
            if (oldValue == .sketchpad) != (section == .sketchpad) { sketchpad.setActive(section == .sketchpad) }
            if (oldValue == .stage) != (section == .stage) { stage.setActive(section == .stage) }
        }
    }
    /// Plays, cues and takes (milestone 3).
    @ObservationIgnored let sketchpad: SketchpadModel
    /// Live mode (milestone 4).
    @ObservationIgnored let stage: StageModel
    /// Which pad or knob does what (requirement HW-6).
    private(set) var controlMap = AppModel.savedControlMap() {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(controlMap), forKey: Self.controlMapKey) }
    }
    /// The action waiting for a pad or knob to be touched, while MIDI learn is on.
    var learning: ControlAction?
    /// Where the app also sends what it plays (requirement SN-3).
    private(set) var midiOut = MIDIOutChoice.off
    /// With MIDI out on: keep the app's own instruments quiet so only the other one is heard.
    var mutesOwnSound = UserDefaults.standard.bool(forKey: "midiOutMutes") {
        didSet {
            UserDefaults.standard.set(mutesOwnSound, forKey: "midiOutMutes")
            applyMIDIOut()
        }
    }
    /// Loudness of everything, 0 to 1; a knob can set it.
    private(set) var volume = 1.0
    /// Minutes practiced per day and what was played through (requirement CU-6).
    private(set) var log = PracticeLog()
    /// Best whole-run accuracy per path step id.
    private(set) var drillBest: [String: Double] = [:]
    /// Minutes to practice each day.
    var dailyGoal = UserDefaults.standard.object(forKey: "dailyGoalMinutes") as? Double ?? 25 {
        didSet { UserDefaults.standard.set(dailyGoal, forKey: "dailyGoalMinutes") }
    }
    /// Songs in the library, newest first.
    private(set) var songs: [SongEntry] = [] { didSet { refreshProgress() } }
    /// Best accuracy and last practice date per song, for the library table.
    private(set) var progress: [UUID: (best: Double?, last: Date)] = [:]
    /// The song open on the Practice screen.
    private(set) var session: PracticeSession?
    /// Why the last import or open failed; shown until dismissed.
    var libraryError: String?
    private(set) var soundStatus = SoundStatus.loading
    private(set) var latency: AudioEngine.Latency?
    /// Whether the sustain pedal is down (requirement HW-5).
    private(set) var pedalIsDown = false
    /// Keys currently held, on any keyboard or with the mouse.
    private(set) var pressed: Set<Pitch> = []
    /// Keys shown by the on-screen keyboard.
    private(set) var range = KeyboardRange.fortyNineKeys

    @ObservationIgnored private let audio = AudioEngine()
    @ObservationIgnored private let piano = SamplerInstrument()
    @ObservationIgnored private let clicks = SamplerInstrument()
    /// Strings, pads and the other sounds of the Sketchpad (requirement SN-2).
    @ObservationIgnored private let palette = PaletteSynth()
    /// Everything played, kept for ten minutes (requirement CO-1).
    @ObservationIgnored private let capture = CaptureBuffer()
    /// What the keyboard plays: the piano, or the Sketchpad's chosen sound.
    @ObservationIgnored private let keyboard: LiveSound
    @ObservationIgnored private let store: SongStore
    /// The open song's player, reachable from the MIDI thread so key presses are judged
    /// with their exact time.
    @ObservationIgnored private let activePlayer = PlayerBox()

    @ObservationIgnored private var auditionTask: Task<Void, Never>?
    @ObservationIgnored private let seedsStarterSongs: Bool
    /// Drills keep their run history beside the songs, in their own folder.
    @ObservationIgnored private var drillStore: SongStore { SongStore(root: store.root.deletingLastPathComponent().appendingPathComponent("Drills")) }
    @ObservationIgnored private var logURL: URL { store.root.deletingLastPathComponent().appendingPathComponent("practice-log.json") }
    /// Where Back and Done lead from the Practice screen.
    @ObservationIgnored private var returnSection = AppSection.library

    /// Milliseconds subtracted from every key press before it is judged, on top of the
    /// automatic allowance for audio output delay. Raise it if on-time notes are marked late.
    var timingAdjustment = UserDefaults.standard.double(forKey: "timingAdjustmentMs") {
        didSet {
            UserDefaults.standard.set(timingAdjustment, forKey: "timingAdjustmentMs")
            updatePressCompensation()
        }
    }

    /// - Parameter seedsStarterSongs: copy the bundled starter pieces into an empty library, once.
    init(store: SongStore = .standard, seedsStarterSongs: Bool = true) {
        self.store = store
        self.seedsStarterSongs = seedsStarterSongs
        keyboard = LiveSound(piano)
        sketchpad = SketchpadModel(
            store: PlayStore(root: store.root.deletingLastPathComponent().appendingPathComponent("Plays", isDirectory: true)),
            capture: capture, piano: piano, palette: palette, clicks: clicks, keyboard: keyboard
        )
        stage = StageModel(sketchpad: sketchpad, piano: piano, palette: palette, keyboard: keyboard, devices: devices)
    }
    @ObservationIgnored private var isStarted = false

    func start() {
        guard !isStarted else { return }
        isStarted = true

        songs = store.entries()
        if let data = try? Data(contentsOf: logURL), let saved = try? JSONDecoder().decode(PracticeLog.self, from: data) { log = saved }
        refreshDrillBest()
        trackPracticeTime()
        seedStarterSongsIfNeeded()
        sketchpad.load()
        audio.attach(piano)
        audio.attach(clicks)
        audio.attach(palette)
        do {
            try audio.start()
            latency = audio.latency
            updatePressCompensation()
        } catch {
            soundStatus = .failed(error.localizedDescription)
            return
        }

        // Large SoundFonts take seconds to load; keep the window responsive meanwhile.
        let bank = SoundBank.piano()
        let paletteBank = SoundBank.palette()
        Task.detached(priority: .userInitiated) { [piano, clicks, palette] in
            let status: SoundStatus
            // The metronome uses the drum kit built into macOS; without it the app still works.
            try? clicks.load(.system, percussion: true)
            try? palette.load(paletteBank)
            do {
                try piano.load(bank)
                status = .ready(bank)
            } catch {
                status = .failed(error.localizedDescription)
            }
            await MainActor.run { self.soundStatus = status }
        }

        devices.start { [keyboard, capture, activePlayer, weak self] event in
            // On the MIDI thread: make sound first, then remember it, then tell the interface.
            let instrument = keyboard.current
            let time = event.seconds ?? SongPlayer.now
            switch event.kind {
            case let .noteOn(pitch, velocity):
                instrument.noteOn(pitch, velocity: velocity)
                activePlayer.pressed(pitch, at: event.seconds)
                capture.record(.noteOn(pitch: pitch.midiNumber, velocity: velocity), at: time)
            case let .noteOff(pitch):
                instrument.noteOff(pitch)
                capture.record(.noteOff(pitch: pitch.midiNumber), at: time)
            case let .sustain(isDown):
                instrument.setSustain(isDown)
                capture.record(.sustain(isDown: isDown), at: time)
            }
            Task { @MainActor in self?.show(event) }
        } onControl: { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        followPadLights()
        // Rendering screenshots must not send notes to whatever is listening.
        if !ProcessInfo.processInfo.arguments.contains("-snapshot"),
           let saved = UserDefaults.standard.data(forKey: "midiOut").flatMap({ try? JSONDecoder().decode(MIDIOutChoice.self, from: $0) }) {
            setMIDIOut(saved)
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [devices] _ in
            MainActor.assumeIsolated {
                devices.releasePadLights()
                devices.out.silence()
            }
        }
    }

    // MARK: MIDI out (requirement SN-3)

    /// Sends everything the app plays somewhere else as well: the piano on channel 1, the
    /// other sounds on the channels they use here. The metronome stays in the app.
    func setMIDIOut(_ choice: MIDIOutChoice) {
        midiOut = choice
        UserDefaults.standard.set(try? JSONEncoder().encode(choice), forKey: "midiOut")
        devices.setOutput(choice)
        applyMIDIOut()
        stage.outputChanged()
        // A port that was only just opened can miss the sounds chosen so far; say them again.
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard let self, self.midiOut == choice else { return }
            self.applyMIDIOut()
            self.stage.outputChanged()
        }
    }

    private func applyMIDIOut() {
        let isOn = midiOut != .off
        piano.isMuted = isOn && mutesOwnSound
        palette.isMuted = isOn && mutesOwnSound
        guard isOn else {
            piano.mirror(to: nil)
            palette.mirror(to: nil)
            return
        }
        let out = devices.out
        // The piano and the Sketchpad's sound share channel 1. The other end is told which of
        // the two is about to play whenever it changes: `wanted` is the Sketchpad's sound,
        // `sent` the one the other end has now.
        let channelOne = Mutex<(wanted: Int?, sent: Int?)>((nil, nil))
        @Sendable func choose(_ program: Int) {
            let isNew = channelOne.withLock { state -> Bool in
                defer { state.sent = program }
                return state.sent != program
            }
            if isNew { out.program(program, channel: 0) }
        }
        @Sendable func send(_ message: ChannelMessage, isPiano: Bool) {
            switch message {
            case let .noteOn(note, velocity, channel):
                if channel == 0 {
                    if isPiano { choose(0) } else if let wanted = channelOne.withLock({ $0.wanted }) { choose(wanted) }
                }
                out.noteOn(note, velocity: velocity, channel: channel)
            case let .noteOff(note, channel): out.noteOff(note, channel: channel)
            case let .controller(number, value, channel): out.controller(number, value: value, channel: channel)
            case let .program(program, channel):
                guard channel == 0 else { return out.program(program, channel: channel) }
                channelOne.withLock { $0.wanted = program }
                choose(program)
            }
        }
        piano.mirror(to: { send($0, isPiano: true) }, channel: 0)
        palette.mirror(to: { send($0, isPiano: false) })
    }

    /// Call when the set of connected keyboards changes.
    func devicesChanged() {
        // A key held on a keyboard that was just unplugged would otherwise sound forever.
        keyboard.current.allNotesOff()
        // Close any note the capture still thinks is held.
        for pitch in pressed { capture.record(.noteOff(pitch: pitch.midiNumber), at: SongPlayer.now) }
        capture.record(.sustain(isDown: false), at: SongPlayer.now)
        pressed.removeAll()
        pedalIsDown = false
        range = devices.devices.mainInstrument?.profile.range ?? .fortyNineKeys
        latency = audio.latency
        updatePressCompensation()
    }

    /// The player hears the app's notes late by the output delay and plays along with what
    /// they hear, so that delay is taken off their press times before judging (requirement SN-4).
    private func updatePressCompensation() {
        activePlayer.pressCompensation = (latency?.total ?? 0) + timingAdjustment / 1000
        sketchpad.pressCompensation = activePlayer.pressCompensation
    }

    private func seedStarterSongsIfNeeded() {
        let key = "didSeedStarterSongs"
        guard seedsStarterSongs, songs.isEmpty, !UserDefaults.standard.bool(forKey: key),
              let urls = Bundle.main.urls(forResourcesWithExtension: "musicxml", subdirectory: "Songs"), !urls.isEmpty
        else { return }
        UserDefaults.standard.set(true, forKey: key)
        importSongs(from: urls.sorted { $0.lastPathComponent > $1.lastPathComponent })
    }

    // MARK: Library

    /// Copies files into the library. Failures are collected into `libraryError`.
    func importSongs(from urls: [URL]) {
        let store = store
        Task {
            let failures = await Task.detached(priority: .userInitiated) {
                urls.compactMap { url -> String? in
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    do {
                        try store.importFile(at: url)
                        return nil
                    } catch let SongStore.StoreError.unreadable(reason) {
                        return "\(url.lastPathComponent): \(reason)"
                    } catch SongStore.StoreError.unsupportedFile {
                        return "\(url.lastPathComponent): only MIDI and MusicXML files can be imported."
                    } catch {
                        return "\(url.lastPathComponent): \(error.localizedDescription)"
                    }
                }
            }.value
            songs = store.entries()
            libraryError = failures.isEmpty ? nil : failures.joined(separator: "\n")
        }
    }

    /// Sets where a MIDI song's notes divide between the hands; nil is automatic.
    func setSplitPitch(_ pitch: Int?, for entry: SongEntry) {
        if session?.loaded.entry.id == entry.id { closeSong() }
        _ = try? store.setSplitPitch(pitch, for: entry)
        songs = store.entries()
    }

    func delete(_ entry: SongEntry) {
        if session?.loaded.entry.id == entry.id { closeSong() }
        try? store.delete(entry)
        songs = store.entries()
    }

    /// Opens a song on the Practice screen.
    func open(_ entry: SongEntry) {
        let store = store
        Task {
            do {
                var loaded = try await Task.detached(priority: .userInitiated) { try store.load(entry) }.value
                // On a keyboard too small for the piece, rearrange it to fit (requirement HW-3).
                var foldedRange: KeyboardRange?
                if let keyboard = devices.devices.mainInstrument?.profile.range, !keyboard.canPlay(loaded.song) {
                    let target = keyboard.bestPosition(for: loaded.song)
                    loaded = LoadedSong(entry: loaded.entry, song: loaded.song.folded(into: target), pages: loaded.pages)
                    foldedRange = target
                }
                session?.stop()
                let new = PracticeSession(
                    loaded: loaded, piano: piano.voice(channel: 1), clicks: clicks,
                    history: { store.runs(for: entry) },
                    onRunEnded: { [weak self] run in
                        try? store.appendRun(run, for: entry)
                        self?.refreshProgress()
                        if run.completed { self?.markCompleted(entry.id.uuidString) }
                    }
                )
                // With a keyboard connected, start in the mode a learner wants: play it yourself, unhurried.
                if !devices.devices.isEmpty {
                    new.handMode = .both
                    new.waitsForPlayer = true
                }
                new.foldedRange = foldedRange
                returnSection = section == .practice ? returnSection : section
                session = new
                activePlayer.player = new.player
                section = .practice
            } catch {
                libraryError = "\(entry.title): \(error.localizedDescription)"
            }
        }
    }

    // MARK: Drills and daily practice

    /// Opens a step of the path on the Practice screen: a drill for one hand or both.
    func open(_ step: Curriculum.Step, title: String) {
        let store = drillStore
        let drill = step.drill
        let key = drill.key
        // Reading and rhythm drills change daily; everything else is fixed.
        let day = UInt64(max(Date().timeIntervalSince1970 / 86_400, 0))
        let id = Self.uuid(for: step.id)
        Task {
            let loaded = await Task.detached(priority: .userInitiated) {
                LoadedSong(
                    generated: step.song(title: title, seed: day), id: id,
                    fifths: key.fifths, sharpened: key.isMinor ? (key.tonic + 11) % 12 : nil
                )
            }.value
            session?.stop()
            let new = PracticeSession(
                loaded: loaded, piano: piano.voice(channel: 1), clicks: clicks,
                history: { store.runs(for: loaded.entry) },
                onRunEnded: { [weak self] run in
                    try? store.appendRun(run, for: loaded.entry)
                    self?.refreshDrillBest()
                    if run.completed { self?.markCompleted(step.id) }
                }
            )
            if !devices.devices.isEmpty {
                switch step.hands {
                case .right: new.handMode = .right
                case .left: new.handMode = .left
                case .together: new.handMode = .both
                }
                // Reading is about finding the note, not keeping time.
                if case .bassReading = drill { new.waitsForPlayer = true }
            }
            returnSection = section == .practice ? returnSection : section
            session = new
            activePlayer.player = new.player
            section = .practice
        }
    }

    /// A stable identifier for a drill, so its history folder is found again.
    private static func uuid(for drillID: String) -> UUID {
        let digest = Array(SHA256.hash(data: Data(drillID.utf8)))
        return UUID(uuid: (digest[0], digest[1], digest[2], digest[3], digest[4], digest[5], digest[6], digest[7],
                           digest[8], digest[9], digest[10], digest[11], digest[12], digest[13], digest[14], digest[15]))
    }

    private func refreshDrillBest() {
        let store = drillStore
        var best: [String: Double] = [:]
        for step in Curriculum.allSteps {
            let entry = LoadedSongEntry.placeholder(id: Self.uuid(for: step.id))
            // A run counts only when the step's hands were the ones playing.
            let runs = store.runs(for: entry).filter { $0.completed && step.accepts(runHands: $0.hands) }
            if let value = runs.compactMap(\.accuracy).max() { best[step.id] = value }
        }
        drillBest = best
    }

    private func markCompleted(_ id: String) {
        log.markCompleted(id, on: Date())
        saveLog()
    }

    private func saveLog() {
        try? JSONEncoder().encode(log).write(to: logURL)
    }

    /// Counts time toward the daily goal while music is actually playing.
    private func trackPracticeTime() {
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self else { return }
                if self.session?.isPlaying == true {
                    self.log.add(seconds: 5, on: Date())
                    self.saveLog()
                }
            }
        }
    }

    private func refreshProgress() {
        var progress: [UUID: (best: Double?, last: Date)] = [:]
        for entry in songs {
            let runs = store.runs(for: entry)
            guard let last = runs.last else { continue }
            // Best counts whole-piece runs only; a perfect two-bar loop is not a best run.
            progress[entry.id] = (runs.filter(\.completed).compactMap(\.accuracy).max(), last.date)
        }
        self.progress = progress
    }

    func closeSong() {
        session?.stop()
        session = nil
        activePlayer.player = nil
        section = returnSection
    }

    // MARK: Playing

    /// Sounds a chord on the piano for a moment, for the chord cheat sheet.
    func audition(_ pitches: [Pitch]) {
        auditionTask?.cancel()
        let voice = piano.voice(channel: 3)
        voice.allNotesOff()
        auditionTask = Task {
            for pitch in pitches { voice.noteOn(pitch, velocity: 76) }
            try? await Task.sleep(for: .milliseconds(1500))
            if !Task.isCancelled { voice.allNotesOff() }
        }
    }

    func mouseDown(on pitch: Pitch) {
        keyboard.current.noteOn(pitch, velocity: 90)
        capture.record(.noteOn(pitch: pitch.midiNumber, velocity: 90), at: SongPlayer.now)
        pressed.insert(pitch)
        activePlayer.pressed(pitch, at: nil)
        sketchpad.heard(pressed)
    }

    func mouseUp(on pitch: Pitch) {
        keyboard.current.noteOff(pitch)
        capture.record(.noteOff(pitch: pitch.midiNumber), at: SongPlayer.now)
        pressed.remove(pitch)
        session?.released(pitch)
    }

    // MARK: Pads and knobs (requirements HW-2, HW-6, LV-5)

    private static let controlMapKey = "controlMap"

    private static func savedControlMap() -> ControlMap {
        UserDefaults.standard.data(forKey: controlMapKey).flatMap { try? JSONDecoder().decode(ControlMap.self, from: $0) }
            ?? .launchkeyDefaults
    }

    func resetControlMap() {
        learning = nil
        controlMap = .launchkeyDefaults
    }

    func clearControl(_ action: ControlAction) {
        controlMap.clear(action)
    }

    /// Where pads and knobs act right now.
    private var controlContext: ControlAction.Context {
        if section == .stage { return .stage }
        if section == .practice, session != nil { return .practice }
        return .everywhere
    }

    /// How the pad of `action` should be lit right now: bright when it can be used, dim when
    /// it cannot, pulsing while what it started is under way. The screen and the Launchkey
    /// both follow this (requirement HW-2).
    func padLightStyle(_ action: ControlAction) -> PadLight.Style {
        switch action {
        case .cueBack: stage.isChoosing || stage.index == 0 ? .dim : .bright
        case .cueGo: stage.isChoosing || stage.next == nil ? .dim : .bright
        case .playLayer: stage.isPlaying ? .pulsing : stage.layerTake != nil && !stage.isChoosing ? .bright : .dim
        case .fadeIn: stage.fadeDirection > 0 ? .pulsing : stage.layerTake != nil && !stage.isChoosing ? .bright : .dim
        case .fadeOut: stage.fadeDirection < 0 ? .pulsing : stage.playingCueID != nil ? .bright : .dim
        case .stopLayer: stage.playingCueID != nil ? .bright : .dim
        case .playPause: session?.isPlaying == true ? .pulsing : .bright
        case .toggleWait: session?.waitsForPlayer == true ? .bright : .dim
        case .toggleMetronome: session?.metronomeIsOn == true ? .bright : .dim
        case .toggleCountIn: session?.countInIsOn == true ? .bright : .dim
        case .handLeft: session?.handMode == .left ? .bright : .dim
        case .handBoth: session?.handMode == .both ? .bright : .dim
        case .handRight: session?.handMode == .right ? .bright : .dim
        case .restart, .tempoDown, .tempoUp, .panic, .tempo, .volume: .bright
        }
    }

    /// Keeps the Launchkey's pads lit to match what they do, for as long as the app runs.
    private func followPadLights() {
        withObservationTracking {
            devices.setPadLights(controlMap.padLights(in: controlContext) { padLightStyle($0) })
        } onChange: { [weak self] in
            Task { @MainActor in self?.followPadLights() }
        }
    }

    /// Last position seen of each controller, to tell a button press from a held or falling value.
    @ObservationIgnored private var controllerValues: [Int: Int] = [:]

    /// A pad was hit or a knob moved.
    func handle(_ event: ControlEvent) {
        // A press is a pad struck, or a controller crossing its midpoint on the way up.
        let isPress: Bool
        switch event.source {
        case .pad:
            isPress = event.value > 0
        case let .controller(number):
            isPress = event.value >= 64 && (controllerValues[number] ?? 0) < 64
            controllerValues[number] = event.value
        }

        if let action = learning {
            // Knob actions take the first controller that moves; button actions wait for a press.
            guard action.isContinuous || isPress else { return }
            if controlMap.assign(event.source, to: action) { learning = nil }
            return
        }
        guard let action = controlMap.action(for: event.source, in: controlContext) else { return }
        if action.isContinuous {
            set(action, to: Double(event.value) / 127)
        } else if isPress {
            perform(action)
        }
    }

    private func perform(_ action: ControlAction) {
        switch action {
        case .playPause: session?.togglePlay()
        case .restart: session?.restart()
        case .toggleWait: session?.waitsForPlayer.toggle()
        case .toggleMetronome: session?.metronomeIsOn.toggle()
        case .toggleCountIn: session?.countInIsOn.toggle()
        case .handLeft: session?.handMode = .left
        case .handBoth: session?.handMode = .both
        case .handRight: session?.handMode = .right
        case .tempoDown: nudgeRate(by: -0.05)
        case .tempoUp: nudgeRate(by: 0.05)
        case .cueBack: stage.back()
        case .cueGo: stage.go()
        case .playLayer: stage.playLayer()
        case .fadeIn: stage.fadeIn()
        case .fadeOut: stage.fadeOut()
        case .stopLayer: stage.stopLayer()
        case .panic: panic()
        case .tempo, .volume: break
        }
    }

    private func set(_ action: ControlAction, to fraction: Double) {
        switch action {
        case .tempo:
            // A quarter speed to one and a half, in steps of 5%.
            session?.rate = ((0.25 + fraction * 1.25) * 20).rounded() / 20
        case .volume:
            volume = fraction
            audio.volume = fraction
        default: break
        }
    }

    private func nudgeRate(by step: Double) {
        guard let session else { return }
        session.rate = min(max(((session.rate + step) * 20).rounded() / 20, 0.25), 1.5)
    }

    /// Silences everything at once: the keyboard, anything the app is playing, and held
    /// notes (requirement LV-6).
    func panic() {
        session?.pause()
        sketchpad.stop()
        stage.panic()
        auditionTask?.cancel()
        keyboard.current.allNotesOff()
        piano.allNotesOff()
        for channel in 1...3 { piano.voice(channel: channel).allNotesOff() }
        palette.allNotesOff()
        clicks.allNotesOff()
        pedalIsDown = false
    }

    private func show(_ event: PerformanceEvent) {
        switch event.kind {
        case let .noteOn(pitch, _):
            pressed.insert(pitch)
            sketchpad.heard(pressed)
            // Follow the keyboard's octave buttons.
            range = range.shifted(toContain: pitch)
        case let .noteOff(pitch):
            pressed.remove(pitch)
            session?.released(pitch)
        case let .sustain(isDown):
            pedalIsDown = isDown
        }
    }
}

/// Holds the current song player where the MIDI thread can read it.
private final class PlayerBox: Sendable {
    private let storage = Mutex<SongPlayer?>(nil)

    private let compensation = Mutex<Double>(0)

    var player: SongPlayer? {
        get { storage.withLock { $0 } }
        set { storage.withLock { $0 = newValue } }
    }

    /// Seconds taken off each press time before judging.
    var pressCompensation: Double {
        get { compensation.withLock { $0 } }
        set { compensation.withLock { $0 = newValue } }
    }

    /// Reports a key press to the open song, if any. `time` nil means now.
    func pressed(_ pitch: Pitch, at time: Double?) {
        player?.playerPressed(pitch, at: (time ?? SongPlayer.now) - pressCompensation)
    }
}

/// Builds the minimal library entry needed to look up a generated song's run history.
private enum LoadedSongEntry {
    static func placeholder(id: UUID) -> SongEntry {
        SongEntry(
            id: id, title: "", addedAt: Date(timeIntervalSince1970: 0), format: .drill, fileName: "",
            noteCount: 0, lowestPitch: 60, highestPitch: 60, durationSeconds: 0
        )
    }
}
