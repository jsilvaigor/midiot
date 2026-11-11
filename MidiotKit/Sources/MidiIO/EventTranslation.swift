import MusicCore
import SwiftMIDIIO

extension PerformanceEvent.Kind {
    /// Converts a MIDI message into a playing gesture, or nil if it is not one
    /// (knobs, pads, pitch bend and so on).
    /// - Parameter padChannel: channel whose notes come from drum pads and are ignored.
    init?(_ event: MIDIEvent, padChannel: Int?) {
        switch event {
        case let .noteOn(note):
            guard Int(note.channel) != padChannel else { return nil }
            let pitch = Pitch(midiNumber: Int(note.note.number))
            let velocity = Int(note.velocity.midi1Value)
            // MIDI 1 devices may send note-on with velocity 0 to mean note-off.
            self = velocity == 0 ? .noteOff(pitch: pitch) : .noteOn(pitch: pitch, velocity: velocity)
        case let .noteOff(note):
            guard Int(note.channel) != padChannel else { return nil }
            self = .noteOff(pitch: Pitch(midiNumber: Int(note.note.number)))
        case let .cc(cc) where cc.controller == .sustainPedal:
            self = .sustain(isDown: Int(cc.value.midi1Value) >= 64)
        default:
            return nil
        }
    }
}

extension ControlEvent {
    /// Converts a MIDI message into a control gesture, or nil if it is playing: a pad note on
    /// the device's pad channel, or any controller but the sustain pedal.
    init?(_ event: MIDIEvent, padChannel: Int?, deviceID: Int32? = nil) {
        switch event {
        case let .noteOn(note) where Int(note.channel) == padChannel:
            self.init(source: .pad(note: Int(note.note.number)), value: Int(note.velocity.midi1Value), deviceID: deviceID)
        case let .noteOff(note) where Int(note.channel) == padChannel:
            self.init(source: .pad(note: Int(note.note.number)), value: 0, deviceID: deviceID)
        case let .cc(cc) where cc.controller != .sustainPedal:
            self.init(source: .controller(number: Int(cc.controller.number)), value: Int(cc.value.midi1Value), deviceID: deviceID)
        default:
            return nil
        }
    }
}
