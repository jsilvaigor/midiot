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
    }

    /// The instrument that plays on one channel.
    public func voice(channel: Int) -> any Instrument {
        Voice(node: node, channel: UInt8(min(max(channel, 0), 15)))
    }

    /// Silences every channel.
    public func allNotesOff() {
        for channel in 0..<16 { voice(channel: channel).allNotesOff() }
    }

    private final class Voice: Instrument, @unchecked Sendable {
        let node: AVAudioUnitMIDIInstrument
        let channel: UInt8

        init(node: AVAudioUnitMIDIInstrument, channel: UInt8) {
            self.node = node
            self.channel = channel
        }

        func noteOn(_ pitch: Pitch, velocity: Int) {
            guard let note = UInt8(exactly: pitch.midiNumber), note < 128 else { return }
            node.startNote(note, withVelocity: UInt8(min(max(velocity, 1), 127)), onChannel: channel)
        }

        func noteOff(_ pitch: Pitch) {
            guard let note = UInt8(exactly: pitch.midiNumber), note < 128 else { return }
            node.stopNote(note, onChannel: channel)
        }

        func setSustain(_ isDown: Bool) {
            node.sendController(64, withValue: isDown ? 127 : 0, onChannel: channel)
        }

        func allNotesOff() {
            node.sendController(64, withValue: 0, onChannel: channel)
            node.sendController(123, withValue: 0, onChannel: channel)
            node.sendController(120, withValue: 0, onChannel: channel)
        }
    }
}
