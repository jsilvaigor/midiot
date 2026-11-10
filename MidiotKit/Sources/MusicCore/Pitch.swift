/// A pitch identified by its MIDI note number (60 = middle C).
public struct Pitch: Hashable, Comparable, Sendable {
    public let midiNumber: Int

    public init(midiNumber: Int) {
        self.midiNumber = midiNumber
    }

    /// 0 for C through 11 for B.
    public var pitchClass: Int { ((midiNumber % 12) + 12) % 12 }

    /// Scientific octave number: middle C (MIDI 60) is in octave 4.
    public var octave: Int { Int((Double(midiNumber) / 12).rounded(.down)) - 1 }

    public var isBlackKey: Bool { [1, 3, 6, 8, 10].contains(pitchClass) }

    public static func < (lhs: Pitch, rhs: Pitch) -> Bool { lhs.midiNumber < rhs.midiNumber }

    public static let middleC = Pitch(midiNumber: 60)
}
