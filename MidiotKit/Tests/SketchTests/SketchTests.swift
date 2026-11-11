import Foundation
import MusicCore
import Testing
@testable import Sketch

@Suite struct CaptureTests {
    @Test func keepsNotesThatStartInsideTheWindow() {
        var history = CaptureHistory()
        history.record(.noteOn(pitch: 60, velocity: 90), at: 10)
        history.record(.noteOff(pitch: 60), at: 11)
        history.record(.noteOn(pitch: 64, velocity: 70), at: 50)
        history.record(.noteOff(pitch: 64), at: 50.5)

        let recent = history.notes(from: 40, to: 60)
        #expect(recent == [.init(pitch: 64, velocity: 70, start: 50, end: 50.5)])
        #expect(history.notes(from: 0, to: 60).count == 2)
    }

    @Test func aHeldKeyEndsAtTheEndOfTheWindow() {
        var history = CaptureHistory()
        history.record(.noteOn(pitch: 60, velocity: 90), at: 5)
        #expect(history.notes(from: 0, to: 8) == [.init(pitch: 60, velocity: 90, start: 5, end: 8)])
    }

    @Test func theSustainPedalLengthensNotes() {
        var history = CaptureHistory()
        history.record(.sustain(isDown: true), at: 0)
        history.record(.noteOn(pitch: 60, velocity: 90), at: 1)
        history.record(.noteOff(pitch: 60), at: 1.2)
        history.record(.sustain(isDown: false), at: 3)
        #expect(history.notes(from: 0, to: 10).first?.end == 3)
    }

    @Test func oldPlayingIsForgotten() {
        var history = CaptureHistory(retention: 100)
        history.record(.noteOn(pitch: 60, velocity: 90), at: 0)
        history.record(.noteOff(pitch: 60), at: 1)
        history.record(.noteOn(pitch: 62, velocity: 90), at: 500)
        #expect(history.notes(from: 0, to: 600).map(\.pitch) == [62])
    }

    @Test func eventsOutOfOrderAreSorted() {
        var history = CaptureHistory()
        history.record(.noteOff(pitch: 60), at: 2)
        history.record(.noteOn(pitch: 60, velocity: 80), at: 1)
        #expect(history.notes(from: 0, to: 5) == [.init(pitch: 60, velocity: 80, start: 1, end: 2)])
    }

    @Test func activityShowsWhereThePlayingWas() {
        var history = CaptureHistory()
        for step in 0..<6 { history.record(.noteOn(pitch: 60 + step, velocity: 127), at: 95 + Double(step) * 0.1) }
        let activity = history.activity(buckets: 10, window: 100, now: 100)
        #expect(activity.count == 10)
        #expect(activity[9] == 1)
        #expect(activity[..<9].allSatisfy { $0 == 0 })
    }

    @Test func aTakeStartsAtItsFirstNote() throws {
        let played: [CaptureHistory.PlayedNote] = [
            .init(pitch: 60, velocity: 90, start: 100, end: 100.5),
            .init(pitch: 64, velocity: 90, start: 101, end: 102),
        ]
        let take = try #require(Take(played: played, number: 1, bpm: 120))
        #expect(take.layers[0].notes.map(\.start) == [0, 2])
        #expect(take.layers[0].notes.map(\.duration) == [1, 2])
        #expect(take.seconds == 2)
        #expect(Take(played: [], number: 1, bpm: 120) == nil)
    }
}

@Suite struct TakeEditingTests {
    private let take = Take(number: 1, bpm: 120, layers: [
        Layer(notes: [
            SketchNote(pitch: 60, start: 1.1, duration: 0.4),
            SketchNote(pitch: 64, start: 2.6, duration: 1.3),
        ]),
        Layer(notes: [SketchNote(pitch: 36, start: 1.0, duration: 4)], program: 48),
    ])

    @Test func trimMovesTheFirstNoteToTheStart() {
        let trimmed = take.trimmed()
        #expect(trimmed.layers[1].notes[0].start == 0)
        #expect(abs(trimmed.layers[0].notes[0].start - 0.1) < 1e-9)
    }

    @Test func trimToARangeCutsNotesAtItsEdges() {
        let trimmed = take.trimmed(to: 2...3)
        #expect(trimmed.layers[0].notes.count == 1)
        #expect(abs(trimmed.layers[0].notes[0].start - 0.6) < 1e-9)
        #expect(abs(trimmed.layers[0].notes[0].duration - 0.4) < 1e-9)
        #expect(trimmed.layers[1].notes[0] == SketchNote(pitch: 36, start: 0, duration: 1))
    }

