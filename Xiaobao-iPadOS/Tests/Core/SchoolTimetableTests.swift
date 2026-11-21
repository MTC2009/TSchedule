import Foundation
import XCTest
@testable import XiaobaoCore

@MainActor final class SchoolTimetableTests: XCTestCase {
    private let origin = SchoolClock.date(2030, 4, 1)
    private func date(_ offset: Int) -> Date { SchoolClock.calendar.date(byAdding: .day, value: offset, to: origin)! }

    /// A wholly synthetic calendar: a Saturday teaches, a weekday closes, one date is unpublished.
    private func publication() throws -> PublishedSchoolCalendar {
        var next = 4
        let rows: [[String: Any]] = (0..<100).map { n in
            let day = date(n), off = SchoolClock.calendar.isDateInWeekend(day)
            var row: [String: Any] = ["date": SchoolClock.key(day), "notices": []]
            if n == 89 { row["status"] = "unpublished" }
            else if n == 29 { row["status"] = "no_class"; row["day"] = 5 }
            else if off && n != 40 { row["status"] = "weekend" }
            else { row["status"] = "teaching"; row["day"] = next; next = next % 6 + 1 }
            return row
        }
        return try JSONDecoder().decode(PublishedSchoolCalendar.self, from: JSONSerialization.data(withJSONObject:
            ["campus":"main","division":"HS","academic_year":"synthetic","source_sha256":"local-specimen",
             "from":SchoolClock.key(origin),"through":SchoolClock.key(date(99)),"days":rows]))
    }

    private func sample(_ start: Date, _ cal: PublishedSchoolCalendar, title: String = "Studio",
                        omit: String? = nil, special: String? = nil) throws -> SchoolPortalWeek {
        let week = TimetableWeek(containing: start)
        var rows: [SchoolPortalWeek.Row] = []
        for d in week.dates {
            let key = SchoolClock.key(d)
            guard key != omit, let cycle = cal.day(on: d).teachingDay else { continue }
            let name = key == special ? "One-date seminar" : "\(title) \(cycle)"
            rows.append(.init(id:"slot-"+key, name:name, start:key+"T09:13:00+08:00", course:name,
                              kind:.lesson, end:key+"T10:01:00+08:00", room:"Studio East", allDay:false))
            if key == special {
                rows.append(.init(id:"date-only", name:"Exhibition", start:key+"T12:00:00+08:00",
                                  course:"", kind:.activity, end:key+"T12:45:00+08:00", room:nil, allDay:false))
            }
        }
        return try .init(week: week, rows: rows)
    }
    private func storage() -> (URL, UserDefaults) {
        let id = UUID().uuidString, suite = "SchoolTimetableTests."+id
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(id)
        let file = root.appendingPathComponent("book.plist")
        addTeardownBlock {
            UserDefaults(suiteName:suite)?.removePersistentDomain(forName:suite)
            let fm = FileManager.default
            if fm.fileExists(atPath:file.path) { try fm.removeItem(at:file) }
            if fm.fileExists(atPath:root.path), try fm.contentsOfDirectory(atPath:root.path).isEmpty {
                try fm.removeItem(at:root)
            }
        }
        return (file, UserDefaults(suiteName:suite)!)
    }

    func testNextSchoolDaySkipsAClosureEvenWhenItHasAPrintedDay() throws {
        let cal = try publication()
        var book = SchoolTimetable(owner: "reader", calendar: cal, now: origin)
        try book.absorb(sample(date(31), cal), calendar: cal)
        let next = try XCTUnwrap(book.nextSchoolDay(after: SchoolClock.at(minute: 1234, on: date(28)), calendar: cal))
        XCTAssertEqual(next.date, date(30))
        XCTAssertEqual(next.rotation, cal.day(on: date(30)).teachingDay)
        XCTAssertEqual(next.firstLessons.map(\.room), ["Studio East"])
    }

