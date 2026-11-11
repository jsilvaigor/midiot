import Foundation
import MusicCore
import Testing
@testable import ScoreImport

/// Builds Standard MIDI File bytes for tests.
struct MIDIBuilder {
    var tracks: [[UInt8]] = []

    static func track(_ events: [(delta: Int, bytes: [UInt8])]) -> [UInt8] {
        var body: [UInt8] = []
        for event in events {
            body += vlq(event.delta) + event.bytes
        }
        body += [0x00, 0xFF, 0x2F, 0x00]
        return Array("MTrk".utf8) + uint32(body.count) + body
    }

    func data(ticksPerQuarter: Int = 480) -> Data {
        var out = Array("MThd".utf8) + Self.uint32(6) + [0, 1] + Self.uint16(tracks.count) + Self.uint16(ticksPerQuarter)
        for track in tracks { out += track }
        return Data(out)
    }

    static func vlq(_ value: Int) -> [UInt8] {
        var bytes = [UInt8(value & 0x7F)]
        var rest = value >> 7
        while rest > 0 {
            bytes.insert(UInt8(rest & 0x7F) | 0x80, at: 0)
            rest >>= 7
        }
        return bytes
    }

    static func uint16(_ v: Int) -> [UInt8] { [UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)] }
    static func uint32(_ v: Int) -> [UInt8] { uint16(v >> 16) + uint16(v & 0xFFFF) }
}

@Suite struct MIDIFileTests {
    /// Tempo track, a right-hand track and a left-hand track.
    static func twoHandFile() -> Data {
        var builder = MIDIBuilder()
        builder.tracks = [
            MIDIBuilder.track([
                (0, [0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20]), // 500000 us per quarter = 120 bpm
                (0, [0xFF, 0x58, 0x04, 0x03, 0x02, 0x18, 0x08]), // 3/4
            ]),
            MIDIBuilder.track([
                (0, [0xFF, 0x03, 0x02] + Array("RH".utf8)),
                (0, [0x90, 72, 100]),
                (480, [0x80, 72, 0]),
                (0, [0x90, 74, 90]),
                (480, [74, 0]), // running status, note-on with velocity 0 ends the note
            ]),
            MIDIBuilder.track([
                (0, [0x90, 48, 70]),
                (1440, [0x80, 48, 0]),
            ]),
        ]
        return builder.data()
    }

    @Test func parsesTracksTempoAndTimeSignature() throws {
        let file = try MIDIFile(data: Self.twoHandFile())
        #expect(file.ticksPerQuarter == 480)
        #expect(file.tracks.count == 3)
        #expect(file.tempos == [.init(tick: 0, bpm: 120)])
        #expect(file.timeSignatures == [.init(tick: 0, numerator: 3, denominator: 4)])
        #expect(file.tracks[1].name == "RH")
        #expect(file.tracks[1].notes.map(\.pitch) == [72, 74])
        #expect(file.tracks[1].notes.map(\.startTick) == [0, 480])
        #expect(file.tracks[1].notes.map(\.durationTicks) == [480, 480])
        #expect(file.tracks[2].notes.first?.durationTicks == 1440)
    }

    @Test func rejectsOtherData() {
        #expect(throws: MIDIFile.ParseError.notAMIDIFile) { try MIDIFile(data: Data("not a midi file".utf8)) }
        #expect(throws: MIDIFile.ParseError.truncated) { try MIDIFile(data: Self.twoHandFile().prefix(40)) }
    }

    @Test func variableLengthQuantities() throws {
        var builder = MIDIBuilder()
        builder.tracks = [MIDIBuilder.track([(200, [0x90, 60, 80]), (20000, [0x80, 60, 0])])]
        let note = try #require(try MIDIFile(data: builder.data()).tracks[0].notes.first)
        #expect(note.startTick == 200)
        #expect(note.durationTicks == 20000)
    }
}

@Suite struct SongFromMIDITests {
    @Test func twoTracksBecomeTwoHands() throws {
        let song = Song(midiFile: try MIDIFile(data: MIDIFileTests.twoHandFile()), title: "Waltz")
        #expect(song.notes.count == 3)
        #expect(song.notes.filter { $0.hand == .right }.map(\.pitch.midiNumber) == [72, 74])
        #expect(song.notes.filter { $0.hand == .left }.map(\.pitch.midiNumber) == [48])
        #expect(song.notes.first { $0.pitch.midiNumber == 74 }?.start == 1)
        #expect(song.tempoMap.bpm(atBeat: 0) == 120)
        // 3 beats of music in 3/4 is one bar.
        #expect(song.measures == [Measure(number: 1, start: 0, length: 3)])
    }

    @Test func singleTrackSplitsAtMiddleC() throws {
        var builder = MIDIBuilder()
        builder.tracks = [MIDIBuilder.track([
            (0, [0x90, 48, 80]), (0, [0x90, 60, 80]), (0, [0x99, 36, 80]), // channel 10 is drums
            (480, [0x80, 48, 0]), (0, [0x80, 60, 0]), (0, [0x89, 36, 0]),
        ])]
        let song = Song(midiFile: try MIDIFile(data: builder.data()), title: "One track")
        #expect(song.notes.map(\.hand) == [.left, .right])
        #expect(song.measures.first?.length == 4)
    }

    @Test func explicitSplitPoint() throws {
        let file = try MIDIFile(data: MIDIFileTests.twoHandFile())
        let song = Song(midiFile: file, title: "T", hands: .split(at: Pitch(midiNumber: 73)))
        #expect(song.notes.filter { $0.hand == .right }.map(\.pitch.midiNumber) == [74])
    }
}

@Suite struct SpellingTests {
    @Test func spellingFollowsTheKey() {
        // B♭ major: B♭ and E♭ need no accidental; in D minor the raised seventh is C♯, with one.
        let flats = MusicXMLWriter.Spelling(fifths: -2, sharpened: nil)
        #expect(flats.spell(Pitch(midiNumber: 70)).step == "B")
        #expect(flats.spell(Pitch(midiNumber: 70)).alter == -1)
        #expect(flats.spell(Pitch(midiNumber: 70)).accidental == nil)
        #expect(flats.spell(Pitch(midiNumber: 71)).accidental == "natural")
        let dMinor = MusicXMLWriter.Spelling(fifths: -1, sharpened: 1)
        #expect(dMinor.spell(Pitch(midiNumber: 61)).step == "C")
        #expect(dMinor.spell(Pitch(midiNumber: 61)).accidental == "sharp")
        let sharps = MusicXMLWriter.Spelling(fifths: 2, sharpened: nil)
        #expect(sharps.spell(Pitch(midiNumber: 66)).accidental == nil)
        #expect(sharps.spell(Pitch(midiNumber: 65)).accidental == "natural")
    }
}
