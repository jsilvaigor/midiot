/// Converts between musical time (beats, where one beat is a quarter note) and seconds.
public struct TempoMap: Hashable, Sendable {
    public struct Change: Hashable, Sendable {
        public let beat: Double
        /// Quarter notes per minute.
        public let bpm: Double

        public init(beat: Double, bpm: Double) {
            self.beat = beat
            self.bpm = bpm
        }
    }

    /// Tempo changes ordered by beat; the first is always at beat 0.
    public let changes: [Change]
    /// Seconds elapsed at the start of each change, parallel to `changes`.
    private let offsets: [Double]

    /// - Parameter changes: any order; a change at beat 0 is added at 120 bpm if missing.
    public init(changes: [Change] = []) {
        var sorted = changes.filter { $0.bpm > 0 && $0.beat >= 0 }.sorted { $0.beat < $1.beat }
        if sorted.first?.beat != 0 {
            sorted.insert(Change(beat: 0, bpm: 120), at: 0)
        }
        var offsets = [0.0]
        for index in 1..<sorted.count {
            let previous = sorted[index - 1]
            offsets.append(offsets[index - 1] + (sorted[index].beat - previous.beat) * 60 / previous.bpm)
        }
        self.changes = sorted
        self.offsets = offsets
    }

    public init(bpm: Double) {
        self.init(changes: [Change(beat: 0, bpm: bpm)])
    }

    public func seconds(atBeat beat: Double) -> Double {
        let index = max(changes.lastIndex { $0.beat <= beat } ?? 0, 0)
        return offsets[index] + (beat - changes[index].beat) * 60 / changes[index].bpm
    }

    public func beat(atSeconds seconds: Double) -> Double {
        let index = max(offsets.lastIndex { $0 <= seconds } ?? 0, 0)
        return changes[index].beat + (seconds - offsets[index]) * changes[index].bpm / 60
    }

    public func bpm(atBeat beat: Double) -> Double {
        (changes.last { $0.beat <= beat } ?? changes[0]).bpm
    }
}