    func testClassAlertsUseDistinctFutureStartsNotEventsOrPrintedDays() throws {
        let cal = try publication(), key = SchoolClock.key(date(29))
        var book = SchoolTimetable(owner: "fixture", calendar: cal, now: origin)
        func row(_ id: String, _ time: String, _ kind: SchoolPortalWeek.Row.Kind) -> SchoolPortalWeek.Row {
            .init(id: id, name: id, start: key+"T"+time+":00+08:00", course: id, kind: kind,
                  end: key+"T14:00:00+08:00", room: "private room", allDay: false)
        }
        let week = TimetableWeek(containing: date(29))
        try book.absorb(.init(week: week, rows: [
            row("Briefing", "10:05", .activity), row("Earlier", "08:15", .lesson),
            row("Parallel A", "10:50", .lesson), row("Parallel B", "10:50", .lesson)
        ]), calendar: cal)
        let now = SchoolClock.at(minute: 9*60, on: date(29))
        let offered = book.lessonReminders(now: now, lead: 10, calendar: cal)
        XCTAssertEqual(offered.map(\.fireDate), [SchoolClock.at(minute: 10*60+40, on: date(29))])
        XCTAssertEqual(Set(offered.map(\.id)).count, 1)
        XCTAssertTrue(book.lessonReminders(now: try XCTUnwrap(offered.first).fireDate, lead: 10, calendar: cal).isEmpty)
        XCTAssertTrue(book.lessonReminders(now: now, lead: -1, calendar: cal).isEmpty)
        XCTAssertTrue(book.lessonReminders(now: date(19), lead: 10, calendar: cal).isEmpty)
    }

    func testClassAlertsUseCalendarRotationAndSkipUnconfirmedDates() throws {
        let cal = try publication()
        var book = SchoolTimetable(owner: "fixture", calendar: cal, now: origin)
        for n in [0, 7, 14, 21] { try book.absorb(sample(date(n), cal), calendar: cal) }
        let checked = book.lessonReminders(now: date(27), lead: 0, calendar: cal)
        XCTAssertFalse(checked.isEmpty)
        XCTAssertFalse(checked.contains { SchoolClock.key($0.fireDate) == SchoolClock.key(date(29)) })
        XCTAssertEqual(checked.map(\.fireDate), checked.map(\.fireDate).sorted())
        XCTAssertTrue(book.lessonReminders(now: date(39), lead: 5, calendar: cal)
            .contains { SchoolClock.key($0.fireDate) == SchoolClock.key(date(40)) })
    }

    func testReminderOptInBelongsToOneRegistrationNotTheInstallation() async throws {
        let cal = try publication(), (file, prefs) = storage(), book = SchoolTimetableStore(file: file, defaults: prefs)
        await book.update(for: "first", calendar: cal, now: date(15), manual: false, current: { true }) { try self.sample($0, cal) }
        let id = try XCTUnwrap(book.reminderRegistration)
        XCTAssertFalse(book.lessonRemindersEnabled)
        XCTAssertTrue(book.setLessonReminders(true, registration: id)); book.setLessonLead(0)
        book.reviewAccount()
        let cold = SchoolTimetableStore(file: file, defaults: prefs)
        XCTAssertFalse(cold.lessonRemindersEnabled)
        XCTAssertFalse(cold.setLessonReminders(true, registration: id))
        cold.verified("first")
        XCTAssertTrue(cold.lessonRemindersEnabled); XCTAssertEqual(cold.lessonLead, 0)
        cold.verified("second")
        await cold.update(for: "second", calendar: cal, now: date(15), manual: false, current: { true }) { try self.sample($0, cal) }
        XCTAssertNotEqual(cold.reminderRegistration, id)
        XCTAssertFalse(cold.setLessonReminders(true, registration: id))
        XCTAssertFalse(cold.lessonRemindersEnabled); XCTAssertEqual(cold.lessonLead, 5)
    }

    func testNextSchoolDayKeepsAPublishedWeekendMakeupEvenWithoutItsLessons() throws {
        let cal = try publication()
        var book = SchoolTimetable(owner: "reader", calendar: cal, now: origin)
        try book.absorb(sample(date(39), cal, omit: SchoolClock.key(date(40))), calendar: cal)
        let makeup = try XCTUnwrap(book.nextSchoolDay(after: date(39), calendar: cal))
        XCTAssertEqual(makeup.date, date(40))
        XCTAssertEqual(makeup.rotation, cal.day(on: date(40)).teachingDay)
        XCTAssertTrue(makeup.firstLessons.isEmpty, "Missing classes do not cancel a published teaching day")
        XCTAssertEqual(book.nextSchoolDay(after: date(4), calendar: cal)?.date, date(7))
    }

