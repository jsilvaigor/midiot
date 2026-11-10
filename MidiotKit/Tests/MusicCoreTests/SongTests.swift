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
