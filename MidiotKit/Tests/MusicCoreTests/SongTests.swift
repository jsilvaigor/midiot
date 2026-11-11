import Testing
@testable import MusicCore

@Suite struct TempoMapTests {
    @Test func constantTempo() {
        let map = TempoMap(bpm: 120)
        #expect(map.seconds(atBeat: 4) == 2)
        #expect(map.beat(atSeconds: 2) == 4)
    }

    @Test func tempoChange() {
        // 4 beats at 120 (2 s), then 60 bpm.
        let map = TempoMap(changes: [.init(beat: 4, bpm: 60), .init(beat: 0, bpm: 120)])
        #expect(map.seconds(atBeat: 6) == 4)
        #expect(map.beat(atSeconds: 4) == 6)
        #expect(map.bpm(atBeat: 3.9) == 120)
        #expect(map.bpm(atBeat: 4) == 60)
    }

    @Test func defaultsTo120WhenNoTempoAtStart() {
        let map = TempoMap(changes: [.init(beat: 8, bpm: 90)])
        #expect(map.bpm(atBeat: 0) == 120)
        #expect(map.seconds(atBeat: 8) == 4)
    }
}

@Suite struct SongTests {
    func song(pitches: [Int]) -> Song {
        let notes = pitches.enumerated().map {
            Note(id: 99, pitch: Pitch(midiNumber: $1), start: Double(pitches.count - $0), duration: 1, hand: .right)
        }
        return Song(title: "T", notes: notes, tempoMap: TempoMap(bpm: 60),
                    measures: Song.evenMeasures(beatsPerMeasure: 4, covering: Double(pitches.count + 1)))
    }

    @Test func notesAreSortedAndRenumbered() {
        let s = song(pitches: [60, 62, 64])
        #expect(s.notes.map(\.pitch.midiNumber) == [64, 62, 60])
        #expect(s.notes.map(\.id) == [0, 1, 2])
        #expect(s.length == 4)
    }

    @Test func measures() {
        let s = song(pitches: [60, 62, 64, 65, 67])
        #expect(s.measures.count == 2)
        #expect(s.measure(atBeat: 4.5)?.number == 2)
        #expect(s.measure(atBeat: 0)?.number == 1)
    }

    @Test func fitsKeyboard() {
        // Two octaves fit on 25 keys from any C...
        #expect(KeyboardRange.twentyFiveKeys.canPlay(song(pitches: [36, 60])))
        // ...but not when they straddle the octave grid (D to D needs a C-to-C keyboard shifted).
        #expect(!KeyboardRange.twentyFiveKeys.canPlay(song(pitches: [38, 62])))
        #expect(!KeyboardRange.twentyFiveKeys.canPlay(song(pitches: [36, 72])))
        #expect(KeyboardRange.fortyNineKeys.canPlay(song(pitches: [36, 72])))
        #expect(KeyboardRange.twentyFiveKeys.canPlay(song(pitches: [])))
    }
}

@Suite struct FoldingTests {
    func song(_ pitches: [(Int, Double)]) -> Song {
        Song(
            title: "T",
            notes: pitches.map { Note(id: 0, pitch: Pitch(midiNumber: $0.0), start: $0.1, duration: 1, hand: .right) },
            tempoMap: TempoMap(bpm: 60), measures: Song.evenMeasures(beatsPerMeasure: 4, covering: 4)
        )
    }

    @Test func keyboardMovesToWhereTheNotesAre() {
        // Most notes sit in C5...C7; one stray low note.
        let s = song([(72, 0), (76, 1), (84, 2), (96, 3), (40, 3)])
        #expect(KeyboardRange.twentyFiveKeys.bestPosition(for: s).lowest == Pitch(midiNumber: 72))
    }

    @Test func outOfRangeNotesMoveByOctavesAndCollisionsMerge() {
        let range = KeyboardRange.twentyFiveKeys // 48...72
        let folded = song([(36, 0), (60, 0), (84, 0), (79, 1), (45, 2)]).folded(into: range)
        // 36 and 84 both fold onto pitches at beat 0: 36 -> 48, 84 -> 72 (60 stays).
        #expect(folded.notes.filter { $0.start == 0 }.map(\.pitch.midiNumber) == [48, 60, 72])
        #expect(folded.notes.first { $0.start == 1 }?.pitch.midiNumber == 67)
        #expect(folded.notes.first { $0.start == 2 }?.pitch.midiNumber == 57)
        #expect(folded.notes.allSatisfy { range.contains($0.pitch) })

        // A folded note landing on an existing one is dropped; the original stays.
        let merged = song([(60, 0), (72, 0), (84, 0)]).folded(into: range)
        #expect(merged.notes.map(\.pitch.midiNumber) == [60, 72])
    }
}
