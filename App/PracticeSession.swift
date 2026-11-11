import DesignSystem
import Library
import MusicCore
import Notation
import Observation
import Practice
import Sound
import SwiftUI

/// One song open for practice: its player, the settings chosen for it, and how the run is going.
@MainActor
@Observable
final class PracticeSession {
    /// Who plays what (requirement SP-3).
    enum HandMode: String, CaseIterable {
        /// The app plays everything.
        case listen
        case both, right, left

        var playerHands: Set<Hand> {
            switch self {
            case .listen: []
            case .both: [.left, .right]
            case .right: [.right]
            case .left: [.left]
            }
        }
    }

    let loaded: LoadedSong
    var song: Song { loaded.song }
    /// Where each beat and bar falls on the engraved pages.
    let layout: ScoreLayout
    var hasSheet: Bool { !loaded.pages.isEmpty && !layout.isEmpty }
    /// Set when the song was rearranged to fit a small keyboard: the range it was folded into.
    var foldedRange: KeyboardRange?
    /// The real-time player. Safe to use from any thread, including the MIDI thread.
    nonisolated let player: SongPlayer

    private(set) var isPlaying = false
    /// Playback speed as a fraction of the song's tempo: 0.25...1.5 (requirement SP-5).
    var rate = 1.0 { didSet { player.setRate(rate) } }
    var metronomeIsOn = false { didSet { player.setMetronome(metronomeIsOn) } }
    var countInIsOn = true
    var handMode = HandMode.listen { didSet { player.setPlayerHands(handMode.playerHands) } }
    /// Wait mode (requirement SP-2).
    var waitsForPlayer = false { didSet { player.setWaitsForPlayer(waitsForPlayer) } }
    /// Bars to repeat, by bar number (requirement SP-4).
    var loopBars: ClosedRange<Int>? { didSet { applyLoop() } }

    /// Keys the app is sounding right now, with the hand they belong to.
    private(set) var sounding: [Pitch: Hand] = [:]
    /// What the player did on each note so far, by note id (requirement FB-1).
    private(set) var attempts: [Int: Attempt] = [:]
    var results: [Int: PlaybackEngine.Judgement] { attempts.mapValues(\.judgement) }
    /// Set when a run reaches the end of the song: what to show on the review screen.
    private(set) var review: Review?
    /// Adaptive practice (requirement FB-3): while looping, raise the tempo after clean
    /// passes and lower it after poor ones.
    var adaptsTempo = false
    /// Clean loop passes in a row so far, toward the three that raise the tempo.
    var cleanPasses: Int { adaptive.cleanPasses }
    private var adaptive = AdaptiveTempo()

    /// A finished run with the history it is compared against.
    struct Review {
        let analysis: RunReview
        /// Accuracy of this song's runs, oldest first, ending with this one.
        let history: [Double]
        let handMode: HandMode
        let rate: Double
        let usedWaitMode: Bool
    }
    /// Wrong keys currently held down.
    private(set) var wrongKeys: Set<Pitch> = []
    /// Notes wait mode is holding for.
    private(set) var awaited: [Note] = []

    @ObservationIgnored private var wrongKeyBeats: [Double] = []
    @ObservationIgnored private let onRunEnded: (RunResult) -> Void
    @ObservationIgnored private let history: () -> [RunResult]

    /// - Parameters:
    ///   - piano: plays the song's notes.
    ///   - clicks: a percussion instrument for the metronome.
    ///   - history: the song's earlier runs, oldest first.
    ///   - onRunEnded: receives the result of each run in which the player played.
    init(
        loaded: LoadedSong, piano: any Instrument, clicks: any Instrument,
        history: @escaping () -> [RunResult], onRunEnded: @escaping (RunResult) -> Void
    ) {
        self.loaded = loaded
        self.history = history
        layout = ScoreLayout(song: loaded.song, pages: loaded.pages)
        self.onRunEnded = onRunEnded
        // The player's callback needs the session, which does not exist until init returns.
        let relay = Relay()
        player = SongPlayer(song: loaded.song) { event in
            // On the player's queue: sound first, then tell the interface.
            switch event {
            case let .noteOn(note): piano.noteOn(note.pitch, velocity: note.velocity)
            case let .noteOff(note): piano.noteOff(note.pitch)
            case let .click(isDownbeat):
                // General MIDI percussion: 76 is the high wood block, 77 the low one.
                clicks.noteOn(Pitch(midiNumber: isDownbeat ? 76 : 77), velocity: isDownbeat ? 110 : 80)
            case .allNotesOff, .finished: piano.allNotesOff()
            case .judged, .wrongKey, .waiting, .resumed, .judgementsCleared: break
            }
            Task { @MainActor in relay.session?.show(event) }
        }
        relay.session = self
    }

    /// Current position in beats; cheap enough to call every frame.
    var beat: Double { player.beat }

    func togglePlay() {
        if isPlaying {
            pause()
        } else {
            review = nil
            let measure = song.measure(atBeat: max(beat, 0))
            player.play(countInBeats: countInIsOn ? measure?.length ?? 4 : 0)
            isPlaying = true
        }
    }

