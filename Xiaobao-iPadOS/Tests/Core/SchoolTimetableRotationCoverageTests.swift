import Foundation
import XCTest
@testable import XiaobaoCore

/// These are invented registrations; the bundled publication supplies only dates and Day numbers.
@MainActor final class SchoolTimetableRotationCoverageTests: XCTestCase {
    private func calendar() throws -> PublishedSchoolCalendar {
        let root = (0..<4).reduce(URL(fileURLWithPath: #filePath)) { url, _ in url.deletingLastPathComponent() }
        return try JSONDecoder().decode(PublishedSchoolCalendar.self, from: Data(contentsOf:
            root.appendingPathComponent("xiaobao-backend/src/provider/academic-calendar-hs-2026-2027.json")))
    }

    private func sample(_ start: Date, calendar: PublishedSchoolCalendar, alteredDate: String? = nil,
                        substitutions: [String: [SchoolPortalWeek.Row]] = [:]) throws -> SchoolPortalWeek {
        let week = TimetableWeek(containing: start)
        var rows: [SchoolPortalWeek.Row] = []
        for date in week.dates {
            guard let rotation = calendar.day(on: date).teachingDay else { continue }
            let key = SchoolClock.key(date)
            if let replacement = substitutions[key] { rows.append(contentsOf: replacement); continue }
            func add(_ title: String, _ start: String, _ end: String) {
                rows.append(.init(id: key + start, name: title, start: key+"T"+start+":00+08:00",
                                  course: title, kind: .lesson, end: key+"T"+end+":00+08:00", room:nil, allDay:false))
            }
            add("Sculpture \(rotation)", "10:10", "10:50")
            add(key == alteredDate ? "Dated colloquium" : "Studio \(rotation)", "14:15", "14:55")
            add("Archive lab", "15:55", "16:45")
            // The optional late visit follows a weekday; it is not part of the six-Day cycle.
            if [2,4].contains(SchoolClock.calendar.component(.weekday, from: date)) {
                add("Production visit", "18:20", "19:10")
            }
        }
        return try .init(week: week, rows: rows)
    }

    func testVaryingLateRegistrationNeverInvalidatesTheDaytimeRotation() throws {
        let calendar = try calendar(), now = SchoolClock.date(2027,3,18)
        var book = SchoolTimetable(owner:"fixture", calendar:calendar, now:now)
        for start in SchoolTimetable.sampleWeeks(near:now, calendar:calendar) {
            try book.absorb(sample(start,calendar:calendar),calendar:calendar)
        }
        XCTAssertEqual(book.rotations.count,6)
        let dates = calendar.days.filter { $0.teachingDay != nil && book.dated[$0.date] == nil }
        XCTAssertGreaterThan(dates.count,100)
        let missing = dates.filter { row in
            guard let date = SchoolClock.dayDate(row.date), let day = book.day(on:date,calendar:calendar) else { return true }
            let school = PlannerSchoolDay.connected(on:date,schedule:day.schedule,calendar:day.events) { $0 }
            let lessons = school.entries.filter { $0.kind == .lesson && SchoolClock.minute(in:$0.start) < 945 }
            return !school.hasTimetable || lessons.map(\.title) != ["Sculpture \(row.teachingDay!)","Studio \(row.teachingDay!)"]
        }
        XCTAssertEqual(missing.count,0, "A dated evening difference cannot erase corroborated daytime classes.")
        let target = try XCTUnwrap(dates.first.flatMap { SchoolClock.dayDate($0.date) })
        let late = try XCTUnwrap(book.day(on:target, calendar:calendar)?.timeline).blocks.compactMap(\.lesson)
            .filter { SchoolClock.minute(in:$0.start) >= 945 }
        XCTAssertEqual(late.map(\.name), ["Archive lab"], "A corroborated elective survives; a dated visit does not recur.")
        let exact = try XCTUnwrap(book.dated.first { $0.value.contains { $0.title == "Production visit" } })
        XCTAssertTrue(try XCTUnwrap(book.day(on:SchoolClock.dayDate(exact.key)!, calendar:calendar)?.timeline)
            .blocks.compactMap(\.lesson).contains { $0.name == "Production visit" })
    }

    func testDaytimeConflictAndClosuresCannotBeFilledWithAConvenientWeek() throws {
        let cal = try calendar(), pivot = SchoolClock.date(2026,12,10)
        let occurrence = try XCTUnwrap(cal.day(on:pivot).teachingDay)
        var book = SchoolTimetable(owner:"fixture", calendar:cal, now:pivot)
        for start in SchoolTimetable.sampleWeeks(near:pivot,calendar:cal) {
            try book.absorb(sample(start,calendar:cal,alteredDate:SchoolClock.key(pivot)),calendar:cal)
        }
        let other = try XCTUnwrap(cal.days.last { $0.teachingDay == occurrence && book.dated[$0.date] == nil })
        let day = try XCTUnwrap(book.day(on:SchoolClock.dayDate(other.date)!, calendar:cal))
        XCTAssertFalse(day.schedule?.hasConfirmedRoster == true)
        XCTAssertTrue(try XCTUnwrap(day.timeline).blocks.allSatisfy { if case .activity = $0 { true } else { false } })
        let closed = try XCTUnwrap(cal.days.first { $0.status == .noClass })
        XCTAssertTrue(book.day(on:SchoolClock.dayDate(closed.date)!, calendar:cal)?.timeline?.blocks.isEmpty == true)
    }

    private func special(_ date: String, _ name: String, _ kind: SchoolPortalWeek.Row.Kind,
                         _ start: String, _ end: String) -> SchoolPortalWeek.Row {
        .init(id:date+start, name:name, start:date+"T"+start+":00+08:00", course:kind == .lesson ? name : "",
              kind:kind, end:date+"T"+end+":00+08:00", room:nil, allDay:false)
    }

    func testTruncatedPublicationDoesNotInvalidateRotationOrHideDatedEvening() throws {
        let cal = try calendar(), asOf = SchoolClock.date(2027,3,4)
        let evening = "2027-03-17", empty = "2027-03-18", event = "2027-03-19", interior = "2027-03-05"
        let changes: [String:[SchoolPortalWeek.Row]] = [
            evening:[special(evening,"Visiting ensemble",.lesson,"18:21","19:01")], empty:[], interior:[],
            event:[special(event,"Matinee",.activity,"10:00","11:30")]
        ]
        var book = SchoolTimetable(owner:"fixture",calendar:cal,now:asOf)
        for start in [SchoolClock.date(2027,2,22), SchoolClock.date(2027,3,1),
                      SchoolClock.date(2027,3,8), SchoolClock.date(2027,3,15)] {
            try book.absorb(sample(start,calendar:cal,substitutions:changes),calendar:cal)
        }
        func day(_ key: String) throws -> SchoolTimetable.Day {
            try XCTUnwrap(book.day(on:SchoolClock.dayDate(key)!,calendar:cal))
        }
        func classes(_ key: String) throws -> [String] { try day(key).schedule?.lessons.map(\.course_id) ?? [] }
        XCTAssertEqual(book.rotations.count,6)
        XCTAssertEqual(try classes(evening),["Sculpture 1","Studio 1","Visiting ensemble"])
        XCTAssertEqual(try classes(empty),["Sculpture 2","Studio 2"])
        XCTAssertTrue(try day(evening).usesDaytimeRotation)
        XCTAssertTrue(try day(empty).usesDaytimeRotation)
        XCTAssertFalse(try day(interior).usesDaytimeRotation)
        XCTAssertTrue(try classes("2027-03-25").contains("Sculpture 1"))
        XCTAssertTrue(try classes(interior).isEmpty)
        XCTAssertFalse(try day(interior).schedule?.hasConfirmedRoster == true)
        XCTAssertFalse(try day(event).schedule?.hasConfirmedRoster == true)
        XCTAssertEqual(try day(event).events.events.map(\.title),["Matinee"])
        let fires = book.lessonReminders(now:SchoolClock.dayDate(evening)!,lead:0,calendar:cal).map(\.fireDate)
        XCTAssertEqual(fires.filter { SchoolClock.key($0) == evening }.map { SchoolClock.minute(in:$0) },[18*60+21])
        XCTAssertFalse(fires.contains { SchoolClock.key($0) == empty })

        let encoded = try PropertyListEncoder().encode(book)
        let fields = try XCTUnwrap(PropertyListSerialization.propertyList(from:encoded,format:nil) as? [String:Any])
        XCTAssertNil(fields["daytimeProjectionDates"], "A coverage decision is not a dated school record")
        book = try PropertyListDecoder().decode(SchoolTimetable.self,from:encoded)
        book.rebuildRotations(calendar:cal)
        XCTAssertTrue(try day(evening).usesDaytimeRotation)
        XCTAssertEqual(try classes(empty),["Sculpture 2","Studio 2"])

        // More dated teaching later makes the old tail an interior gap, not a permanent override.
        try book.absorb(sample(SchoolClock.date(2027,3,22),calendar:cal),calendar:cal)
        XCTAssertEqual(try classes(evening),["Visiting ensemble"])
        XCTAssertTrue(try classes(empty).isEmpty)
    }

    func testExplicitBlankOrPastGapIsNeverFilledFromThePublishedCycle() throws {
        let cal = try calendar(), last = "2027-03-19", late = special(last,"Music hour",.lesson,"18:00","18:50")
        var book = SchoolTimetable(owner:"fixture",calendar:cal,now:SchoolClock.date(2027,3,25))
        for start in [SchoolClock.date(2027,3,1), SchoolClock.date(2027,3,8), SchoolClock.date(2027,3,15)] {
            try book.absorb(sample(start,calendar:cal,substitutions:["2027-03-18":[], last:[late]]),calendar:cal)
        }
        let past = try XCTUnwrap(book.day(on:SchoolClock.date(2027,3,18),calendar:cal))
        XCTAssertFalse(past.schedule?.hasConfirmedRoster == true)
        var blanks = SchoolTimetable(owner:"fixture",calendar:cal,now:SchoolClock.date(2027,3,5))
        let explicit = CampusBells.teachingSlots.map { special(last,"",.vacant,SchoolClock.time($0.start),SchoolClock.time($0.end)) }
        for start in [SchoolClock.date(2027,3,1), SchoolClock.date(2027,3,8), SchoolClock.date(2027,3,15)] {
            try blanks.absorb(sample(start,calendar:cal,substitutions:[last:explicit + [late]]),calendar:cal)
        }
        let date = try XCTUnwrap(blanks.day(on:SchoolClock.dayDate(last)!,calendar:cal))
        XCTAssertEqual(date.schedule?.lessons.map(\.course_id),["Music hour"])
        XCTAssertEqual(date.schedule?.teaching_slots,CampusBells.teachingSlots)
    }

    func testPartialVacancyConstrainsOnlyItsReportedBell() throws {
        let cal = try calendar(), key = "2027-03-17", now = SchoolClock.date(2027,3,5)
        let late = special(key,"Music hour",.lesson,"18:00","18:50")
        func book(with rows: [SchoolPortalWeek.Row]) throws -> SchoolTimetable {
            var book = SchoolTimetable(owner:"fixture",calendar:cal,now:now)
            for start in [SchoolClock.date(2027,3,1),SchoolClock.date(2027,3,8),SchoolClock.date(2027,3,15)] {
                try book.absorb(sample(start,calendar:cal,substitutions:[key:rows]),calendar:cal)
            }
            return book
        }
        let compatible = try book(with:[special(key,"",.vacant,"11:00","11:40"),late])
        let other = try XCTUnwrap(compatible.day(on:SchoolClock.date(2027,3,25),calendar:cal))
        XCTAssertTrue(other.schedule?.lessons.contains { $0.course_id == "Sculpture 1" } == true)
        let exact = try XCTUnwrap(compatible.day(on:SchoolClock.dayDate(key)!,calendar:cal))
        XCTAssertFalse(exact.usesDaytimeRotation)
        XCTAssertEqual(exact.schedule?.lessons.map(\.course_id),["Music hour"])
        XCTAssertEqual(exact.schedule?.teaching_slots,[.init(start:660,end:700)])

        // Even without an enrollment that day, an explicit blank overlapping a normal
        // class is evidence against the proposed cycle. A single blank is not a free day.
        let conflicting = try book(with:[special(key,"",.vacant,"10:10","10:50")])
        XCTAssertNil(conflicting.rotations[1])
    }

    func testBuildFiveArchiveRestoresCoverageWithoutARefreshOrFileRewrite() async throws {
        let cal = try calendar(), pivot = SchoolClock.date(2027,3,18)
        var source = SchoolTimetable(owner:"fixture",calendar:cal,now:pivot)
        for start in SchoolTimetable.sampleWeeks(near:pivot,calendar:cal) {
            try source.absorb(sample(start,calendar:cal),calendar:cal)
        }
        let encoded = try PropertyListEncoder().encode(source)
        var legacy = try XCTUnwrap(PropertyListSerialization.propertyList(from:encoded,format:nil) as? [String:Any])
        legacy["rotations"] = [String:Any]()  // Earlier full-day comparison rejected every useful template.
        legacy.removeValue(forKey:"bellRevision")
        let registration = UUID(), suite = "CoverageTests."+registration.uuidString
        let settings = try XCTUnwrap(UserDefaults(suiteName:suite))
        settings.set(registration.uuidString, forKey:"tschedule.timetable.v1.registration")
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(suite+".plist")
        let bytes = try PropertyListSerialization.data(fromPropertyList:
            ["version":1, "registration":registration.uuidString, "timetable":legacy], format:.binary, options:0)
        try bytes.write(to:file)
        defer { settings.removePersistentDomain(forName:suite); try? FileManager.default.removeItem(at:file) }
        let store = SchoolTimetableStore(file:file,defaults:settings,publication:cal)
        let book = try XCTUnwrap(store.visible)
        XCTAssertEqual(book.rotations.count,6)
        let target = try XCTUnwrap(cal.days.last { $0.teachingDay != nil && source.dated[$0.date] == nil })
        let date = try XCTUnwrap(SchoolClock.dayDate(target.date))
        XCTAssertTrue(book.day(on:date,calendar:cal)?.schedule?.hasConfirmedRoster == true)
        await store.update(for:"fixture",calendar:cal,now:date,manual:false,current:{true}) { _ in
            XCTFail("Restoring the existing year must not contact the portal")
            throw SchoolPortalIssue.network
        }
        XCTAssertEqual(try Data(contentsOf:file),bytes)
        XCTAssertEqual(store.reminderRegistration,registration.uuidString)
    }
}
