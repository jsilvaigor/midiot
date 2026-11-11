import AVFoundation
import MusicCore

/// Plays one instrument from a sound bank using the system sampler.
public final class SamplerInstrument: Instrument, @unchecked Sendable {
    // AVAudioUnitSampler's note and controller calls are safe from any thread.
    let node: AVAudioUnitSampler
    private let channel: UInt8
    /// Shared by every voice of the same sound.
    private let copies: MIDIMirror

    public init() {
        node = AVAudioUnitSampler()
        channel = 0
        copies = MIDIMirror()
    }

    private init(sharing node: AVAudioUnitSampler, channel: UInt8, mirror: MIDIMirror) {
        self.node = node
        self.channel = channel
        self.copies = mirror
    }

    /// Copies everything this sound plays, from all its voices, to `sink` on one channel.
    /// Nil stops copying.
    public func mirror(to sink: (@Sendable (ChannelMessage) -> Void)?, channel: Int = 0) {
        guard let sink else { return copies.set(nil) }
        copies.set { message in sink(message.on(channel: channel)) }
    }

    /// Silences the sound itself without stopping what it copies out.
    public var isMuted: Bool {
        get { node.volume == 0 }
        set { node.volume = newValue ? 0 : 1 }
    }

    /// A second player of the same loaded sound on its own MIDI channel, so the app's part
    /// and the user's playing can hold and release the same key independently.
    public func voice(channel: Int) -> SamplerInstrument {
        SamplerInstrument(sharing: node, channel: UInt8(min(max(channel, 0), 15)), mirror: copies)
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
        let velocity = UInt8(min(max(velocity, 1), 127))
        node.startNote(note, withVelocity: velocity, onChannel: channel)
        copies.send(.noteOn(note: Int(note), velocity: Int(velocity), channel: Int(channel)))
    }

    public func noteOff(_ pitch: Pitch) {
        guard let note = UInt8(exactly: pitch.midiNumber), note < 128 else { return }
        node.stopNote(note, onChannel: channel)
        copies.send(.noteOff(note: Int(note), channel: Int(channel)))
    }

    public func setSustain(_ isDown: Bool) {
        control(64, isDown ? 127 : 0)
    }

    public func allNotesOff() {
        control(64, 0)
        control(123, 0) // all notes off
        control(120, 0) // all sound off
    }

    private func control(_ number: UInt8, _ value: UInt8) {
        node.sendController(number, withValue: value, onChannel: channel)
        copies.send(.controller(number: Int(number), value: Int(value), channel: Int(channel)))
    }
}
