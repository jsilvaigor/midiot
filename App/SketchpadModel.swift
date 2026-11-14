import Foundation
import MusicCore
import Notation
import Observation
import Practice
import ScoreImport
import Sketch
import Sound
import Synchronization

/// The Sketchpad: plays with their scenes and cues, the takes kept from what was played,
/// and what the app hears in the playing (requirements CO-1 to CO-7).
@MainActor
@Observable
final class SketchpadModel {
    private(set) var plays: [Play] = []
    private(set) var selectedPlayID: UUID?
    private(set) var selectedCueID: UUID?
    private(set) var selectedTakeID: UUID?
    /// Notes picked in the selected take, for trimming and deleting.
    var selectedNotes: Set<NoteRef> = []

    /// Tempo new takes are measured at, and the metronome's speed.
    var bpm = UserDefaults.standard.object(forKey: "sketchTempo") as? Double ?? 90 {
        didSet {
            UserDefaults.standard.set(bpm, forKey: "sketchTempo")
            refreshIdleClick()
        }
    }
    /// The sound the keyboard plays on the Sketchpad.
    var sound = SketchSound.sound(program: UserDefaults.standard.object(forKey: "sketchProgram") as? Int) {
        didSet {
            UserDefaults.standard.set(sound.program, forKey: "sketchProgram")
            if isActive { routeKeyboard() }
        }
    }
    /// Clicks at the tempo while idle, playing a take, and always while overdubbing. The click
    /// goes to the speakers only, so it is never heard as playing and never lands in a take.
    var metronomeIsOn = UserDefaults.standard.bool(forKey: "sketchMetronome") {
        didSet {
            UserDefaults.standard.set(metronomeIsOn, forKey: "sketchMetronome")
            player?.setMetronome(metronomeIsOn || isOverdubbing)
            refreshIdleClick()
        }
    }
    /// Step that Quantize snaps to, in beats: 0.5 is an eighth note.
    var quantizeGrid = 0.5

    /// The chord being held, or the last one heard (requirement CO-3).
    private(set) var chord: Chord?
    /// The last few different chords, oldest first, ending with `chord`.
    private(set) var chordHistory: [Chord] = []
    private(set) var key: SketchKey?
    /// A suggested chord whose keys are lit on the on-screen keyboard.
    var shownChord: Chord?

    private(set) var isPlaying = false
    private(set) var isOverdubbing = false
    /// Take being played or recorded over.
    private(set) var playingTakeID: UUID?
    /// Set when there is something to undo in the selected cue.
    private(set) var canUndo = false
    /// A short message for the capture bar, such as "nothing was played".
    private(set) var captureCameUpEmpty = false
    /// Why the last save or export failed; shown until dismissed.
    var error: String?

    /// Seconds taken off overdubbed notes: the player follows what they hear, which is late
    /// by the output delay.
    @ObservationIgnored var pressCompensation = 0.0

    @ObservationIgnored private var store: PlayStore
    @ObservationIgnored private let capture: CaptureBuffer
    @ObservationIgnored private let piano: SamplerInstrument
    @ObservationIgnored private let palette: PaletteSynth
    @ObservationIgnored private let clicks: any Instrument
    @ObservationIgnored private let keyboard: LiveSound
    @ObservationIgnored private var isActive = false
    @ObservationIgnored private var player: SongPlayer?
    /// Clicks while nothing plays, and the tempo it was started at.
    @ObservationIgnored private var idleClick: (player: SongPlayer, bpm: Double)?
    /// Host time of beat 0 of the take being recorded over.
    @ObservationIgnored private var overdubOrigin = 0.0
    @ObservationIgnored private var undoStack: [(cue: UUID, takes: [Take])] = []
    @ObservationIgnored private var auditionTask: Task<Void, Never>?

    /// Channels of the palette synth: the keyboard, chord and scale previews, then one per layer.
    private enum Channel {
        static let keyboard = 0
        static let preview = 15
        static let layers = Array(1...8)
    }

