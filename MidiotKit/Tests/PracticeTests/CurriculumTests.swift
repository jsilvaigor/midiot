import Foundation
import Testing
@testable import Practice

@Suite struct CurriculumTests {
    func unit(_ topic: Curriculum.Unit.Topic) -> Curriculum.Unit { Curriculum.units.first { $0.topic == topic }! }

    @Test func aBeginnerStartsAtFiveFingerPositions() {
        #expect(Curriculum.currentUnit(best: [:])?.topic == .fiveFinger)
        #expect(Curriculum.status(of: unit(.treble), best: [:]) == .known)
        #expect(Curriculum.status(of: unit(.rhythm), best: [:]) == .known)
        #expect(Curriculum.status(of: unit(.fiveFinger), best: [:]) == .current(passed: 0))
        #expect(Curriculum.status(of: unit(.bassClef), best: [:]) == .upcoming)
    }

    @Test func passingDrillsMovesThePathOn() {
        var best = [Drill.fiveFinger(.c, pattern: 1).id: 0.9]
        #expect(Curriculum.status(of: unit(.fiveFinger), best: best) == .done)
        #expect(Curriculum.currentUnit(best: best)?.topic == .bassClef)
        best[Drill.bassReading(level: 1).id] = 0.86
        best[Drill.bassReading(level: 2).id] = 0.5 // tried, not passed
        #expect(Curriculum.status(of: unit(.bassClef), best: best) == .current(passed: 1))
    }

    @Test func dailyPlan() {
        let first = Curriculum.plan(best: [:], day: 3)
        #expect(first.warmUp == .scale(.c))
        #expect(first.drill == .fiveFinger(.c, pattern: 1))

        // With two scales learned the warm-up alternates, and the drill is the next unpassed one.
        var best = [Drill.fiveFinger(.c, pattern: 1).id: 1.0, Drill.scale(.c).id: 0.9, Drill.scale(.g).id: 0.9]
        for level in 1...3 { best[Drill.bassReading(level: level).id] = 0.9 }
        #expect(Curriculum.plan(best: best, day: 0).warmUp == .scale(.c))
        #expect(Curriculum.plan(best: best, day: 1).warmUp == .scale(.g))
        #expect(Curriculum.plan(best: best, day: 0).drill == .fiveFinger(.c, pattern: 2))
    }

    @Test func everyDrillInThePathExistsInTheCatalog() {
        let catalog = Set(Drill.catalog)
        #expect(Curriculum.units.flatMap(\.drills).allSatisfy(catalog.contains))
    }
}

@Suite struct PracticeLogTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    func day(_ number: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: number, hour: 12))!
    }

    @Test func minutesAndWeek() {
        var log = PracticeLog()
        log.add(seconds: 600, on: day(10), calendar: calendar)
        log.add(seconds: 300, on: day(10), calendar: calendar)
        log.add(seconds: 120, on: day(8), calendar: calendar)
        #expect(log.minutes(on: day(10), calendar: calendar) == 15)
        let week = log.week(endingOn: day(10), calendar: calendar)
        #expect(week.count == 7)
        #expect(week.map(\.minutes) == [0, 0, 0, 0, 2, 0, 15])
        #expect(PracticeLog.key(for: day(4), calendar: calendar) == "2026-11-04")
    }

    @Test func streakCountsConsecutiveDays() {
        var log = PracticeLog()
        for number in [5, 6, 7, 9, 10] { log.add(seconds: 400, on: day(number), calendar: calendar) }
        #expect(log.streak(asOf: day(10), calendar: calendar) == 2)
        #expect(log.streak(asOf: day(7), calendar: calendar) == 3)
        // Not practiced yet today: yesterday's streak still stands.
        #expect(log.streak(asOf: day(11), calendar: calendar) == 2)
        #expect(log.streak(asOf: day(13), calendar: calendar) == 0)
        // Two minutes is not enough to count.
        log.add(seconds: 120, on: day(11), calendar: calendar)
        #expect(log.streak(asOf: day(11), calendar: calendar) == 2)
    }

    @Test func survivesSaving() throws {
        var log = PracticeLog()
        log.add(seconds: 90, on: day(3), calendar: calendar)
        let copy = try JSONDecoder().decode(PracticeLog.self, from: JSONEncoder().encode(log))
        #expect(copy == log)
    }
}
