import AVFoundation
import Foundation
import MusicCore
import Testing
@testable import Sound

/// These use the Mac's real audio output, so they need an output device to be present.
/// One at a time: Core Audio aborts when two engines start in the same instant.
@Suite(.serialized) struct SoundTests {
    @Test func engineStartsAndLoadsTheSystemPiano() throws {
        let engine = AudioEngine()
        let piano = SamplerInstrument()
        engine.attach(piano)
        try engine.start()
        try piano.load(.system)

        // Silent smoke test of the note path.
        piano.noteOn(.middleC, velocity: 1)
        piano.noteOff(.middleC)
        piano.allNotesOff()

        let latency = engine.latency
        #expect(latency.buffer > 0)
        // The app asks for a 128-frame buffer; anything under 10 ms meets requirement SN-5.
        #expect(latency.buffer < 0.010)
        print("buffer \(latency.buffer * 1000) ms, device \(latency.device * 1000) ms")
    }

    @Test func fallsBackToSystemSoundsWithoutABundledSoundFont() {
        #expect(SoundBank.piano(in: Bundle(for: SamplerInstrument.self)).isSystemFallback)
    }

    @Test func choosesBanksByName() {
        let piano = URL(fileURLWithPath: "/x/SalamanderGrandPiano-V3+20200602.sf2")
        let general = URL(fileURLWithPath: "/x/GeneralUser-GS.sf2")
        #expect(SoundBank.choose(from: [general, piano], isPalette: false).url == piano)
        #expect(SoundBank.choose(from: [general, piano], isPalette: true).url == general)
        #expect(SoundBank.choose(from: [piano], isPalette: true).isSystemFallback)
        #expect(SoundBank.choose(from: [general], isPalette: false).isSystemFallback)
    }

    /// Renders without an output device and checks that each channel makes its own sound.
    @Test func thePaletteSynthSoundsDifferentProgramsOnDifferentChannels() throws {
        let engine = AVAudioEngine()
        let synth = PaletteSynth()
        engine.attach(synth.node)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        engine.connect(synth.node, to: engine.mainMixerNode, format: format)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        try engine.start()
        try synth.load(.system)

        func peak(program: Int, channel: Int) throws -> Float {
            synth.setProgram(program, channel: channel)
            let voice = synth.voice(channel: channel)
            voice.noteOn(.middleC, velocity: 100)
            var peak: Float = 0
            let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4096)!
            for _ in 0..<6 {
                _ = try engine.renderOffline(4096, to: buffer)
                let samples = UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength))
                peak = max(peak, samples.map(abs).max() ?? 0)
            }
            voice.allNotesOff()
            for _ in 0..<12 { _ = try engine.renderOffline(4096, to: buffer) }
            return peak
        }

        // Strings on one channel, a celesta on another, then strings again.
        #expect(try peak(program: 48, channel: 1) > 0.001)
        #expect(try peak(program: 8, channel: 2) > 0.001)
        #expect(try peak(program: 48, channel: 1) > 0.001)
    }
}
