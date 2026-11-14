import Foundation

/// A piece of music for one moment of a play (requirement CO-5).
public struct Cue: Codable, Hashable, Sendable, Identifiable {
    public enum Status: String, Codable, CaseIterable, Sendable {
        case sketch, draft, ready
    }

    public let id: UUID
    public var name: String
    /// Where it sits in the action, what it should do, when it ends.
    public var note: String
    /// How long the cue should last, in seconds.
    public var targetSeconds: Double?
    public var status: Status
    public var mood: MoodPalette.Mood?
    /// Oldest first.
    public var takes: [Take]
    /// What stepping to the cue on stage recalls; nil until it is set, which means the
    /// sound of the take and its own tempo (requirement LV-1).
    public var stage: StagePreset?

    public init(
        id: UUID = UUID(), name: String, note: String = "", targetSeconds: Double? = nil,
        status: Status = .sketch, mood: MoodPalette.Mood? = nil, takes: [Take] = [],
        stage: StagePreset? = nil
    ) {
        self.id = id
        self.name = name
        self.note = note
        self.targetSeconds = targetSeconds
        self.status = status
        self.mood = mood
        self.takes = takes
        self.stage = stage
    }

    /// The preset in force: the one set for the stage, else the sound the take was played with.
    public var stagePreset: StagePreset {
        stage ?? StagePreset(program: bestTake?.layers.first?.program)
    }

    /// Changes a take in place. Does nothing if the cue has no such take.
    public mutating func updateTake(_ id: UUID, _ change: (inout Take) -> Void) {
        guard let index = takes.firstIndex(where: { $0.id == id }) else { return }
        change(&takes[index])
    }

    /// The take to export or perform: the keeper, else the newest.
    public var bestTake: Take? { takes.last(where: \.isKeeper) ?? takes.last }
}

public struct PlayScene: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public var title: String
    public var cues: [Cue]

    public init(id: UUID = UUID(), title: String, cues: [Cue] = []) {
        self.id = id
        self.title = title
        self.cues = cues
    }
}

/// A theater production: scenes in order, each with its cues.
public struct Play: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public var title: String
    public var opensOn: Date?
    public var createdAt: Date
    public var scenes: [PlayScene]

    public init(id: UUID = UUID(), title: String, opensOn: Date? = nil, createdAt: Date = Date(), scenes: [PlayScene] = []) {
        self.id = id
        self.title = title
        self.opensOn = opensOn
        self.createdAt = createdAt
        self.scenes = scenes
    }

    public var cueCount: Int { scenes.reduce(0) { $0 + $1.cues.count } }

    /// The label a cue is called by: scene number and a letter, "3B". Nil if the cue is not in this play.
    public func label(of cueID: UUID) -> String? {
        for (sceneIndex, scene) in scenes.enumerated() {
            guard let cueIndex = scene.cues.firstIndex(where: { $0.id == cueID }) else { continue }
            return "\(sceneIndex + 1)" + Self.letters(cueIndex)
        }
        return nil
    }

    /// A, B, … Z, AA, AB, …
    private static func letters(_ index: Int) -> String {
        var index = index
        var text = ""
        repeat {
            text = String(UnicodeScalar(UInt8(65 + index % 26))) + text
            index = index / 26 - 1
        } while index >= 0
        return text
    }

    public func cue(_ id: UUID) -> Cue? {
        scenes.lazy.flatMap(\.cues).first { $0.id == id }
    }

    /// Changes a cue in place. Does nothing if the cue is not in this play.
    public mutating func updateCue(_ id: UUID, _ change: (inout Cue) -> Void) {
        for sceneIndex in scenes.indices {
            guard let cueIndex = scenes[sceneIndex].cues.firstIndex(where: { $0.id == id }) else { continue }
            change(&scenes[sceneIndex].cues[cueIndex])
            return
        }
    }
}

/// Keeps plays as plain JSON files, one per play (requirement PL-3).
public struct PlayStore: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// `~/Library/Application Support/Midiot/Plays`
    public static var standard: PlayStore {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return PlayStore(root: support.appendingPathComponent("Midiot/Plays", isDirectory: true))
    }

    /// All plays, oldest first. Files that cannot be read are skipped.
    public func plays() -> [Play] {
        let files = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
            .compactMap { read($0) }
            .sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
    }

    public func play(_ id: UUID) -> Play? {
        read(url(for: id))
    }

    public func save(_ play: Play) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let data = try Self.encoder.encode(play)
        try coordinate(writingTo: url(for: play.id)) { try data.write(to: $0, options: .atomic) }
    }

    public func delete(_ play: Play) throws {
        try coordinate(writingTo: url(for: play.id), deleting: true) { try FileManager.default.removeItem(at: $0) }
    }

    // Reads and writes go through a file coordinator so they never cross a copy of the file
    // arriving from iCloud (requirement PL-3 across devices). For a local folder this costs nothing.

    private func read(_ url: URL) -> Play? {
        var result: Play?
        var error: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: .withoutChanges, error: &error) { url in
            result = (try? Data(contentsOf: url)).flatMap { try? Self.decoder.decode(Play.self, from: $0) }
        }
        return result
    }

    private func coordinate(writingTo url: URL, deleting: Bool = false, _ body: (URL) throws -> Void) throws {
        var coordinationError: NSError?
        var bodyError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(
            writingItemAt: url, options: deleting ? .forDeleting : .forReplacing, error: &coordinationError
        ) { url in
            do { try body(url) } catch { bodyError = error }
        }
        if let error = coordinationError ?? bodyError { throw error }
    }

    func url(for id: UUID) -> URL {
        root.appendingPathComponent(id.uuidString).appendingPathExtension("json")
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
