import Testing
@testable import MusicCore

@Suite struct FingeringTests {
    func song(_ pitches: [[Int]], hand: Hand) -> Song {
        var notes: [Note] = []
        for (beat, chord) in pitches.enumerated() {
            for pitch in chord { notes.append(Note(id: 0, pitch: Pitch(midiNumber: pitch), start: Double(beat), duration: 1, hand: hand)) }
        }
        return Song(title: "T", notes: notes, tempoMap: TempoMap(bpm: 60), measures: Song.evenMeasures(beatsPerMeasure: 4, covering: Double(pitches.count)))
    }

    func fingers(_ song: Song) -> [Int?] { song.suggestingFingering().notes.map(\.finger) }

    @Test func rightHandScaleUsesTheThumbUnder() {
        let up = [60, 62, 64, 65, 67, 69, 71, 72].map { [$0] }
        #expect(fingers(song(up, hand: .right)) == [1, 2, 3, 1, 2, 3, 4, 5])
        #expect(fingers(song(up.reversed(), hand: .right)) == [5, 4, 3, 2, 1, 3, 2, 1])
    }

    @Test func leftHandMirrorsTheRight() {
        let up = [48, 50, 52, 53, 55, 57, 59, 60].map { [$0] }
        #expect(fingers(song(up, hand: .left)) == [5, 4, 3, 2, 1, 3, 2, 1])
    }

    @Test func fiveNotesStayInOnePosition() {
        #expect(fingers(song([[60], [62], [64], [65], [67], [65], [64], [62], [60]], hand: .right)) == [1, 2, 3, 4, 5, 4, 3, 2, 1])
    }

    @Test func chordsGetStandardShapes() {
        #expect(fingers(song([[60, 64, 67]], hand: .right)) == [1, 3, 5])
        #expect(fingers(song([[64, 67, 72]], hand: .right)) == [1, 2, 5])
        // Left hand: little finger on the bottom.
        #expect(fingers(song([[48, 52, 55]], hand: .left)) == [5, 3, 1])
    }

    @Test func existingFingeringIsKept() {
        var notes = song([[60], [62], [64]], hand: .right).notes
        notes[0].finger = 2
        let fixed = Song(title: "T", notes: notes, tempoMap: TempoMap(bpm: 60), measures: [])
        #expect(fixed.suggestingFingering().notes.map(\.finger) == [2, 3, 4])
    }

    @Test func thumbAvoidsBlackKeys() {
        // F♯ G♯ A♯: starting on the thumb would put it on a black key.
        let result = fingers(song([[66], [68], [70]], hand: .right))
        #expect(result.first != 1)
    }
}