    init(
        store: PlayStore, capture: CaptureBuffer, piano: SamplerInstrument, palette: PaletteSynth,
        clicks: any Instrument, keyboard: LiveSound
    ) {
        self.store = store
        self.capture = capture
        self.piano = piano
        self.palette = palette
        self.clicks = clicks
        self.keyboard = keyboard
    }

    /// The folder of plays on this device, from before iCloud is found.
    var localStore: PlayStore { store }

    func load() {
        plays = store.plays()
        selectedPlayID = UserDefaults.standard.string(forKey: "sketchPlay").flatMap(UUID.init) ?? plays.last?.id
        if play == nil { selectedPlayID = plays.last?.id }
        selectCue(play?.scenes.first { !$0.cues.isEmpty }?.cues.first?.id)
    }

    // MARK: Plays arriving from another device

    /// Switches to another folder of plays: the iCloud one, once it is found.
    func use(_ store: PlayStore) {
        self.store = store
        reload()
    }

    /// Reads the plays again, after another device may have changed them. What is selected
    /// stays selected when it still exists.
    func reload() {
        // A take being recorded over must not change underneath the recording.
        guard !isOverdubbing else { return }
        let fresh = store.plays()
        guard !Self.same(fresh, plays) else { return }
        let cueBefore = cue
        plays = fresh
        if play == nil {
            selectPlay(plays.last?.id)
        } else if cue == nil {
            selectedCueID = nil
            selectCue(play?.scenes.first { !$0.cues.isEmpty }?.cues.first?.id)
        } else if !Self.same(cue, cueBefore) {
            // The cue open here was changed elsewhere: steps to undo no longer apply to it.
            stop()
            undoStack.removeAll()
            canUndo = false
            if take == nil { selectTake(cue?.bestTake?.id) }
            selectedNotes = []
        }
    }

