import CoreGraphics
import Foundation
import MusicCore
import ScoreImport
import Testing
@testable import Notation

@Suite struct ScorePDFTests {
    /// A long single line, enough bars to need several lines of music and more than one sheet.
    private func longSong(bars: Int) -> Song {
        let notes = (0..<bars * 4).map { index in
            Note(id: 0, pitch: Pitch(midiNumber: 60 + [0, 2, 4, 5, 7, 9, 11, 12][index % 8]), start: Double(index), duration: 1, hand: .right)
        } + (0..<bars).map { Note(id: 0, pitch: Pitch(midiNumber: 48), start: Double($0) * 4, duration: 4, hand: .left) }
        return Song(title: "Long", notes: notes, tempoMap: TempoMap(bpm: 96), measures: Song.evenMeasures(beatsPerMeasure: 4, covering: Double(bars * 4)))
    }

    @Test func aShortPieceFitsOneSheet() throws {
        let score = try EngravedScore(musicXML: Data(MusicXMLWriter.draft(from: longSong(bars: 8)).utf8), title: "Short", pageWidth: 700)
        let data = ScorePDF.data(pages: score.pages, title: "Short", subtitle: "Dream · Cue 1A")
        let document = try #require(CGPDFDocument(CGDataProvider(data: data as CFData)!))
        #expect(document.numberOfPages == 1)
        #expect(document.page(at: 1)?.getBoxRect(.mediaBox).size == ScorePDF.a4)
        if let folder = ProcessInfo.processInfo.environment["SNAPSHOT_OUT"] {
            try data.write(to: URL(fileURLWithPath: folder).appendingPathComponent("short.pdf"))
        }
    }

    @Test func aLongPieceFlowsOntoMoreSheetsWithoutCuttingLines() throws {
        let score = try EngravedScore(musicXML: Data(MusicXMLWriter.draft(from: longSong(bars: 120)).utf8), title: "Long", pageWidth: 700)
        let bands = score.pages.flatMap { ScorePDF.bands(of: $0) }
        #expect(bands.count > 10)
        // Strips tile the page: each starts where the one before ends.
        for (a, b) in zip(bands, bands.dropFirst()) where b.minY > a.minY { #expect(abs(a.maxY - b.minY) < 0.01) }
        let data = ScorePDF.data(pages: score.pages, title: "Long")
        let document = try #require(CGPDFDocument(CGDataProvider(data: data as CFData)!))
        #expect(document.numberOfPages > 1)
    }

    @Test func aLeadSheetShowsItsChordSymbols() throws {
        let xml = MusicXMLWriter.leadSheet(from: longSong(bars: 8), chords: [
            1: .init(root: "C", kind: "major", suffix: ""), 3: .init(root: "B♭", kind: "major-seventh", suffix: "maj7"),
            5: .init(root: "D", kind: "minor-ninth", suffix: "m9"),
        ])
        let score = try EngravedScore(musicXML: Data(xml.utf8), title: "Lead", pageWidth: 700)
        let text = score.pages.flatMap(\.labels).map { $0.runs.map(\.text).joined() }
        #expect(text.contains("B♭maj7"))
        #expect(text.contains { $0.contains("m9") })
        // One staff: only the top line is engraved.
        #expect(score.song.notes.count == 32)
        if let folder = ProcessInfo.processInfo.environment["SNAPSHOT_OUT"] {
            try ScorePDF.data(pages: score.pages, title: "Lead sheet").write(to: URL(fileURLWithPath: folder).appendingPathComponent("lead.pdf"))
        }
    }
}
