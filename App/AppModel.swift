import DesignSystem
import Foundation
import Library
import MidiIO
import MusicCore
import Observation
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
    var section = AppSection.library
    /// Songs in the library, newest first.
    private(set) var songs: [SongEntry] = []
    /// The song open on the Practice screen.
    private(set) var session: PracticeSession?
    /// Why the last import or open failed; shown until dismissed.
    var libraryError: String?
    private(set) var soundStatus = SoundStatus.loading
    private(set) var latency: AudioEngine.Latency?
    /// Keys currently held, on any keyboard or with the mouse.
    private(set) var pressed: Set<Pitch> = []
    /// Keys shown by the on-screen keyboard.
    private(set) var range = KeyboardRange.fortyNineKeys

    @ObservationIgnored private let audio = AudioEngine()
    @ObservationIgnored private let piano = SamplerInstrument()
    @ObservationIgnored private let clicks = SamplerInstrument()
    @ObservationIgnored private let store: SongStore
    /// The open song's player, reachable from the MIDI thread so key presses are judged
    /// with their exact time.
    @ObservationIgnored private let activePlayer = PlayerBox()

    @ObservationIgnored private let seedsStarterSongs: Bool

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
    }
    @ObservationIgnored private var isStarted = false

    func start() {
        guard !isStarted else { return }
        isStarted = true

        songs = store.entries()
        seedStarterSongsIfNeeded()
        audio.attach(piano)
        audio.attach(clicks)
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
        Task.detached(priority: .userInitiated) { [piano, clicks] in
            let status: SoundStatus
            // The metronome uses the drum kit built into macOS; without it the app still works.
            try? clicks.load(.system, percussion: true)
            do {
                try piano.load(bank)
                status = .ready(bank)
            } catch {
                status = .failed(error.localizedDescription)
            }
            await MainActor.run { self.soundStatus = status }
        }

        devices.start { [piano, activePlayer, weak self] event in
            // On the MIDI thread: make sound first, then tell the interface.
            switch event.kind {
            case let .noteOn(pitch, velocity):
                piano.noteOn(pitch, velocity: velocity)
                activePlayer.pressed(pitch, at: event.seconds)
            case let .noteOff(pitch): piano.noteOff(pitch)
            case let .sustain(isDown): piano.setSustain(isDown)
            }
            Task { @MainActor in self?.show(event) }
        }
    }

    /// Call when the set of connected keyboards changes.
    func devicesChanged() {
        // A key held on a keyboard that was just unplugged would otherwise sound forever.
        piano.allNotesOff()
        pressed.removeAll()
        range = devices.devices.mainInstrument?.profile.range ?? .fortyNineKeys
        latency = audio.latency
        updatePressCompensation()
    }

    /// The player hears the app's notes late by the output delay and plays along with what
    /// they hear, so that delay is taken off their press times before judging (requirement SN-4).
    private func updatePressCompensation() {
        activePlayer.pressCompensation = (latency?.total ?? 0) + timingAdjustment / 1000
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
                let new = PracticeSession(loaded: loaded, piano: piano.voice(channel: 1), clicks: clicks) { run in
                    try? store.appendRun(run, for: entry)
                }
                // With a keyboard connected, start in the mode a learner wants: play it yourself, unhurried.
                if !devices.devices.isEmpty {
                    new.handMode = .both
                    new.waitsForPlayer = true
                }
                new.foldedRange = foldedRange
                session = new
                activePlayer.player = new.player
                section = .practice
            } catch {
                libraryError = "\(entry.title): \(error.localizedDescription)"
            }
        }
    }

    func closeSong() {
        session?.stop()
        session = nil
        activePlayer.player = nil
        section = .library
    }

    // MARK: Playing

    func mouseDown(on pitch: Pitch) {
        piano.noteOn(pitch, velocity: 90)
        pressed.insert(pitch)
        activePlayer.pressed(pitch, at: nil)
    }

    func mouseUp(on pitch: Pitch) {
        piano.noteOff(pitch)
        pressed.remove(pitch)
        session?.released(pitch)
    }

    private func show(_ event: PerformanceEvent) {
        switch event.kind {
        case let .noteOn(pitch, _):
            pressed.insert(pitch)
            // Follow the keyboard's octave buttons.
            range = range.shifted(toContain: pitch)
        case let .noteOff(pitch):
            pressed.remove(pitch)
            session?.released(pitch)
        case .sustain:
            break
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
