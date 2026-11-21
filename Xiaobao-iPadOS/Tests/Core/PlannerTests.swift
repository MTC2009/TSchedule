import Foundation
import XCTest
@testable import XiaobaoCore

final class PlannerTests: XCTestCase {
    private let date = SchoolClock.date(2027, 1, 6)
    private var day: String { SchoolClock.key(date) }
    private var tomorrow: Date { SchoolClock.date(2027, 1, 7) }
    private func at(_ minute: Int) -> Date { SchoolClock.at(minute: minute, on: date) }

    private func entry(_ id: String, _ kind: PlannerSchoolEntry.Kind, from start: Int, until end: Int? = nil,
                       allDay: Bool = false) -> PlannerSchoolEntry {
        .init(id: .event(id), kind: kind, title: "Independent fixture", location: nil,
              start: at(start), end: end.map(at), allDay: allDay)
    }

    func testSchedulesIndependentItemsInOneStableOrderAndKeepsUntimedPlansOnTheirDate() throws {
        let lesson = entry("workshop", .lesson, from: 570, until: 630)
        let briefing = entry("briefing", .activity, from: 570)
        let allDay = entry("notices", .calendar, from: 0, allDay: true)
        let untimed = try XCTUnwrap(PersonalPlan(day: day, title: "Return the field notebook", time: nil))
        let timed = try XCTUnwrap(PersonalPlan(day: day, title: lesson.title, time: PlanTime(startMinute: 570)))
        let extra = try XCTUnwrap(PersonalPlan(day: SchoolClock.key(tomorrow), title: "Pack pen", time: nil))
        let school = PlannerSchoolDay(rotationDay: 2, hasTimetable: true, hasCalendar: true,
                                      entries: [lesson, allDay, briefing])

        let projection = PlannerDay(on: date, school: school, plans: [untimed, extra, timed])

        XCTAssertEqual(projection.timed.map(\.id), [.school(lesson.id), .school(briefing.id), .personal(timed.id)])
        XCTAssertEqual(projection.allDay.map(\.id), [allDay.id])
        XCTAssertEqual(projection.unscheduled, [untimed])
    }

    func testPrefersTheNextRealItemOverVacanciesCompletedPlansAndEarlierWork() throws {
        let earlier = entry("first", .lesson, from: 500, until: 600)
        let slot = entry("slot", .freeblock, from: 605, until: 645)
        let later = entry("later", .activity, from: 700, until: 740)
        let completed = try XCTUnwrap(PersonalPlan(day: day, title: "Return tripod", time: PlanTime(startMinute: 610),
                                                    isCompleted: true))
        let school = PlannerSchoolDay(rotationDay: 2, hasTimetable: true, hasCalendar: true, entries: [earlier, slot, later])
        let projection = PlannerDay(on: date, school: school, plans: [completed])

        XCTAssertEqual(projection.focus(at: at(580)), .next(.school(later.id)))
        XCTAssertEqual(projection.focus(at: at(700)), .next(.school(later.id)))
        XCTAssertEqual(projection.focus(at: at(710)), .ongoing(.school(later.id)))
        XCTAssertNil(projection.focus(at: at(740)))
        XCTAssertNil(projection.focus(at: tomorrow))
    }

    func testDueOnlyRecordsDoNotBecomeMarkersOrChoosePlannerFocus() throws {
        let tour = entry("studio-tour", .activity, from: 792, until: 804)
        let varieties: [PlannerSchoolEntry.Kind] = [.taskDeadline, .examDeadline, .evaluationDeadline, .deadline]
        let deadlines = varieties.enumerated().map { index, kind in
            entry("due-\(index)", kind, from: 930 + 15 * index)
        }
        let school = PlannerSchoolDay(rotationDay: 2, hasTimetable: true, hasCalendar: true,
                                      entries: [tour] + deadlines)
        let point = try XCTUnwrap(PersonalPlan(day: day, title: "Collect survey forms",
                                              time: PlanTime(startMinute: 945)))
        let projection = PlannerDay(on: date, school: school, plans: [point])
        let layout = PlannerTimelineLayout(day: projection, scale: PlannerTimeScale(hourHeight: 96), minimumHeight: 48)

        XCTAssertEqual(projection.timed.map(\.id), [.school(tour.id), .personal(point.id)])
        XCTAssertEqual(layout.school.markGroups.flatMap(\.marks).map(\.id), [.school(tour.id)])
        XCTAssertEqual(layout.personal.markGroups.flatMap(\.marks).map(\.id), [.personal(point.id)])
        XCTAssertEqual(projection.focus(at: at(900)), .next(.personal(point.id)))
        XCTAssertNil(PlannerDay(on: date, school: school, plans: []).focus(at: at(900)))
    }

