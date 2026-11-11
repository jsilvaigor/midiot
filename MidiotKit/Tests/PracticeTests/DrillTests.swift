import MusicCore
import Testing
@testable import Practice

@Suite struct DrillTests {
    func pitches(_ song: Song, _ hand: Hand) -> [Int] {
        song.notes.filter { $0.hand == hand }.sorted { ($0.start, $0.pitch.midiNumber) < ($1.start, $1.pitch.midiNumber) }.map(\.pitch.midiNumber)
    }

    @Test func keySignatures() {
        #expect(MusicKey.c.fifths == 0)
        #expect(MusicKey.d.fifths == 2)
        #expect(MusicKey.bFlat.fifths == -2)
        #expect(MusicKey.aMinor.fifths == 0)
        #expect(MusicKey.dMinor.fifths == -1)
        #expect(MusicKey.bFlat.tonicName == "B♭")
    }

    @Test func cMajorScaleWithStandardFingering() {
        let song = Drill.scale(.c).song(title: "C")
        #expect(pitches(song, .right) == [60, 62, 64, 65, 67, 69, 71, 72, 71, 69, 67, 65, 64, 62, 60])
        #expect(pitches(song, .left).first == 48)
        let right = song.notes.filter { $0.hand == .right }.sorted { $0.start < $1.start }
        #expect(right.prefix(8).map(\.finger) == [1, 2, 3, 1, 2, 3, 4, 5])
        #expect(song.measures.count == 4)
        #expect(song.length == 16)
    }

    @Test func otherKeysUseTheirOwnNotesAndFingering() {
        #expect(pitches(Drill.scale(.d).song(title: ""), .right).prefix(8) == [62, 64, 66, 67, 69, 71, 73, 74])
        // Harmonic minor: raised seventh.
        #expect(pitches(Drill.scale(.aMinor).song(title: ""), .right).prefix(8) == [57, 59, 60, 62, 64, 65, 68, 69])
        let f = Drill.scale(.f).song(title: "").notes.filter { $0.hand == .right }.sorted { $0.start < $1.start }
        #expect(f.prefix(8).map(\.finger) == [1, 2, 3, 4, 1, 2, 3, 4])
    }

    @Test func chordsAndCadence() {
        let inversions = Drill.inversions(.c).song(title: "")
        #expect(inversions.notes.filter { $0.hand == .right && $0.start == 0 }.map(\.pitch.midiNumber) == [60, 64, 67])
        #expect(inversions.notes.filter { $0.hand == .right && $0.start == 2 }.map(\.pitch.midiNumber) == [64, 67, 72])

        let cadence = Drill.cadence(.c).song(title: "")
        func chord(at beat: Double) -> [Int] { cadence.notes.filter { $0.hand == .right && $0.start == beat }.map(\.pitch.midiNumber) }
        #expect(chord(at: 0) == [60, 64, 67])
        #expect(chord(at: 2) == [60, 65, 69]) // F major, C on the bottom
        #expect(chord(at: 4) == [59, 62, 67]) // G major, B on the bottom
        #expect(cadence.notes.filter { $0.hand == .left }.prefix(4).map(\.pitch.midiNumber) == [48, 53, 43, 48])
    }

    @Test func readingDrillsAreRepeatablePerSeedAndStayInRange() {
        let a = Drill.bassReading(level: 2).song(title: "", seed: 5)
        #expect(a == Drill.bassReading(level: 2).song(title: "", seed: 5))
        #expect(a != Drill.bassReading(level: 2).song(title: "", seed: 6))
        #expect(a.notes.allSatisfy { $0.hand == .left && (36...48).contains($0.pitch.midiNumber) && !$0.pitch.isBlackKey })
        #expect(zip(a.notes, a.notes.dropFirst()).allSatisfy { $0.pitch != $1.pitch })
        #expect(a.notes.count == 16)
    }

    @Test func rhythmBarsAddUp() {
        for level in 1...3 {
            let song = Drill.rhythm(level: level).song(title: "", seed: 11)
            #expect(song.measures.count == 8)
            let right = song.notes.filter { $0.hand == .right }
            #expect(right.allSatisfy { $0.end <= 32 })
            // No note overlaps the next.
            #expect(zip(right, right.dropFirst()).allSatisfy { $0.end <= $1.start + 1e-9 })
            #expect(song.notes.filter { $0.hand == .left }.count == 32)
        }
    }

    @Test func everyCatalogDrillBuildsAndHasAUniqueID() {
        #expect(Set(Drill.catalog.map(\.id)).count == Drill.catalog.count)
        for drill in Drill.catalog {
            let song = drill.song(title: drill.id, seed: 1)
            #expect(!song.notes.isEmpty)
            #expect(song.length.truncatingRemainder(dividingBy: 4) == 0)
        }
    }
}
