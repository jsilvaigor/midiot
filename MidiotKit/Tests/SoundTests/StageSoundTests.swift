import AVFoundation
import MusicCore
import Synchronization
import Testing
@testable import Sound

private final class Recorder: Instrument {
    let log = Mutex<[String]>([])
    func noteOn(_ pitch: Pitch, velocity: Int) { log.withLock { $0.append("on \(pitch.midiNumber)") } }
    func noteOff(_ pitch: Pitch) { log.withLock { $0.append("off \(pitch.midiNumber)") } }
    func setSustain(_ isDown: Bool) { log.withLock { $0.append("pedal \(isDown)") } }
    func allNotesOff() { log.withLock { $0.append("silence") } }
    var events: [String] { log.withLock { $0 } }
}

@Suite struct FadeTests {
    @Test func aFadeIsAStraightLine() {
        let fade = Fade(from: 0, to: 1, start: 10, duration: 4)
        #expect(fade.level(at: 9) == 0)
        #expect(fade.level(at: 11) == 0.25)
        #expect(fade.level(at: 14) == 1)
        #expect(fade.level(at: 99) == 1)
        #expect(!fade.isOver(at: 13.9))
        #expect(fade.isOver(at: 14))
        #expect(Fade.steady(0.5).level(at: 3) == 0.5)
    }

    @Test func turningRoundStartsFromTheCurrentLevel() {
        let out = Fade(from: 1, to: 0, start: 0, duration: 4)
        // A quarter of the way out, fade back in: no jump, and only a quarter of the time.
        let back = out.turning(to: 1, at: 1, fullDuration: 4)
        #expect(back.level(at: 1) == 0.75)
        #expect(back.duration == 1)
        #expect(back.level(at: 2) == 1)
    }
}

@Suite struct SplitInstrumentTests {
    @Test func aSplitSendsLowKeysToTheSecondSound() {
        let main = Recorder(), second = Recorder()
        let split = SplitInstrument(main: main, second: second, splitAt: .middleC)
        split.noteOn(Pitch(midiNumber: 59), velocity: 80)
        split.noteOn(.middleC, velocity: 80)
        split.noteOff(Pitch(midiNumber: 59))
        split.noteOff(.middleC)
        #expect(main.events == ["on 60", "off 60"])
        #expect(second.events == ["on 59", "off 59"])
    }

    @Test func aLayerPlaysBothSoundsOnEveryKey() {
        let main = Recorder(), second = Recorder()
        let layer = SplitInstrument(main: main, second: second, splitAt: nil)
        layer.noteOn(.middleC, velocity: 80)
        layer.setSustain(true)
        layer.allNotesOff()
        #expect(main.events == ["on 60", "pedal true", "silence"])
        #expect(second.events == main.events)
    }
}

// In the `SoundTests` suite so it never runs beside another audio engine.
extension SoundTests {
    /// Renders without an output device: turning one channel down must not quieten another,
    /// or a fading layer would take the live playing with it.
    @Test func aChannelFadesWithoutTouchingTheOthers() throws {
        let engine = AVAudioEngine()
        let synth = PaletteSynth()
        engine.attach(synth.node)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        engine.connect(synth.node, to: engine.mainMixerNode, format: format)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        try engine.start()
        try synth.load(.system)
        synth.setProgram(19, channel: 0)
        synth.setProgram(19, channel: 1)
        let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4096)!

        func peak(channel: Int) throws -> Float {
            let voice = synth.voice(channel: channel)
            voice.noteOn(.middleC, velocity: 100)
            var peak: Float = 0
            for _ in 0..<6 {
                _ = try engine.renderOffline(4096, to: buffer)
                let samples = UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength))
                peak = max(peak, samples.map(abs).max() ?? 0)
            }
            voice.allNotesOff()
            for _ in 0..<20 { _ = try engine.renderOffline(4096, to: buffer) }
            return peak
        }

        let full = try peak(channel: 1)
        synth.setVolume(0.1, channel: 1)
        let quiet = try peak(channel: 1)
        let other = try peak(channel: 0)
        synth.setVolume(1, channel: 1)
        let restored = try peak(channel: 1)
        #expect(full > 0.001)
        #expect(quiet < full * 0.2)
        #expect(other > full * 0.8)
        #expect(restored > full * 0.8)
    }

    /// MIDI out: everything a synth is told reaches the copy, and a late listener is first
    /// told which sound each channel has.
    @Test func whatASynthPlaysIsCopiedOut() throws {
        let engine = AVAudioEngine()
        let synth = PaletteSynth()
        let piano = SamplerInstrument()
        engine.attach(synth.node)
        engine.attach(piano.node)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        engine.connect(synth.node, to: engine.mainMixerNode, format: format)
        engine.connect(piano.node, to: engine.mainMixerNode, format: format)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        try engine.start()
        try synth.load(.system)
        synth.setProgram(48, channel: 3)

        let sent = Mutex<[ChannelMessage]>([])
        synth.mirror { message in sent.withLock { $0.append(message) } }
        #expect(sent.withLock { $0 } == [.program(48, channel: 3)])

        sent.withLock { $0 = [] }
        let voice = synth.voice(channel: 3)
        voice.noteOn(.middleC, velocity: 80)
        synth.setVolume(0.5, channel: 3)
        voice.setSustain(true)
        voice.noteOff(.middleC)
        synth.setProgram(19, channel: 4)
        #expect(sent.withLock { $0 } == [
            .noteOn(note: 60, velocity: 80, channel: 3),
            .controller(number: 7, value: 64, channel: 3),
            .controller(number: 64, value: 127, channel: 3),
            .noteOff(note: 60, channel: 3),
            .program(19, channel: 4),
        ])

        // Every voice of the piano goes out on the one channel asked for.
        sent.withLock { $0 = [] }
        piano.mirror(to: { message in sent.withLock { $0.append(message) } }, channel: 0)
        piano.voice(channel: 2).noteOn(.middleC, velocity: 70)
        piano.voice(channel: 2).noteOff(.middleC)
        #expect(sent.withLock { $0 } == [.noteOn(note: 60, velocity: 70, channel: 0), .noteOff(note: 60, channel: 0)])

        // Stopping the copy and muting the sound are separate things.
        synth.mirror(to: nil)
        sent.withLock { $0 = [] }
        voice.noteOn(.middleC, velocity: 80)
        voice.noteOff(.middleC)
        #expect(sent.withLock { $0.isEmpty })
        synth.isMuted = true
        #expect(synth.isMuted)
        synth.isMuted = false
        #expect(!synth.isMuted)
        engine.stop()
    }
}
