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

@Suite struct ScoreLayoutTests {
    @Test func cursorMovesLeftToRightThroughTheBars() throws {
        let url = try #require(Bundle.module.url(forResource: "two-hands", withExtension: "musicxml", subdirectory: "Fixtures"))
        let score = try EngravedScore(musicXML: try Data(contentsOf: url), title: "Fixture")
        let layout = ScoreLayout(song: score.song, pages: score.pages)
        #expect(!layout.isEmpty)

        // The fixture fits on one line, so x only grows with time.
        let xs = try stride(from: 0.0, through: 15.5, by: 0.5).map { try #require(layout.position(atBeat: $0)).x }
        #expect(zip(xs, xs.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(xs.last! - xs.first! > 200)

        // Between two notes a beat apart, the cursor is in between.
        let a = try #require(layout.position(atBeat: 1)), mid = try #require(layout.position(atBeat: 1.5))
        let b = try #require(layout.position(atBeat: 2))
        #expect(a.x < mid.x && mid.x < b.x)
        #expect(a.bottom > a.top)

        // Every bar can be found from a point inside it.
        for measure in score.song.measures {
            let bar = try #require(layout.frame(ofMeasure: measure.number))
            #expect(layout.measure(at: CGPoint(x: bar.frame.midX, y: bar.frame.midY), page: bar.page) == measure.number)
        }
    }
}
