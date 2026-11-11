import Foundation

/// A pad or knob that can run the app (requirements HW-2, HW-6).
public enum ControlSource: Hashable, Sendable, Codable {
    /// A drum pad, by the MIDI note it sends.
    case pad(note: Int)
    /// A knob, slider or button, by its MIDI controller number.
    case controller(number: Int)

    /// How to call the control in the interface.
    public enum Name: Hashable, Sendable {
        /// Numbered as on the Launchkey Mini: 1 to 8 on the top row, 9 to 16 below.
        case pad(Int)
        /// 1 to 8, left to right.
        case knob(Int)
        case note(Int)
        case controller(Int)
    }

    public var name: Name {
        switch self {
        case let .pad(note):
            DeviceProfile.launchkeyPadNotes.firstIndex(of: note).map { .pad($0 + 1) } ?? .note(note)
        case let .controller(number):
            DeviceProfile.launchkeyKnobControllers.contains(number)
                ? .knob(number - DeviceProfile.launchkeyKnobControllers.lowerBound + 1) : .controller(number)
        }
    }
}

/// A pad was pressed or released, or a knob moved.
public struct ControlEvent: Hashable, Sendable {
    public let source: ControlSource
    /// 0...127: how hard the pad was hit (0 when released), or where the knob is.
    public let value: Int
    public let deviceID: Int32?

    public init(source: ControlSource, value: Int, deviceID: Int32? = nil) {
        self.source = source
        self.value = value
        self.deviceID = deviceID
    }
}

/// Something a pad or knob can do.
public enum ControlAction: String, Codable, CaseIterable, Sendable {
    // While practicing.
    case playPause, restart, toggleWait, toggleMetronome, handLeft, handBoth, handRight, toggleCountIn
    case tempoDown, tempoUp
    /// Knob: practice tempo, from a quarter speed to one and a half.
    case tempo
    // On stage (requirement LV-5).
    case cueBack, cueGo, playLayer, fadeIn, fadeOut, stopLayer
    // Anywhere.
    case panic
    /// Knob: loudness of everything.
    case volume

    /// Where an action applies. The same pad can do one thing while practicing and another on stage.
    public enum Context: String, Sendable, CaseIterable {
        case practice, stage, everywhere
    }

    public var context: Context {
        switch self {
        case .playPause, .restart, .toggleWait, .toggleMetronome, .handLeft, .handBoth, .handRight,
             .toggleCountIn, .tempoDown, .tempoUp, .tempo: .practice
        case .cueBack, .cueGo, .playLayer, .fadeIn, .fadeOut, .stopLayer: .stage
        case .panic, .volume: .everywhere
        }
    }

    /// True for actions that follow a knob's position instead of firing on a press.
    public var isContinuous: Bool { self == .tempo || self == .volume }
}

/// Which pad or knob does what. Editable by pressing the control to use (MIDI learn, HW-6).
public struct ControlMap: Hashable, Sendable {
    public private(set) var sources: [ControlAction: ControlSource]

    public init(sources: [ControlAction: ControlSource] = [:]) {
        self.sources = sources
    }

    public func source(of action: ControlAction) -> ControlSource? {
        sources[action]
    }

    /// What a control does in `context`: an action of that context, or one that works everywhere.
    public func action(for source: ControlSource, in context: ControlAction.Context) -> ControlAction? {
        ControlAction.allCases.first {
            sources[$0] == source && ($0.context == context || $0.context == .everywhere)
        }
    }

    /// Gives `action` to a control, taking the control away from any action it would clash with.
    /// A pad cannot drive a knob action or a knob a pad action; such a request is ignored.
    /// - Returns: false when the control does not suit the action.
    @discardableResult
    public mutating func assign(_ source: ControlSource, to action: ControlAction) -> Bool {
        if case .pad = source, action.isContinuous { return false }
        for other in ControlAction.allCases where other != action && sources[other] == source {
            let clashes = other.context == action.context || other.context == .everywhere || action.context == .everywhere
            if clashes { sources[other] = nil }
        }
        sources[action] = source
        return true
    }

    public mutating func clear(_ action: ControlAction) {
        sources[action] = nil
    }

    /// The Launchkey Mini MK3 out of the box, pads in Drum mode. Top row left to right, then
    /// the last pad of the bottom row for panic.
    public static let launchkeyDefaults: ControlMap = {
        let pads = DeviceProfile.launchkeyPadNotes
        let knobs = DeviceProfile.launchkeyKnobControllers
        var sources: [ControlAction: ControlSource] = [:]
        let practice: [ControlAction] = [.playPause, .restart, .toggleWait, .toggleMetronome, .handLeft, .handBoth, .handRight, .toggleCountIn, .tempoDown, .tempoUp]
        for (index, action) in practice.enumerated() { sources[action] = .pad(note: pads[index]) }
        let stage: [ControlAction] = [.cueBack, .cueGo, .playLayer, .fadeIn, .fadeOut, .stopLayer]
        for (index, action) in stage.enumerated() { sources[action] = .pad(note: pads[index]) }
        sources[.panic] = .pad(note: pads[15])
        sources[.tempo] = .controller(number: knobs.lowerBound)
        sources[.volume] = .controller(number: knobs.upperBound)
        return ControlMap(sources: sources)
    }()
}

extension ControlMap: Codable {
    // Stored as a list of pairs so the file reads plainly and unknown actions from a newer
    // version are skipped instead of failing the whole map.
    private struct Binding: Codable {
        let action: String
        let source: ControlSource
    }

    public init(from decoder: Decoder) throws {
        let bindings = try decoder.singleValueContainer().decode([Binding].self)
        var sources: [ControlAction: ControlSource] = [:]
        for binding in bindings {
            if let action = ControlAction(rawValue: binding.action) { sources[action] = binding.source }
        }
        self.init(sources: sources)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(ControlAction.allCases.compactMap { action in
            sources[action].map { Binding(action: action.rawValue, source: $0) }
        })
    }
}
