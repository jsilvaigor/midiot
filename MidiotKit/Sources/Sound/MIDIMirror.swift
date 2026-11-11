import Synchronization

/// One MIDI channel message, as the app's own synths receive it.
public enum ChannelMessage: Hashable, Sendable {
    /// - Parameter channel: 0...15, here and below.
    case noteOn(note: Int, velocity: Int, channel: Int)
    case noteOff(note: Int, channel: Int)
    case controller(number: Int, value: Int, channel: Int)
    case program(Int, channel: Int)

    /// The same message on another channel.
    func on(channel: Int) -> ChannelMessage {
        switch self {
        case let .noteOn(note, velocity, _): .noteOn(note: note, velocity: velocity, channel: channel)
        case let .noteOff(note, _): .noteOff(note: note, channel: channel)
        case let .controller(number, value, _): .controller(number: number, value: value, channel: channel)
        case let .program(program, _): .program(program, channel: channel)
        }
    }
}

/// Where a synth copies everything it is told to play, so another instrument can play it
/// too (MIDI out, requirement SN-3). Readable from any thread.
final class MIDIMirror: Sendable {
    typealias Sink = @Sendable (ChannelMessage) -> Void

    private let sink = Mutex<Sink?>(nil)

    func set(_ new: Sink?) {
        sink.withLock { $0 = new }
    }

    func send(_ message: ChannelMessage) {
        sink.withLock { $0 }?(message)
    }
}
