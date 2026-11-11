import AVFoundation
import MusicCore

/// Plays one instrument from a sound bank using the system sampler.
public final class SamplerInstrument: Instrument, @unchecked Sendable {
    // AVAudioUnitSampler's note and controller calls are safe from any thread.
    let node: AVAudioUnitSampler
    private let channel: UInt8

    public init() {
        node = AVAudioUnitSampler()
        channel = 0
    }

    private init(sharing node: AVAudioUnitSampler, channel: UInt8) {
        self.node = node
        self.channel = channel
    }

    /// A second player of the same loaded sound on its own MIDI channel, so the app's part
    /// and the user's playing can hold and release the same key independently.
    public func voice(channel: Int) -> SamplerInstrument {
        SamplerInstrument(sharing: node, channel: UInt8(min(max(channel, 0), 15)))
    }

    /// Loads a program (0 = acoustic grand piano) from the bank. Can take seconds for large banks.
    /// The instrument must already be attached to a running `AudioEngine`.
    /// - Parameter percussion: load the bank's drum kit instead of a melodic program.
    public func load(_ bank: SoundBank, program: Int = 0, percussion: Bool = false) throws {
        try node.loadSoundBankInstrument(
            at: bank.url,
            program: UInt8(program),
            bankMSB: UInt8(percussion ? kAUSampler_DefaultPercussionBankMSB : kAUSampler_DefaultMelodicBankMSB),
            bankLSB: UInt8(kAUSampler_DefaultBankLSB)
        )
    }

    public func noteOn(_ pitch: Pitch, velocity: Int) {
        guard let note = UInt8(exactly: pitch.midiNumber), note < 128 else { return }
        node.startNote(note, withVelocity: UInt8(min(max(velocity, 1), 127)), onChannel: channel)
    }

    public func noteOff(_ pitch: Pitch) {
        guard let note = UInt8(exactly: pitch.midiNumber), note < 128 else { return }
        node.stopNote(note, onChannel: channel)
    }

    public func setSustain(_ isDown: Bool) {
        node.sendController(64, withValue: isDown ? 127 : 0, onChannel: channel)
    }

    public func allNotesOff() {
        node.sendController(64, withValue: 0, onChannel: channel)
        node.sendController(123, withValue: 0, onChannel: channel) // all notes off
        node.sendController(120, withValue: 0, onChannel: channel) // all sound off
    }
}