    func testNextSchoolDayUsesDatedExceptionAndOnlyItsEarliestLessons() throws {
        let cal = try publication(), key = SchoolClock.key(date(29))
        var book = SchoolTimetable(owner: "reader", calendar: cal, now: origin)
        func row(_ name: String, at start: String, until end: String, kind: SchoolPortalWeek.Row.Kind = .lesson,
                 room: String? = nil) -> SchoolPortalWeek.Row {
            .init(id: name, name: name, start: key + "T" + start + ":00+08:00", course: name, kind: kind,
                  end: key + "T" + end + ":00+08:00", room: room, allDay: false)
        }
        let rows = [row("Workshop", at: "13:10", until: "14:10", room: "Hall"),
                    row("Welcome", at: "08:00", until: "08:12", kind: .activity),
                    row("Printmaking", at: "09:00", until: "10:00")]
        let week = TimetableWeek(containing: date(29))
        try book.absorb(.init(week: week, rows: rows), calendar: cal)
        let special = try XCTUnwrap(book.nextSchoolDay(after: date(28), calendar: cal))
        XCTAssertEqual(special.date, date(29))
        XCTAssertNil(special.rotation, "A dated class doesn't turn the closure's printed Day into a rotation")
        XCTAssertEqual(special.firstLessons.map(\.name), ["Printmaking"])
        XCTAssertNil(special.firstLessons.first?.room)
        let overlap = row("Sculpture", at: "09:00", until: "09:50", room: "North")
        try book.absorb(.init(week: week, rows: rows + [overlap]), calendar: cal)
        XCTAssertEqual(Set(try XCTUnwrap(book.nextSchoolDay(after: date(28), calendar: cal)).firstLessons.map(\.name)),
                       ["Printmaking", "Sculpture"], "Don't choose an arbitrary classroom when two rows start together")
    }

    func testNextSchoolDayDoesNotLeapOverUnpublishedDatesOrCrossTheAcademicYear() throws {
        let cal = try publication()
        var book = SchoolTimetable(owner: "reader", calendar: cal, now: origin)
        try book.absorb(sample(date(92), cal), calendar: cal)
        XCTAssertNil(book.nextSchoolDay(after: date(88), calendar: cal))
        XCTAssertNil(book.nextSchoolDay(after: date(99), calendar: cal))
        XCTAssertNil(book.nextSchoolDay(after: date(-2), calendar: cal))
    }

    func testColdRelaunchAndFutureDateNeedNoScheduleReads() async throws {
        let cal = try publication(), (file,prefs) = storage()
        let original = SchoolTimetableStore(file:file,defaults:prefs)
        var calls = 0
        await original.update(for:"student-A",calendar:cal,now:date(15),manual:false,current:{true}) { start in
            calls += 1; return try self.sample(start,cal)
        }
        XCTAssertTrue((3...6).contains(calls))
        let cold = SchoolTimetableStore(file:file,defaults:prefs)
        let book = try XCTUnwrap(cold.visible)
        XCTAssertEqual(book.rotations.count,6)
        await cold.update(for:"student-A",calendar:cal,now:date(68),manual:false,current:{true}) { _ in
            XCTFail("Opening or browsing the saved year must not read the portal"); throw SchoolPortalIssue.network
        }
        let teaching = try XCTUnwrap(book.day(on:date(40),calendar:cal))
        XCTAssertEqual(teaching.schedule?.lessons.first?.course_id, "Studio \(try XCTUnwrap(cal.day(on:date(40)).teachingDay))")
        XCTAssertEqual(teaching.timeline?.blocks.count,1, "No invented bells or campus activities")
        XCTAssertTrue(book.day(on:date(29),calendar:cal)?.schedule?.lessons.isEmpty == true)
        XCTAssertNil(book.day(on:date(29),calendar:cal)?.schedule?.day, "Printed Day on an HS closure is not a teaching Day")
        XCTAssertNil(book.day(on:date(89),calendar:cal)?.schedule)
        XCTAssertNil(book.day(on:date(101),calendar:cal))
    }

