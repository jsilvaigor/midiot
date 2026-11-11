import MusicCore

/// Two sounds on one keyboard: layered over every key, or split so the lower keys play one
/// and the upper keys the other (requirement LV-1).
public final class SplitInstrument: Instrument {
    private let main: any Instrument
    private let second: any Instrument
    private let splitAt: Pitch?

    /// - Parameter splitAt: lowest key that plays `main`; keys below it play `second`.
    ///   Nil plays both sounds on every key.
    public init(main: any Instrument, second: any Instrument, splitAt: Pitch?) {
        self.main = main
        self.second = second
        self.splitAt = splitAt
    }

    public func noteOn(_ pitch: Pitch, velocity: Int) {
        for instrument in players(of: pitch) { instrument.noteOn(pitch, velocity: velocity) }
    }

    public func noteOff(_ pitch: Pitch) {
        for instrument in players(of: pitch) { instrument.noteOff(pitch) }
    }

    public func setSustain(_ isDown: Bool) {
        main.setSustain(isDown)
        second.setSustain(isDown)
    }

    public func allNotesOff() {
        main.allNotesOff()
        second.allNotesOff()
    }

    private func players(of pitch: Pitch) -> [any Instrument] {
        guard let splitAt else { return [main, second] }
        return [pitch < splitAt ? second : main]
    }
}
