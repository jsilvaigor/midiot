import Foundation

/// The musical content of a Standard MIDI File (.mid), with times in ticks.
public struct MIDIFile: Hashable, Sendable {
    public struct Note: Hashable, Sendable {
        public let pitch: Int
        public let velocity: Int
        public let startTick: Int
        public let durationTicks: Int
        /// 0-based MIDI channel; 9 is the General MIDI drum channel.
        public let channel: Int
    }

    public struct Track: Hashable, Sendable {
        public var name: String?
        public var notes: [Note] = []
    }

    public struct Tempo: Hashable, Sendable {
        public let tick: Int
        public let bpm: Double
    }

    public struct TimeSignature: Hashable, Sendable {
        public let tick: Int
        public let numerator: Int
        public let denominator: Int
    }

    public enum ParseError: Error, Equatable {
        case notAMIDIFile
        case truncated
        /// The file measures time in film frames rather than beats, which the app does not read.
        case timecodeBasedTiming
    }

    public let ticksPerQuarter: Int
    public let tracks: [Track]
    public let tempos: [Tempo]
    public let timeSignatures: [TimeSignature]

    public init(data: Data) throws(ParseError) {
        var reader = Reader(bytes: [UInt8](data))
        guard try reader.tag() == "MThd" else { throw .notAMIDIFile }
        let headerLength = try reader.uint32()
        _ = try reader.uint16() // format: tracks are merged the same way for formats 0 and 1
        let trackCount = try reader.uint16()
        let division = try reader.uint16()
        try reader.skip(headerLength - 6)
        guard division & 0x8000 == 0, division > 0 else { throw .timecodeBasedTiming }

        var tracks: [Track] = []
        var tempos: [Tempo] = []
        var signatures: [TimeSignature] = []

        for _ in 0..<trackCount {
            guard !reader.isAtEnd else { break } // tolerate files that declare more tracks than they hold
            let tag = try reader.tag()
            let length = try reader.uint32()
            guard tag == "MTrk" else {
                try reader.skip(length)
                continue
            }
            var chunk = try reader.sub(length)
            tracks.append(try Self.parseTrack(&chunk, tempos: &tempos, signatures: &signatures))
        }

        ticksPerQuarter = division
        self.tracks = tracks
        self.tempos = tempos.sorted { $0.tick < $1.tick }
        timeSignatures = signatures.sorted { $0.tick < $1.tick }
    }

    private static func parseTrack(
        _ reader: inout Reader, tempos: inout [Tempo], signatures: inout [TimeSignature]
    ) throws(ParseError) -> Track {
        var track = Track()
        var tick = 0
        var runningStatus: UInt8 = 0
        // Notes currently sounding, keyed by channel and pitch.
        var open: [Int: (tick: Int, velocity: Int)] = [:]

        func close(_ key: Int, at tick: Int) {
            guard let start = open.removeValue(forKey: key) else { return }
            track.notes.append(Note(
                pitch: key & 0x7F, velocity: start.velocity, startTick: start.tick,
                durationTicks: max(tick - start.tick, 1), channel: key >> 8
            ))
        }

        while !reader.isAtEnd {
            tick += try reader.variableLength()
            var status = try reader.byte()
            if status < 0x80 {
                // Running status: the byte is data and the previous status applies.
                reader.unread()
                status = runningStatus
                guard status >= 0x80 else { throw .truncated }
            }

            switch status {
            case 0xFF:
                let type = try reader.byte()
                let payload = try reader.bytes(try reader.variableLength())
                switch type {
                case 0x03:
                    track.name = String(bytes: payload, encoding: .utf8) ?? String(bytes: payload, encoding: .isoLatin1)
                case 0x51 where payload.count == 3:
                    let microseconds = Int(payload[0]) << 16 | Int(payload[1]) << 8 | Int(payload[2])
                    if microseconds > 0 { tempos.append(Tempo(tick: tick, bpm: 60_000_000 / Double(microseconds))) }
                case 0x58 where payload.count >= 2:
                    signatures.append(TimeSignature(tick: tick, numerator: Int(payload[0]), denominator: 1 << Int(payload[1])))
                default:
                    break
                }
            case 0xF0, 0xF7:
                try reader.skip(try reader.variableLength())
            default:
                runningStatus = status
                let channel = Int(status & 0x0F)
                switch status & 0xF0 {
                case 0x90:
                    let pitch = Int(try reader.byte()), velocity = Int(try reader.byte())
                    let key = channel << 8 | pitch
                    close(key, at: tick) // a repeated note-on restarts the note
                    if velocity > 0 { open[key] = (tick, velocity) }
                case 0x80:
                    let pitch = Int(try reader.byte())
                    _ = try reader.byte()
                    close(channel << 8 | pitch, at: tick)
                case 0xC0, 0xD0:
                    _ = try reader.byte()
                default:
                    try reader.skip(2)
                }
            }
        }
        for key in open.keys.sorted() { close(key, at: tick) }
        track.notes.sort { ($0.startTick, $0.pitch) < ($1.startTick, $1.pitch) }
        return track
    }
}

/// Cursor over big-endian bytes.
private struct Reader {
    let bytes: [UInt8]
    var position = 0
    var end: Int

    init(bytes: [UInt8]) {
        self.bytes = bytes
        end = bytes.count
    }

    var isAtEnd: Bool { position >= end }

    mutating func byte() throws(MIDIFile.ParseError) -> UInt8 {
        guard position < end else { throw .truncated }
        defer { position += 1 }
        return bytes[position]
    }

    mutating func unread() { position -= 1 }

    mutating func bytes(_ count: Int) throws(MIDIFile.ParseError) -> [UInt8] {
        guard count >= 0, position + count <= end else { throw .truncated }
        defer { position += count }
        return Array(bytes[position..<position + count])
    }

    mutating func skip(_ count: Int) throws(MIDIFile.ParseError) {
        guard count >= 0, position + count <= end else { throw .truncated }
        position += count
    }

    mutating func uint16() throws(MIDIFile.ParseError) -> Int {
        let b = try bytes(2)
        return Int(b[0]) << 8 | Int(b[1])
    }

    mutating func uint32() throws(MIDIFile.ParseError) -> Int {
        let b = try bytes(4)
        return Int(b[0]) << 24 | Int(b[1]) << 16 | Int(b[2]) << 8 | Int(b[3])
    }

    mutating func tag() throws(MIDIFile.ParseError) -> String {
        String(decoding: try bytes(4), as: UTF8.self)
    }

    /// MIDI variable-length quantity: 7 bits per byte, high bit set on all but the last.
    mutating func variableLength() throws(MIDIFile.ParseError) -> Int {
        var value = 0
        for _ in 0..<4 {
            let b = try byte()
            value = value << 7 | Int(b & 0x7F)
            if b & 0x80 == 0 { return value }
        }
        throw .truncated
    }

    /// A reader limited to the next `count` bytes; this reader moves past them.
    mutating func sub(_ count: Int) throws(MIDIFile.ParseError) -> Reader {
        guard count >= 0, position + count <= end else { throw .truncated }
        var child = self
        child.end = position + count
        position += count
        return child
    }
}