    @Test func quantizeSnapsToTheGrid() {
        let quantized = take.quantized(grid: 0.5)
        #expect(quantized.layers[0].notes.map(\.start) == [1, 2.5])
        #expect(quantized.layers[0].notes.map(\.duration) == [0.5, 1.5])
    }

    @Test func transposeStaysInsideTheMIDIRange() {
        #expect(take.transposed(by: 2).layers[0].notes.map(\.pitch) == [62, 66])
        // 36 − 40 would be below zero, so the shift is raised by octaves.
        #expect(take.transposed(by: -40).pitchSpan == 8...36)
    }

    @Test func deletingNotesDropsEmptyLayers() {
        let deleted = take.deleting([NoteRef(layer: 1, index: 0), NoteRef(layer: 0, index: 0)])
        #expect(deleted.layers.count == 1)
        #expect(deleted.layers[0].notes.map(\.pitch) == [64])
        let emptied = take.deleting([NoteRef(layer: 0, index: 0), NoteRef(layer: 0, index: 1), NoteRef(layer: 1, index: 0)])
        #expect(emptied.layers.count == 1)
        #expect(emptied.noteCount == 0)
    }

    @Test func theSongRemembersEachNotesLayer() {
        let (song, layers) = take.song(title: "Take")
        #expect(song.notes.map(\.pitch.midiNumber) == [36, 60, 64])
        #expect(layers == [1, 0, 0])
        #expect(song.notes.map(\.hand) == [.left, .right, .right])
        #expect(song.tempoMap.bpm(atBeat: 0) == 120)
        #expect(song.measures.count == 2)
    }
}

@Suite struct HarmonyTests {
    private func chord(_ numbers: Int...) -> String? {
        Chord.detect(numbers.map(Pitch.init(midiNumber:)))?.name()
    }

    @Test func namesCommonChords() {
        #expect(chord(60, 64, 67) == "C")
        #expect(chord(62, 65, 69) == "Dm")
        #expect(chord(59, 62, 65) == "Bdim")
        #expect(chord(55, 59, 62, 65) == "G7")
        #expect(chord(60, 64, 67, 71) == "Cmaj7")
        #expect(chord(62, 65, 69, 72) == "Dm7")
        #expect(chord(50, 65, 69, 72, 76) == "Dm9")
        #expect(chord(60, 65, 67) == "Csus4")
        #expect(chord(48, 55) == "C5")
    }

    @Test func namesInversionsByTheirBass() {
        #expect(chord(64, 67, 72) == "C/E")
        // The same four notes read as C6 over C and as Am7 over A.
        #expect(chord(60, 64, 67, 69) == "C6")
        #expect(chord(57, 60, 64, 67) == "Am7")
    }

    @Test func toleratesAMissingFifthButNotNoise() {
        #expect(chord(55, 59, 65) == "G7")
        #expect(chord(60) == nil)
        #expect(chord(60, 61, 62, 63, 64) == nil)
    }

    @Test func spellsRootsToSuitTheKey() {
        let chord = Chord(root: 10, quality: .major7)
        #expect(chord.name() == "B♭maj7")
        #expect(chord.name(fifths: 3) == "A♯maj7")
        #expect(Chord(root: 6, quality: .minor).name(fifths: -4) == "G♭m")
    }

    @Test func findsTheKey() {
        // C major scale with the tonic and dominant held longest.
        let major = [(60, 4.0), (62, 1), (64, 2), (65, 1), (67, 3), (69, 1), (71, 1)].map { (pitch: $0.0, duration: $0.1) }
        #expect(SketchKey.detect(notes: major) == SketchKey(tonic: 0, isMinor: false))
        let minor = [(57, 4.0), (59, 1), (60, 2), (62, 1), (64, 3), (65, 1), (68, 1)].map { (pitch: $0.0, duration: $0.1) }
        #expect(SketchKey.detect(notes: minor) == SketchKey(tonic: 9, isMinor: true))
        #expect(SketchKey.detect(notes: [(pitch: 60, duration: 1.0)]) == nil)
    }

