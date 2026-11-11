public enum Hand: String, Hashable, Sendable, Codable, CaseIterable {
    case left, right
}

/// One note of a song, timed in beats (one beat is a quarter note).
public struct Note: Hashable, Sendable, Identifiable {
    /// Position in `Song.notes`.
    public let id: Int
    public var pitch: Pitch
    public var start: Double
    public var duration: Double
    public var hand: Hand
    /// Finger number 1 (thumb) to 5, when the source gives one.
    public var finger: Int?
    /// Loudness 1...127, used when the app plays the note.
    public var velocity: Int
    /// Identifier of the matching notehead in the rendered score, when there is one.
    public var notationID: String?

    public init(
        id: Int, pitch: Pitch, start: Double, duration: Double, hand: Hand,
        finger: Int? = nil, velocity: Int = 80, notationID: String? = nil
    ) {
        self.id = id
        self.pitch = pitch
        self.start = start
        self.duration = duration
        self.hand = hand
        self.finger = finger
        self.velocity = velocity
        self.notationID = notationID
    }

    public var end: Double { start + duration }
}

/// A bar of music, used for looping and for showing position.
public struct Measure: Hashable, Sendable {
    /// 1-based bar number as printed in the score.
    public let number: Int
    public let start: Double
    public let length: Double
    /// Identifier of the bar in the rendered score, when there is one.
    public var notationID: String?

    public init(number: Int, start: Double, length: Double, notationID: String? = nil) {
        self.number = number
        self.start = start
        self.length = length
        self.notationID = notationID
    }

    public var end: Double { start + length }
}

/// A piece ready to practice.
public struct Song: Hashable, Sendable {
    public var title: String
    /// Sorted by start, then pitch; each note's `id` is its index.
    public let notes: [Note]
    public var tempoMap: TempoMap
    public let measures: [Measure]

    /// - Parameter notes: any order; they are sorted and renumbered.
    public init(title: String, notes: [Note], tempoMap: TempoMap, measures: [Measure]) {
        self.title = title
        self.tempoMap = tempoMap
        self.measures = measures
        self.notes = notes
            .sorted { ($0.start, $0.pitch.midiNumber) < ($1.start, $1.pitch.midiNumber) }
            .enumerated()
            .map { index, note in
                var note = note
                note = Note(
                    id: index, pitch: note.pitch, start: note.start, duration: note.duration, hand: note.hand,
                    finger: note.finger, velocity: note.velocity, notationID: note.notationID
                )
                return note
            }
    }

    /// Beat at which the last note or bar ends.
    public var length: Double {
        max(notes.map(\.end).max() ?? 0, measures.last?.end ?? 0)
    }

    /// Lowest and highest pitch used, or nil for an empty song.
    public var pitchSpan: ClosedRange<Pitch>? {
        guard let low = notes.map(\.pitch).min(), let high = notes.map(\.pitch).max() else { return nil }
        return low...high
    }

    public func measure(atBeat beat: Double) -> Measure? {
        measures.last { $0.start <= beat }
    }

    /// Bars of equal length covering `length` beats, for sources that give only a time signature.
    public static func evenMeasures(beatsPerMeasure: Double, covering length: Double) -> [Measure] {
        guard beatsPerMeasure > 0, length > 0 else { return [] }
        let count = Int((length / beatsPerMeasure).rounded(.up))
        return (0..<count).map { Measure(number: $0 + 1, start: Double($0) * beatsPerMeasure, length: beatsPerMeasure) }
    }
}

public extension KeyboardRange {
    /// Whether every note of the song can be reached on this keyboard using its octave buttons
    /// once, before starting (requirement HW-3).
    func canPlay(_ song: Song) -> Bool {
        guard let span = song.pitchSpan else { return true }
        return canPlay(lowest: span.lowerBound, highest: span.upperBound)
    }

    func canPlay(lowest low: Pitch, highest high: Pitch) -> Bool {
        // Move the keyboard up as many octaves as possible while its lowest key stays at or
        // below the lowest note, then see whether the top note is still on it.
        let octaves = Int((Double(low.midiNumber - lowest.midiNumber) / 12).rounded(.down))
        return high.midiNumber <= highest.midiNumber + octaves * 12
    }
}

public extension Song {
    /// This song with the notation identifiers of `engraved`, a score generated from it.
    ///
    /// The generated score rounds rhythms, so notes are paired by hand, pitch and nearest
    /// start within `tolerance` beats. Timing stays this song's own.
    func adoptingNotation(of engraved: Song, tolerance: Double = 0.26) -> Song {
        var available = engraved.notes
        let linked = notes.map { note -> Note in
            var note = note
            let match = available.indices
                .filter { available[$0].pitch == note.pitch && available[$0].hand == note.hand
                    && abs(available[$0].start - note.start) <= tolerance }
                .min { abs(available[$0].start - note.start) < abs(available[$1].start - note.start) }
            if let match {
                note.notationID = available[match].notationID
                available.remove(at: match)
            }
            return note
        }
        let bars = measures.enumerated().map { index, measure -> Measure in
            var measure = measure
            if index < engraved.measures.count { measure.notationID = engraved.measures[index].notationID }
            return measure
        }
        return Song(title: title, notes: linked, tempoMap: tempoMap, measures: bars)
    }
}
