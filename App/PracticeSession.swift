import DesignSystem
import Library
import MusicCore
import Observation
import Practice
import Sound
import SwiftUI

/// One song open for practice: its player and the settings chosen for it.
@MainActor
@Observable
final class PracticeSession {
    let loaded: LoadedSong
    var song: Song { loaded.song }

    private(set) var isPlaying = false
    /// Playback speed as a fraction of the song's tempo: 0.25...1.5 (requirement SP-5).
    var rate = 1.0 { didSet { player.setRate(rate) } }
    var metronomeIsOn = false { didSet { player.setMetronome(metronomeIsOn) } }
    var countInIsOn = true
    /// Keys the app is sounding right now, with the hand they belong to.
    private(set) var sounding: [Pitch: Hand] = [:]

    @ObservationIgnored private var player: SongPlayer!

    /// - Parameters:
    ///   - piano: plays the song's notes.
    ///   - clicks: a percussion instrument for the metronome.
    init(loaded: LoadedSong, piano: any Instrument, clicks: any Instrument) {
        self.loaded = loaded
        player = SongPlayer(song: loaded.song) { [weak self] event in
            // On the player's queue: sound first, then tell the interface.
            switch event {
            case let .noteOn(note): piano.noteOn(note.pitch, velocity: note.velocity)
            case let .noteOff(note): piano.noteOff(note.pitch)
            case let .click(isDownbeat):
                // General MIDI percussion: 76 is the high wood block, 77 the low one.
                clicks.noteOn(Pitch(midiNumber: isDownbeat ? 76 : 77), velocity: isDownbeat ? 110 : 80)
            case .allNotesOff, .finished: piano.allNotesOff()
            }
            Task { @MainActor in self?.show(event) }
        }
    }

    /// Current position in beats; cheap enough to call every frame.
    var beat: Double { player.beat }

    func togglePlay() {
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            let measure = song.measure(atBeat: max(beat, 0))
            player.play(countInBeats: countInIsOn ? measure?.length ?? 4 : 0)
            isPlaying = true
        }
    }

    func restart() {
        seek(to: 0)
    }

    func seek(to beat: Double) {
        player.seek(to: beat)
        sounding.removeAll()
    }

    func stop() {
        player.pause()
        isPlaying = false
        sounding.removeAll()
    }

    private func show(_ event: PlaybackEngine.Event) {
        switch event {
        case let .noteOn(note): sounding[note.pitch] = note.hand
        case let .noteOff(note): sounding[note.pitch] = nil
        case .allNotesOff: sounding.removeAll()
        case .finished:
            sounding.removeAll()
            isPlaying = false
        case .click: break
        }
    }
}
