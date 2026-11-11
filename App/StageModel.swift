import Foundation
import MusicCore
import Observation
import Practice
import Sketch
import Sound

/// Live mode: steps through the cues of a play, recalls each cue's sound, and plays its
/// recorded layer under the live keyboard (requirements LV-1 to LV-4).
@MainActor
@Observable
final class StageModel {
    /// Position in the cue sheet.
    private(set) var index = 0
    /// While locked, only the performing controls work: nothing can be edited and the
    /// stage cannot be left (requirement LV-4).
    var isLocked = true
    /// Cue whose recorded layer is sounding, if any.
    private(set) var playingCueID: UUID?
    /// Loudness of the recorded layer, 0 to 1.
    private(set) var level = 1.0
    /// Where the layer's loudness is heading: up, down, or nowhere.
    private(set) var fadeDirection = 0
    /// True while the play to perform is still being chosen.
    private(set) var isChoosing = true

    @ObservationIgnored private let sketchpad: SketchpadModel
    @ObservationIgnored private let piano: SamplerInstrument
    @ObservationIgnored private let palette: PaletteSynth
    @ObservationIgnored private let keyboard: LiveSound
    @ObservationIgnored private var isActive = false
    @ObservationIgnored private var playback: Playback?
    @ObservationIgnored private var ticker: Task<Void, Never>?

    /// A recorded layer in flight.
    private struct Playback {
        let cueID: UUID
        let take: Take
        let plan: LayerPlan
        let player: SongPlayer
        let voices: [any Instrument]
        let channels: [Int]
        var fade: Fade
        /// Set once the fade toward the cue's target length has begun.
        var startedAutoFade = false
    }

    /// Channels of the palette synth used on stage. The Sketchpad is silent meanwhile, so the
    /// layer channels are the ones it uses too.
    private enum Channel {
        static let main = 11
        static let second = 12
        static let layers = Array(1...8)
    }

    init(sketchpad: SketchpadModel, piano: SamplerInstrument, palette: PaletteSynth, keyboard: LiveSound) {
        self.sketchpad = sketchpad
        self.piano = piano
        self.palette = palette
        self.keyboard = keyboard
    }

    // MARK: Cue sheet (requirement LV-1)

    var play: Play? { sketchpad.play }
    var plays: [Play] { sketchpad.plays }
    var sheet: CueSheet { play.map(CueSheet.init) ?? CueSheet(Play(title: "")) }
    var current: CueSheet.Entry? {
        let entries = sheet.entries
        return entries.indices.contains(index) ? entries[index] : nil
    }
    var next: CueSheet.Entry? {
        let entries = sheet.entries
        return entries.indices.contains(index + 1) ? entries[index + 1] : nil
    }

