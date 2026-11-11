import SwiftMIDIIO

/// A colour a pad can be lit in, the same on the device and on screen (requirement HW-2).
public enum PadColor: String, Sendable, CaseIterable, Codable {
    case red, orange, yellow, green, cyan, blue, purple, pink, white

    /// Index in the Novation colour palette, at full brightness.
    public var paletteIndex: Int {
        switch self {
        case .red: 5
        case .orange: 9
        case .yellow: 13
        case .green: 21
        case .cyan: 37
        case .blue: 45
        case .purple: 49
        case .pink: 53
        case .white: 3
        }
    }

    /// The same colour turned low, for a pad that does nothing right now.
    public var dimPaletteIndex: Int {
        // The palette runs in groups of four from light to dim; white is the exception.
        self == .white ? 1 : paletteIndex + 2
    }

    /// Red, green and blue, 0 to 1, close to what the pad shows.
    public var rgb: (red: Double, green: Double, blue: Double) {
        switch self {
        case .red: (1.00, 0.24, 0.20)
        case .orange: (1.00, 0.55, 0.12)
        case .yellow: (1.00, 0.86, 0.20)
        case .green: (0.25, 0.90, 0.35)
        case .cyan: (0.25, 0.85, 0.95)
        case .blue: (0.30, 0.45, 1.00)
        case .purple: (0.62, 0.38, 1.00)
        case .pink: (1.00, 0.35, 0.80)
        case .white: (0.95, 0.95, 0.95)
        }
    }
}

/// How one pad is lit.
public struct PadLight: Hashable, Sendable {
    public enum Style: Hashable, Sendable {
        /// The pad's action cannot be used right now.
        case dim
        case bright
        /// Breathing: the action is under way.
        case pulsing
    }

    public var color: PadColor
    public var style: Style

    public init(_ color: PadColor, _ style: Style = .bright) {
        self.color = color
        self.style = style
    }
}

public extension ControlAction {
    /// Colour of the pad that runs this action; nil for knob actions.
    var padColor: PadColor? {
        switch self {
        case .playPause, .cueGo: .green
        case .restart, .fadeOut: .orange
        case .toggleWait, .cueBack: .blue
        case .toggleMetronome, .playLayer: .yellow
        case .handLeft, .fadeIn: .cyan
        case .handBoth: .white
        case .handRight: .pink
        case .toggleCountIn, .stopLayer: .purple
        case .tempoDown, .tempoUp: .white
        case .panic: .red
        case .tempo, .volume: nil
        }
    }
}

public extension ControlMap {
    /// The light of every mapped pad in `context`, keyed by pad note.
    /// - Parameter style: how to light an action's pad; return nil to leave it dark.
    func padLights(
        in context: ControlAction.Context, style: (ControlAction) -> PadLight.Style? = { _ in .bright }
    ) -> [Int: PadLight] {
        var lights: [Int: PadLight] = [:]
        for action in ControlAction.allCases where action.context == context || action.context == .everywhere {
            guard case let .pad(note) = source(of: action), let color = action.padColor, let style = style(action) else { continue }
            lights[note] = PadLight(color, style)
        }
        return lights
    }
}

/// The messages that light the Launchkey Mini MK3's pads, sent on its DAW port.
///
/// From Novation's Launchkey MK3 programmer's reference: DAW mode is entered with a note on
/// channel 16; the pads are then put back in the Drum layout, where they keep sending the
/// same notes on the keyboard port, and are coloured by notes on channel 10 (steady) or 12
/// (pulsing) whose velocity is a palette index.
enum LaunchkeyLights {
    private static let steadyChannel: UInt4 = 9
    private static let pulsingChannel: UInt4 = 11
    private static let setupChannel: UInt4 = 15

    static let padModeController: UInt7 = 3
    static let drumLayout = 1

    /// Takes the device into DAW mode with the pads in the Drum layout.
    static var enter: [MIDIEvent] {
        [
            .noteOn(12, velocity: .midi1(127), channel: setupChannel),
            .cc(padModeController, value: .midi1(UInt7(drumLayout)), channel: setupChannel),
        ]
    }

    /// Hands the device back the way it was found.
    static var leave: [MIDIEvent] {
        [.noteOff(12, velocity: .midi1(0), channel: setupChannel)]
    }

    static func events(pad note: Int, light: PadLight?) -> [MIDIEvent] {
        guard let note = UInt7(exactly: note) else { return [] }
        guard let light else {
            // A note-off: a note-on at velocity 0 does not survive the trip through CoreMIDI.
            return [.noteOff(note, velocity: .midi1(0), channel: steadyChannel)]
        }
        switch light.style {
        case .dim:
            return [.noteOn(note, velocity: .midi1(UInt7(light.color.dimPaletteIndex)), channel: steadyChannel)]
        case .bright:
            return [.noteOn(note, velocity: .midi1(UInt7(light.color.paletteIndex)), channel: steadyChannel)]
        case .pulsing:
            return [.noteOn(note, velocity: .midi1(UInt7(light.color.paletteIndex)), channel: pulsingChannel)]
        }
    }

    /// A drum pad struck or released, as reported on the DAW port: the usual pad notes, on
    /// channel 10 or the one after (Novation's reference names both).
    static func padPress(_ event: MIDIEvent, deviceID: Int32?) -> ControlEvent? {
        let (note, channel, value): (Int, Int, Int)
        switch event {
        case let .noteOn(on): (note, channel, value) = (Int(on.note.number), Int(on.channel), Int(on.velocity.midi1Value))
        case let .noteOff(off): (note, channel, value) = (Int(off.note.number), Int(off.channel), 0)
        default: return nil
        }
        guard channel == 9 || channel == 10, DeviceProfile.launchkeyPadNotes.contains(note) else { return nil }
        return ControlEvent(source: .pad(note: note), value: value, deviceID: deviceID)
    }

    /// True for the port that carries DAW mode, by the name CoreMIDI reports.
    static func isDAWPort(name: String) -> Bool {
        name.lowercased().contains("daw")
    }
}
