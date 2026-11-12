import MidiIO
import MusicCore
import Sound

/// Plays by sending to MIDI out on one channel, for a synth or host on the other end.
final class ExternalInstrument: Instrument {
    private let out: MIDIOutPort
    /// 0...15.
    private let channel: Int

    init(out: MIDIOutPort, channel: Int) {
        self.out = out
        self.channel = channel
    }

    func noteOn(_ pitch: Pitch, velocity: Int) {
        out.noteOn(pitch.midiNumber, velocity: velocity, channel: channel)
    }

    func noteOff(_ pitch: Pitch) {
        out.noteOff(pitch.midiNumber, channel: channel)
    }

    func setSustain(_ isDown: Bool) {
        out.controller(64, value: isDown ? 127 : 0, channel: channel)
    }

    func allNotesOff() {
        out.controller(64, value: 0, channel: channel)
        out.controller(123, value: 0, channel: channel)
        out.controller(120, value: 0, channel: channel)
    }

    func program(_ program: Int) {
        out.program(program, channel: channel)
    }
}
