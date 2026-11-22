import Foundation
import XCTest
@testable import XiaobaoCore

final class TimetablePresentationTests: XCTestCase {
    private let date = SchoolClock.date(2027, 1, 19)

    func testTurningOffACourseDoesNotCreateAnAvailableStudioOrDiscardAnExamEvent() throws {
        let start = SchoolClock.at(minute: 660, on: date), end = SchoolClock.at(minute: 700, on: date)
        let lesson = LessonTimeline.Period(id: "ceramics", name: "Advanced Placement Ceramics", shortName: "Ceramics", room: nil, start: start, end: end)
        let raw = try XCTUnwrap(LessonTimeline(on: date, periods: [lesson], teachingSlots: CampusBells.teachingSlots, includesCampusActivities: true))
        var entries = raw.blocks.map(PlannerSchoolDay.blockEntry)
        entries.append(.init(id: .event("recital"), kind: .exam, title: "Performance assessment", location: nil, start: start, end: end, allDay: false))
        let school = PlannerSchoolDay(rotationDay: 2, hasTimetable: true, hasCalendar: true, entries: entries)
        var choices = LocalPersonalization()
        choices.setShown(false, for: .examCourse)
        let display = TimetablePresentation(on: date, school: school, plans: [], settings: choices)
        XCTAssertEqual(display.school.entries.filter { $0.start == start }.map(\.kind), [.exam])
        let today = try XCTUnwrap(display.timeline(original: raw))
        XCTAssertFalse(today.blocks.contains { $0.start == start })
        XCTAssertEqual(raw.blocks.compactMap(\.lesson).map(\.id), ["ceramics"])
    }

    func testLessonDetailLabelsDoNotChangeAnAssignedInterval() throws {
        let time = SchoolClock.at(minute: 756, on: date), end = SchoolClock.at(minute: 802, on: date)
        let period = LessonTimeline.Period(id: "scene", name: "Stage patterns", shortName: "Stage", room: "Lab", start: time, end: end,
            metadata: .init(grade: "Intermediate", className: "Studio group", teacher: "An instructor", note: "Bring notebook"))
        let source = PlannerSchoolDay(rotationDay: nil, hasTimetable: true, hasCalendar: true,
            entries: [PlannerSchoolDay.blockEntry(.lesson(period))])
        let projection = TimetablePresentation(on: date, school: source, plans: [], settings: .init())
        let shown = try XCTUnwrap(projection.timeline(original: nil)?.focus(at: time))
        XCTAssertEqual(shown.metadata, period.metadata)
        XCTAssertEqual(shown.start, time); XCTAssertEqual(shown.end, end)
        let other = TimetableLessonMetadata(grade: "Intermediate", teacher: "Substitute")
        let consensus = TimetableLessonMetadata.agreement([period.metadata, other])
        XCTAssertEqual(consensus?.grade, "Intermediate")
        XCTAssertNil(consensus?.teacher); XCTAssertNil(consensus?.note)
    }

    private func lesson(_ id: String, _ title: String, _ from: Int, _ until: Int) -> PlannerSchoolEntry {
        .init(id: .block(.lesson(id)), kind: .lesson, title: title, location: "Studio",
              start: SchoolClock.at(minute: from, on: date), end: SchoolClock.at(minute: until, on: date), allDay: false)
    }

    func testACommuterGetsOnlyTheirActualEveningIntervalsIndependentlyOfOptionalCourses() throws {
        let late = lesson("e", "ＴＳＳＡ · Media lab", 1222, 1258), elective = lesson("a", "Robotics", 955, 1005)
        let secondGroup = lesson("simultaneous", "T.S.S.A. / Sound", 1222, 1258)
        let selfStudy = lesson("independent", "Evening self-study", 1102, 1140)
        let source = PlannerSchoolDay(rotationDay: 2, hasTimetable: true, hasCalendar: true,
                                      entries: [late, elective, secondGroup, selfStudy])
        var choices = LocalPersonalization()
        func view() -> TimetablePresentation { .init(on: date, school: source, plans: [], settings: choices) }
        choices.setShown(false, for: .tssa)
        let masked = view()
        XCTAssertEqual(masked.school.entries.count, 3)
        let replacement = try XCTUnwrap(masked.school.entries.first { $0.start == late.start })
        XCTAssertEqual(replacement.title, TimetableCategory.study.title)
        XCTAssertNil(replacement.lessonID); XCTAssertEqual(replacement.location, PlannerCampusPeriod.firstStudy.location)
        XCTAssertEqual(replacement.end, late.end)
        XCTAssertEqual(masked.timeline(original: nil)?.focus(at: late.start)?.title, replacement.title)
        XCTAssertEqual(masked.timeline(original: nil)?.focus(at: late.start)?.location, replacement.location)
        XCTAssertEqual(masked.placementSchool.entries.compactMap(\.lessonID).count, 4, "Filtering cannot alter conflict input")
        choices.setShown(false, for: .study)
        XCTAssertEqual(view().school.entries.compactMap(\.lessonID), ["a"])
        choices.setShown(true, for: .tssa)
        XCTAssertEqual(view().school.entries.compactMap(\.lessonID), ["e", "a", "simultaneous"])
        let alone = PlannerSchoolDay(rotationDay: 2, hasTimetable: true, hasCalendar: true, entries: [elective])
        XCTAssertEqual(TimetablePresentation(on: date, school: alone, plans: [], settings: choices).school.entries.count, 1)
    }

