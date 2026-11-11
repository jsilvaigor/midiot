import Foundation
import MusicCore
import Testing
@testable import Library

@Suite struct SongStoreTests {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("midiot-tests-\(UUID().uuidString)")

    /// One track: middle C for a beat, then the C two octaves up.
    func writeMIDI(named name: String) throws -> URL {
        let track: [UInt8] = [0, 0x90, 60, 80, 0x83, 0x60, 0x80, 60, 0, 0, 0x90, 84, 80, 0x83, 0x60, 0x80, 84, 0, 0, 0xFF, 0x2F, 0]
        let bytes: [UInt8] = Array("MThd".utf8) + [0, 0, 0, 6, 0, 0, 0, 1, 0x01, 0xE0]
            + Array("MTrk".utf8) + [0, 0, 0, UInt8(track.count)] + track
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        try Data(bytes).write(to: url)
        return url
    }

    @Test func importListLoadDelete() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = SongStore(root: folder.appendingPathComponent("Songs"))
        #expect(store.entries().isEmpty)

        let entry = try store.importFile(at: try writeMIDI(named: "my_first_song.mid"))
        #expect(entry.title == "my first song")
        #expect(entry.format == .midi)
        #expect(entry.noteCount == 2)
        #expect(entry.lowestPitch == 60)
        #expect(entry.highestPitch == 84)
        #expect(entry.durationSeconds == 2) // one 4/4 bar at the default 120 bpm
        #expect(entry.fits(.twentyFiveKeys))
        #expect(store.entries() == [entry])

        let loaded = try store.load(entry)
        #expect(loaded.song.notes.map(\.pitch.midiNumber) == [60, 84])
        #expect(loaded.pages.isEmpty)

        #expect(store.runs(for: entry).isEmpty)
        let run = RunResult(
            date: Date(timeIntervalSince1970: 1_000), rate: 0.6, hands: ["right"], usedWaitMode: true,
            completed: true, correct: 2, early: 0, late: 0, missed: 0, wrongKeys: 1
        )
        try store.appendRun(run, for: entry)
        try store.appendRun(run, for: entry)
        #expect(store.runs(for: entry) == [run, run])

        try store.delete(entry)
        #expect(store.entries().isEmpty)
    }

    @Test func rejectsUnsupportedAndBrokenFiles() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = SongStore(root: folder.appendingPathComponent("Songs"))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let text = folder.appendingPathComponent("notes.txt")
        try Data("hello".utf8).write(to: text)
        #expect(throws: SongStore.StoreError.unsupportedFile) { try store.importFile(at: text) }

        let broken = folder.appendingPathComponent("broken.mid")
        try Data("hello".utf8).write(to: broken)
        #expect(throws: SongStore.StoreError.unreadable("This is not a MIDI file.")) { try store.importFile(at: broken) }
        #expect(store.entries().isEmpty)
    }
}
