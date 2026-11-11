import Foundation

/// The guided path (requirement CU-1): units of drills in teaching order, for someone who
/// already reads music and keeps time but is new to the keyboard.
public enum Curriculum {
    public struct Unit: Identifiable, Hashable, Sendable {
        public enum Topic: String, Sendable, CaseIterable {
            case treble, rhythm, fiveFinger, bassClef, handsTogether, scales, arpeggios, chords
        }

        public let topic: Topic
        public let drills: [Drill]
        /// True for what a flautist already knows; such a unit never blocks the path.
        public let isKnown: Bool

        public var id: String { topic.rawValue }
    }

    public enum Status: Hashable, Sendable {
        /// Known from earlier musical training.
        case known
        case done
        /// The unit being worked on, with how many of its drills are passed.
        case current(passed: Int)
        case upcoming
    }

    /// A drill is passed once its best whole run reaches this accuracy.
    public static let passAccuracy = 0.85

    public static let units: [Unit] = [
        Unit(topic: .treble, drills: [], isKnown: true),
        Unit(topic: .rhythm, drills: (1...3).map { Drill.rhythm(level: $0) }, isKnown: true),
        Unit(topic: .fiveFinger, drills: [.fiveFinger(.c, pattern: 1)], isKnown: false),
        Unit(topic: .bassClef, drills: (1...3).map { Drill.bassReading(level: $0) }, isKnown: false),
        Unit(topic: .handsTogether, drills: [.fiveFinger(.c, pattern: 2), .fiveFinger(.c, pattern: 3)], isKnown: false),
        Unit(topic: .scales, drills: MusicKey.drillKeys.map(Drill.scale), isKnown: false),
        Unit(topic: .arpeggios, drills: MusicKey.drillKeys.map(Drill.arpeggio), isKnown: false),
        Unit(topic: .chords, drills: MusicKey.drillKeys.prefix(7).flatMap { [Drill.inversions($0), .cadence($0)] }, isKnown: false),
    ]

    /// - Parameter best: best whole-run accuracy per drill id.
    public static func status(of unit: Unit, best: [String: Double]) -> Status {
        if unit.isKnown { return .known }
        let passed = unit.drills.count { (best[$0.id] ?? 0) >= passAccuracy }
        if passed == unit.drills.count { return .done }
        return currentUnit(best: best)?.id == unit.id ? .current(passed: passed) : .upcoming
    }

    /// The first unit that is neither known nor finished.
    public static func currentUnit(best: [String: Double]) -> Unit? {
        units.first { unit in
            !unit.isKnown && unit.drills.contains { (best[$0.id] ?? 0) < passAccuracy }
        }
    }

    /// What to practice today besides a song.
    public struct DailyPlan: Hashable, Sendable {
        /// A scale to warm up with.
        public let warmUp: Drill
        /// The next drill on the path; nil when the path is complete.
        public let drill: Drill?
    }

    /// - Parameters:
    ///   - best: best whole-run accuracy per drill id.
    ///   - day: any number that changes daily; it rotates the warm-up.
    public static func plan(best: [String: Double], day: Int) -> DailyPlan {
        // Warm up with a scale already learned, rotating daily; C major until one is.
        let learned = MusicKey.drillKeys.map(Drill.scale).filter { (best[$0.id] ?? 0) >= passAccuracy }
        let warmUp = learned.isEmpty ? Drill.scale(.c) : learned[((day % learned.count) + learned.count) % learned.count]
        let next = currentUnit(best: best)?.drills.first { (best[$0.id] ?? 0) < passAccuracy && $0 != warmUp }
        return DailyPlan(warmUp: warmUp, drill: next)
    }
}

/// Minutes practiced per day, for the daily goal, the week view and the streak (requirement CU-6).
public struct PracticeLog: Codable, Hashable, Sendable {
    /// Seconds practiced, keyed by day as "yyyy-MM-dd" in the user's calendar.
    public private(set) var secondsByDay: [String: Double] = [:]
    /// Identifiers of the drills and songs played through to the end, per day.
    public private(set) var completedByDay: [String: Set<String>] = [:]

    /// A day counts toward the streak from this many minutes.
    public static let streakMinutes = 5.0

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        secondsByDay = try container.decodeIfPresent([String: Double].self, forKey: .secondsByDay) ?? [:]
        completedByDay = try container.decodeIfPresent([String: Set<String>].self, forKey: .completedByDay) ?? [:]
    }

    public static func key(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    public mutating func add(seconds: Double, on date: Date, calendar: Calendar = .current) {
        secondsByDay[Self.key(for: date, calendar: calendar), default: 0] += seconds
    }

    /// Records that a drill or song was played through on a day.
    public mutating func markCompleted(_ id: String, on date: Date, calendar: Calendar = .current) {
        completedByDay[Self.key(for: date, calendar: calendar), default: []].insert(id)
    }

    public func isCompleted(_ id: String, on date: Date, calendar: Calendar = .current) -> Bool {
        completedByDay[Self.key(for: date, calendar: calendar)]?.contains(id) ?? false
    }

    public func minutes(on date: Date, calendar: Calendar = .current) -> Double {
        (secondsByDay[Self.key(for: date, calendar: calendar)] ?? 0) / 60
    }

    /// Minutes for the seven days ending on `date`, oldest first.
    public func week(endingOn date: Date, calendar: Calendar = .current) -> [(date: Date, minutes: Double)] {
        (0..<7).reversed().compactMap { back in
            calendar.date(byAdding: .day, value: -back, to: date).map { ($0, minutes(on: $0, calendar: calendar)) }
        }
    }

    /// Days in a row with enough practice, ending today, or yesterday if today has not
    /// reached it yet (so the streak does not vanish each morning).
    public func streak(asOf date: Date, calendar: Calendar = .current) -> Int {
        func counts(_ day: Date) -> Bool { minutes(on: day, calendar: calendar) >= Self.streakMinutes }
        var day = date
        if !counts(day) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var streak = 0
        while counts(day), let previous = calendar.date(byAdding: .day, value: -1, to: day) {
            streak += 1
            day = previous
        }
        return streak
    }
}
