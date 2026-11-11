import Synchronization
import SwiftMIDIIO

/// Somewhere the app can send what it plays: a synth, an interface, or another app's port.
public struct MIDIDestination: Identifiable, Hashable, Sendable {
    public let id: Int32
    public let name: String
}

/// Where MIDI out goes (requirement SN-3).
public enum MIDIOutChoice: Hashable, Sendable, Codable {
    case off
    /// A port named "Midiot" that other apps on this Mac can listen to.
    case otherApps
    /// A device or port. The name is kept to show while it is unplugged.
    case destination(id: Int32, name: String)
}

/// Sends notes out. Safe to call from any thread; does nothing until `DeviceManager` points
/// it somewhere.
public final class MIDIOutPort: Sendable {
    private let target = Mutex<(any MIDIManagedSendsMessages & Sendable)?>(nil)

    init() {}

    func use(_ new: (any MIDIManagedSendsMessages & Sendable)?) {
        target.withLock { $0 = new }
    }

    private func send(_ event: MIDIEvent) {
        try? target.withLock { $0 }?.send(event: event)
    }

    /// - Parameter channel: 0...15, here and below.
    public func noteOn(_ note: Int, velocity: Int, channel: Int) {
        guard let note = UInt7(exactly: note), let channel = UInt4(exactly: channel) else { return }
        send(.noteOn(note, velocity: .midi1(UInt7(min(max(velocity, 1), 127))), channel: channel))
    }

    public func noteOff(_ note: Int, channel: Int) {
        guard let note = UInt7(exactly: note), let channel = UInt4(exactly: channel) else { return }
        send(.noteOff(note, velocity: .midi1(0), channel: channel))
    }

    public func controller(_ number: Int, value: Int, channel: Int) {
        guard let number = UInt7(exactly: number), let channel = UInt4(exactly: channel) else { return }
        send(.cc(number, value: .midi1(UInt7(min(max(value, 0), 127))), channel: channel))
    }

    public func program(_ program: Int, channel: Int) {
        guard let program = UInt7(exactly: program), let channel = UInt4(exactly: channel) else { return }
        send(.programChange(program: program, channel: channel))
    }

    /// Releases every key and pedal on every channel.
    public func silence() {
        for channel in 0..<16 {
            controller(64, value: 0, channel: channel)
            controller(123, value: 0, channel: channel)
        }
    }
}

/// A port whose input comes straight back out, such as an IAC bus. What the app sends to
/// one must not be heard again as playing, or it would go round for ever.
struct LoopbackPort: Hashable, Sendable {
    let name: String
    let deviceID: Int32?

    /// Drivers that hand back what they are sent.
    static let drivers: Set<String> = ["com.apple.AppleMIDIIACDriver", "com.apple.AppleMIDIRTPDriver"]
}
