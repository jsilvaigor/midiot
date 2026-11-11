import MusicCore

/// What the app knows about a keyboard model (requirements HW-1 to HW-3).
public struct DeviceProfile: Hashable, Sendable {
    public enum Model: Hashable, Sendable {
        case rolandA49
        case launchkeyMiniMK3
        case generic
    }

    public let model: Model
    /// Key range at the device's default octave setting.
    public let range: KeyboardRange
    /// MIDI channel (0-based) on which the device's drum pads send notes, if it has pads.
    /// Those notes are controls, not playing.
    public let padChannel: Int?

    public static let rolandA49 = DeviceProfile(model: .rolandA49, range: .fortyNineKeys, padChannel: nil)
    public static let launchkeyMiniMK3 = DeviceProfile(model: .launchkeyMiniMK3, range: .twentyFiveKeys, padChannel: 9)
    public static let generic = DeviceProfile(model: .generic, range: .fortyNineKeys, padChannel: nil)

    /// Notes the Launchkey Mini MK3's sixteen pads send in Drum mode, top row left to right,
    /// then the bottom row.
    public static let launchkeyPadNotes = [40, 41, 42, 43, 48, 49, 50, 51, 36, 37, 38, 39, 44, 45, 46, 47]
    /// Controller numbers of its eight knobs, left to right.
    public static let launchkeyKnobControllers = 21...28

    /// Picks the profile for a device from the name CoreMIDI reports.
    public static func matching(deviceName: String) -> DeviceProfile {
        let name = deviceName.lowercased()
        if name.contains("a-49") || name.contains("a49") { return .rolandA49 }
        if name.contains("launchkey mini") { return .launchkeyMiniMK3 }
        return .generic
    }
}

/// A keyboard that is plugged in right now.
public struct ConnectedDevice: Identifiable, Hashable, Sendable {
    public let id: Int32
    public let name: String
    public let profile: DeviceProfile

    public init(id: Int32, name: String, profile: DeviceProfile) {
        self.id = id
        self.name = name
        self.profile = profile
    }
}

public extension [ConnectedDevice] {
    /// The device whose key range the app should show: the largest keyboard connected.
    /// With both supported keyboards plugged in this is the A-49 (requirement HW-2).
    var mainInstrument: ConnectedDevice? {
        self.max { $0.profile.range.keyCount < $1.profile.range.keyCount }
    }
}
