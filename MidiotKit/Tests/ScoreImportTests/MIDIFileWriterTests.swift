import Foundation
import MusicCore
import Testing
@testable import ScoreImport

@Suite struct MIDIFileWriterTests {
    @Test func whatIsWrittenReadsBackTheSame() throws {
        let data = MIDIFileWriter.data(title: "Forest at night", bpm: 75, tracks: [
            .init(name: "Layer 1", program: 88, notes: [
                .init(pitch: 62, velocity: 64, start: 0, duration: 1.5),
                .init(pitch: 65, velocity: 70, start: 0, duration: 1.5),
                // The same key struck again exactly as it is released.
                .init(pitch: 62, velocity: 80, start: 1.5, duration: 0.5),
            ]),
            .init(name: "Layer 2", notes: [.init(pitch: 38, velocity: 90, start: 300, duration: 4)]),
        ])
        let file = try MIDIFile(data: data)
        #expect(file.ticksPerQuarter == 480)
        #expect(file.tempos.map(\.bpm) == [75])
        #expect(file.tracks.map(\.name) == ["Forest at night", "Layer 1", "Layer 2"])
        #expect(file.tracks[1].notes.map(\.startTick) == [0, 0, 720])
        #expect(file.tracks[1].notes.map(\.durationTicks) == [720, 720, 240])
        #expect(file.tracks[1].notes.map(\.velocity) == [64, 70, 80])
        // A long gap needs a multi-byte delta time.
        #expect(file.tracks[2].notes.first?.startTick == 144_000)
        #expect(Set(file.tracks[1].notes.map(\.channel)) != Set(file.tracks[2].notes.map(\.channel)))

        let song = Song(midiFile: file, title: "Forest at night")
        #expect(song.notes.count == 4)
        #expect(song.tempoMap.bpm(atBeat: 0) == 75)
    }

    @Test func theMelodyLineIsTheTopVoice() {
        let song = Song(title: "T", notes: [
            Note(id: 0, pitch: Pitch(midiNumber: 48), start: 0, duration: 4, hand: .left),
            Note(id: 0, pitch: Pitch(midiNumber: 64), start: 0, duration: 2, hand: .right),
            Note(id: 0, pitch: Pitch(midiNumber: 60), start: 0, duration: 2, hand: .right),
            Note(id: 0, pitch: Pitch(midiNumber: 67), start: 1, duration: 1, hand: .right),
        ], tempoMap: TempoMap(bpm: 100), measures: Song.evenMeasures(beatsPerMeasure: 4, covering: 4))
        let line = song.melodyLine()
        #expect(line.notes.map(\.pitch.midiNumber) == [64, 67])
        #expect(line.notes.map(\.duration) == [1, 1])
        #expect(line.notes.allSatisfy { $0.hand == .right })
    }

    @Test func aLeadSheetHasOneStaffAndChordSymbols() {
        let song = Song(title: "T", notes: [
            Note(id: 0, pitch: Pitch(midiNumber: 70), start: 0, duration: 4, hand: .right),
            Note(id: 0, pitch: Pitch(midiNumber: 46), start: 0, duration: 4, hand: .left),
        ], tempoMap: TempoMap(bpm: 100), measures: Song.evenMeasures(beatsPerMeasure: 4, covering: 4))
        let xml = MusicXMLWriter.leadSheet(
            from: song, chords: [1: .init(root: "B♭", kind: "major-seventh", suffix: "maj7")], fifths: -2
        )
        #expect(!xml.contains("<staves>"))
        #expect(xml.contains("<root-step>B</root-step><root-alter>-1</root-alter>"))
        #expect(xml.contains("<kind text=\"maj7\">major-seventh</kind>"))
        #expect(xml.components(separatedBy: "<pitch>").count == 2)
        // The grand-staff draft is unchanged by the lead-sheet option.
        #expect(MusicXMLWriter.draft(from: song).contains("<staves>2</staves>"))
    }
}
