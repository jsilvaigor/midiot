import MusicCore
import Testing
@testable import Practice

@Suite struct RunReviewTests {
    /// Four bars of 4/4: the right hand plays every beat, the left hand the first beat of each bar.
    static let song: Song = {
        var notes: [Note] = []
        for beat in 0..<16 { notes.append(Note(id: 0, pitch: Pitch(midiNumber: 72), start: Double(beat), duration: 1, hand: .right)) }
        for bar in 0..<4 { notes.append(Note(id: 0, pitch: Pitch(midiNumber: 48), start: Double(bar * 4), duration: 4, hand: .left)) }
        return Song(title: "T", notes: notes, tempoMap: TempoMap(bpm: 60), measures: Song.evenMeasures(beatsPerMeasure: 4, covering: 16))
    }()

    /// Everything correct and on time, then the given changes by note id.
    func attempts(_ changes: [Int: Attempt] = [:], offset: Double = 0) -> [Int: Attempt] {
        var all = Dictionary(uniqueKeysWithValues: Self.song.notes.map { ($0.id, Attempt(judgement: .correct, offset: offset)) })
        for (id, attempt) in changes { all[id] = attempt }
        return all
    }

    func ids(bar: Int, hand: Hand) -> [Int] {
        Self.song.notes.filter { $0.hand == hand && Int($0.start) / 4 == bar - 1 }.map(\.id)
    }

    @Test func cleanRun() {
        let review = RunReview(song: Self.song, attempts: attempts(), wrongKeyBeats: [], playerHands: [.left, .right], rate: 1)
        #expect(review.accuracy == 1)
        #expect(review.accuracyByHand == [.left: 1, .right: 1])
        #expect(review.tendency == .steady)
        #expect(review.bars.map(\.score) == [1, 1, 1, 1])
        #expect(review.suggestedLoop == nil)
    }

    @Test func troubleBarsBecomeASuggestedLoop() {
        // Bar 3: the right hand misses two of four notes and there is a wrong key.
        var changes: [Int: Attempt] = [:]
        for id in ids(bar: 3, hand: .right).prefix(2) { changes[id] = Attempt(judgement: .missed, offset: nil) }
        let review = RunReview(song: Self.song, attempts: attempts(changes), wrongKeyBeats: [9.5], playerHands: [.left, .right], rate: 0.8)

        let bar3 = review.bars[2]
        #expect(bar3.missed == 2)
        #expect(bar3.wrongKeys == 1)
        #expect(bar3.score == 0.5) // 3 of 5 notes played, plus one wrong key: 3 / 6
        #expect(review.bars[0].score == 1)
        #expect(review.accuracy == 18.0 / 21.0)
        #expect(review.accuracyByHand[.right] == 14.0 / 16.0)
        #expect(review.accuracyByHand[.left] == 1)

        let loop = try! #require(review.suggestedLoop)
        #expect(loop.bars == 2...3) // the weak bar with a lead-in
        #expect(loop.rate == 0.65)
        #expect(loop.hand == .right)
    }

    @Test func rushingIsNamedWithTheHandThatDoesIt() {
        var changes: [Int: Attempt] = [:]
        for note in Self.song.notes where note.hand == .left { changes[note.id] = Attempt(judgement: .early, offset: -0.12) }
        let review = RunReview(song: Self.song, attempts: attempts(changes, offset: -0.01), wrongKeyBeats: [], playerHands: [.left, .right], rate: 1)
        #expect(review.tendency == .rushing)
        #expect(review.tendencyHand == .left)
        #expect(abs(review.averageOffset! - (-0.032)) < 0.001)
        #expect(review.offsets.count == 20)
    }

    @Test func onlyThePlayersHandCounts() {
        let rightOnly = attempts().filter { Self.song.notes[$0.key].hand == .right }
        let review = RunReview(song: Self.song, attempts: rightOnly, wrongKeyBeats: [], playerHands: [.right], rate: 1)
        #expect(review.accuracyByHand == [.right: 1])
        #expect(review.tendencyHand == nil)
    }

    @Test func draggingAndWaitModeWithoutTiming() {
        let late = RunReview(song: Self.song, attempts: attempts(offset: 0.05), wrongKeyBeats: [], playerHands: [.left, .right], rate: 1)
        #expect(late.tendency == .dragging)
        let untimed = attempts().mapValues { _ in Attempt(judgement: .correct, offset: nil) }
        let waited = RunReview(song: Self.song, attempts: untimed, wrongKeyBeats: [], playerHands: [.left, .right], rate: 1)
        #expect(waited.averageError == nil)
        #expect(waited.tendency == .steady)
    }
}

@Suite struct AdaptiveTempoTests {
    @Test func threeCleanPassesRaiseTheTempo() {
        var adaptive = AdaptiveTempo()
        #expect(adaptive.passEnded(accuracy: 0.95, rate: 0.6) == 0.6)
        #expect(adaptive.passEnded(accuracy: 1, rate: 0.6) == 0.6)
        #expect(adaptive.cleanPasses == 2)
        #expect(adaptive.passEnded(accuracy: 0.9, rate: 0.6) == 0.65)
        #expect(adaptive.cleanPasses == 0)
    }

    @Test func aMiddlingPassBreaksTheStreak() {
        var adaptive = AdaptiveTempo()
        _ = adaptive.passEnded(accuracy: 1, rate: 0.6)
        _ = adaptive.passEnded(accuracy: 1, rate: 0.6)
        #expect(adaptive.passEnded(accuracy: 0.8, rate: 0.6) == 0.6)
        #expect(adaptive.cleanPasses == 0)
    }

    @Test func twoPoorPassesLowerTheTempo() {
        var adaptive = AdaptiveTempo()
        #expect(adaptive.passEnded(accuracy: 0.4, rate: 0.6) == 0.6)
        #expect(adaptive.passEnded(accuracy: 0.5, rate: 0.6) == 0.55)
    }

    @Test func tempoStaysWithinLimits() {
        var adaptive = AdaptiveTempo()
        for _ in 0..<3 { _ = adaptive.passEnded(accuracy: 1, rate: 1) }
        #expect(adaptive.passEnded(accuracy: 1, rate: 1) == 1)
        var slow = AdaptiveTempo()
        _ = slow.passEnded(accuracy: 0, rate: 0.4)
        #expect(slow.passEnded(accuracy: 0, rate: 0.4) == 0.4)
    }
}
