import DesignSystem
import Foundation
import Library
import MidiIO
import MusicCore
import Observation
import Sound
import Practice
import SwiftUI
import Synchronization

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
    var section = AppSection.library
    /// Songs in the library, newest first.
    private(set) var songs: [SongEntry] = []
    /// The song open on the Practice screen.
    private(set) var session: PracticeSession?
    /// Why the last import or open failed; shown until dismissed.
    var libraryError: String?
    private(set) var soundStatus = SoundStatus.loading
    private(set) var latency: AudioEngine.Latency?
    /// Keys currently held, on any keyboard or with the mouse.
    private(set) var pressed: Set<Pitch> = []
    /// Keys shown by the on-screen keyboard.
    private(set) var range = KeyboardRange.fortyNineKeys

    @ObservationIgnored private let audio = AudioEngine()
    @ObservationIgnored private let piano = SamplerInstrument()
    @ObservationIgnored private let clicks = SamplerInstrument()
    @ObservationIgnored private let store: SongStore
    /// The open song's player, reachable from the MIDI thread so key presses are judged
    /// with their exact time.
    @ObservationIgnored private let activePlayer = PlayerBox()

    init(store: SongStore = .standard) {
        self.store = store
    }
    @ObservationIgnored private var isStarted = false

    func start() {
        guard !isStarted else { return }
        isStarted = true

        songs = store.entries()
        audio.attach(piano)
        audio.attach(clicks)
        do {
            try audio.start()
            latency = audio.latency
        } catch {
            soundStatus = .failed(error.localizedDescription)
            return
        }

        // Large SoundFonts take seconds to load; keep the window responsive meanwhile.
        let bank = SoundBank.piano()
        Task.detached(priority: .userInitiated) { [piano, clicks] in
            let status: SoundStatus
            // The metronome uses the drum kit built into macOS; without it the app still works.
            try? clicks.load(.system, percussion: true)
            do {
                try piano.load(bank)
                status = .ready(bank)
            } catch {
                status = .failed(error.localizedDescription)
            }
            await MainActor.run { self.soundStatus = status }
        }

        devices.start { [piano, activePlayer, weak self] event in
            // On the MIDI thread: make sound first, then tell the interface.
            switch event.kind {
            case let .noteOn(pitch, velocity):
                piano.noteOn(pitch, velocity: velocity)
                activePlayer.player?.playerPressed(pitch, at: event.seconds)
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

    // MARK: Library

    /// Copies files into the library. Failures are collected into `libraryError`.
    func importSongs(from urls: [URL]) {
        let store = store
        Task {
            let failures = await Task.detached(priority: .userInitiated) {
                urls.compactMap { url -> String? in
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    do {
                        try store.importFile(at: url)
                        return nil
                    } catch let SongStore.StoreError.unreadable(reason) {
                        return "\(url.lastPathComponent): \(reason)"
                    } catch SongStore.StoreError.unsupportedFile {
                        return "\(url.lastPathComponent): only MIDI and MusicXML files can be imported."
                    } catch {
                        return "\(url.lastPathComponent): \(error.localizedDescription)"
                    }
                }
            }.value
            songs = store.entries()
            libraryError = failures.isEmpty ? nil : failures.joined(separator: "\n")
        }
    }

    func delete(_ entry: SongEntry) {
        if session?.loaded.entry.id == entry.id { closeSong() }
        try? store.delete(entry)
        songs = store.entries()
    }

    /// Opens a song on the Practice screen.
    func open(_ entry: SongEntry) {
        let store = store
        Task {
            do {
                let loaded = try await Task.detached(priority: .userInitiated) { try store.load(entry) }.value
                session?.stop()
                let new = PracticeSession(loaded: loaded, piano: piano.voice(channel: 1), clicks: clicks) { run in
                    try? store.appendRun(run, for: entry)
                }
                // With a keyboard connected, start in the mode a learner wants: play it yourself, unhurried.
                if !devices.devices.isEmpty {
                    new.handMode = .both
                    new.waitsForPlayer = true
                }
                session = new
                activePlayer.player = new.player
                section = .practice
            } catch {
                libraryError = "\(entry.title): \(error.localizedDescription)"
            }
        }
    }

    func closeSong() {
        session?.stop()
        session = nil
        activePlayer.player = nil
        section = .library
    }

    // MARK: Playing

    func mouseDown(on pitch: Pitch) {
        piano.noteOn(pitch, velocity: 90)
        pressed.insert(pitch)
        session?.player.playerPressed(pitch)
    }

    func mouseUp(on pitch: Pitch) {
        piano.noteOff(pitch)
        pressed.remove(pitch)
        session?.released(pitch)
    }

    private func show(_ event: PerformanceEvent) {
        switch event.kind {
        case let .noteOn(pitch, _):
            pressed.insert(pitch)
            // Follow the keyboard's octave buttons.
            range = range.shifted(toContain: pitch)
        case let .noteOff(pitch):
            pressed.remove(pitch)
            session?.released(pitch)
        case .sustain:
            break
        }
    }
}

/// Holds the current song player where the MIDI thread can read it.
private final class PlayerBox: Sendable {
    private let storage = Mutex<SongPlayer?>(nil)

    var player: SongPlayer? {
        get { storage.withLock { $0 } }
        set { storage.withLock { $0 = newValue } }
    }
}
