import DesignSystem
import MidiIO
import MusicCore
import Observation
import Sound
import SwiftUI

/// App-wide state: connected keyboards, the piano sound, and which keys are down.
@MainActor
@Observable
final class AppModel {
    enum SoundStatus: Equatable {
        case loading
        case ready(SoundBank)
        case failed(String)
    }

    let devices = DeviceManager()
    private(set) var soundStatus = SoundStatus.loading
    private(set) var latency: AudioEngine.Latency?
    /// Keys currently held, on any keyboard or with the mouse.
    private(set) var pressed: Set<Pitch> = []
    /// Keys shown by the on-screen keyboard.
    private(set) var range = KeyboardRange.fortyNineKeys

    @ObservationIgnored private let audio = AudioEngine()
    @ObservationIgnored private let piano = SamplerInstrument()
    @ObservationIgnored private var isStarted = false

    func start() {
        guard !isStarted else { return }
        isStarted = true

        audio.attach(piano)
        do {
            try audio.start()
            latency = audio.latency
        } catch {
            soundStatus = .failed(error.localizedDescription)
            return
        }

        // Large SoundFonts take seconds to load; keep the window responsive meanwhile.
        let bank = SoundBank.piano()
        Task.detached(priority: .userInitiated) { [piano] in
            let status: SoundStatus
            do {
                try piano.load(bank)
                status = .ready(bank)
            } catch {
                status = .failed(error.localizedDescription)
            }
            await MainActor.run { self.soundStatus = status }
        }

        devices.start { [piano, weak self] event in
            // On the MIDI thread: make sound first, then tell the interface.
            switch event.kind {
            case let .noteOn(pitch, velocity): piano.noteOn(pitch, velocity: velocity)
            case let .noteOff(pitch): piano.noteOff(pitch)
            case let .sustain(isDown): piano.setSustain(isDown)
            }
            Task { @MainActor in self?.show(event) }
        }
    }

    /// Call when the set of connected keyboards changes.
    func devicesChanged() {
        // A key held on a keyboard that was just unplugged would otherwise sound forever.
        piano.allNotesOff()
        pressed.removeAll()
        range = devices.devices.mainInstrument?.profile.range ?? .fortyNineKeys
        latency = audio.latency
    }

    func mouseDown(on pitch: Pitch) {
        piano.noteOn(pitch, velocity: 90)
        pressed.insert(pitch)
    }

    func mouseUp(on pitch: Pitch) {
        piano.noteOff(pitch)
        pressed.remove(pitch)
    }

    private func show(_ event: PerformanceEvent) {
        switch event.kind {
        case let .noteOn(pitch, _):
            pressed.insert(pitch)
            // Follow the keyboard's octave buttons.
            range = range.shifted(toContain: pitch)
        case let .noteOff(pitch):
            pressed.remove(pitch)
        case .sustain:
            break
        }
    }
}
