import Foundation

/// Writes a Standard MIDI File (format 1) that other music software can open (requirement CO-6).
public enum MIDIFileWriter {
    public struct Note: Hashable, Sendable {
        public let pitch: Int
        public let velocity: Int
        /// In beats (quarter notes).
        public let start: Double
        public let duration: Double

        public init(pitch: Int, velocity: Int, start: Double, duration: Double) {
            self.pitch = pitch
            self.velocity = velocity
            self.start = start
            self.duration = duration
        }
    }

    public struct Track: Hashable, Sendable {
        public let name: String
        /// General MIDI program, 0-based.
        public let program: Int
        public let notes: [Note]

        public init(name: String, program: Int = 0, notes: [Note]) {
            self.name = name
            self.program = program
            self.notes = notes
        }
    }

    public static let ticksPerQuarter = 480

    /// - Parameter title: written as the name of the first track, which also carries the tempo.
    public static func data(title: String, bpm: Double, tracks: [Track]) -> Data {
        var bytes: [UInt8] = Array("MThd".utf8) + uint32(6) + uint16(1) + uint16(tracks.count + 1) + uint16(ticksPerQuarter)

        var conductor = meta(0x03, Array(title.utf8), delta: 0)
        let microseconds = Int((60_000_000 / max(bpm, 1)).rounded())
        conductor += meta(0x51, [UInt8(microseconds >> 16 & 0xFF), UInt8(microseconds >> 8 & 0xFF), UInt8(microseconds & 0xFF)], delta: 0)
        conductor += meta(0x58, [4, 2, 24, 8], delta: 0) // 4/4
        bytes += chunk(conductor + meta(0x2F, [], delta: 0))

        // Channel 10 (index 9) is percussion in General MIDI, so melodic tracks skip it.
        let channels = Array(0..<9) + Array(10..<16)
        for (index, track) in tracks.enumerated() {
            let channel = UInt8(channels[index % channels.count])
            var body = meta(0x03, Array(track.name.utf8), delta: 0)
            body += [0x00, 0xC0 | channel, UInt8(min(max(track.program, 0), 127))]

            // Note-offs sort before note-ons at the same tick, so a repeated key is released first.
            var events: [(tick: Int, isOn: Bool, pitch: UInt8, velocity: UInt8)] = []
            for note in track.notes where (0...127).contains(note.pitch) {
                let start = max(Int((note.start * Double(ticksPerQuarter)).rounded()), 0)
                let length = max(Int((note.duration * Double(ticksPerQuarter)).rounded()), 1)
                events.append((start, true, UInt8(note.pitch), UInt8(min(max(note.velocity, 1), 127))))
                events.append((start + length, false, UInt8(note.pitch), 0))
            }
            events.sort { ($0.tick, $0.isOn ? 1 : 0, $0.pitch) < ($1.tick, $1.isOn ? 1 : 0, $1.pitch) }
            var tick = 0
            for event in events {
                body += variableLength(event.tick - tick) + [(event.isOn ? 0x90 : 0x80) | channel, event.pitch, event.velocity]
                tick = event.tick
            }
            bytes += chunk(body + meta(0x2F, [], delta: 0))
        }
        return Data(bytes)
    }

    private static func chunk(_ body: [UInt8]) -> [UInt8] {
        Array("MTrk".utf8) + uint32(body.count) + body
    }

    private static func meta(_ type: UInt8, _ payload: [UInt8], delta: Int) -> [UInt8] {
        variableLength(delta) + [0xFF, type] + variableLength(payload.count) + payload
    }

    private static func uint16(_ value: Int) -> [UInt8] { [UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)] }

    private static func uint32(_ value: Int) -> [UInt8] {
        [UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
    }

    /// MIDI variable-length quantity: 7 bits per byte, high bit set on all but the last.
    private static func variableLength(_ value: Int) -> [UInt8] {
        var value = max(value, 0)
        var bytes = [UInt8(value & 0x7F)]
        value >>= 7
        while value > 0 {
            bytes.insert(UInt8(value & 0x7F) | 0x80, at: 0)
            value >>= 7
        }
        return bytes
    }
}
