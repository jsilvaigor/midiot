import Foundation
import MusicCore
import Testing
@testable import Notation

@Suite struct EngravedScoreTests {
    func fixture() throws -> Data {
        let url = try #require(Bundle.module.url(forResource: "two-hands", withExtension: "musicxml", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    @Test func importsNotesHandsFingeringTempoAndBars() throws {
        let score = try EngravedScore(musicXML: try fixture(), title: "Fixture")
        let song = score.song

        #expect(song.title == "Fixture")
        #expect(song.notes.count == 25)
        #expect(song.tempoMap.bpm(atBeat: 0) == 90)
        #expect(song.measures.map(\.start) == [0, 4, 8, 12])
        #expect(song.measures.map(\.length) == [4, 4, 4, 4])
        #expect(song.length == 16)

        let right = song.notes.filter { $0.hand == .right }
        let left = song.notes.filter { $0.hand == .left }
        #expect(right.count == 13)
        #expect(left.count == 12)
        #expect(right.prefix(4).map(\.pitch.midiNumber) == [60, 62, 64, 65])
        #expect(right.prefix(4).map(\.finger) == [1, 2, 3, 4])
        #expect(right.prefix(4).map(\.start) == [0, 1, 2, 3])
        #expect(left.prefix(3).map(\.pitch.midiNumber) == [48, 52, 55])
        #expect(left.prefix(3).allSatisfy { $0.duration == 4 })
    }

    @Test func everyNoteHasAShapeOnThePage() throws {
        let score = try EngravedScore(musicXML: try fixture(), title: "Fixture")
        #expect(score.pages.count == 1)
        let frames = score.pages[0].frames
        #expect(score.song.notes.allSatisfy { $0.notationID.map { frames[$0] != nil } == true })
    }

    @Test func rejectsOtherData() {
        #expect(throws: EngravedScore.ImportError.self) {
            try EngravedScore(musicXML: Data("hello".utf8), title: "x")
        }
    }
}
