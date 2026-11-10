import Testing
@testable import MusicCore

@Suite struct PitchTests {
    @Test func middleCIsC4() {
        #expect(Pitch.middleC.pitchClass == 0)
        #expect(Pitch.middleC.octave == 4)
        #expect(!Pitch.middleC.isBlackKey)
    }

    @Test func octaveBoundaries() {
        #expect(Pitch(midiNumber: 59).octave == 3)
        #expect(Pitch(midiNumber: 0).octave == -1)
        #expect(Pitch(midiNumber: 127).octave == 9)
    }

    @Test func blackKeys() {
        let black = (60..<72).filter { Pitch(midiNumber: $0).isBlackKey }
        #expect(black == [61, 63, 66, 68, 70])
    }

    @Test func letterNames() {
        #expect(NoteNaming.letters.nameWithOctave(of: .middleC) == "C4")
        #expect(NoteNaming.letters.name(of: Pitch(midiNumber: 66)) == "F♯")
        #expect(NoteNaming.letters.name(of: Pitch(midiNumber: 71)) == "B")
    }

    @Test func solfegeNames() {
        #expect(NoteNaming.solfege.nameWithOctave(of: .middleC) == "Dó4")
        #expect(NoteNaming.solfege.name(of: Pitch(midiNumber: 67)) == "Sol")
        #expect(NoteNaming.solfege.name(of: Pitch(midiNumber: 70)) == "Lá♯")
    }
}

@Suite struct KeyboardRangeTests {
    @Test func bounds() {
        let range = KeyboardRange.fortyNineKeys
        #expect(range.highest == Pitch(midiNumber: 84))
        #expect(range.pitches.count == 49)
        #expect(range.contains(.middleC))
        #expect(!range.contains(Pitch(midiNumber: 85)))
    }

    @Test func shiftsByWholeOctavesOnlyWhenNeeded() {
        let range = KeyboardRange.twentyFiveKeys // 48...72
        #expect(range.shifted(toContain: Pitch(midiNumber: 60)) == range)
        #expect(range.shifted(toContain: Pitch(midiNumber: 73)).lowest == Pitch(midiNumber: 60))
        #expect(range.shifted(toContain: Pitch(midiNumber: 47)).lowest == Pitch(midiNumber: 36))
        #expect(range.shifted(toContain: Pitch(midiNumber: 96)).lowest == Pitch(midiNumber: 72))
        #expect(range.shifted(toContain: Pitch(midiNumber: 24)).lowest == Pitch(midiNumber: 24))
    }
}