    func testConflictingInstructionAndDatedEventsNeverRepeat() throws {
        let cal = try publication(), special = SchoolClock.key(date(8)), missing = SchoolClock.key(date(3))
        var book = SchoolTimetable(owner:"owner",calendar:cal,now:date(15))
        for i in [1,8,15,22,30] { try book.absorb(sample(date(i),cal,omit:missing,special:special),calendar:cal) }
        let exact = try XCTUnwrap(book.day(on:date(8),calendar:cal))
        XCTAssertEqual(exact.schedule?.lessons.first?.course_id,"One-date seminar")
        XCTAssertEqual(exact.events.events.map(\.title),["Exhibition"])
        XCTAssertNil(book.day(on:date(3),calendar:cal)?.schedule)
        let day = try XCTUnwrap(cal.day(on:date(8)).teachingDay)
        XCTAssertNil(book.rotations[day])
        let later = try XCTUnwrap((50...80).first { cal.day(on:date($0)).teachingDay == day })
        XCTAssertNil(book.day(on:date(later),calendar:cal)?.schedule)
        XCTAssertTrue(book.day(on:date(later),calendar:cal)?.events.events.isEmpty == true)
    }

    func testOnlySuccessfulManualReplacementCanDisplaceSavedYear() async throws {
        let cal = try publication(), (f,p) = storage(), owner = "A"
        let cache = SchoolTimetableStore(file:f,defaults:p)
        await cache.update(for:owner,calendar:cal,now:date(15),manual:false,current:{true}) { try self.sample($0,cal) }
        let bytes = try Data(contentsOf:f)
        await cache.update(for:owner,calendar:cal,now:date(16),manual:true,current:{true}) { _ in throw SchoolPortalIssue.network }
        XCTAssertEqual(try Data(contentsOf:f),bytes)
        await cache.update(for:owner,calendar:cal,now:date(16),manual:true,current:{true}) { try SchoolPortalWeek(week:.init(containing:$0),rows:[]) }
        XCTAssertEqual(try Data(contentsOf:f),bytes)
        await cache.update(for:owner,calendar:cal,now:date(16),manual:true,current:{true}) { try self.sample($0,cal,title:"Seminar") }
        XCTAssertNotEqual(try Data(contentsOf:f),bytes)
        XCTAssertTrue(cache.visible?.rotations[1]?.first?.title.hasPrefix("Seminar") == true)
    }

    func testManualAccountReviewPersistsAcrossTerminationAndLogoutRevokesFile() async throws {
        let cal = try publication(), (f,p) = storage(), cache = SchoolTimetableStore(file:f,defaults:p)
        await cache.update(for:"A",calendar:cal,now:date(17),manual:false,current:{true}) { try self.sample($0,cal) }
        cache.reviewAccount()
        let relaunched = SchoolTimetableStore(file:f,defaults:p); XCTAssertNil(relaunched.visible)
        relaunched.verified("A"); XCTAssertNotNil(relaunched.visible)
        relaunched.reviewAccount(); relaunched.verified("B")
        XCTAssertNil(relaunched.visible); XCTAssertFalse(FileManager.default.fileExists(atPath:f.path))
        await relaunched.update(for:"B",calendar:cal,now:date(17),manual:false,current:{true}) { try self.sample($0,cal) }
        XCTAssertEqual(relaunched.visible?.owner,"B")
        relaunched.forget(); XCTAssertNil(SchoolTimetableStore(file:f,defaults:p).visible)
    }

    func testInFlightOldOwnerCannotWriteAfterSwitch() async throws {
        let cal = try publication(), (f,p) = storage(), cache = SchoolTimetableStore(file:f,defaults:p)
        var held: CheckedContinuation<SchoolPortalWeek, Never>?
        let old = Task { await cache.update(for:"A",calendar:cal,now:date(17),manual:false,current:{true}) { _ in
            await withCheckedContinuation { held = $0 }
        } }
        while held == nil { await Task.yield() }
        cache.verified("B")
        await cache.update(for:"B",calendar:cal,now:date(17),manual:false,current:{true}) { try self.sample($0,cal) }
        held?.resume(returning:try sample(date(17),cal)); await old.value
        XCTAssertEqual(SchoolTimetableStore(file:f,defaults:p).visible?.owner,"B")
    }