    /// Compared as they would be saved: dates lose their fractions of a second on disk, so a
    /// play just read back is not `==` to the one in memory.
    private static func same<T: Encodable>(_ a: T, _ b: T) -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(a)) == (try? encoder.encode(b))
    }

    // MARK: Selection

    var play: Play? { plays.first { $0.id == selectedPlayID } }
    var cue: Cue? { selectedCueID.flatMap { play?.cue($0) } }
    var take: Take? { cue?.takes.first { $0.id == selectedTakeID } }

    func selectPlay(_ id: UUID?) {
        stop()
        selectedPlayID = id
        UserDefaults.standard.set(id?.uuidString, forKey: "sketchPlay")
        selectCue(play?.scenes.first { !$0.cues.isEmpty }?.cues.first?.id)
    }

    func selectCue(_ id: UUID?) {
        guard id != selectedCueID || id == nil else { return }
        stop()
        selectedCueID = id
        undoStack.removeAll()
        canUndo = false
        selectTake(cue?.bestTake?.id)
    }

    func selectTake(_ id: UUID?) {
        guard id != selectedTakeID else { return }
        stop()
        selectedTakeID = id
        selectedNotes = []
    }

    // MARK: Plays, scenes and cues (requirement CO-5)

    func newPlay(title: String, sceneTitle: String, cueName: String) {
        let cue = Cue(name: cueName)
        let play = Play(title: title, scenes: [PlayScene(title: sceneTitle, cues: [cue])])
        plays.append(play)
        save(play)
        selectPlay(play.id)
    }

    func updatePlay(_ change: (inout Play) -> Void) {
        guard let index = plays.firstIndex(where: { $0.id == selectedPlayID }) else { return }
        change(&plays[index])
        save(plays[index])
    }

    func deletePlay() {
        guard let play else { return }
        stop()
        do { try store.delete(play) } catch { self.error = error.localizedDescription }
        plays.removeAll { $0.id == play.id }
        selectPlay(plays.last?.id)
    }

    func addScene(title: String) {
        updatePlay { $0.scenes.append(PlayScene(title: title)) }
    }

    func renameScene(_ id: UUID, to title: String) {
        updatePlay { play in
            if let index = play.scenes.firstIndex(where: { $0.id == id }) { play.scenes[index].title = title }
        }
    }

    func deleteScene(_ id: UUID) {
        let hadSelection = play?.scenes.first { $0.id == id }?.cues.contains { $0.id == selectedCueID } ?? false
        if hadSelection { selectCue(nil) }
        updatePlay { $0.scenes.removeAll { $0.id == id } }
    }

    func addCue(to sceneID: UUID, name: String) {
        let cue = Cue(name: name)
        updatePlay { play in
            if let index = play.scenes.firstIndex(where: { $0.id == sceneID }) { play.scenes[index].cues.append(cue) }
        }
        selectCue(cue.id)
    }

    func deleteCue(_ id: UUID) {
        if id == selectedCueID { selectCue(nil) }
        updatePlay { play in
            for index in play.scenes.indices { play.scenes[index].cues.removeAll { $0.id == id } }
        }
    }

    /// Changes the selected cue's name, note, target, status or mood.
    func updateCue(_ change: (inout Cue) -> Void) {
        guard let id = selectedCueID else { return }
        updatePlay { $0.updateCue(id, change) }
    }

    private func save(_ play: Play) {
        do { try store.save(play) } catch { self.error = error.localizedDescription }
    }

    // MARK: Capture (requirement CO-1)

    /// How much was played in each slice of the last ten minutes, oldest first.
    func activity(buckets: Int) -> [Double] {
        capture.activity(buckets: buckets, window: capture.retention, now: SongPlayer.now)
    }

    /// Turns the last `seconds` of playing into a take in the selected cue.
    /// Returns false when nothing was played or no cue is selected.
    @discardableResult
    func keepLast(seconds: Double) -> Bool {
        let now = SongPlayer.now
        guard let cue, let take = Take(
            played: capture.notes(from: now - seconds, to: now),
            number: (cue.takes.map(\.number).max() ?? 0) + 1, bpm: bpm, program: sound.program
        ) else {
            captureCameUpEmpty = true
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                self?.captureCameUpEmpty = false
            }
            return false
        }
        captureCameUpEmpty = false
        updateCue { $0.takes.append(take) }
        selectTake(take.id)
        return true
    }

    // MARK: Takes (requirement CO-2)

    func toggleKeeper(_ id: UUID) {
        updateCue { cue in
            for index in cue.takes.indices { cue.takes[index].isKeeper = cue.takes[index].id == id && !cue.takes[index].isKeeper }
        }
    }

    func deleteTake(_ id: UUID) {
        if id == playingTakeID { stop() }
        rememberForUndo()
        updateCue { $0.takes.removeAll { $0.id == id } }
        if id == selectedTakeID { selectTake(cue?.bestTake?.id) }
    }

    // MARK: Layers

    /// Plays the layer with another instrument.
    func setProgram(_ program: Int?, ofLayer id: UUID) {
        edit(keepsSelection: true) { $0.updatingLayer(id) { $0.program = program } }
    }

    /// Silences a layer for listening, on the stage too, or brings it back. The notes stay.
    func toggleMute(layer id: UUID) {
        guard let take else { return }
        stop()
        replace(take.updatingLayer(id) { $0.isMuted.toggle() })
    }

    /// Removes a layer, which can be undone. The only layer of a take goes with the take.
    func deleteLayer(_ id: UUID) {
        guard let take else { return }
        guard let rest = take.deletingLayer(id) else { return deleteTake(take.id) }
        stop()
        rememberForUndo()
        replace(rest)
        selectedNotes = []
    }

    /// With notes selected, keeps only the stretch they span; otherwise removes the silence
    /// before the first note.
    func trim() {
        guard let take else { return }
        let picked = selectedNotes.compactMap { ref -> SketchNote? in
            guard take.layers.indices.contains(ref.layer), take.layers[ref.layer].notes.indices.contains(ref.index) else { return nil }
            return take.layers[ref.layer].notes[ref.index]
        }
        if let start = picked.map(\.start).min(), let end = picked.map(\.end).max() {
            edit { $0.trimmed(to: start...end) }
        } else {
            edit { $0.trimmed() }
        }
    }

    func quantize() {
        let grid = quantizeGrid
        edit(keepsSelection: true) { $0.quantized(grid: grid) }
    }

    func transpose(by semitones: Int) {
        edit(keepsSelection: true) { $0.transposed(by: semitones) }
    }

    func deleteSelectedNotes() {
        let refs = selectedNotes
        guard !refs.isEmpty else { return }
        edit { $0.deleting(refs) }
    }

    func undo() {
        guard let last = undoStack.popLast(), last.cue == selectedCueID else { return }
        stop()
        updateCue { $0.takes = last.takes }
        canUndo = !undoStack.isEmpty
        selectedNotes = []
        if take == nil { selectedTakeID = cue?.bestTake?.id }
    }

    private func edit(keepsSelection: Bool = false, _ change: (Take) -> Take) {
        guard let take else { return }
        stop()
        let edited = change(take)
        guard edited != take else { return }
        rememberForUndo()
        replace(edited)
        if !keepsSelection { selectedNotes = [] }
    }

    private func replace(_ take: Take) {
        updateCue { cue in
            if let index = cue.takes.firstIndex(where: { $0.id == take.id }) { cue.takes[index] = take }
        }
    }

    private func rememberForUndo() {
        guard let cue else { return }
        undoStack.append((cue.id, cue.takes))
        if undoStack.count > 30 { undoStack.removeFirst() }
        canUndo = true
    }

    // MARK: Playing takes

    /// Position in the take being played, in beats.
    var beat: Double { player?.beat ?? 0 }

    func togglePlay() {
        if isPlaying { stop() } else if let take { start(take, overdub: false) }
    }

    /// Plays the selected take from the start, after a bar of count-in, and records what is
    /// played over it as a new layer.
    func overdub() {
        guard let take else { return }
        start(take, overdub: true)
    }

    private func start(_ take: Take, overdub: Bool) {
        stopPlayback()
        idleClick = nil
        let (song, layerOfNote) = take.song(title: "")
        guard !song.notes.isEmpty else { return }

        let voices: [any Instrument] = take.layers.enumerated().map { index, layer in
            guard let program = layer.program else { return piano.voice(channel: 2) }
            let channel = Channel.layers[index % Channel.layers.count]
            palette.setProgram(program, channel: channel)
            return palette.voice(channel: channel)
        }
        let relay = Relay()
        let player = SongPlayer(song: song) { [clicks] event in
            switch event {
            case let .noteOn(note): voices[layerOfNote[note.id]].noteOn(note.pitch, velocity: note.velocity)
            case let .noteOff(note): voices[layerOfNote[note.id]].noteOff(note.pitch)
            case let .click(isDownbeat):
                clicks.noteOn(Pitch(midiNumber: isDownbeat ? 76 : 77), velocity: isDownbeat ? 110 : 80)
            case .allNotesOff:
                for voice in voices { voice.allNotesOff() }
            case .finished:
                for voice in voices { voice.allNotesOff() }
                Task { @MainActor in relay.model?.stop() }
            case .judged, .wrongKey, .waiting, .resumed, .judgementsCleared: break
            }
        }
        relay.model = self
        self.player = player
        isOverdubbing = overdub
        player.setMetronome(metronomeIsOn || overdub)
        player.play(countInBeats: overdub ? 4 : 0)
        // During the count-in the position is negative, which puts beat 0 in the future.
        overdubOrigin = SongPlayer.now - player.beat * 60 / max(take.bpm, 1)
        playingTakeID = take.id
        isPlaying = true
        refreshIdleClick()
    }

    /// Stops playback. An overdub in progress is kept as a new layer if anything was played.
    func stop() {
        stopPlayback()
        refreshIdleClick()
    }

    /// Runs the metronome on its own while nothing plays and the Sketchpad is shown, so the
    /// player can rehearse against it. Does nothing if it already runs at the right tempo.
    private func refreshIdleClick() {
        guard isActive, metronomeIsOn, player == nil else {
            idleClick = nil
            return
        }
        if let idleClick, idleClick.bpm == bpm { return }
        // Four-beat bars for as long as anyone will sit at it; the engine counts the clicks.
        let song = Song(
            title: "", notes: [], tempoMap: TempoMap(bpm: bpm),
            measures: Song.evenMeasures(beatsPerMeasure: 4, covering: 4 * 3600)
        )
        let click = SongPlayer(song: song) { [clicks] event in
            if case let .click(isDownbeat) = event {
                clicks.noteOn(Pitch(midiNumber: isDownbeat ? 76 : 77), velocity: isDownbeat ? 110 : 80)
            }
        }
        click.setMetronome(true)
        click.play()
        idleClick = (click, bpm)
    }

    private func stopPlayback() {
        guard let player else { return }
        player.pause()
        self.player = nil
        let wasOverdubbing = isOverdubbing
        isPlaying = false
        isOverdubbing = false
        defer { playingTakeID = nil }

        guard wasOverdubbing, let take = cue?.takes.first(where: { $0.id == playingTakeID }) else { return }
        let origin = overdubOrigin + pressCompensation
        let layer = Layer(
            played: capture.notes(from: origin - 0.0625, to: SongPlayer.now), origin: origin,
            bpm: take.bpm, program: sound.program
        )
        guard !layer.notes.isEmpty else { return }
        rememberForUndo()
        replace(take.adding(layer))
    }

    // MARK: Sound

    /// Call when the Sketchpad is shown or left: on it, the keyboard plays the chosen sound.
    func setActive(_ active: Bool) {
        isActive = active
        refreshIdleClick()
        if active {
            routeKeyboard()
        } else {
            stop()
            auditionTask?.cancel()
            palette.allNotesOff()
            keyboard.use(piano)
        }
    }

    private func routeKeyboard() {
        keyboard.use(instrument(for: sound, channel: Channel.keyboard))
    }

    private func instrument(for sound: SketchSound, channel: Int) -> any Instrument {
        guard let program = sound.program else { return piano }
        palette.setProgram(program, channel: channel)
        return palette.voice(channel: channel)
    }

    /// Plays a suggested chord as it is shown on the keyboard, so it can be heard before it is tried.
    func audition(_ chord: Chord, on range: KeyboardRange) {
        let placed = chord.voicing(in: range)
        preview(((placed.bass.map { [$0] } ?? []) + placed.tones).map { [$0] }, together: true)
    }

    /// Plays a scale up from the tonic of the key heard, or from C.
    func audition(_ scale: SketchScale) {
        let tonic = 60 + (key?.tonic ?? 0) - ((key?.tonic ?? 0) > 6 ? 12 : 0)
        preview((scale.intervals + [12]).map { [Pitch(midiNumber: tonic + $0)] }, together: false)
    }

    private func preview(_ steps: [[Pitch]], together: Bool) {
        auditionTask?.cancel()
        let voice = sound.program == nil ? piano.voice(channel: 3) : instrument(for: sound, channel: Channel.preview)
        voice.allNotesOff()
        auditionTask = Task {
            if together {
                for pitch in steps.flatMap({ $0 }) { voice.noteOn(pitch, velocity: 78) }
                try? await Task.sleep(for: .milliseconds(1400))
            } else {
                for step in steps {
                    for pitch in step { voice.noteOn(pitch, velocity: 84) }
                    try? await Task.sleep(for: .milliseconds(240))
                    for pitch in step { voice.noteOff(pitch) }
                    if Task.isCancelled { break }
                }
            }
            voice.allNotesOff()
        }
    }

    // MARK: Hearing (requirement CO-3)

    /// Call whenever the set of held keys changes.
    func heard(_ pressed: Set<Pitch>) {
        guard pressed.count >= 3, let detected = Chord.detect(pressed), detected != chord else { return }
        chord = detected
        // The suggestions change with the chord, so a pinned one no longer applies.
        shownChord = nil
        if chordHistory.last != detected { chordHistory.append(detected) }
        if chordHistory.count > 4 { chordHistory.removeFirst(chordHistory.count - 4) }
        // The key comes from the last minute and a half of playing.
        let now = SongPlayer.now
        key = SketchKey.detect(notes: capture.notes(from: now - 90, to: now).map { (pitch: $0.pitch, duration: $0.end - $0.start) })
    }

    var suggestions: [ChordSuggestion] {
        chord.map { ChordSuggestion.next(after: $0, in: key) } ?? []
    }

    // MARK: Export (requirements CO-6, CO-7)

    enum ExportFormat {
        case midi, musicXML, pdfGrandStaff, pdfLeadSheet

        var fileExtension: String {
            switch self {
            case .midi: "mid"
            case .musicXML: "musicxml"
            case .pdfGrandStaff, .pdfLeadSheet: "pdf"
            }
        }
    }

    /// The take to export from the selected cue: the keeper, else the selected one.
    var exportTake: Take? { cue?.takes.last(where: \.isKeeper) ?? take ?? cue?.bestTake }

    /// - Parameters:
    ///   - layerName: name of a layer's track in a MIDI file, given its number.
    ///   - subtitle: line under the title of a PDF.
    func export(_ format: ExportFormat, layerName: (Int) -> String, subtitle: String) -> Data? {
        guard let cue, let take = exportTake, take.noteCount > 0 else { return nil }
        let song = take.song(title: cue.name, includingMuted: true).song
        let fifths = SketchKey.detect(notes: take.layers.flatMap(\.notes).map { (pitch: $0.pitch, duration: $0.duration) })?.fifths ?? 0

        switch format {
        case .midi:
            return MIDIFileWriter.data(title: cue.name, bpm: take.bpm, tracks: take.layers.enumerated().map { index, layer in
                MIDIFileWriter.Track(name: layerName(index + 1), program: layer.program ?? 0, notes: layer.notes.map {
                    MIDIFileWriter.Note(pitch: $0.pitch, velocity: $0.velocity, start: $0.start, duration: $0.duration)
                })
            })
        case .musicXML:
            return Data(MusicXMLWriter.draft(from: song, fifths: fifths).utf8)
        case .pdfGrandStaff, .pdfLeadSheet:
            let xml = format == .pdfLeadSheet
                ? MusicXMLWriter.leadSheet(from: song, chords: Self.chords(in: song, fifths: fifths), fifths: fifths)
                : MusicXMLWriter.draft(from: song, fifths: fifths)
            guard let score = try? EngravedScore(musicXML: Data(xml.utf8), title: cue.name, pageWidth: 700) else { return nil }
            return ScorePDF.data(pages: score.pages, title: cue.name, subtitle: subtitle)
        }
    }

    /// The chord of each bar, by bar number; a bar that repeats the chord before it gets none.
    private static func chords(in song: Song, fifths: Int) -> [Int: MusicXMLWriter.ChordSymbol] {
        var result: [Int: MusicXMLWriter.ChordSymbol] = [:]
        var previous: Chord?
        for measure in song.measures {
            let sounding = song.notes.filter { $0.start < measure.end - 1e-6 && $0.end > measure.start + 1e-6 }
            guard let chord = Chord.detect(sounding.map(\.pitch)), chord.quality != .power else { continue }
            let plain = Chord(root: chord.root, quality: chord.quality)
            defer { previous = plain }
            guard plain != previous else { continue }
            result[measure.number] = MusicXMLWriter.ChordSymbol(
                root: Chord.name(ofPitchClass: plain.root, fifths: fifths),
                kind: plain.quality.musicXMLKind, suffix: plain.quality.suffix
            )
        }
        return result
    }
}

/// Lets a player's callback reach the model created before it.
@MainActor
private final class Relay: Sendable {
    weak var model: SketchpadModel?
}

/// The instrument the keyboard plays right now, readable from the MIDI thread.
final class LiveSound: Sendable {
    private let instrument: Mutex<any Instrument>

    init(_ instrument: any Instrument) {
        self.instrument = Mutex(instrument)
    }

    var current: any Instrument { instrument.withLock { $0 } }

    /// Switches instruments, silencing the old one so no key is left sounding on it.
    func use(_ new: any Instrument) {
        let old = instrument.withLock { current -> any Instrument in
            let old = current
            current = new
            return old
        }
        if old !== new { old.allNotesOff() }
    }
}