    func testChecksHalfOpenOverlapsWithoutTreatingDeadlinesOrAllDayNoticesAsBusy() throws {
        let lesson = entry("lab", .lesson, from: 550, until: 600)
        let deadline = entry("brief", .taskDeadline, from: 600)
        let assembly = entry("gathering", .activity, from: 630)
        let allDay = entry("notice", .calendar, from: 0, until: 1440, allDay: true)
        let school = PlannerSchoolDay(rotationDay: 2, hasTimetable: true, hasCalendar: true,
                                      entries: [lesson, deadline, assembly, allDay])
        let projection = PlannerDay(on: date, school: school, plans: [])
        func conflicts(_ start: Int, _ end: Int? = nil) throws -> [PlannerSchoolEntry.ID] {
            projection.conflicts(with: try XCTUnwrap(PlanTime(startMinute: start, endMinute: end))).map(\.id)
        }

        XCTAssertEqual(try conflicts(549, 550), [])
        XCTAssertEqual(try conflicts(550), [lesson.id])
        XCTAssertEqual(try conflicts(599, 600), [lesson.id])
        XCTAssertEqual(try conflicts(600, 630), [])
        XCTAssertEqual(try conflicts(630), [assembly.id])
        XCTAssertEqual(try conflicts(629, 631), [assembly.id])
        XCTAssertEqual(try conflicts(631, 1440), [])
    }

    func testConnectedKeepsCalendarFallbackAndOnlyConfirmedSlotsCanBePlanned() throws {
        let lesson = CampusLesson(id: "example-lab", course_id: "lab",
                                  start: "2027-01-06T10:10:00+08:00", end: "2027-01-06T10:50:00+08:00", room: "N14")
        let event = CampusEvent(id: "multi-day", title: "Facilities notice", start: "2027-01-05T00:00:00+08:00",
                                end: "2027-01-08T00:00:00+08:00", kind: "school_calendar", all_day: true)
        let exam = CampusWork(id: "short-assessment", title: "Soil classification",
                              due_at: "2027-01-06T19:00:00+08:00", status: "pending", description: "",
                              course_id: "lab", kind: "exam")
        let calendar = CampusCalendar(lessons: [lesson], events: [event], deadlines: [exam])
        func project(_ schedule: CampusSchedule?) -> PlannerSchoolDay {
            .connected(on: date, schedule: schedule, calendar: calendar) { $0 == "lab" ? "Applied Lab" : $0 }
        }

        let fallback = project(nil)
        XCTAssertFalse(fallback.hasTimetable)
        XCTAssertTrue(fallback.hasCalendar)
        XCTAssertEqual(fallback.entries.filter { $0.kind == .lesson }.first?.location, "N14")
        XCTAssertTrue(fallback.entries.filter(\.allDay).contains { $0.id == .event("multi-day") })
        XCTAssertFalse(fallback.entries.contains { $0.kind == .freeblock })
        XCTAssertEqual(fallback.entries.first { $0.kind == .examDeadline }?.start, at(19 * 60))
        XCTAssertFalse(fallback.entries.contains { $0.kind == .exam })
        let plannerDay = PlannerDay(on: date, school: fallback, plans: [])
        XCTAssertEqual(plannerDay.timed.map(\.id), [.school(.block(.lesson(lesson.id)))])
        XCTAssertEqual(plannerDay.allDay.map(\.id), [.event(event.id)])

        let bells = [TeachingSlot(start: 610, end: 650), .init(start: 660, end: 700)]
        let confirmed = project(.init(date: day, day: 2, lessons: [lesson], teaching_slots: bells))
        XCTAssertTrue(confirmed.hasTimetable)
        XCTAssertEqual(confirmed.rotationDay, 2)
        XCTAssertEqual(confirmed.entries.filter { $0.kind == .lesson }.count, 1)
        let slot = try XCTUnwrap(confirmed.entries.first { $0.kind == .freeblock })
        XCTAssertEqual(slot.start, at(660))
        XCTAssertEqual(slot.end, at(700))
        XCTAssertFalse(project(.init(date: day, day: 2, lessons: [lesson])).entries.contains { $0.kind == .freeblock })
        XCTAssertFalse(project(.init(date: SchoolClock.key(tomorrow), day: 2, lessons: [lesson], teaching_slots: bells)).hasTimetable)
    }

