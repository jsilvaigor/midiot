import Darwin
import MusicCore

/// Something the player did on a keyboard, stamped with the time it happened.
public struct PerformanceEvent: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// Velocity is 1...127.
        case noteOn(pitch: Pitch, velocity: Int)
        case noteOff(pitch: Pitch)
        case sustain(isDown: Bool)
    }

    public let kind: Kind
    /// Host clock time (`mach_absolute_time` units) reported by CoreMIDI for the event.
    public let hostTime: UInt64
    /// Identifier of the device that sent it, matching `ConnectedDevice.id`; nil if unknown.
    public let deviceID: Int32?

    public init(kind: Kind, hostTime: UInt64, deviceID: Int32?) {
        self.kind = kind
        self.hostTime = hostTime
        self.deviceID = deviceID
    }

    /// `hostTime` in seconds on the host clock, comparable with `DispatchTime` uptime.
    /// Nil when the device gave no timestamp.
    public var seconds: Double? {
        guard hostTime > 0 else { return nil }
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        return Double(hostTime) * Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
    }
}