    func testPersonalCourseOccupiesOnlyItsOwnSlotAndRegularNotesNeverBecomeLessons() throws {
        let raw = try XCTUnwrap(LessonTimeline(on: date, periods: [], teachingSlots: CampusBells.teachingSlots, includesCampusActivities: true))
        let base = PlannerSchoolDay(rotationDay: 1, hasTimetable: true, hasCalendar: true,
                                    entries: raw.blocks.map(PlannerSchoolDay.blockEntry), hasStandardBells: true)
        let day = SchoolClock.key(date), time = try XCTUnwrap(PlanTime(startMinute: 710, endMinute: 750))
        let added = try XCTUnwrap(PersonalPlan(day: day, title: "Kiln design", time: time, courseKind: .examCourse))
        let note = try XCTUnwrap(PersonalPlan(day: day, title: "Pick up prints", time: time))
        var settings = LocalPersonalization()
        func view() -> TimetablePresentation { .init(on: date, school: base, plans: [added, note], settings: settings) }
        XCTAssertEqual(view().plans, [added, note])
        let today = try XCTUnwrap(view().timeline(original: raw))
        XCTAssertEqual(today.focus(at: time.start(on: date))?.title, added.title)
        XCTAssertFalse(today.blocks.contains { $0.title == note.title })
        settings.setShown(false, for: .examCourse)
        XCTAssertEqual(view().plans, [note])
        XCTAssertFalse(view().school.entries.contains { $0.start == time.start(on: date) })
        XCTAssertFalse(view().timeline(original: raw)!.blocks.contains { $0.start == time.start(on: date) })
        let editor = TimetablePresentation(on: date, school: base, plans: [added, note], settings: settings, editingPersonalCourses: true)
        XCTAssertEqual(editor.plans, [added, note])
        XCTAssertNil(PersonalPlan(day: day, title: "Missing end", time: PlanTime(startMinute: 690), courseKind: .study))
    }