    func testInterruptedFirstImportKeepsOnlyVerifiedDatesAndDoesNotRetryOnRelaunch() async throws {
        let cal = try publication(), (f, p) = storage(), cache = SchoolTimetableStore(file:f,defaults:p)
        var calls = 0
        await cache.update(for:"reader",calendar:cal,now:date(15),manual:false,current:{true}) { day in
            calls += 1
            if calls > 1 { throw SchoolPortalIssue.network }
            return try self.sample(day,cal)
        }
        let cold = SchoolTimetableStore(file:f,defaults:p)
        XCTAssertTrue(cold.visible?.day(on:date(15),calendar:cal)?.schedule?.lessons.isEmpty == false)
        XCTAssertNil(cold.visible?.day(on:date(50),calendar:cal)?.schedule)
        await cold.update(for:"reader",calendar:cal,now:date(22),manual:false,current:{true}) { _ in
            XCTFail("A saved partial timetable can only be refreshed in Settings"); throw SchoolPortalIssue.network
        }
        XCTAssertTrue(cache.message?.contains("部分") == true)
    }

    func testRestoredPreferencesWithoutDocumentDoNotSuppressFirstImportOnANewDevice() async throws {
        let cal = try publication(), (oldFile,prefs) = storage(), (newFile,_) = storage()
        let old = SchoolTimetableStore(file:oldFile,defaults:prefs)
        await old.update(for:"owner",calendar:cal,now:date(15),manual:false,current:{true}) { try self.sample($0,cal) }
        let restored = SchoolTimetableStore(file:newFile,defaults:prefs)
        XCTAssertNil(restored.visible)
        await restored.update(for:"owner",calendar:cal,now:date(15),manual:false,current:{true}) { try self.sample($0,cal) }
        XCTAssertEqual(restored.visible?.rotations.count,6)
    }

    func testAuthoritativeIdentityChangeRevokesSynchronouslyButLossOfNetworkDoesNot() async throws {
        let cal = try publication(), (f,p) = storage(), cache = SchoolTimetableStore(file:f,defaults:p)
        let a = String(repeating:"a",count:64), b = String(repeating:"b",count:64)
        final class Source { var id: String; init(_ id: String) { self.id = id } }
        let source = Source(a)
        let live = SchoolPortalStore(selected:true) { _,_ in
            try JSONSerialization.data(withJSONObject:["owner":source.id])
        }
        live.onAccountConfirmation = { owner in
            if let owner { cache.verified(owner) } else { cache.forget() }
        }
        await live.verify()
        await cache.update(for:a,calendar:cal,now:date(15),manual:false,current:{true}) { try self.sample($0,cal) }
        live.invalidate(.network); XCTAssertEqual(cache.visible?.owner,a)
        await live.verify(); source.id=b; await live.verify()
        XCTAssertEqual(live.identityIssue,.changed)
        XCTAssertNil(cache.visible); XCTAssertNil(SchoolTimetableStore(file:f,defaults:p).visible)
    }

    func testPassiveGPAUsesVerifiedCurrentTermAndNeverEnablesScoresOrRecoversLogin() async throws {
        let owner=String(repeating:"a",count:64)
        var reads:[SchoolPortalRead]=[]
        let online=SchoolPortalStore(selected:true) { op,_ in
            reads.append(op); let v:Any
            switch op {
            case .identity:return try JSONSerialization.data(withJSONObject:["owner":owner])
            case .tasks:v=["term":"Current","rows":[]] as [String:Any]
            case .grades:v=["term":"Current","termID":"c","courses":[],"gpa":3.25] as [String:Any]
            case .terms:v=["current":"c","terms":[["id":"c","name":"Current"],["id":"p","name":"Previous"]]] as [String:Any]
            default:throw SchoolPortalIssue.unavailable
            }
            return try JSONSerialization.data(withJSONObject:["owner":owner,"value":v])
        }
        await online.refreshGradesFromToday(); XCTAssertTrue(reads.isEmpty)
        await online.verify(); await online.loadTasks(); await online.refreshGradesFromToday(); await online.refreshGradesFromToday()
        XCTAssertEqual(reads.filter{$0 == .grades}.count,1); XCTAssertEqual(online.grades?.gpa,3.25)
        XCTAssertFalse(online.allowsTaskScores); XCTAssertNotNil(online.tasks)
        await online.loadTerms(); online.selectTerm("p"); await online.refreshGradesFromToday()
        XCTAssertFalse(reads.contains(.archivedGrades("p")))
        online.suspend(); let total=reads.count; await online.refreshGradesFromToday(); XCTAssertEqual(reads.count,total)
    }
}