    /// Call when the stage is shown or left.
    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        if active {
            isLocked = true
            isChoosing = true
            index = 0
        } else {
            stopLayer()
            palette.allNotesOff()
            keyboard.use(piano)
        }
    }

    /// Makes a play the current one and opens the stage on its first cue, locked.
    func choose(_ id: UUID) {
        guard isChoosing else { return }
        sketchpad.selectPlay(id)
        index = 0
        isLocked = true
        isChoosing = false
        recall()
    }

    /// Returns to the play chooser, silencing the layer. Ignored while locked.
    func changePlay() {
        guard !isLocked, !isChoosing else { return }
        stopLayer()
        palette.allNotesOff()
        keyboard.use(piano)
        isChoosing = true
    }

    /// Steps to the next cue and recalls its sound.
    func go() { select(sheet.index(stepping: 1, from: index)) }

    func back() { select(sheet.index(stepping: -1, from: index)) }

    func select(_ newIndex: Int) {
        guard !isChoosing, newIndex != index, sheet.entries.indices.contains(newIndex) else { return }
        index = newIndex
        // The layer of the cue just left bows out quickly instead of being cut.
        if playback != nil { fade(to: 0, over: 1) }
        recall()
    }

    /// Points the keyboard at the current cue's sound, split or layer.
    private func recall() {
        guard isActive, !isChoosing else { return }
        guard let preset = current?.cue.stagePreset else {
            keyboard.use(piano)
            return
        }
        let main = instrument(program: preset.program, channel: Channel.main)
        if let second = preset.second {
            keyboard.use(SplitInstrument(
                main: main, second: instrument(program: second.program, channel: Channel.second),
                splitAt: second.splitAt.map(Pitch.init(midiNumber:))
            ))
        } else {
            keyboard.use(main)
        }
    }

    private func instrument(program: Int?, channel: Int) -> any Instrument {
        guard let program else { return piano }
        palette.setProgram(program, channel: channel)
        palette.setVolume(1, channel: channel)
        return palette.voice(channel: channel)
    }

    /// Changes the current cue's preset. Ignored while locked.
    func updatePreset(_ change: (inout StagePreset) -> Void) {
        guard !isLocked, let cue = current?.cue else { return }
        var preset = cue.stagePreset
        change(&preset)
        guard preset != cue.stagePreset else { return }
        sketchpad.updatePlay { $0.updateCue(cue.id) { $0.stage = preset } }
        recall()
    }

    // MARK: Recorded layer (requirements LV-2, LV-3)

    /// The take the current cue plays, when it has one with notes in it.
    var layerTake: Take? {
        guard let take = current?.cue.bestTake, take.noteCount > 0 else { return nil }
        return take
    }

    /// How the current cue's layer would run, or is running.
    var plan: LayerPlan? {
        guard let cue = current?.cue else { return nil }
        if let playback, playback.cueID == cue.id { return playback.plan }
        return layerTake.map { LayerPlan(take: $0, preset: cue.stagePreset, targetSeconds: cue.targetSeconds) }
    }

    /// True while the current cue's own layer is sounding.
    var isPlaying: Bool { playingCueID != nil && playingCueID == current?.cue.id }

    /// Seconds into the layer; cheap enough to call every frame.
    var elapsed: Double {
        guard let playback else { return 0 }
        return min(playback.plan.seconds(atBeat: playback.player.beat, bpm: playback.take.bpm), playback.plan.duration)
    }

    /// Starts the current cue's layer from the top.
    /// - Parameter fadingIn: start silent and rise to full instead of starting at full.
    func playLayer(fadingIn: Bool = false) {
        stopLayer()
        guard !isChoosing, let cue = current?.cue, let take = layerTake else { return }
        let (song, layerOfNote) = take.song(title: cue.name)
        let plan = LayerPlan(take: take, preset: cue.stagePreset, targetSeconds: cue.targetSeconds)
        let now = SongPlayer.now
        let fade = fadingIn ? Fade(from: 0, to: 1, start: now, duration: LayerPlan.fadeSeconds) : .steady(1)

        // Every layer goes through the palette synth, the piano included: its channels can be
        // turned down one by one, which the sampled grand piano cannot.
        let channels = take.layers.indices.map { Channel.layers[$0 % Channel.layers.count] }
        for (layer, channel) in zip(take.layers, channels) {
            palette.setProgram(layer.program ?? 0, channel: channel)
            palette.setVolume(fade.level(at: now), channel: channel)
        }
        let voices = channels.map { palette.voice(channel: $0) }
        let relay = Relay()
        let player = SongPlayer(song: song) { event in
            switch event {
            case let .noteOn(note): voices[layerOfNote[note.id]].noteOn(note.pitch, velocity: note.velocity)
            case let .noteOff(note): voices[layerOfNote[note.id]].noteOff(note.pitch)
            case .allNotesOff:
                for voice in voices { voice.allNotesOff() }
            case .finished:
                for voice in voices { voice.allNotesOff() }
                Task { @MainActor in relay.model?.layerEnded(cue.id) }
            case .click, .judged, .wrongKey, .waiting, .resumed, .judgementsCleared: break
            }
        }
        relay.model = self
        player.setRate(plan.rate)
        player.play()
        playback = Playback(
            cueID: cue.id, take: take, plan: plan, player: player, voices: voices,
            channels: Array(Set(channels)), fade: fade
        )
        playingCueID = cue.id
        level = fade.level(at: now)
        fadeDirection = fadingIn ? 1 : 0
        startTicker()
    }

    /// Brings the layer up: starts it silent if it is not playing, or turns a fade-out round.
    func fadeIn() {
        if playback == nil || !isPlaying {
            playLayer(fadingIn: true)
        } else {
            fade(to: 1, over: LayerPlan.fadeSeconds)
        }
    }

    /// Takes the layer down to silence, then stops it.
    func fadeOut() {
        fade(to: 0, over: LayerPlan.fadeSeconds)
    }

    private func fade(to target: Double, over seconds: Double) {
        guard var playback else { return }
        playback.fade = playback.fade.turning(to: target, at: SongPlayer.now, fullDuration: seconds)
        // A fade asked for by hand replaces the automatic one.
        playback.startedAutoFade = true
        self.playback = playback
        fadeDirection = target > level ? 1 : target < level ? -1 : 0
    }

    func stopLayer() {
        ticker?.cancel()
        ticker = nil
        guard let playback else { return }
        self.playback = nil
        playback.player.pause()
        for voice in playback.voices { voice.allNotesOff() }
        // Leave the channels at full for whoever uses them next.
        for channel in playback.channels { palette.setVolume(1, channel: channel) }
        playingCueID = nil
        level = 1
        fadeDirection = 0
    }

    /// Silences the layer and the keyboard at once (requirement LV-6).
    func panic() {
        stopLayer()
        keyboard.current.allNotesOff()
    }

    private func layerEnded(_ cueID: UUID) {
        if playback?.cueID == cueID { stopLayer() }
    }

    /// Moves the layer's loudness along its fade, fifty times a second.
    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(20))
                guard !Task.isCancelled, let self else { return }
                self.tick()
            }
        }
    }

    private func tick() {
        guard var playback else { return }
        let now = SongPlayer.now
        if !playback.startedAutoFade, let start = playback.plan.fadeOutStart, elapsed >= start {
            playback.startedAutoFade = true
            playback.fade = playback.fade.turning(to: 0, at: now, fullDuration: LayerPlan.fadeSeconds)
            self.playback = playback
            fadeDirection = -1
        }
        let newLevel = playback.fade.level(at: now)
        if newLevel != level {
            for channel in playback.channels { palette.setVolume(newLevel, channel: channel) }
            level = newLevel
        }
        if playback.fade.isOver(at: now) {
            if playback.fade.to == 0 {
                stopLayer()
            } else if fadeDirection != 0 {
                fadeDirection = 0
            }
        }
    }
}

/// Lets a player's callback reach the model created before it.
@MainActor
private final class Relay: Sendable {
    weak var model: StageModel?
}
