import Foundation
import MusicCore

/// The guided path (requirement CU-1): units of drills in teaching order, for someone who
/// already reads music and keeps time but is new to the keyboard. Each hand learns a drill
/// alone first; the same drills come back hands together later in the path.
public enum Curriculum {
    /// One thing to practice: a drill, and which hands play it.
    public struct Step: Identifiable, Hashable, Sendable {
        public enum Hands: String, Hashable, Sendable {
            case right, left, together
        }

        public let drill: Drill
        public let hands: Hands

        public init(_ drill: Drill, _ hands: Hands) {
            self.drill = drill
            self.hands = hands
        }

        /// Stable identifier, used to keep the step's practice history. The full form of a
        /// drill keeps the drill's own identifier.
        public var id: String {
            switch hands {
            case .together: drill.id
            case .right: drill.id + "-rh"
            case .left: drill.isForLeftHandAlone ? drill.id : drill.id + "-lh"
            }
        }

        /// The exercise with only the notes of the hands that play it.
        public func song(title: String, seed: UInt64 = 0) -> Song {
            let full = drill.song(title: title, seed: seed)
            guard hands != .together else { return full }
            let hand: Hand = hands == .right ? .right : .left
            return Song(title: title, notes: full.notes.filter { $0.hand == hand }, tempoMap: full.tempoMap, measures: full.measures)
        }

        /// Whether a run played with these hands ("left", "right") counts for this step.
        public func accepts(runHands: [String]) -> Bool {
            switch hands {
            case .together: Set(runHands) == ["left", "right"]
            case .right: runHands.contains("right")
            case .left: runHands.contains("left")
            }
        }
    }

    public struct Unit: Identifiable, Hashable, Sendable {
        public enum Topic: String, Sendable, CaseIterable {
            case treble, rhythm, fiveFinger, bassClef, scales, arpeggios, chords
            case handsTogether, scalesTogether, arpeggiosTogether, chordsTogether
        }

        public let topic: Topic
        public let steps: [Step]
        /// True for what a flautist already knows; such a unit never blocks the path.
        public let isKnown: Bool

        public var id: String { topic.rawValue }
    }

    public enum Status: Hashable, Sendable {
        /// Known from earlier musical training.
        case known
        case done
        /// The unit being worked on, with how many of its steps are passed.
        case current(passed: Int)
        case upcoming
    }

    /// A step is passed once its best whole run reaches this accuracy.
    public static let passAccuracy = 0.85

    /// First each hand alone, then, with the fingers trained, both together.
    public static let units: [Unit] = {
        func eachHand(_ drill: Drill) -> [Step] { [Step(drill, .right), Step(drill, .left)] }
        let keys = MusicKey.drillKeys
        let chordKeys = Array(keys.prefix(7))
        return [
            Unit(topic: .treble, steps: [], isKnown: true),
            Unit(topic: .rhythm, steps: (1...3).map { Step(.rhythm(level: $0), .together) }, isKnown: true),
            Unit(topic: .fiveFinger, steps: eachHand(.fiveFinger(.c, pattern: 1)), isKnown: false),
            Unit(topic: .bassClef, steps: (1...3).map { Step(.bassReading(level: $0), .left) }, isKnown: false),
            Unit(topic: .scales, steps: keys.flatMap { eachHand(.scale($0)) }, isKnown: false),
            Unit(topic: .arpeggios, steps: keys.flatMap { eachHand(.arpeggio($0)) }, isKnown: false),
            // The chords sit in the right hand; the left only adds the bass note later.
            Unit(topic: .chords, steps: chordKeys.flatMap { [Step(.inversions($0), .right), Step(.cadence($0), .right)] }, isKnown: false),
            Unit(topic: .handsTogether, steps: (1...3).map { Step(.fiveFinger(.c, pattern: $0), .together) }, isKnown: false),
            Unit(topic: .scalesTogether, steps: keys.map { Step(.scale($0), .together) }, isKnown: false),
            Unit(topic: .arpeggiosTogether, steps: keys.map { Step(.arpeggio($0), .together) }, isKnown: false),
            Unit(topic: .chordsTogether, steps: chordKeys.flatMap { [Step(.inversions($0), .together), Step(.cadence($0), .together)] }, isKnown: false),
        ]
    }()

    /// Every step of the path, in order.
    public static var allSteps: [Step] { units.flatMap(\.steps) }

    /// - Parameter best: best whole-run accuracy per step id.
    public static func status(of unit: Unit, best: [String: Double]) -> Status {
        if unit.isKnown { return .known }
        let passed = unit.steps.count { (best[$0.id] ?? 0) >= passAccuracy }
        if passed == unit.steps.count { return .done }
        return currentUnit(best: best)?.id == unit.id ? .current(passed: passed) : .upcoming
    }

    /// The first unit that is neither known nor finished.
    public static func currentUnit(best: [String: Double]) -> Unit? {
        units.first { unit in
            !unit.isKnown && unit.steps.contains { (best[$0.id] ?? 0) < passAccuracy }
        }
    }

    /// What to practice today besides a song.
    public struct DailyPlan: Hashable, Sendable {
        /// A scale to warm up with.
        public let warmUp: Step
        /// The next step on the path; nil when the path is complete.
        public let drill: Step?
    }

    /// - Parameters:
    ///   - best: best whole-run accuracy per step id.
    ///   - day: any number that changes daily; it rotates the warm-up.
    public static func plan(best: [String: Double], day: Int) -> DailyPlan {
        // Warm up with a scale already learned, rotating daily; C major, right hand, until one is.
        let scales = allSteps.filter { if case .scale = $0.drill { true } else { false } }
        let learned = scales.filter { (best[$0.id] ?? 0) >= passAccuracy }
        let warmUp = learned.isEmpty ? Step(.scale(.c), .right) : learned[((day % learned.count) + learned.count) % learned.count]
        let next = currentUnit(best: best)?.steps.first { (best[$0.id] ?? 0) < passAccuracy && $0 != warmUp }
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