    @Test func keySignatures() {
        #expect(SketchKey(tonic: 0, isMinor: false).fifths == 0)
        #expect(SketchKey(tonic: 2, isMinor: true).fifths == -1)
        #expect(SketchKey(tonic: 10, isMinor: false).fifths == -2)
        #expect(SketchKey(tonic: 4, isMinor: false).fifths == 4)
        #expect(SketchKey(tonic: 10, isMinor: false).tonicName == "B♭")
    }

    @Test func suggestsWhereToGoNext() {
        let key = SketchKey(tonic: 0, isMinor: false)
        let afterTonic = ChordSuggestion.next(after: Chord(root: 0, quality: .major), in: key)
        #expect(afterTonic.map { $0.chord.name() } == ["F", "G7", "Am"])
        #expect(afterTonic.map(\.effect) == [.opens, .tension, .darker])

        let afterDominant = ChordSuggestion.next(after: Chord(root: 7, quality: .dominant7), in: key)
        #expect(afterDominant.map { $0.chord.name() } == ["C", "Am", "F"])
        #expect(afterDominant.map(\.effect) == [.home, .surprise, .opens])

        // Without a key, the chord is treated as home.
        let alone = ChordSuggestion.next(after: Chord(root: 2, quality: .minor9), in: nil)
        #expect(alone.map { $0.chord.name(fifths: -1) } == ["Gm", "B♭", "A7"])
    }

    @Test func voicingsArePlayable() {
        for root in 0..<12 {
            let voicing = Chord(root: root, quality: .dominant9).voicing
            #expect(voicing.allSatisfy { (36...76).contains($0.midiNumber) })
            #expect(Chord.detect(voicing)?.root == root)
        }
    }
}

@Suite struct PlayTests {
    @Test func cuesAreLabelledBySceneAndLetter() {
        let cues = (0..<28).map { Cue(name: "Cue \($0)") }
        let play = Play(title: "Dream", scenes: [PlayScene(title: "Act I", cues: [Cue(name: "Overture")]), PlayScene(title: "Act II", cues: cues)])
        #expect(play.label(of: play.scenes[0].cues[0].id) == "1A")
        #expect(play.label(of: cues[1].id) == "2B")
        #expect(play.label(of: cues[25].id) == "2Z")
        #expect(play.label(of: cues[26].id) == "2AA")
        #expect(play.label(of: UUID()) == nil)
        #expect(play.cueCount == 29)
    }

    @Test func theBestTakeIsTheKeeperElseTheNewest() {
        var cue = Cue(name: "Dawn")
        #expect(cue.bestTake == nil)
        cue.takes = [Take(number: 1, bpm: 90, layers: []), Take(number: 2, bpm: 90, layers: [])]
        #expect(cue.bestTake?.number == 2)
        cue.takes[0].isKeeper = true
        #expect(cue.bestTake?.number == 1)
    }

    @Test func playsSurviveBeingSavedAndLoaded() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("midiot-plays-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PlayStore(root: root)
        #expect(store.plays().isEmpty)

        let take = Take(number: 1, createdAt: Date(timeIntervalSince1970: 1_800_000_000), bpm: 72, layers: [
            Layer(notes: [SketchNote(pitch: 62, start: 0, duration: 1.5, velocity: 64)], program: 88),
        ], isKeeper: true)
        var play = Play(
            title: "A Midsummer Night’s Dream", opensOn: Date(timeIntervalSince1970: 1_810_000_000),
            createdAt: Date(timeIntervalSince1970: 1_799_000_000),
            scenes: [PlayScene(title: "Act III", cues: [
                Cue(name: "Forest at night", note: "Under Puck’s line.", targetSeconds: 45, status: .draft, mood: .mystery, takes: [take]),
            ])]
        )
        try store.save(play)
        #expect(store.plays() == [play])

        play.updateCue(play.scenes[0].cues[0].id) { $0.status = .ready }
        try store.save(play)
        #expect(store.plays().first?.scenes[0].cues[0].status == .ready)

        try store.delete(play)
        #expect(store.plays().isEmpty)
    }

    @Test func everyMoodHasAPalette() {
        #expect(Set(MoodPalette.all.map(\.id)) == Set(MoodPalette.Mood.allCases))
        #expect(MoodPalette.palette(for: .mystery).scales == [.dorian, .wholeTone])
        #expect(SketchSound.catalog.count == Set(SketchSound.catalog.map(\.id)).count)
        for palette in MoodPalette.all {
            #expect(palette.sounds.allSatisfy { SketchSound.catalog.contains($0) })
        }
    }
}
