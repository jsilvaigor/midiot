import Foundation
import MusicCore
import Notation
import ScoreImport

/// A song in the library, as listed without opening its file.
public struct SongEntry: Identifiable, Codable, Hashable, Sendable {
    public enum Format: String, Codable, Sendable {
        case midi, musicXML
    }

    public let id: UUID
    public var title: String
    public let addedAt: Date
    public let format: Format
    /// Name of the imported file inside the song's folder.
    public let fileName: String
    public let noteCount: Int
    public let lowestPitch: Int
    public let highestPitch: Int
    /// Length at the song's own tempo, to the end of the last bar.
    public let durationSeconds: Double

    /// Whether the song fits on a keyboard of this size (requirement HW-3).
    public func fits(_ range: KeyboardRange) -> Bool {
        range.canPlay(lowest: Pitch(midiNumber: lowestPitch), highest: Pitch(midiNumber: highestPitch))
    }
}

/// A song opened for practice.
public struct LoadedSong: Sendable {
    public let entry: SongEntry
    public let song: Song
    /// Engraved pages; empty for MIDI imports until a sheet is generated for them.
    public let pages: [ScoreScene]
}

/// Keeps imported songs as plain files, one folder per song (requirement PL-3):
/// the original file plus `entry.json`.
public struct SongStore: Sendable {
    public enum StoreError: Error, Equatable {
        case unsupportedFile
        /// The file could not be read as music; the text says why.
        case unreadable(String)
    }

    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// `~/Library/Application Support/Midiot/Songs`
    public static var standard: SongStore {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return SongStore(root: support.appendingPathComponent("Midiot/Songs", isDirectory: true))
    }

    public static let supportedExtensions = ["mid", "midi", "musicxml", "mxl", "xml"]

    /// All songs, newest first. Folders that cannot be read are skipped.
    public func entries() -> [SongEntry] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return folders
            .compactMap { try? Data(contentsOf: $0.appendingPathComponent("entry.json")) }
            .compactMap { try? Self.decoder.decode(SongEntry.self, from: $0) }
            .sorted { $0.addedAt > $1.addedAt }
    }

    /// Copies a MIDI or MusicXML file into the library after checking that it can be read.
    @discardableResult
    public func importFile(at url: URL) throws -> SongEntry {
        let format: SongEntry.Format
        switch url.pathExtension.lowercased() {
        case "mid", "midi": format = .midi
        case "musicxml", "mxl", "xml": format = .musicXML
        default: throw StoreError.unsupportedFile
        }

        let data = try Data(contentsOf: url)
        let title = url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespaces)
        let song = try Self.parse(data, format: format, title: title).song
        guard let span = song.pitchSpan else { throw StoreError.unreadable("The file has no notes.") }

        let entry = SongEntry(
            id: UUID(), title: title,
            // Whole seconds, so the value survives being written to and read from disk unchanged.
            addedAt: Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down)),
            format: format, fileName: url.lastPathComponent,
            noteCount: song.notes.count,
            lowestPitch: span.lowerBound.midiNumber, highestPitch: span.upperBound.midiNumber,
            durationSeconds: song.tempoMap.seconds(atBeat: song.length)
        )
        let folder = folder(for: entry)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: folder.appendingPathComponent(entry.fileName))
        try Self.encoder.encode(entry).write(to: folder.appendingPathComponent("entry.json"))
        return entry
    }

    public func load(_ entry: SongEntry) throws -> LoadedSong {
        let data = try Data(contentsOf: folder(for: entry).appendingPathComponent(entry.fileName))
        let parsed = try Self.parse(data, format: entry.format, title: entry.title)
        return LoadedSong(entry: entry, song: parsed.song, pages: parsed.pages)
    }

    public func delete(_ entry: SongEntry) throws {
        try FileManager.default.removeItem(at: folder(for: entry))
    }

    private func folder(for entry: SongEntry) -> URL {
        root.appendingPathComponent(entry.id.uuidString, isDirectory: true)
    }

    private static func parse(_ data: Data, format: SongEntry.Format, title: String) throws -> (song: Song, pages: [ScoreScene]) {
        switch format {
        case .midi:
            do {
                return (Song(midiFile: try MIDIFile(data: data), title: title), [])
            } catch {
                let reason = switch error {
                case .notAMIDIFile: "This is not a MIDI file."
                case .truncated: "The MIDI file is incomplete or damaged."
                case .timecodeBasedTiming: "The MIDI file uses film timecode instead of beats, which is not supported."
                }
                throw StoreError.unreadable(reason)
            }
        case .musicXML:
            do {
                let score = try EngravedScore(musicXML: data, title: title)
                return (score.song, score.pages)
            } catch {
                let reason = switch error {
                case .missingResources: "The app's engraving data is missing."
                case .unreadableScore: "The file could not be read as MusicXML."
                case .noNotes: "The score has no notes."
                }
                throw StoreError.unreadable(reason)
            }
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
