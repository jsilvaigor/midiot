import AVFoundation
import MusicCore
import Synchronization

/// Plays many sounds from one General MIDI sound bank at once, a different one on each of
/// sixteen channels (requirement SN-2). The Sketchpad uses it for everything but the grand piano.
public final class PaletteSynth: @unchecked Sendable {
    // The synth's note and controller calls are safe from any thread.
    let node: AVAudioUnitMIDIInstrument
    /// Program selected on each channel, to skip reloading a sound that is already there.
    private let programs = Mutex<[Int: Int]>([:])
    private let copies = MIDIMirror()

    public init() {
        node = AVAudioUnitMIDIInstrument(audioComponentDescription: AudioComponentDescription(
            componentType: kAudioUnitType_MusicDevice, componentSubType: kAudioUnitSubType_MIDISynth,
            componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0
        ))
    }

    public struct LoadError: Error, Equatable {
        public let status: Int32
    }

    /// Points the synth at a sound bank. The synth must already be attached to an engine.
    public func load(_ bank: SoundBank) throws {
        var url = bank.url as CFURL
        let status = withUnsafePointer(to: &url) {
            AudioUnitSetProperty(
                node.audioUnit, kMusicDeviceProperty_SoundBankURL, kAudioUnitScope_Global, 0,
                $0, UInt32(MemoryLayout<CFURL>.size)
            )
        }
        guard status == noErr else { throw LoadError(status: status) }
        programs.withLock { $0.removeAll() }
    }

    /// Chooses the sound of a channel. Loading a sound the first time can take a moment.
    /// - Parameters:
    ///   - program: General MIDI program, 0...127.
    ///   - channel: 0...15.
    public func setProgram(_ program: Int, channel: Int) {
        let program = min(max(program, 0), 127), channel = min(max(channel, 0), 15)
        let isNew = programs.withLock { current -> Bool in
            guard current[channel] != program else { return false }
            current[channel] = program
            return true
        }
        guard isNew else { return }
        copies.send(.program(program, channel: channel))
        // The synth reads a sound's samples only while preloading is switched on.
        setPreload(true)
        node.sendProgramChange(UInt8(program), onChannel: UInt8(channel))
        setPreload(false)
        node.sendProgramChange(UInt8(program), onChannel: UInt8(channel))
    }

    private func setPreload(_ isOn: Bool) {
        var value: UInt32 = isOn ? 1 : 0
        AudioUnitSetProperty(
            node.audioUnit, kAUMIDISynthProperty_EnablePreload, kAudioUnitScope_Global, 0,
            &value, UInt32(MemoryLayout<UInt32>.size)
        )
    }

    /// Sets how loud one channel is, without touching the others. Notes already sounding
    /// follow, which is what lets a recorded layer fade under live playing (requirement LV-2).
    /// - Parameter level: 0 (silent) to 1 (full).
    public func setVolume(_ level: Double, channel: Int) {
        let value = UInt8((min(max(level, 0), 1) * 127).rounded())
        node.sendController(7, withValue: value, onChannel: UInt8(min(max(channel, 0), 15)))
        copies.send(.controller(number: 7, value: Int(value), channel: min(max(channel, 0), 15)))
    }

    /// The instrument that plays on one channel.
    public func voice(channel: Int) -> any Instrument {
        Voice(node: node, channel: UInt8(min(max(channel, 0), 15)), mirror: copies)
    }

    /// Copies everything the synth plays to `sink`, on the same channels, starting with the
    /// sound already chosen on each channel. Nil stops copying.
    public func mirror(to sink: (@Sendable (ChannelMessage) -> Void)?) {
        copies.set(sink)
        guard let sink else { return }
        for (channel, program) in programs.withLock({ $0 }).sorted(by: { $0.key < $1.key }) {
            sink(.program(program, channel: channel))
        }
    }

    /// Silences the synth's own sound without stopping what it copies out.
    public var isMuted: Bool {
        get { node.volume == 0 }
        set { node.volume = newValue ? 0 : 1 }
    }

    /// Silences every channel.
    public func allNotesOff() {
        for channel in 0..<16 { voice(channel: channel).allNotesOff() }
    }

    private final class Voice: Instrument, @unchecked Sendable {
        let node: AVAudioUnitMIDIInstrument
        let channel: UInt8
        let copies: MIDIMirror

        init(node: AVAudioUnitMIDIInstrument, channel: UInt8, mirror: MIDIMirror) {
            self.node = node
            self.channel = channel
            self.copies = mirror
        }

        func noteOn(_ pitch: Pitch, velocity: Int) {
            guard let note = UInt8(exactly: pitch.midiNumber), note < 128 else { return }
            let velocity = UInt8(min(max(velocity, 1), 127))
            node.startNote(note, withVelocity: velocity, onChannel: channel)
            copies.send(.noteOn(note: Int(note), velocity: Int(velocity), channel: Int(channel)))
        }

        func noteOff(_ pitch: Pitch) {
            guard let note = UInt8(exactly: pitch.midiNumber), note < 128 else { return }
            node.stopNote(note, onChannel: channel)
            copies.send(.noteOff(note: Int(note), channel: Int(channel)))
        }

        func setSustain(_ isDown: Bool) {
            control(64, isDown ? 127 : 0)
        }

        func allNotesOff() {
            control(64, 0)
            control(123, 0) // all notes off
            control(120, 0) // all sound off
        }

        private func control(_ number: UInt8, _ value: UInt8) {
            node.sendController(number, withValue: value, onChannel: channel)
            copies.send(.controller(number: Int(number), value: Int(value), channel: Int(channel)))
        }
    }
}
