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
