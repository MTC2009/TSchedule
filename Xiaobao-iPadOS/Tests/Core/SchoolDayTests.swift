import XCTest
@testable import XiaobaoCore

final class SchoolDayTests: XCTestCase {
    func testElapsedFractionUsesEachIntervalIncludingItsExactEdges() {
        let start = SchoolClock.date(2027, 3, 10, minute: 571).addingTimeInterval(12)
        let end = start.addingTimeInterval(2240)
        let period = LessonTimeline.Period(id: "p", name: "Seminar", shortName: "S",
                                           room: nil, start: start, end: end)
        let interval = DateInterval(start: start, end: end)
        let blocks: [LessonTimeline.Block] = [.lesson(period), .freeblock(interval),
                                               .activity(.lunch, interval), .activity(.assembly, interval)]
        // Exercise the exact same fractions and rewind for every source of a tile.
        for block in blocks {
            for (offset, expected) in [(1680.0, 0.75), (-1, 0), (2240, 1), (560, 0.25), (0, 0), (2500, 1)] {
                XCTAssertEqual(block.elapsedFraction(at: start.addingTimeInterval(offset)), expected, accuracy: 0.000001)
            }
        }
        let invalid = LessonTimeline.Period(id: "zero", name: "", shortName: "", room: nil, start: end, end: end)
        XCTAssertEqual(LessonTimeline.Block.lesson(invalid).elapsedFraction(at: end), 0)
    }

    func testBreakCanFocusTheNextLessonWithoutMarkingAnyOfItElapsed() throws {
        let day = SchoolClock.date(2027, 4, 8)
        func period(_ id: String, _ start: Int, _ end: Int) -> LessonTimeline.Period {
            .init(id: id, name: id, shortName: id, room: nil,
                  start: SchoolClock.at(minute: start, on: day), end: SchoolClock.at(minute: end, on: day))
        }
        let dayPlan = try XCTUnwrap(LessonTimeline(on: day, periods: [period("lab", 558, 600), period("arts", 642, 667)]))
        for (minute, expected): (Int, [Double]) in [(500, [0, 0]), (579, [0.5, 0]), (623, [1, 0]), (652, [1, 0.4]), (700, [1, 1])] {
            let at = SchoolClock.at(minute: minute, on: day)
            XCTAssertEqual(dayPlan.blocks.map { $0.elapsedFraction(at: at) }, expected)
        }
        XCTAssertEqual(dayPlan.focus(at: SchoolClock.at(minute: 623, on: day))?.lesson?.id, "arts")
    }

    func testTimelineUsesSourceHoursAndEndExclusiveFocus() throws {
        let date = SchoolClock.date(2026, 2, 2)
        func period(_ id: String, _ start: Int, _ end: Int) -> LessonTimeline.Period {
            .init(id: id, name: id, shortName: id, room: nil,
                  start: SchoolClock.at(minute: start, on: date), end: SchoolClock.at(minute: end, on: date))
        }
        let data = try XCTUnwrap(LessonTimeline(on: date, periods: [period("later", 1090, 1150), period("first", 837, 901)]))
        XCTAssertEqual(data.bounds, 810...1170)
        XCTAssertEqual(data.blocks.compactMap(\.lesson).map(\.id), ["first", "later"])
        for (minute, id): (Int, String?) in [(0, "first"), (837, "first"), (900, "first"), (901, "later"),
                                               (1089, "later"), (1090, "later"), (1150, nil)] {
            XCTAssertEqual(data.focus(at: SchoolClock.at(minute: minute, on: date))?.lesson?.id, id)
        }
        let midnightEnd = try XCTUnwrap(LessonTimeline(on: date, periods: [period("late", 1420, 1440)]))
        XCTAssertEqual(midnightEnd.bounds, 1410...1440)
        XCTAssertNil(LessonTimeline(on: date, periods: [period("bad", 480, 479)]))
        XCTAssertNil(try XCTUnwrap(LessonTimeline(on: date, periods: [])).bounds)
    }