    func testReturnNightAndFollowingMorningHaveIdenticalVisiblePeriodsInBothViews() throws {
        let root = (0..<4).reduce(URL(fileURLWithPath: #filePath)) { url, _ in url.deletingLastPathComponent() }
        let calendar = try JSONDecoder().decode(PublishedSchoolCalendar.self, from: Data(contentsOf:
            root.appendingPathComponent("xiaobao-backend/src/provider/academic-calendar-hs-2026-2027.json")))
        let base = PlannerSchoolDay(rotationDay: nil, hasTimetable: false, hasCalendar: true, entries: [])
        var settings = LocalPersonalization()
        settings.showsBoardingRoutine = true; settings.setShown(false, for: .wash)
        func entries(_ date: Date) throws -> [PlannerSchoolEntry] {
            let routine = base.withCampusRoutine(on: date, calendar: calendar, showsBoardingRoutine: settings.showsBoardingRoutine)
            let display = TimetablePresentation(on: date, school: routine, plans: [], settings: settings)
            XCTAssertEqual(display.timeline(original: nil)?.blocks.map(\.start) ?? [], display.school.entries.map(\.start).sorted())
            XCTAssertFalse(display.school.entries.contains { TimetablePresentation.category(for: $0) == .wash })
            return display.school.entries
        }
        let sunday = SchoolClock.date(2026, 12, 6)
        XCTAssertTrue(try entries(sunday).contains { $0.id == .routine(.secondStudy, anchor: sunday) })
        XCTAssertTrue(try entries(SchoolClock.date(2026,12,7)).contains { $0.id == .routine(.breakfast, anchor: sunday) })
        XCTAssertFalse(try entries(SchoolClock.date(2026,12,11)).contains { TimetablePresentation.category(for: $0) == .study })
        settings.showsBoardingRoutine = false
        XCTAssertTrue(try entries(sunday).isEmpty)
    }

    func testCurriculumMarkersAreWholeTermsNotEnglishSubstringsOrAnExamCalendarFilter() {
        for title in ["IGCSE Theatre", "Design (A-Level)", "ＡＰ 统计学", "IG · 音乐", "AL 经济", "A2·Art", "Cambridge AS Level Drama"] {
            XCTAssertEqual(TimetablePresentation.courseCategory(title: title, start: date), .examCourse, title)
        }
        for title in ["Applied Arts", "Algebra", "Digital studio", "Landscape", "Writing as practice", "Capstone", "普通数学"] {
            XCTAssertEqual(TimetablePresentation.courseCategory(title: title, start: date), .schoolCourse, title)
        }
    }

    func testShortMealRetainsCardGeometryWhileAnUnrelatedShortEventKeepsItsMarker() throws {
        let a = lesson("meal", "Morning Meal", 421, 442)
        let event = lesson("short", "Team check-in", 448, 461)
        let meal = PlannerSchoolEntry(id: .routine(.breakfast, anchor: date), kind: .campusRoutine,
            title: a.title, location: "Hall", start: a.start, end: a.end, allDay: false)
        let full = lesson("after", "Drawing", 442, 502)
        let school = PlannerSchoolDay(rotationDay: nil, hasTimetable: true, hasCalendar: true, entries: [meal, full, event])
        let display = TimetablePresentation(on: date, school: school, plans: [], settings: .init())
        let day = PlannerDay(on: date, school: display.school, plans: [])
        let scale = PlannerTimeScale(hourHeight: 96)
        let layout = PlannerTimelineLayout(day: day, scale: scale, minimumHeight: 48)
        let card = try XCTUnwrap(layout.school.items.first { $0.id == .school(meal.id) })
        XCTAssertEqual(card.top, scale.position(at: 421))
        XCTAssertEqual(card.bottom, scale.position(at: 442))
        XCTAssertEqual(layout.school.items.first { $0.id == .school(full.id) }?.laneCount, 1)
        XCTAssertTrue(layout.school.markGroups.flatMap(\.marks).contains { $0.id == .school(event.id) })
        let preceding = display.timeline(original: nil)?.focus(at: meal.start)
        XCTAssertEqual(preceding?.location, "Hall")
        XCTAssertEqual(preceding?.title, "Morning Meal")
    }

    @MainActor func testSupplementalCourseKeepsItsKindAcrossRecurrenceStorageUndoAndOwners() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("plans.plist")
        let store = PlanStore(file: file), owner = PlanOwner.local, session = UUID()
        let key = SchoolClock.key(date), weekday = SchoolClock.calendar.component(.weekday, from: date)
        let plan = try XCTUnwrap(PersonalPlan(day: key, title: "Studio hour", time: PlanTime(startMinute: 1190, endMinute: 1221), courseKind: .study))
        let edit = PlanEdit(target: .create, plan: plan, reusable: false, recurrence: .weekday(weekday), effectiveDay: key)
        _ = try await store.apply(.save(edit), for: owner, session: session)
        let next = SchoolClock.key(try XCTUnwrap(SchoolClock.calendar.date(byAdding: .day, value: 7, to: date)))
        let reloaded = PlanStore(file: file)
        let scheduled = try await reloaded.read(day: next, for: owner)
        XCTAssertEqual(scheduled.first?.courseKind, .study)
        let other = try await reloaded.read(day: next, for: .campus(origin: URL(string: "https://fixture.invalid")!, profile: "unrelated"))
        XCTAssertTrue(other.isEmpty)
        _ = try await store.step(.undo, for: owner, session: session)
        let afterUndo = try await store.read(day: next, for: owner)
        XCTAssertTrue(afterUndo.isEmpty)
        _ = try await store.step(.redo, for: owner, session: session)
        let afterRedo = try await store.read(day: next, for: owner)
        XCTAssertEqual(scheduled, afterRedo)
    }
}