    func testLocalPlannerReusesBellActivitiesAndAllowsAPlanOnARestDay() throws {
        let provider = DemoSchoolProvider()
        let scheduled = PlannerSchoolDay.local(on: date, provider: provider, work: [])
        XCTAssertTrue(scheduled.hasTimetable)
        XCTAssertEqual(scheduled.entries.filter { $0.kind == .freeblock }.count, 1)
        XCTAssertEqual(scheduled.entries.filter { $0.kind == .assembly }.count, 1)
        XCTAssertEqual(scheduled.entries.filter { $0.kind == .lunch }.count, 1)

        let saturday = SchoolClock.date(2027, 1, 9)
        let rest = PlannerSchoolDay.local(on: saturday, provider: provider, work: [])
        let plan = try XCTUnwrap(PersonalPlan(day: SchoolClock.key(saturday), title: "Sort watercolor samples", time: nil))
        XCTAssertNil(rest.rotationDay)
        XCTAssertTrue(rest.hasTimetable)
        XCTAssertTrue(rest.entries.isEmpty)
        XCTAssertEqual(PlannerDay(on: saturday, school: rest, plans: [plan]).unscheduled, [plan])
    }

    func testLocalDemoExamsUseTheirCourseSlotAndDoNotCreateAnotherLane() throws {
        let repository = (0..<4).reduce(URL(fileURLWithPath: #filePath)) { path, _ in path.deletingLastPathComponent() }
        let publicationURL = repository.appendingPathComponent("xiaobao-backend/src/provider/academic-calendar-hs-2026-2027.json")
        let publication = try JSONDecoder().decode(PublishedSchoolCalendar.self, from: Data(contentsOf: publicationURL))
        let published = DemoSchoolProvider(schoolCalendar: .init(publication: publication))
        for (provider, work) in [(DemoSchoolProvider.local, StudentServices.work), (published, StudentServices.makeWork(using: published))] {
            let exams = work.filter { $0.kind == .exam }
            XCTAssertEqual(exams.count, 3)
            for exam in exams {
                let lesson = try XCTUnwrap(provider.lessons(on: exam.date).first { $0.id == exam.inClassLessonID })
                XCTAssertEqual(exam.course, lesson.course.name, exam.id)
                XCTAssertEqual(exam.date, lesson.start, exam.id)
                XCTAssertEqual(exam.end, lesson.end, exam.id)
                XCTAssertEqual(exam.location, lesson.course.room, exam.id)

                let school = PlannerSchoolDay.local(on: exam.date, provider: provider, work: work)
                let occupying = school.entries.filter { entry in
                    entry.kind.occupiesTime && entry.start < lesson.end && (entry.end.map { lesson.start < $0 } ?? false)
                }
                XCTAssertEqual(occupying.map(\.id), [.work(kind: "exam", id: exam.id)])
                let projection = PlannerDay(on: exam.date, school: school, plans: [])
                let layout = PlannerTimelineLayout(day: projection, scale: PlannerTimeScale(hourHeight: 96), minimumHeight: 48)
                XCTAssertTrue(layout.school.items.allSatisfy { $0.laneCount == 1 }, exam.id)
            }
        }
    }

    func testLocalPlannerDoesNotHideTeachingForUnlinkedExamsOrStaleLinks() throws {
        let provider = DemoSchoolProvider()
        let lesson = try XCTUnwrap(provider.lessons(on: date).first)
        let separate = SchoolWork(id: "sample-identification", kind: .exam, title: "Specimen identification",
                                  course: lesson.course.name, date: lesson.start, end: lesson.end,
                                  location: nil, status: .pending, detail: "Lab practical.")
        let stale = SchoolWork(id: "stale-link", kind: .exam, title: "Field notes assessment",
                               course: lesson.course.name, date: lesson.start, end: lesson.end.addingTimeInterval(60),
                               location: nil, status: .pending, detail: "Practical assessment.", inClassLessonID: lesson.id)

        for exam in [separate, stale] {
            let school = PlannerSchoolDay.local(on: date, provider: provider, work: [exam])
            XCTAssertTrue(school.entries.contains { $0.lessonID == lesson.id })
            XCTAssertTrue(school.entries.contains { $0.id == .work(kind: "exam", id: exam.id) })
        }
    }

    func testClosedDayDoesNotProduceAnInClassDemoExam() throws {
        let provider = DemoSchoolProvider()
        let exam = try XCTUnwrap(StudentServices.makeWork(using: provider).first { $0.kind == .exam })
        let key = SchoolClock.key(exam.date)
        let closed = DemoSchoolProvider(schoolCalendar: .init(closures: [key]))
        let work = StudentServices.makeWork(using: closed)
        XCTAssertFalse(work.contains { $0.kind == .exam && SchoolClock.key($0.date) == key })
        XCTAssertTrue(work.contains { $0.kind == .exam && SchoolClock.key($0.date) != key })
    }

    func testRejectsInvalidDatesTitlesAndTimeRanges() throws {
        XCTAssertNil(PersonalPlan(day: "2027-02-30", title: "Read a chapter", time: nil))
        XCTAssertNil(PersonalPlan(day: day, title: " \n  ", time: nil))
        XCTAssertNil(PersonalPlan(day: day, title: String(repeating: "字", count: PersonalPlan.titleLimit + 1), time: nil))
        XCTAssertEqual(PersonalPlan(day: day, title: "\n Sketch the watershed \t", time: nil)?.title, "Sketch the watershed")
        XCTAssertNil(PlanTime(startMinute: -1))
        XCTAssertNil(PlanTime(startMinute: 1440))
        XCTAssertNil(PlanTime(startMinute: 570, endMinute: 570))
        XCTAssertNil(PlanTime(startMinute: 570, endMinute: 1441))
        XCTAssertEqual(PlanTime(startMinute: 1439, endMinute: 1440)?.end(on: date), tomorrow)
    }

    @MainActor func testPersistsEditingAndCompletionAndKeepsProfilesAndOriginsSeparate() async throws {
        let url = temporaryArchive()
        let a = PlanOwner.campus(origin: URL(string: "https://one.example.invalid/")!, profile: "sample-a")
        let b = PlanOwner.campus(origin: URL(string: "https://one.example.invalid/")!, profile: "sample-b")
        let otherServer = PlanOwner.campus(origin: URL(string: "https://two.example.invalid/")!, profile: "sample-a")
        let recorded = try XCTUnwrap(PersonalPlan(day: day, title: "Pack trays", time: nil))
        let localOnly = try XCTUnwrap(PersonalPlan(day: day, title: "Label samples", time: nil))
        let edited = try XCTUnwrap(PersonalPlan(id: recorded.id, day: day, title: "Pack trays and lids",
                                                time: PlanTime(startMinute: 900, endMinute: 930)))
        let store = PlanStore(file: url)
        _ = try await store.create(recorded, for: a)
        _ = try await store.create(localOnly, for: .local)
        _ = try await store.setCompleted(true, plan: recorded, for: a)
        let updated = try await store.update(edited, for: a)
        XCTAssertTrue(try XCTUnwrap(updated.first).isCompleted)

        let reopened = PlanStore(file: url)
        let restarted = try await reopened.read(day: day, for: a)
        let localhost = try await reopened.read(day: day, for: .local)
        let otherProfile = try await reopened.read(day: day, for: b)
        let otherOrigin = try await reopened.read(day: day, for: otherServer)
        let nextDate = try await reopened.read(day: SchoolClock.key(tomorrow), for: a)
        XCTAssertEqual(restarted, updated)
        XCTAssertEqual(localhost, [localOnly])
        XCTAssertTrue(otherProfile.isEmpty)
        XCTAssertTrue(otherOrigin.isEmpty)
        XCTAssertTrue(nextDate.isEmpty)
        do {
            _ = try await reopened.setCompleted(false, plan: recorded, for: b)
            XCTFail("Another profile cannot change this record")
        } catch PlanStore.StoreError.missingPlan {}
        let undone = try await reopened.setCompleted(false, plan: recorded, for: a)
        XCTAssertEqual(undone, [edited])
    }

    @MainActor func testCorruptArchiveIsNotOverwrittenByCreate() async throws {
        let url = temporaryArchive()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let invalid = Data("unreadable test archive".utf8)
        try invalid.write(to: url)
        let store = PlanStore(file: url)
        let plan = try XCTUnwrap(PersonalPlan(day: day, title: "Clean brushes", time: nil))
        do {
            _ = try await store.create(plan, for: .local)
            XCTFail("Corrupt records must not be replaced with an empty archive.")
        } catch {
            XCTAssertEqual(try Data(contentsOf: url), invalid)
        }
    }

    @MainActor func testOldRecordsReadWithoutAppearanceAndMovingKeepsNewAppearanceAcrossLaunch() async throws {
        // Encode the original on-disk shape, not a new PersonalPlan with nils.
        struct LegacyPlan: Encodable {
            let id = UUID()
            let day: String
            let title: String
            let isCompleted: Bool
            let time: PlanTime
        }
        let old = LegacyPlan(day: day, title: "Check specimen rack", isCompleted: true,
                             time: try XCTUnwrap(PlanTime(startMinute: 465, endMinute: 510)))
        let url = temporaryArchive()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PropertyListEncoder().encode([PlanOwner.local: [old]]).write(to: url)
        let store = PlanStore(file: url)
        let initial = try await store.read(day: day, for: .local)
        let restored = try XCTUnwrap(initial.first)
        XCTAssertEqual(restored.id, old.id)
        XCTAssertNil(restored.color)
        XCTAssertNil(restored.icon)
        let styled = try XCTUnwrap(PersonalPlan(id: old.id, day: day, title: old.title, time: old.time,
                                               color: .teal, icon: .computer))
        _ = try await store.update(styled, for: .local)
        let moved = try XCTUnwrap(styled.placing(at: PlanTime(startMinute: 485, endMinute: 530)))
        _ = try await store.update(moved, for: .local)
        let restarted = try await PlanStore(file: url).read(day: day, for: .local)
        XCTAssertEqual(restarted.first?.time, moved.time)
        XCTAssertEqual(restarted.first?.color, .teal)
        XCTAssertEqual(restarted.first?.icon, .computer)
        XCTAssertEqual(restarted.first?.isCompleted, true)
        XCTAssertEqual(restarted.first?.placing(at: nil)?.color, .teal)
        XCTAssertEqual(restarted.first?.placing(at: nil)?.icon, .computer)
    }

    @MainActor func testWriteFailureDoesNotPublishAnEditedRecord() async throws {
        let url = temporaryArchive()
        let original = try XCTUnwrap(PersonalPlan(day: day, title: "Measure trays", time: nil))
        let store = PlanStore(file: url)
        _ = try await store.create(original, for: .local)
        let preserved = url.deletingLastPathComponent().appendingPathComponent("preserved.plist")
        try FileManager.default.moveItem(at: url, to: preserved)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        do {
            _ = try await store.setCompleted(true, plan: original, for: .local)
            XCTFail("Writing over a directory should fail.")
        } catch {
            let kept = try await store.read(day: day, for: .local)
            let persisted = try await PlanStore(file: preserved).read(day: day, for: .local)
            XCTAssertEqual(kept, [original])
            XCTAssertEqual(persisted, [original])
        }
    }

    private func temporaryArchive() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("XiaobaoPlannerTests-\(UUID())", isDirectory: true)
            .appendingPathComponent("plans.plist")
    }
}
