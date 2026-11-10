import Foundation
import MusicCore
import Testing
@testable import Sound

/// These use the Mac's real audio output, so they need an output device to be present.
@Suite struct SoundTests {
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
}
