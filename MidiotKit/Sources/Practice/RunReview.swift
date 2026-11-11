import MusicCore

/// What the player did on one note of a run.
public struct Attempt: Hashable, Sendable {
    public let judgement: PlaybackEngine.Judgement
    /// Seconds from the note to the key press, negative when early; nil if not measured.
    public let offset: Double?

    public init(judgement: PlaybackEngine.Judgement, offset: Double?) {
        self.judgement = judgement
        self.offset = offset
    }
}

/// The analysis of one run shown after it ends (requirement FB-2).
public struct RunReview: Hashable, Sendable {
    public enum Tendency: String, Hashable, Sendable, Codable {
        case rushing, dragging, steady
    }

    public struct Bar: Hashable, Sendable {
        public let number: Int
        /// 0...1, or nil when the player had nothing to play in this bar.
        public let score: Double?
        public let wrongKeys: Int
        public let missed: Int
        public let early: Int
        public let late: Int
    }

    public struct SuggestedLoop: Hashable, Sendable {
        public let bars: ClosedRange<Int>
        /// Tempo to practice at, as a fraction of the song's tempo.
        public let rate: Double
        /// The hand to start with when one is clearly weaker.
        public let hand: Hand?
    }

    /// Share of the player's notes that were played, 0...1, counting wrong keys against it.
    public let accuracy: Double
    public let accuracyByHand: [Hand: Double]
    /// Average distance from the beat in seconds, ignoring direction; nil if never measured.
    public let averageError: Double?
    /// Average signed offset in seconds: negative means early overall.
    public let averageOffset: Double?
    /// Signed offsets of every timed note, for drawing the spread.
    public let offsets: [Double]
    public let tendency: Tendency
    /// The hand that shows the tendency most, when both were played.
    public let tendencyHand: Hand?
    public let bars: [Bar]
    public let suggestedLoop: SuggestedLoop?

    /// Mean offsets smaller than this are called steady.
    public static let steadyWindow = 0.015
    /// Bars scoring below this are worth looping.
    public static let troubleScore = 0.8

    /// - Parameters:
    ///   - attempts: by note id, for the notes the player was asked to play.
    ///   - wrongKeyBeats: the beat of every wrong key press.
    ///   - playerHands: the hands the player played.
    ///   - rate: the tempo of the run, as a fraction of the song's tempo.
    public init(
        song: Song, attempts: [Int: Attempt], wrongKeyBeats: [Double], playerHands: Set<Hand>, rate: Double
    ) {
        let expected = song.notes.filter { playerHands.contains($0.hand) && attempts[$0.id] != nil }

        func score(_ notes: [Note], wrong: Int) -> Double? {
            guard !notes.isEmpty || wrong > 0 else { return nil }
            let played = notes.count { attempts[$0.id]?.judgement != .missed }
            return Double(played) / Double(notes.count + wrong)
        }

        accuracy = score(expected, wrong: wrongKeyBeats.count) ?? 0
        var byHand: [Hand: Double] = [:]
        for hand in playerHands {
            // Wrong keys cannot be pinned on a hand, so hand scores count played notes only.
            if let value = score(expected.filter { $0.hand == hand }, wrong: 0) { byHand[hand] = value }
        }
        accuracyByHand = byHand

        func timed(_ notes: [Note]) -> [Double] { notes.compactMap { attempts[$0.id]?.offset } }
        func mean(_ values: [Double]) -> Double? { values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) }
        let all = timed(expected)
        offsets = all
        averageOffset = mean(all)
        averageError = mean(all.map(abs))
        if let averageOffset, abs(averageOffset) > Self.steadyWindow {
            tendency = averageOffset < 0 ? .rushing : .dragging
        } else {
            tendency = .steady
        }
        if tendency != .steady, playerHands.count > 1 {
            let means = Hand.allCases.compactMap { hand in
                mean(timed(expected.filter { $0.hand == hand })).map { (hand, $0) }
            }
            tendencyHand = means.max { abs($0.1) < abs($1.1) }.flatMap { abs($0.1) > Self.steadyWindow ? $0.0 : nil }
        } else {
            tendencyHand = nil
        }

        let bars = song.measures.map { measure -> Bar in
            let notes = expected.filter { $0.start >= measure.start - 1e-6 && $0.start < measure.end - 1e-6 }
            let wrong = wrongKeyBeats.count { $0 >= measure.start && $0 < measure.end }
            func count(_ judgement: PlaybackEngine.Judgement) -> Int { notes.count { attempts[$0.id]?.judgement == judgement } }
            return Bar(
                number: measure.number, score: score(notes, wrong: wrong), wrongKeys: wrong,
                missed: count(.missed), early: count(.early), late: count(.late)
            )
        }
        self.bars = bars

        // Suggest up to four bars around the weakest one, grown toward its weaker neighbours.
        let scored = bars.filter { $0.score != nil }
        if let worst = scored.min(by: { $0.score! < $1.score! }), worst.score! < Self.troubleScore,
           let index = bars.firstIndex(of: worst) {
            var low = index, high = index
            func isTrouble(_ i: Int) -> Bool { bars.indices.contains(i) && (bars[i].score ?? 1) < 0.93 }
            while high - low < 3 {
                if isTrouble(high + 1) { high += 1 } else if isTrouble(low - 1) { low -= 1 } else { break }
            }
            // A single bar is hard to get into: lead in from the bar before when there is one.
            if low == high, low > 0 { low -= 1 }
            let weakerHand = byHand.count > 1 ? byHand.min { $0.value < $1.value } : nil
            let handGap = byHand.count > 1 ? (byHand.values.max()! - byHand.values.min()!) : 0
            suggestedLoop = SuggestedLoop(
                bars: bars[low].number...bars[high].number,
                rate: min(1, max(0.4, ((rate - 0.15) * 20).rounded() / 20)),
                hand: handGap >= 0.08 ? weakerHand?.key : nil
            )
        } else {
            suggestedLoop = nil
        }
    }
}
