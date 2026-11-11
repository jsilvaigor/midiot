import Foundation
import MusicCore
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

    @Test func eachHandLearnsAloneBeforeTheyPlayTogether() {
        let steps = Curriculum.allSteps
        // Every drill played together was first met one hand at a time, earlier in the path.
        for (index, step) in steps.enumerated() where step.hands == .together {
            if case .rhythm = step.drill { continue } // known from the flute
            if case .fiveFinger(_, let pattern) = step.drill, pattern > 1 { continue } // made for two hands
            #expect(steps[..<index].contains { $0.drill == step.drill && $0.hands != .together }, "\(step.id)")
        }
        // No hands-together unit comes before the last one-hand unit.
        let firstTogether = Curriculum.units.firstIndex { !$0.isKnown && $0.steps.contains { $0.hands == .together } }!
        #expect(Curriculum.units[firstTogether...].allSatisfy { $0.steps.allSatisfy { $0.hands == .together } })
        #expect(Set(steps.map(\.id)).count == steps.count)
    }

    @Test func aOneHandStepHasOnlyThatHandsNotes() {
        let right = Curriculum.Step(.scale(.g), .right), left = Curriculum.Step(.scale(.g), .left)
        let together = Curriculum.Step(.scale(.g), .together)
        #expect(right.song(title: "").notes.allSatisfy { $0.hand == .right })
        #expect(left.song(title: "").notes.allSatisfy { $0.hand == .left })
        #expect(right.song(title: "").notes.count + left.song(title: "").notes.count == together.song(title: "").notes.count)
        #expect(right.song(title: "").measures == together.song(title: "").measures)
        // History kept before one-hand steps existed belongs to the hands-together form.
        #expect(together.id == Drill.scale(.g).id)
        #expect(right.id != together.id && left.id != together.id && right.id != left.id)
        #expect(Curriculum.Step(.bassReading(level: 2), .left).id == Drill.bassReading(level: 2).id)
    }

    @Test func runsCountOnlyForTheHandsThatPlayed() {
        let together = Curriculum.Step(.scale(.c), .together), right = Curriculum.Step(.scale(.c), .right)
        #expect(together.accepts(runHands: ["left", "right"]))
        #expect(!together.accepts(runHands: ["right"]))
        #expect(right.accepts(runHands: ["right"]))
        #expect(!right.accepts(runHands: ["left"]))
    }

    @Test func passingStepsMovesThePathOn() {
        let five = Drill.fiveFinger(.c, pattern: 1)
        var best = [Curriculum.Step(five, .right).id: 0.9]
        #expect(Curriculum.status(of: unit(.fiveFinger), best: best) == .current(passed: 1))
        best[Curriculum.Step(five, .left).id] = 0.9
        #expect(Curriculum.status(of: unit(.fiveFinger), best: best) == .done)
        #expect(Curriculum.currentUnit(best: best)?.topic == .bassClef)
        best[Drill.bassReading(level: 1).id] = 0.86
        best[Drill.bassReading(level: 2).id] = 0.5 // tried, not passed
        #expect(Curriculum.status(of: unit(.bassClef), best: best) == .current(passed: 1))
    }

    @Test func dailyPlan() {
        typealias Step = Curriculum.Step
        let first = Curriculum.plan(best: [:], day: 3)
        #expect(first.warmUp == Step(.scale(.c), .right))
        #expect(first.drill == Step(.fiveFinger(.c, pattern: 1), .right))

        // With two scale steps learned the warm-up alternates, and the drill is the next unpassed one.
        var best = [Step(.fiveFinger(.c, pattern: 1), .right).id: 1.0, Step(.fiveFinger(.c, pattern: 1), .left).id: 1.0,
                    Step(.scale(.c), .right).id: 0.9, Step(.scale(.c), .left).id: 0.9]
        for level in 1...3 { best[Drill.bassReading(level: level).id] = 0.9 }
        #expect(Curriculum.plan(best: best, day: 0).warmUp == Step(.scale(.c), .right))
        #expect(Curriculum.plan(best: best, day: 1).warmUp == Step(.scale(.c), .left))
        #expect(Curriculum.plan(best: best, day: 0).drill == Step(.scale(.g), .right))
    }

    @Test func everyDrillInThePathExistsInTheCatalog() {
        let catalog = Set(Drill.catalog)
        #expect(Curriculum.allSteps.map(\.drill).allSatisfy(catalog.contains))
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