    /// Back to the start of the loop, or of the song.
    func restart() {
        endRun(completed: false)
        seek(to: loopBeats?.lowerBound ?? 0)
    }

    func seek(to beat: Double) {
        player.seek(to: beat)
        sounding.removeAll()
    }

    func pause() {
        player.pause()
        isPlaying = false
        sounding.removeAll()
        awaited = []
    }

    /// Stops and records the run; call before the session is discarded.
    func stop() {
        pause()
        endRun(completed: false)
    }

    /// A click on a bar in the score: loop that bar, or with `extend` grow the loop to reach it.
    /// Clicking the only looped bar again turns the loop off.
    func tappedMeasure(_ number: Int, extend: Bool) {
        if extend, let loopBars {
            self.loopBars = min(loopBars.lowerBound, number)...max(loopBars.upperBound, number)
        } else if loopBars == number...number {
            loopBars = nil
        } else {
            loopBars = number...number
        }
    }

    /// Call when the player releases a key.
    func released(_ pitch: Pitch) {
        wrongKeys.remove(pitch)
    }

    /// The loop as a range of beats.
    private var loopBeats: ClosedRange<Double>? {
        guard let loopBars,
              let first = song.measures.first(where: { $0.number == loopBars.lowerBound }),
              let last = song.measures.first(where: { $0.number == loopBars.upperBound })
        else { return nil }
        return first.start...last.end
    }

    private func applyLoop() {
        player.setLoop(loopBeats)
        if let loopBeats, !loopBeats.contains(beat) { seek(to: loopBeats.lowerBound) }
    }

    private func show(_ event: PlaybackEngine.Event) {
        switch event {
        case let .noteOn(note): sounding[note.pitch] = note.hand
        case let .noteOff(note): sounding[note.pitch] = nil
        case .allNotesOff: sounding.removeAll()
        case .finished:
            sounding.removeAll()
            isPlaying = false
            endRun(completed: true)
        case let .judged(noteID, judgement, offset): attempts[noteID] = Attempt(judgement: judgement, offset: offset)
        case let .wrongKey(pitch, beat):
            wrongKeys.insert(pitch)
            wrongKeyBeats.append(beat)
        case let .waiting(notes): awaited = notes
        case .resumed: awaited = []
        case let .judgementsCleared(fromBeat):
            // A loop pass or a jump back: the notes ahead are fresh again.
            if isPlaying, let loop = loopBeats, abs(fromBeat - loop.lowerBound) < 1e-6 { finishedLoopPass(loop) }
            attempts = attempts.filter { song.notes[$0.key].start < fromBeat }
            wrongKeyBeats.removeAll { $0 >= fromBeat }
            awaited = []
        case .click: break
        }
    }

    /// Starts the loop the review suggests, with adaptive tempo on.
    func startSuggestedLoop() {
        guard let loop = review?.analysis.suggestedLoop else { return }
        review = nil
        rate = loop.rate
        if let hand = loop.hand { handMode = hand == .right ? .right : .left }
        adaptsTempo = true
        loopBars = loop.bars
        seek(to: loopBeats?.lowerBound ?? 0)
        togglePlay()
    }

    func dismissReview() {
        review = nil
    }

    /// One pass of the loop ended: adjust the tempo if adaptive practice is on.
    private func finishedLoopPass(_ loop: ClosedRange<Double>) {
        guard adaptsTempo, !handMode.playerHands.isEmpty else { return }
        let inLoop = attempts.filter { loop.contains(song.notes[$0.key].start) }
        guard !inLoop.isEmpty else { return }
        let pass = RunReview(
            song: song, attempts: inLoop, wrongKeyBeats: wrongKeyBeats.filter { loop.contains($0) },
            playerHands: handMode.playerHands, rate: rate
        )
        let next = adaptive.passEnded(accuracy: pass.accuracy, rate: rate)
        if next != rate { rate = next }
    }

    private func endRun(completed: Bool) {
        defer {
            attempts.removeAll()
            wrongKeyBeats.removeAll()
        }
        // A few notes before giving up is not a run worth keeping.
        guard completed || attempts.count >= 8 else { return }
        let analysis = RunReview(
            song: song, attempts: attempts, wrongKeyBeats: wrongKeyBeats,
            playerHands: handMode.playerHands, rate: rate
        )
        func count(_ judgement: PlaybackEngine.Judgement) -> Int { attempts.values.count { $0.judgement == judgement } }
        let earlier = history().filter(\.completed).compactMap(\.accuracy)
        onRunEnded(RunResult(
            date: Date(), rate: rate, hands: handMode.playerHands.map(\.rawValue).sorted(),
            usedWaitMode: waitsForPlayer, completed: completed,
            correct: count(.correct), early: count(.early), late: count(.late), missed: count(.missed),
            wrongKeys: wrongKeyBeats.count, accuracy: analysis.accuracy, averageOffset: analysis.averageOffset
        ))
        if completed {
            review = Review(
                analysis: analysis, history: Array((earlier + [analysis.accuracy]).suffix(8)),
                handMode: handMode, rate: rate, usedWaitMode: waitsForPlayer
            )
        }
    }
}

/// Lets the player's callback reach the session created after it.
@MainActor
private final class Relay: Sendable {
    weak var session: PracticeSession?
}
