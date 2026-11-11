/// The span of keys on a physical or on-screen keyboard.
public struct KeyboardRange: Hashable, Sendable {
    /// Lowest key; always a C on the keyboards the app supports.
    public let lowest: Pitch
    public let keyCount: Int

    public init(lowest: Pitch, keyCount: Int) {
        self.lowest = lowest
        self.keyCount = keyCount
    }

    public var highest: Pitch { Pitch(midiNumber: lowest.midiNumber + keyCount - 1) }

    public var pitches: [Pitch] {
        (lowest.midiNumber...highest.midiNumber).map(Pitch.init(midiNumber:))
    }

    public func contains(_ pitch: Pitch) -> Bool {
        pitch >= lowest && pitch <= highest
    }

    /// The same keyboard moved by whole octaves, as few as possible, so that `pitch` is on it.
    /// A keyboard's octave buttons move its range; the on-screen keyboard follows with this.
    public func shifted(toContain pitch: Pitch) -> KeyboardRange {
        var octaves = 0
        if pitch < lowest {
            octaves = -((lowest.midiNumber - pitch.midiNumber + 11) / 12)
        } else if pitch > highest {
            octaves = (pitch.midiNumber - highest.midiNumber + 11) / 12
        }
        return KeyboardRange(lowest: Pitch(midiNumber: lowest.midiNumber + octaves * 12), keyCount: keyCount)
    }

    /// 49 keys, C2 to C6: the Roland A-49 at its default octave.
    public static let fortyNineKeys = KeyboardRange(lowest: Pitch(midiNumber: 36), keyCount: 49)
    /// 25 keys, C3 to C5: the Launchkey Mini at its default octave.
    public static let twentyFiveKeys = KeyboardRange(lowest: Pitch(midiNumber: 48), keyCount: 25)
}
