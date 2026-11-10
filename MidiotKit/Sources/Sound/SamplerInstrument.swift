import AVFoundation
import MusicCore

/// Plays one instrument from a sound bank using the system sampler.
public final class SamplerInstrument: Instrument, @unchecked Sendable {
    // AVAudioUnitSampler's note and controller calls are safe from any thread.
    let node = AVAudioUnitSampler()

    public init() {}

    /// Loads a program (0 = acoustic grand piano) from the bank. Can take seconds for large banks.
    /// The instrument must already be attached to a running `AudioEngine`.
    public func load(_ bank: SoundBank, program: Int = 0) throws {
        try node.loadSoundBankInstrument(
            at: bank.url,
            program: UInt8(program),
            bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
            bankLSB: UInt8(kAUSampler_DefaultBankLSB)
        )
    }

    public func noteOn(_ pitch: Pitch, velocity: Int) {
        guard let note = UInt8(exactly: pitch.midiNumber), note < 128 else { return }
        node.startNote(note, withVelocity: UInt8(min(max(velocity, 1), 127)), onChannel: 0)
    }

    public func noteOff(_ pitch: Pitch) {
        guard let note = UInt8(exactly: pitch.midiNumber), note < 128 else { return }
        node.stopNote(note, onChannel: 0)
    }

    public func setSustain(_ isDown: Bool) {
        node.sendController(64, withValue: isDown ? 127 : 0, onChannel: 0)
    }

    public func allNotesOff() {
        node.sendController(64, withValue: 0, onChannel: 0)
        node.sendController(123, withValue: 0, onChannel: 0) // all notes off
        node.sendController(120, withValue: 0, onChannel: 0) // all sound off
    }
}