    func testServiceTimelineNeverSubstitutesAClassOrRoom() throws {
        let key = "2026-02-02"
        func schedule(_ start: String) -> CampusSchedule {
            CampusSchedule(date: key, day: 2, lessons: [.init(id: "slot", course_id: "subject",
                start: start, end: key + "T17:05:00+08:00", room: nil)])
        }
        let timeline = try XCTUnwrap(schedule(key + "T16:15:00+08:00").timeline { _ in "Studio" })
        XCTAssertEqual(timeline.blocks.first?.lesson?.name, "Studio")
        XCTAssertNil(timeline.blocks.first?.lesson?.room)
        XCTAssertEqual(timeline.bounds, 960...1050)
        XCTAssertNil(schedule("malformed").timeline { $0 })
        XCTAssertTrue(DemoSchoolProvider.courses.allSatisfy { $0.note.isEmpty })
    }
    let provider = DemoSchoolProvider()
    func testRotationAcrossWeekendAndBeforeAnchor() {
        XCTAssertEqual(provider.day(on: SchoolClock.date(2026, 11, 13)), 2)
        XCTAssertEqual(provider.day(on: SchoolClock.date(2026, 11, 16)), 3)
        XCTAssertEqual(provider.day(on: SchoolClock.date(2026, 11, 17)), 4)
        XCTAssertEqual(provider.day(on: SchoolClock.date(2026, 11, 20)), 1)
        XCTAssertNil(provider.day(on: SchoolClock.date(2026, 11, 21)))
        XCTAssertNil(provider.day(on: SchoolClock.date(2026, 11, 22)))
        XCTAssertEqual(provider.day(on: SchoolClock.date(2026, 11, 23)), 2)
    }
    func testSchoolClosureDoesNotConsumeRotationDay() {
        let calendar = SchoolCalendar(closures: ["2026-11-18"])
        XCTAssertNil(calendar.rotationDay(on: SchoolClock.date(2026, 11, 18)))
        XCTAssertEqual(calendar.rotationDay(on: SchoolClock.date(2026, 11, 19)), 5)
    }
    func testRotationMatchesAnIndependentDayWalkOnBothSidesOfAnchor() {
        let cal = SchoolClock.calendar
        let anchor = SchoolClock.date(2024, 2, 29)
        let closures: Set<String> = ["2023-12-25", "2024-02-28", "2024-03-01", "2024-03-02", "2025-01-01", "2024-02-31"]
        let rotation = SchoolCalendar(anchorDate: anchor, anchorDay: 3, cycleLength: 7, closures: closures)
        for direction in [-1, 1] {
            var day = anchor, expected = 3
            for _ in 0..<410 {
                day = cal.date(byAdding: .day, value: direction, to: day)!
                if cal.isDateInWeekend(day) || closures.contains(SchoolClock.key(day)) {
                    XCTAssertNil(rotation.rotationDay(on: day))
                } else {
                    expected = (expected - 1 + direction + 7) % 7 + 1
                    XCTAssertEqual(rotation.rotationDay(on: day), expected, SchoolClock.key(day))
                }
            }
        }
    }
    func testAnchorDateUsesSchoolTimeZone() {
        let date = ISO8601DateFormatter().date(from: "2026-11-16T16:05:00Z")!
        XCTAssertEqual(SchoolClock.key(date), "2026-11-17")
        XCTAssertEqual(provider.day(on: date), 4)
        XCTAssertEqual(SchoolClock.minute(in: date), 5)
        XCTAssertNil(SchoolClock.dayDate("20000-01-01"))
        XCTAssertNil(SchoolClock.dayDate("2026-02-30"))
    }
    func testReferenceTimetableAndStableIDs() {
        let date = SchoolClock.date(2026, 11, 17)
        let lessons = provider.lessons(on: date)
        XCTAssertEqual(lessons.count, 6)
        XCTAssertEqual(lessons[2].course.room, "B302")
        XCTAssertEqual(lessons[2].timeLabel, "11:00 – 11:40")
        XCTAssertEqual(Set(lessons.map(\.id)).count, 6)
        XCTAssertEqual(lessons.map(\.id), provider.lessons(on: date.addingTimeInterval(3600)).map(\.id))
        XCTAssertTrue(provider.lessons(on: SchoolClock.date(2026, 11, 21)).isEmpty)
    }
    func testAgendaAtEveryTransition() {
        let lessons = provider.lessons(on: SchoolClock.date(2026, 11, 17))
        XCTAssertEqual(Agenda(lessons: lessons, minute: 479).status, .beforeSchool)
        XCTAssertEqual(Agenda(lessons: lessons, minute: 480).status, .teaching)
        XCTAssertEqual(Agenda(lessons: lessons, minute: 530).status, .teaching)
        XCTAssertEqual(Agenda(lessons: lessons, minute: 560).status, .recess)
        XCTAssertEqual(Agenda(lessons: lessons, minute: 569).status, .recess)
        XCTAssertEqual(Agenda(lessons: lessons, minute: 570).status, .assembly)
        XCTAssertEqual(Agenda(lessons: lessons, minute: 609).status, .assembly)
        XCTAssertEqual(Agenda(lessons: lessons, minute: 610).status, .teaching)
        let recess = Agenda(lessons: lessons, minute: 655)
        XCTAssertEqual(recess.focus?.course.id, "physics")
        XCTAssertEqual(recess.remainingMinutes, 5)
        XCTAssertEqual(recess.upcoming.first?.course.id, "chinese")
        XCTAssertEqual(Agenda(lessons: lessons, minute: 660).status, .teaching)
        XCTAssertEqual(Agenda(lessons: lessons, minute: 700).status, .recess)
        XCTAssertEqual(Agenda(lessons: lessons, minute: 749).status, .teaching)
        XCTAssertEqual(Agenda(lessons: lessons, minute: 750).status, .lunch)
        XCTAssertEqual(Agenda(lessons: lessons, minute: 804).remainingMinutes, 1)
        XCTAssertEqual(Agenda(lessons: lessons, minute: 805).status, .teaching)
        XCTAssertEqual(Agenda(lessons: lessons, minute: 920).status, .finished)
        XCTAssertNil(Agenda(lessons: lessons, minute: 1400).focus)
        XCTAssertEqual(Agenda(lessons: [], minute: 600).status, .freeDay)
    }
}
