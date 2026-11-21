import XCTest
@testable import XiaobaoCore

final class WeekTimetableTests: XCTestCase {
    private var calendarURL: URL {
        let repository = (0..<4).reduce(URL(fileURLWithPath: #filePath)) { path, _ in path.deletingLastPathComponent() }
        return repository.appendingPathComponent("xiaobao-backend/src/provider/academic-calendar-hs-2026-2027.json")
    }

    func testPortalWeekStartsOnSundayWithoutChangingTheSchoolClock() {
        let week = TimetableWeek(containing: SchoolClock.date(2027, 1, 1))
        XCTAssertEqual(week.dates.map(SchoolClock.key), [
            "2026-12-27", "2026-12-28", "2026-12-29", "2026-12-30", "2026-12-31", "2027-01-01", "2027-01-02"
        ])
        XCTAssertEqual(SchoolClock.calendar.firstWeekday, 2)
    }

    func testTimedColumnsPreserveActualLengthsAndOverlaps() throws {
        let date = SchoolClock.date(2027, 4, 7)
        func period(_ id: String, _ from: Int, _ through: Int) -> LessonTimeline.Period {
            .init(id: id, name: id, shortName: id, room: nil,
                  start: SchoolClock.at(minute: from, on: date), end: SchoolClock.at(minute: through, on: date))
        }
        let timeline = try XCTUnwrap(LessonTimeline(on: date, periods: [
            period("lab", 467, 547), period("seminar", 492, 532), period("studio", 547, 587),
            period("later", 980, 1005),
        ]))
        let layout = WeekTimetableLayout(days: [day(date, status: .teaching, timeline: timeline)])
        XCTAssertEqual(layout.guideMarks, [420, 540, 660, 780, 900, 1020])
        let tiles = try XCTUnwrap(layout.placementsByDay.first)
        XCTAssertEqual(tiles.map { $0.end - $0.start }, [80, 40, 40, 25])
        XCTAssertEqual(tiles.map(\.lane), [0, 1, 0, 0])
        XCTAssertEqual(tiles.map(\.laneCount), [2, 2, 1, 1])
        XCTAssertEqual(tiles[0].end, tiles[2].start)
    }

    func testOnlyConfirmedEmptyColumnsYieldWidth() throws {
        let dates = TimetableWeek(containing: SchoolClock.date(2031, 5, 8)).dates
        let weekendLesson = period("makeup", 630, 670, on: dates[6])
        let makeup = try XCTUnwrap(LessonTimeline(on: dates[6], periods: [weekendLesson]))
        let conflict = try XCTUnwrap(LessonTimeline(on: dates[4], periods: [
            period("dated-lab", 520, 560, on: dates[4])
        ]))
        let days = [
            day(dates[0], status: .weekend),
            day(dates[1], status: .noClass, printedDay: 3),
            day(dates[2], status: .unpublished),
            WeekTimetableDay(date: dates[3], rotationDay: nil,
                             calendarDay: day(dates[3], status: .noClass).calendarDay,
                             timeline: nil, hasUnreadableTimes: true),
            day(dates[4], status: .noClass, timeline: conflict),
            day(dates[5], status: nil),
            day(dates[6], status: .teaching, printedDay: 2, timeline: makeup)
        ]
        let layout = WeekTimetableLayout(days: days)
        let edges = layout.columnEdges(in: 640)
        let widths = zip(edges, edges.dropFirst()).map { $1 - $0 }
        XCTAssertEqual(edges.count, 8)
        XCTAssertEqual(edges.last, 640)
        XCTAssertEqual(widths[0] / widths[6], 0.62, accuracy: 0.0001)
        XCTAssertEqual(widths[1] / widths[6], 0.74, accuracy: 0.0001)
        widths[2...5].forEach { XCTAssertEqual($0, widths[6], accuracy: 0.0001) }
        XCTAssertEqual(days[1].printedDay, 3)
        XCTAssertEqual(layout.placementsByDay[4].first?.id, .lesson("dated-lab"))
        XCTAssertEqual(layout.placementsByDay[6].first?.id, .lesson(weekendLesson.id))

        let empty = WeekTimetableLayout(days: dates.enumerated().map { index, date in
            day(date, status: .noClass, printedDay: index == 3 ? 4 : nil)
        })
        XCTAssertEqual(empty.columnEdges(in: 700), [0, 100, 200, 300, 400, 500, 600, 700])
    }

    func testMatchingCampusActivitiesShareBandsButDifferingIntervalsStayIndividual() throws {
        let dates = TimetableWeek(containing: SchoolClock.date(2031, 3, 18)).dates
        let days = try dates.enumerated().map { index, date -> WeekTimetableDay in
            guard (1...5).contains(index) else { return day(date, status: .weekend) }
            var classes = [period("studio", 540, 560, on: date), period("lab", 829, 880, on: date)]
            if index == 3 { classes.append(period("dated-lesson", 593, 616, on: date)) }
            let timeline = try XCTUnwrap(LessonTimeline(on: date, periods: classes, includesCampusActivities: true))
            return day(date, status: .teaching, printedDay: index, timeline: timeline)
        }
        let layout = WeekTimetableLayout(days: days)
        XCTAssertEqual(layout.activityBands.map(\.columns), [1..<3, 4..<6, 1..<6])
        XCTAssertEqual(layout.activityBands.map { $0.placement.end - $0.placement.start }, [40, 40, 55])
        XCTAssertEqual(layout.placementsByDay[1].map(\.id), [.lesson("studio"), .lesson("lab")])
        XCTAssertEqual(layout.placementsByDay[3].map { $0.end - $0.start }, [20, 23, 23, 51])
        XCTAssertEqual(layout.guideMarks, [480, 570, 660, 750, 805, 900, 960])
        let individualCount = layout.placementsByDay.map(\.count).reduce(0, +)
        let sharedCount = layout.activityBands.map { $0.columns.count }.reduce(0, +)
        let sourceCount = days.compactMap { $0.timeline?.blocks.count }.reduce(0, +)
        XCTAssertEqual(individualCount + sharedCount, sourceCount)
    }

    func testActivityBandsAndNoticesDoNotJumpAcrossCalendarGaps() throws {
        let dates = TimetableWeek(containing: SchoolClock.date(2031, 8, 13)).dates
        let days = try dates.enumerated().map { index, date -> WeekTimetableDay in
            if index == 2 || index == 3 || index == 6 {
                return day(date, status: .noClass, printedDay: 2, notices: ["Staff workshops"])
            }
            let lessons = [period("studio", 530, 552, on: date), period("lab", 852, 893, on: date)]
            let timeline = try XCTUnwrap(LessonTimeline(on: date, periods: lessons, includesCampusActivities: true))
            return day(date, status: .teaching, printedDay: 3,
                       notices: index == 4 ? ["Staff workshops"] : [], timeline: timeline)
        }
        let layout = WeekTimetableLayout(days: days)
        XCTAssertEqual(layout.activityBands.map(\.columns), [0..<2, 4..<6, 0..<2, 4..<6])
        XCTAssertEqual(layout.noticeGroups.filter { !$0.notices.isEmpty }.map(\.columns), [2..<4, 4..<5, 6..<7])
        XCTAssertTrue(layout.placementsByDay[2].isEmpty)
        XCTAssertTrue(layout.placementsByDay[3].isEmpty)
    }

    private func day(_ date: Date, status: SchoolCalendarDay.Status?, printedDay: Int? = nil,
                     notices: [String] = [], timeline: LessonTimeline? = nil) -> WeekTimetableDay {
        let publication = status.map { SchoolCalendarDay(date: SchoolClock.key(date), day: printedDay,
                                                         status: $0, notices: notices) }
        return WeekTimetableDay(date: date, rotationDay: nil, calendarDay: publication, timeline: timeline)
    }

    private func period(_ id: String, _ start: Int, _ end: Int, on date: Date) -> LessonTimeline.Period {
        .init(id: id, name: id, shortName: id, room: "E12",
              start: SchoolClock.at(minute: start, on: date), end: SchoolClock.at(minute: end, on: date))
    }

    func testBundledCalendarSeparatesHighSchoolClosureFromPrintedDay() throws {
        let publication = try JSONDecoder().decode(PublishedSchoolCalendar.self, from: Data(contentsOf: calendarURL))
        let provider = DemoSchoolProvider(schoolCalendar: SchoolCalendar(publication: publication))
        XCTAssertEqual(publication.division, "HS")
        XCTAssertEqual(publication.days.count, 365)
        let later = SchoolClock.date(2027, 4, 26)
        XCTAssertEqual(publication.day(on: later).day, 2)
        XCTAssertEqual(publication.day(on: later).status, .noClass)
        XCTAssertNil(provider.day(on: later))
        XCTAssertTrue(provider.lessons(on: later).isEmpty)
        XCTAssertEqual(provider.day(on: SchoolClock.date(2027, 4, 23)), 2)
        XCTAssertEqual(provider.day(on: SchoolClock.date(2027, 4, 27)), 3)
        XCTAssertEqual(provider.day(on: SchoolClock.date(2027, 1, 18)), 1)
        XCTAssertEqual(provider.day(on: SchoolClock.date(2027, 2, 17)), 5)
        let unknown = SchoolClock.date(2027, 8, 2)
        XCTAssertEqual(publication.day(on: unknown).status, .unpublished)
        XCTAssertNil(provider.timeline(on: unknown, lessons: provider.lessons(on: unknown)))
    }

    func testPublicationSupportsWeekendMakeupAndRejectsMalformedDates() throws {
        let dates = ["2027-03-12", "2027-03-13", "2027-03-14"]
        let rows = [
            SchoolCalendarDay(date: dates[0], day: 5, status: .noClass, notices: ["No regular class"]),
            .init(date: dates[1], day: 5, status: .teaching, notices: []),
            .init(date: dates[2], day: nil, status: .weekend, notices: []),
        ]
        let header: [String: Any] = ["campus": "test", "academic_year": "2026-2027", "division": "HS",
                                     "from": dates[0], "through": dates[2], "source_sha256": "synthetic"]
        func encode(_ rows: [SchoolCalendarDay]) throws -> Data {
            var dict = header
            dict["days"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(rows))
            return try JSONSerialization.data(withJSONObject: dict)
        }
        let publication = try JSONDecoder().decode(PublishedSchoolCalendar.self, from: encode(rows))
        let calendar = SchoolCalendar(publication: publication)
        XCTAssertEqual(calendar.rotationDay(on: SchoolClock.date(2027, 3, 13)), 5)
        XCTAssertNil(calendar.rotationDay(on: SchoolClock.date(2027, 3, 12)))
        XCTAssertThrowsError(try JSONDecoder().decode(PublishedSchoolCalendar.self, from: encode([rows[0], rows[0], rows[2]])))
    }

    func testCalendarConflictKeepsDatedLessonsAndDoesNotInferFreeBlocks() throws {
        let key = "2027-03-26"
        let schedule = CampusSchedule(date: key, day: nil, lessons: [
            .init(id: "dated", course_id: "lab", start: key + "T10:10:00+08:00",
                  end: key + "T10:50:00+08:00", room: "R08")
        ], teaching_slots: CampusBells.teachingSlots,
           calendarDay: .init(date: key, day: nil, status: .noClass, notices: ["Faculty training"]))
        let timeline = try XCTUnwrap(schedule.timeline { $0 })
        XCTAssertEqual(timeline.blocks.map(\.id), [.lesson("dated")])
        XCTAssertTrue(timeline.recesses.isEmpty)
    }
}
