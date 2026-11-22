import Foundation
import XCTest
@testable import XiaobaoCore

/// Only the campus calendar is real. The roster and dates being imported are local fixtures.
final class SchoolTimetableBellTests: XCTestCase {
    private let date = SchoolClock.date(2026, 12, 1)

    private func publication() throws -> PublishedSchoolCalendar {
        let root = (0..<4).reduce(URL(fileURLWithPath: #filePath)) { url, _ in url.deletingLastPathComponent() }
        let url = root.appendingPathComponent("xiaobao-backend/src/provider/academic-calendar-hs-2026-2027.json")
        return try JSONDecoder().decode(PublishedSchoolCalendar.self, from: Data(contentsOf: url))
    }

    private func course(_ title: String, on date: Date, from start: String, to end: String,
                        group: String? = nil) -> SchoolPortalWeek.Row {
        let key = SchoolClock.key(date)
        return .init(id: key + start + title, name: title, start: key + "T" + start + ":00+08:00",
                     course: group ?? "subject:" + title, kind: .lesson, end: key + "T" + end + ":00+08:00",
                     room: nil, allDay: false)
    }

    func testDisplacedSchoolClockKeepsTheMissingBlockAndReservesTheWholeLunch() throws {
        let calendar = try publication()
        for offset in [17, 25] {
            let late = { (minute: Int) in SchoolClock.time(minute + offset) }
            var book = SchoolTimetable(owner: "fixture", calendar: calendar, now: date)
            let rows = [(480,520,"Etching"),(530,570,"Etching"),(610,650,"Form"),
                        (710,750,"Paper"),(805,845,"Color"),(855,895,"History"),(905,945,"Practice")]
                .map { course($0.2, on: date, from: late($0.0), to: late($0.1)) }
            try book.absorb(.init(week: .init(containing: date), rows: rows), calendar: calendar)
            let day = try XCTUnwrap(book.day(on: date, calendar: calendar))
            let school = PlannerSchoolDay.connected(on: date, schedule: day.schedule, calendar: day.events) { $0 }
            func ranges(_ kind: PlannerSchoolEntry.Kind) -> [Range<Int>] {
                school.entries.filter { $0.kind == kind }.map { SchoolClock.minute(in: $0.start)..<SchoolClock.minute(in: $0.end!) }
            }
            XCTAssertEqual(ranges(.lesson), [480..<560,610..<650,710..<750,805..<845,855..<895,905..<945])
            XCTAssertEqual(ranges(.freeblock), [660..<700])
            XCTAssertEqual(ranges(.assembly), [570..<610])
            XCTAssertEqual(ranges(.lunch), [750..<805])
            XCTAssertEqual(book.lessonReminders(now: date, lead: 0, calendar: calendar).map { SchoolClock.minute(in: $0.fireDate) },
                           [480,610,710,805,855,905])
        }
    }

    func testCorroboratedWholeBlocksSplitAroundLunchButAnIndependentLongWorkshopStaysIntact() throws {
        let calendar = try publication()
        let rows = [(505,595,"Lanterns"),(610,700,"Sound"),(755,845,"Type"),(855,945,"Light")]
        var book = SchoolTimetable(owner: "arts-fixture", calendar: calendar, now: date)
        let courses = rows.map { course($0.2, on: date, from: SchoolClock.time($0.0), to: SchoolClock.time($0.1)) }
        try book.absorb(.init(week: .init(containing: date), rows: courses.reversed()), calendar: calendar)
        let blocks = try XCTUnwrap(book.day(on: date, calendar: calendar)?.timeline).blocks
        XCTAssertEqual(blocks.compactMap(\.lesson).map { SchoolClock.minute(in: $0.start) }, [480,610,660,710,805,855,905])
        let midday = SchoolClock.at(minute: 775, on: date)
        XCTAssertEqual(blocks.filter { $0.start <= midday && midday < $0.end }.map(\.id),
                       [.activity(.lunch, SchoolClock.at(minute: 750, on: date))])
        let visit = SchoolTimetable.Period(title: "Open workshop", room: nil, start: 755, end: 845)
        XCTAssertEqual(SchoolBellAlignment(records: [("club", visit)]).periods, [visit])
    }

    func testMixedPortalClocksAlsoRepairUnversionedDatedAndRotatingArchivesOffline() throws {
        let calendar = try publication(), key = SchoolClock.key(date)
        let published = [(505,545,"Mosaic"),(555,595,"Mosaic"),(610,650,"Materials"),(755,795,"Form"),
                         (805,845,"Computing"),(1100,1150,"Open studio")]
        var new = SchoolTimetable(owner: "fixture", calendar: calendar, now: date)
        let input = published.map { course($0.2, on: date, from: SchoolClock.time($0.0), to: SchoolClock.time($0.1)) }
        try new.absorb(.init(week: .init(containing: date), rows: input), calendar: calendar)
        let plist = try PropertyListSerialization.propertyList(from: PropertyListEncoder().encode(new), format: nil)
        var legacy = try XCTUnwrap(plist as? [String: Any])
        legacy.removeValue(forKey: "bellRevision")
        let raw = published.map { ["title": $0.2, "start": $0.0, "end": $0.1] as [String:Any] }
        let rotation = try XCTUnwrap(calendar.day(on: date).teachingDay)
        legacy["rotations"] = [String(rotation): raw]
        func decoded(_ keyed: [String:[[String:Any]]]) throws -> SchoolTimetable {
            var copy = legacy; copy["dated"] = keyed
            let bytes = try PropertyListSerialization.data(fromPropertyList: copy, format: .binary, options: 0)
            return try PropertyListDecoder().decode(SchoolTimetable.self, from: bytes)
        }
        let newSaved = try PropertyListDecoder().decode(SchoolTimetable.self, from: PropertyListEncoder().encode(new))
        for book in [newSaved, try decoded([key:raw]), try decoded([:])] {
            let day = try XCTUnwrap(book.day(on: date, calendar: calendar))
            let timeline = try XCTUnwrap(day.timeline)
            let school = PlannerSchoolDay.connected(on: date, schedule: day.schedule, calendar: day.events) { $0 }
            XCTAssertEqual(school.entries.map(\.id), timeline.blocks.map { .block($0.id) })
            let periods = timeline.blocks.compactMap(\.lesson)
            XCTAssertEqual(periods.map { SchoolClock.minute(in: $0.start) }, [480,610,710,805,1100])
            XCTAssertEqual(periods.map { SchoolClock.minute(in: $0.end) }, [560,650,750,845,1150])
            XCTAssertEqual(school.entries.filter { $0.kind == .freeblock }.map { SchoolClock.minute(in: $0.start) }, [660,855,905])
            XCTAssertEqual(school.entries.filter { $0.kind == .lunch }.map { SchoolClock.minute(in: $0.start)..<SchoolClock.minute(in: $0.end!) }, [750..<805])
            XCTAssertEqual(school.withCampusRoutine(on: date, calendar: calendar, showsBoardingRoutine: true)
                .entries.filter { SchoolClock.minute(in: $0.start) == 1100 }.count, 1)
            let alerts = book.lessonReminders(now: date, lead: 0, calendar: calendar).filter { SchoolClock.key($0.fireDate) == key }
            XCTAssertEqual(alerts.map { SchoolClock.minute(in:$0.fireDate) }, [480,610,710,805,1100])
        }
        let noB5 = try decoded([key:raw.filter { $0["start"] as? Int != 755 }])
        let day = try XCTUnwrap(noB5.day(on: date, calendar: calendar)?.timeline)
        XCTAssertTrue(day.blocks.contains { $0.id == .freeblock(SchoolClock.at(minute: 710, on: date)) })
        XCTAssertEqual(day.blocks.compactMap(\.lesson).map { SchoolClock.minute(in: $0.start) }, [480,610,805,1100])
    }

    func testAnUncorroboratedOpeningOffsetCannotMoveTwoIndependentAppointments() {
        typealias Record = SchoolBellAlignment.Record
        let a: Record = ("visit", .init(title: "Choir", room: nil, start: 496, end: 536))
        let b: Record = ("talk", .init(title: "Design talk", room: nil, start: 546, end: 586))
        let aligned = SchoolBellAlignment(records: [a,b])
        XCTAssertEqual(aligned.periods, [a.period,b.period])
        XCTAssertTrue(aligned.vacancies.isEmpty)
    }

    func testIndependentAppointmentsAndClosureNeverAcquireAnInventedClassTime() throws {
        let cal = try publication(), weekend = SchoolClock.date(2026,12,5)
        var book = SchoolTimetable(owner: "fixture", calendar: cal, now: date)
        let rows = [course("Lab visit", on: date, from: "12:44", to: "13:04"),
                    course("Field trip", on: weekend, from: "12:35", to: "13:15")]
        try book.absorb(.init(week: .init(containing: date), rows: rows), calendar: cal)
        let normal = try XCTUnwrap(book.day(on: date, calendar: cal)?.timeline)
        XCTAssertEqual(normal.blocks.compactMap(\.lesson).map { SchoolClock.minute(in: $0.start) }, [764])
        XCTAssertEqual(normal.focus(at: SchoolClock.at(minute: 770, on: date))?.lesson?.name, "Lab visit")
        XCTAssertEqual(normal.blocks.map(\.start).map(SchoolClock.minute(in:)), [570,750,764])
        let off = try XCTUnwrap(book.day(on: weekend, calendar: cal)?.timeline)
        XCTAssertEqual(off.blocks.count, 1)
        XCTAssertEqual(off.blocks.compactMap(\.lesson).map { SchoolClock.minute(in: $0.start) }, [755])
    }

    func testTwoMorningRowsOfOneEnrollmentBecomeOneClassAndOneReminder() throws {
        let calendar = try publication()
        var source = SchoolTimetable(owner: "local-fixture", calendar: calendar, now: date)
        let rows = [course("Printmaking", on: date, from: "08:00", to: "08:40"),
                    course("Printmaking", on: date, from: "08:50", to: "09:30")]
        try source.absorb(.init(week: .init(containing: date), rows: rows), calendar: calendar)
        let day = try XCTUnwrap(source.day(on: date, calendar: calendar))
        let timeline = try XCTUnwrap(day.timeline)
        let lessons = timeline.blocks.compactMap(\.lesson)
        XCTAssertEqual(lessons.map(\.name), ["Printmaking"])
        XCTAssertEqual(lessons.map { SchoolClock.minute(in: $0.start)..<SchoolClock.minute(in: $0.end) }, [480..<560])
        XCTAssertEqual(source.lessonReminders(now: date, lead: 0, calendar: calendar).map { SchoolClock.minute(in: $0.fireDate) }, [480])
        XCTAssertEqual(timeline.focus(at: SchoolClock.at(minute: 525, on: date))?.lesson?.name, "Printmaking")

        // Same displayed name isn't an enrollment ID; never erase a different section.
        var distinct = SchoolTimetable(owner: "local-fixture", calendar: calendar, now: date)
        try distinct.absorb(.init(week: .init(containing: date),
                                  rows: [rows[0], course("Printmaking", on: date, from: "08:50", to: "09:30", group: "other")]),
                            calendar: calendar)
        let sections = try XCTUnwrap(distinct.day(on: date, calendar: calendar)?.timeline).blocks.compactMap(\.lesson)
        XCTAssertEqual(sections.map { SchoolClock.minute(in: $0.start)..<SchoolClock.minute(in: $0.end) }, [480..<520,520..<560])
    }

    func testPartialExplicitVacanciesSurviveOfflineWithoutInventingOtherClassesOrFreeTime() throws {
        let calendar = try publication(), key = SchoolClock.key(date)
        let rows = [("11:50", "12:30"), ("10:50", "11:00")].map { start, end in
            SchoolPortalWeek.Row(id: key+start, name: "", start: key+"T"+start+":00+08:00", course: "",
                                 kind: .vacant, end: key+"T"+end+":00+08:00", room: nil, allDay: false)
        }
        var book = SchoolTimetable(owner: "fixture", calendar: calendar, now: date)
        try book.absorb(.init(week: .init(containing: date), rows: rows), calendar: calendar)
        let saved = try PropertyListDecoder().decode(SchoolTimetable.self, from: PropertyListEncoder().encode(book))
        XCTAssertTrue(saved.canReplace(nil))
        let blocks = try XCTUnwrap(saved.day(on: date, calendar: calendar)?.timeline).blocks
        XCTAssertEqual(blocks.map(\.id), [.activity(.assembly, SchoolClock.at(minute: 570, on: date)),
                                        .freeblock(SchoolClock.at(minute: 710, on: date)),
                                        .activity(.lunch, SchoolClock.at(minute: 750, on: date))])
        XCTAssertTrue(saved.rotations.isEmpty)
        let next = try XCTUnwrap(saved.day(on: SchoolClock.date(2026,12,2), calendar: calendar))
        XCTAssertEqual(next.schedule?.hasConfirmedRoster, false)
        XCTAssertEqual(next.timeline?.blocks.count, 2, "Only school-wide activities are known")
        XCTAssertTrue(saved.lessonReminders(now: date, lead: 5, calendar: calendar).isEmpty)
    }

    func testFullyBlankRosterAndNoResponseAreDifferentEvenOnReimport() throws {
        let calendar = try publication(), key = SchoolClock.key(date), week = TimetableWeek(containing: date)
        let halves = [TeachingSlot(start: 480, end: 520), TeachingSlot(start: 525, end: 565)]
        let blanks = (halves + CampusBells.teachingSlots.dropFirst()).map { slot in
            SchoolPortalWeek.Row(id: key+String(slot.start), name: "", start: key+"T"+SchoolClock.time(slot.start)+":00+08:00",
                                 course: "", kind: .vacant, end: key+"T"+SchoolClock.time(slot.end)+":00+08:00", room: nil, allDay: false)
        }
        var full = SchoolTimetable(owner: "fixture", calendar: calendar, now: date)
        try full.absorb(.init(week: week, rows: blanks), calendar: calendar)
        let day = try XCTUnwrap(full.day(on: date, calendar: calendar))
        XCTAssertEqual(day.timeline?.blocks.last.map { SchoolClock.minute(in: $0.end) }, 945)
        let school = PlannerSchoolDay.connected(on: date, schedule: day.schedule, calendar: day.events) { $0 }
            .withCampusRoutine(on: date, calendar: calendar, showsBoardingRoutine: false)
        XCTAssertEqual(school.entries.filter { $0.kind == .freeblock }.count, 7)
        XCTAssertEqual(school.entries.filter { $0.kind == .optionalBlock }.map(\.title), ["Block 9", "Block 10"])
        XCTAssertEqual(school.entries.filter { $0.kind == .campusRoutine }.count, 1)
        XCTAssertTrue(full.lessonReminders(now: date, lead: 0, calendar: calendar).isEmpty)
        var partial = SchoolTimetable(owner: "fixture", calendar: calendar, now: date)
        try partial.absorb(.init(week: week, rows: Array(blanks.suffix(2))), calendar: calendar)
        var sparse = SchoolTimetable(owner: "fixture", calendar: calendar, now: date)
        try sparse.absorb(.init(week: week, rows: [blanks[0], blanks.last!]), calendar: calendar)
        XCTAssertEqual(sparse.day(on: date, calendar: calendar)?.timeline?.blocks.count, 3, "One confirmed vacancy plus two campus activities")
        XCTAssertFalse(sparse.canReplace(partial))
        XCTAssertFalse(partial.canReplace(full))
        let classRow = course("Relief", on: date, from: "10:10", to: "10:50")
        try full.absorb(.init(week: week, rows: [classRow]), calendar: calendar)
        try full.absorb(.init(week: week, rows: []), calendar: calendar)
        XCTAssertEqual(full.day(on: date, calendar: calendar)?.timeline?.blocks.compactMap(\.lesson).map(\.name), ["Relief"])
    }

    func testElectiveReplacesOnlyItsOwnPlaceholderAndDoesNotExtendTheDaytimeBells() throws {
        let calendar = try publication()
        var source = SchoolTimetable(owner: "local-fixture", calendar: calendar, now: date)
        let rows = [course("Ceramics", on: date, from: "11:00", to: "11:40"),
                    course("Ensemble", on: date, from: "16:45", to: "17:35")]
        try source.absorb(.init(week: .init(containing: date), rows: rows), calendar: calendar)
        let day = try XCTUnwrap(source.day(on: date, calendar: calendar))
        let base = PlannerSchoolDay.connected(on: date, schedule: day.schedule, calendar: day.events) { $0 }
        let school = base.withCampusRoutine(on: date, calendar: calendar, showsBoardingRoutine: false)
        XCTAssertEqual(school.entries.filter { $0.kind == .optionalBlock }.map(\.title), ["Block 9"])
        XCTAssertEqual(school.entries.filter { $0.kind == .campusRoutine }.map { SchoolClock.minute(in: $0.start) }, [1055])
        let planner = PlannerDay(on: date, school: school, plans: [])
        let placeholder = SchoolClock.at(minute: 955, on: date)
        XCTAssertFalse(planner.timed.first { $0.start == placeholder }?.canBeFocus ?? true)
        XCTAssertTrue(planner.conflicts(with: try XCTUnwrap(PlanTime(startMinute: 980))).isEmpty)
        XCTAssertEqual(planner.conflicts(with: try XCTUnwrap(PlanTime(startMinute: 1010))).map(\.title), ["Ensemble"])
        XCTAssertTrue(try XCTUnwrap(day.timeline).blocks.allSatisfy { $0.lesson != nil || SchoolClock.minute(in: $0.end) <= 945 })
        XCTAssertEqual(source.lessonReminders(now: date, lead: 0, calendar: calendar).count, 2)
    }

    func testBoardingSundayReturnAndFridayDepartureAcrossMidnightAndHoliday() throws {
        let calendar = try publication()
        let bare = PlannerSchoolDay(rotationDay: nil, hasTimetable: false, hasCalendar: false, entries: [])
        func intervals(_ day: Date, enabled: Bool = true) -> [Range<Int>] {
            let school = bare.withCampusRoutine(on: day, calendar: calendar, showsBoardingRoutine: enabled)
            let scale = PlannerTimeScale(hourHeight: 72)
            return school.entries.map { Int(scale.minute($0.start, in: day))..<Int(scale.minute($0.end!, in: day)) }.sorted { $0.lowerBound < $1.lowerBound }
        }
        let sunday = SchoolClock.date(2026,11,29)
        let evening = [1100..<1150, 1155..<1205, 1205..<1260, 1260..<1350, 1350..<1440]
        let morning = [0..<420, 420..<460, 460..<480]
        XCTAssertEqual(intervals(sunday), [1055..<1100] + evening)
        XCTAssertEqual(intervals(SchoolClock.date(2026,12,3)), morning + evening)
        XCTAssertEqual(intervals(SchoolClock.date(2026,12,4)), morning)
        XCTAssertEqual(intervals(SchoolClock.date(2026,12,5)), [])
        XCTAssertEqual(intervals(sunday, enabled: false), [])
        XCTAssertEqual(intervals(SchoolClock.date(2026,10,4)), []) // National Day break
        XCTAssertEqual(intervals(SchoolClock.date(2028,1,9)), [])
        XCTAssertTrue(bare.withCampusRoutine(on: date, calendar: nil, showsBoardingRoutine: true).entries.isEmpty)
        let start = try XCTUnwrap(bare.withCampusRoutine(on: sunday, calendar: calendar, showsBoardingRoutine: true).entries.last)
        let end = try XCTUnwrap(bare.withCampusRoutine(on: SchoolClock.date(2026,11,30), calendar: calendar, showsBoardingRoutine: true).entries.first)
        XCTAssertEqual(start.id, end.id, "Both day columns refer to one overnight stay")
        XCTAssertEqual(start.end, end.start)
        XCTAssertFalse(start.isOvernightContinuation)
        XCTAssertTrue(end.isOvernightContinuation)
        let friday = SchoolClock.date(2026,12,4)
        let projection = bare.withCampusRoutine(on: friday, calendar: calendar, showsBoardingRoutine: true)
        let layout = PlannerTimelineLayout(day: .init(on: friday, school: projection, plans: []), scale: .init(hourHeight: 96), minimumHeight: 48)
        let breakfast = PlannerDay.TimedRow.ID.school(.routine(.breakfast, anchor: SchoolClock.date(2026,12,3)))
        XCTAssertTrue(layout.school.items.contains { $0.id == breakfast })
        XCTAssertFalse(layout.school.markGroups.flatMap(\.marks).contains { $0.id == breakfast })
    }

    func testOfflinePlannerAndTodayShareTheVacantPeriodAndBothCampusActivities() throws {
        let calendar = try publication()
        let roster = [("Composition", "08:00", "09:20"), ("Fieldwork", "10:10", "10:50"),
                      ("Seminar", "11:50", "12:30"), ("Sculpture", "13:25", "14:05"),
                      ("Studio", "14:15", "14:55"), ("Workshop", "15:05", "15:45")]
        var source = SchoolTimetable(owner: "local-fixture", calendar: calendar, now: date)
        try source.absorb(.init(week: .init(containing: date),
                                rows: roster.map { course($0.0, on: date, from: $0.1, to: $0.2) }), calendar: calendar)
        let saved = try PropertyListDecoder().decode(SchoolTimetable.self, from: PropertyListEncoder().encode(source))
        let day = try XCTUnwrap(saved.day(on: date, calendar: calendar))
        let today = try XCTUnwrap(day.timeline)
        let school = PlannerSchoolDay.connected(on: date, schedule: day.schedule, calendar: day.events) { $0 }
        let columns = PlannerDay(on: date, school: school, plans: [])
        let clock = SchoolClock.minute(in:)
        for height in [56.0, 92.0] {
            let layout = PlannerTimelineLayout(day: columns, scale: .init(hourHeight: height), minimumHeight: 18)
            XCTAssertEqual(layout.freeBlocks.map { clock($0.entry.start)..<clock($0.entry.end!) }, [660..<700])
        }
        for (kind, interval) in [(PlannerSchoolEntry.Kind.assembly, 570..<610), (.lunch, 750..<805)] {
            let entry = try XCTUnwrap(school.entries.first { $0.kind == kind })
            XCTAssertEqual(clock(entry.start)..<clock(try XCTUnwrap(entry.end)), interval)
        }
        XCTAssertEqual(school.entries.map(\.id), today.blocks.map { .block($0.id) })
        XCTAssertEqual(day.schedule?.lessons.count, roster.count, "Vacant periods and activities are never enrollments")
        XCTAssertEqual(saved.lessonReminders(now: date, lead: 0, calendar: calendar).count, roster.count)
    }
}
