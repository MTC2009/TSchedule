import XCTest
@testable import XiaobaoCore

final class TeachingSlotTests: XCTestCase {
    private let date = SchoolClock.date(2027, 3, 8)
    private func moment(_ minute: Int) -> Date { SchoolClock.at(minute: minute, on: date) }
    private func lesson(_ id: String, _ start: Int, _ end: Int) -> LessonTimeline.Period {
        .init(id: id, name: id, shortName: id, room: nil, start: moment(start), end: moment(end))
    }
    private func vacancies(_ day: LessonTimeline) -> [DateInterval] {
        day.blocks.compactMap { if case .freeblock(let value) = $0 { value } else { nil } }
    }

    func testLocalBellScheduleIsIndependentOfTheSuppliedStudentAssignments() throws {
        let provider = DemoSchoolProvider()
        let enrolled = provider.lessons(on: date)
        let full = try XCTUnwrap(provider.timeline(on: date, lessons: enrolled))
        let finalSlot = DateInterval(start: moment(905), end: moment(945))
        XCTAssertEqual(vacancies(full), [finalSlot])
        let unassigned = try XCTUnwrap(enrolled.last)
        let studentDay = try XCTUnwrap(provider.timeline(on: date, lessons: Array(enrolled.dropLast())))
        XCTAssertEqual(vacancies(studentDay), [DateInterval(start: unassigned.start, end: unassigned.end), finalSlot])
        XCTAssertTrue(try XCTUnwrap(provider.timeline(on: SchoolClock.date(2027, 3, 14), lessons: [])).blocks.isEmpty)
    }

    func testLegacyMiddayClassKeepsItsTimesInsteadOfBeingReplacedByLunch() throws {
        let key = SchoolClock.key(date)
        let source = CampusSchedule(date: key, day: 2, lessons: [
            .init(id: "lab", course_id: "s", start: key + "T12:17:00+08:00", end: key + "T12:58:00+08:00", room: nil),
            .init(id: "studio", course_id: "t", start: key + "T14:04:00+08:00", end: key + "T14:49:00+08:00", room: nil)
        ])
        let day = try XCTUnwrap(source.timeline { $0 })
        XCTAssertEqual(day.focus(at: moment(777))?.lesson?.id, "lab")
        let remainingLunch = try XCTUnwrap(day.focus(at: moment(778)))
        XCTAssertEqual(remainingLunch.id, .activity(.lunch, moment(778)))
        XCTAssertEqual(remainingLunch.start, moment(778))
        XCTAssertEqual(remainingLunch.end, moment(805))
        XCTAssertTrue(vacancies(day).isEmpty)
    }

    func testCampusMeetingHasItsOwnIntervalNotAFreeOrEnrolledSubject() throws {
        let provider = DemoSchoolProvider()
        let schedule = try XCTUnwrap(provider.timeline(on: date, lessons: provider.lessons(on: date)))
        let meeting = try XCTUnwrap(schedule.focus(at: moment(587)))
        XCTAssertEqual(meeting.title, "班会")
        XCTAssertNil(meeting.lesson)
        XCTAssertEqual(meeting.start, moment(570)); XCTAssertEqual(meeting.end, moment(610))
        XCTAssertNotEqual(schedule.focus(at: moment(610))?.id, meeting.id)
        XCTAssertEqual(meeting.elapsedFraction(at: moment(590)), 0.5)
    }

    func testAnInsertedSourceLessonKeepsItsProgressAndSplitsOnlyTheConflictingAssembly() throws {
        let plan = try XCTUnwrap(LessonTimeline(on: date, periods: [
            lesson("prior", 497, 554), lesson("new-lab", 581, 601), lesson("later", 625, 664)
        ], includesCampusActivities: true))
        XCTAssertEqual(plan.blocks.map(\.id), [.lesson("prior"), .activity(.assembly, moment(570)),
            .lesson("new-lab"), .activity(.assembly, moment(601)), .lesson("later")])
        XCTAssertEqual(plan.blocks.map { $0.elapsedFraction(at: moment(591)) }, [1, 1, 0.5, 0, 0])
        XCTAssertEqual(plan.blocks.map { $0.elapsedFraction(at: moment(610)) }, [1, 1, 1, 1, 0])
        XCTAssertEqual(plan.blocks.map { $0.elapsedFraction(at: moment(560)) }, [1, 0, 0, 0, 0])
    }

    func testLunchDoesNotCreateAnEnrollmentAnExtraSchoolDayOrAPartialVacancy() throws {
        let surrounding = [lesson("assembly", 583, 620), lesson("lab", 868, 893)]
        let stale = [TeachingSlot(start: 734, end: 774)]
        let day = try XCTUnwrap(LessonTimeline(on: date, periods: surrounding, teachingSlots: stale, includesCampusActivities: true))
        XCTAssertTrue(vacancies(day).isEmpty)
        XCTAssertEqual(day.blocks.map(\.id), [.lesson("assembly"), .activity(.lunch, moment(750)), .lesson("lab")])
        let occupied = try XCTUnwrap(LessonTimeline(on: date, periods: surrounding + [lesson("field", 708, 824)],
                                                   teachingSlots: stale, includesCampusActivities: true))
        XCTAssertEqual(occupied.blocks.map(\.id), [.lesson("assembly"), .lesson("field"), .lesson("lab")])
        for input in [[], [surrounding[0]], [surrounding[1]]] {
            let shortened = try XCTUnwrap(LessonTimeline(on: date, periods: input, includesCampusActivities: true))
            XCTAssertEqual(shortened.blocks.map(\.id), input.map { .lesson($0.id) })
        }
    }

    func testCampusLunchAndContinuousMorningHaveDistinctHalfOpenBoundaries() throws {
        let provider = DemoSchoolProvider()
        let timeline = try XCTUnwrap(provider.timeline(on: date, lessons: provider.lessons(on: date)))
        let first = try XCTUnwrap(timeline.focus(at: moment(480))?.lesson)
        for minute in [499, 519, 520, 539, 559] {
            XCTAssertEqual(timeline.focus(at: moment(minute))?.lesson?.id, first.id)
        }
        XCTAssertEqual(first.end, moment(560))
        XCTAssertFalse(timeline.blocks.contains { $0.start < moment(570) && $0.end > moment(560) })
        XCTAssertEqual(timeline.focus(at: moment(570))?.id, .activity(.assembly, moment(570)))
        XCTAssertNotNil(timeline.focus(at: moment(749))?.lesson)
        let lunch = try XCTUnwrap(timeline.focus(at: moment(750)))
        XCTAssertEqual(lunch.id, .activity(.lunch, moment(750)))
        XCTAssertEqual(lunch.start, moment(750)); XCTAssertEqual(lunch.end, moment(805))
        XCTAssertEqual(timeline.focus(at: moment(804))?.id, lunch.id)
        XCTAssertEqual(timeline.focus(at: moment(805))?.lesson?.start, moment(805))
        XCTAssertFalse(vacancies(timeline).contains { $0.start < lunch.end && $0.end > lunch.start })
        XCTAssertNil(timeline.focus(at: moment(945)))
        let teaching = timeline.blocks.filter { if case .activity = $0 { false } else { true } }
        XCTAssertEqual(teaching.map { TeachingSlot(start: SchoolClock.minute(in: $0.start), end: SchoolClock.minute(in: $0.end)) },
                       CampusBells.teachingSlots)
    }

    func testOnlyWholePublishedSlotsWithoutAnyOverlapAreFree() throws {
        let slots = [TeachingSlot(start: 708, end: 749), .init(start: 530, end: 568),
                     .init(start: 575, end: 610), .init(start: 632, end: 677)]
        let day = try XCTUnwrap(LessonTimeline(on: date,
            periods: [lesson("studio", 575, 610), lesson("tutorial", 676, 681)], teachingSlots: slots))
        XCTAssertEqual(vacancies(day), [DateInterval(start: moment(530), end: moment(568)),
                                        DateInterval(start: moment(708), end: moment(749))])
        XCTAssertEqual(day.bounds, 510...750)
        for minute in [509, 568, 570, 610, 631, 675, 681, 699, 749] {
            XCTAssertFalse(vacancies(day).contains { $0.start <= moment(minute) && moment(minute) < $0.end })
        }
        XCTAssertEqual(day.focus(at: moment(734))?.id, .freeblock(moment(708)))
        XCTAssertNil(day.focus(at: moment(749)))
    }

    func testFreeBlockKeepsItsIdentityAcrossTheBreakAndGivesWayToTheNextLesson() throws {
        let plan = try XCTUnwrap(LessonTimeline(on: date,
            periods: [lesson("studio", 511, 548), lesson("seminar", 596, 633)],
            teachingSlots: [.init(start: 554, end: 596)]))
        XCTAssertEqual(plan.focus(at: moment(547))?.id, .lesson("studio"))
        for minute in [548, 553, 554, 575, 595] {
            let slot = try XCTUnwrap(plan.focus(at: moment(minute)))
            XCTAssertEqual(slot.id, .freeblock(moment(554)))
            XCTAssertEqual(slot.title, "Free Block")
            XCTAssertNil(slot.lesson)
        }
        XCTAssertEqual(plan.focus(at: moment(596))?.id, .lesson("seminar"))
    }

    func testOnlyBoundedCampusRecessesGetACardWithoutAddingTimelineBlocks() throws {
        // A class overruns the bell by four minutes; the remaining six are the
        // recess. The longer gap in this incomplete schedule is not a recess.
        let periods = [lesson("lab", 618, 654), lesson("studio", 660, 701), lesson("seminar", 735, 749)]
        let plan = try XCTUnwrap(LessonTimeline(on: date, periods: periods, includesCampusActivities: true))
        let recess = DateInterval(start: moment(654), end: moment(660))
        XCTAssertEqual(plan.recesses, [recess])
        XCTAssertEqual(plan.blocks.map(\.id), periods.map { .lesson($0.id) })
        for minute in [654, 655, 659] {
            XCTAssertEqual(plan.recess(at: moment(minute)), recess)
        }
        for minute in [617, 653, 660, 705, 719, 749] {
            XCTAssertNil(plan.recess(at: moment(minute)))
        }
        XCTAssertTrue(try XCTUnwrap(LessonTimeline(on: date, periods: periods)).recesses.isEmpty)
    }

    func testParallelPublishedLessonsCannotCreateARecessWhileAnotherClassIsRunning() throws {
        let periods = [lesson("extended", 608, 671), lesson("parallel", 632, 650), lesson("studio", 660, 700)]
        let plan = try XCTUnwrap(LessonTimeline(on: date, periods: periods, includesCampusActivities: true))
        XCTAssertNil(plan.recess(at: moment(655)))
        XCTAssertEqual(plan.focus(at: moment(655))?.id, .lesson("extended"))
        XCTAssertTrue(try XCTUnwrap(LessonTimeline(on: date, periods: [], includesCampusActivities: true)).recesses.isEmpty)
    }

    func testResumptionStartsAtTheNextInstructionNotAVacantSlot() throws {
        let provider = DemoSchoolProvider()
        let withoutFirstAfternoon = provider.lessons(on: date).filter { $0.startMinute != 805 }
        let plan = try XCTUnwrap(provider.timeline(on: date, lessons: withoutFirstAfternoon))
        XCTAssertEqual(plan.nextInstructionStart(from: moment(560)), moment(570)) // Assembly is instruction.
        XCTAssertEqual(plan.recess(at: moment(565)), DateInterval(start: moment(560), end: moment(570)))
        XCTAssertNil(plan.recess(at: moment(780))) // Lunch is its own block.
        XCTAssertEqual(plan.focus(at: moment(805))?.id, .freeblock(moment(805)))
        XCTAssertEqual(plan.nextInstructionStart(from: moment(805)), moment(855))
        XCTAssertEqual(plan.recess(at: moment(900)), DateInterval(start: moment(895), end: moment(905)))
        XCTAssertNil(plan.nextInstructionStart(from: moment(905))) // Final period is also vacant.
    }

    func testBadOrAbsentBellTimesCannotCreateVacanciesOrHideRealCourses() throws {
        for slots: [TeachingSlot]? in [nil, [], [.init(start: -1, end: 19)], [.init(start: 580, end: 578)],
            [.init(start: 690, end: 741), .init(start: 735, end: 766)], [.init(start: 1400, end: 1441)]] {
            let day = try XCTUnwrap(LessonTimeline(on: date, periods: [lesson("seminar", 527, 591)], teachingSlots: slots))
            XCTAssertTrue(vacancies(day).isEmpty)
            XCTAssertEqual(day.blocks.map(\.id), [.lesson("seminar")])
        }
    }

    func testDailyAndOfflineContractsAgreeForAnUnassignedTeachingDay() throws {
        let slots = [TeachingSlot(start: 545, end: 590), .init(start: 655, end: 700)]
        let timetable = OfflineTimetable(rotation: .init(anchor_date: SchoolClock.key(date), anchor_day: 1,
            cycle_length: 2, closures: []), days: [[], []], teachingSlots: [slots, [.init(start: 804, end: 839)]])
        let persisted = try JSONDecoder().decode(OfflineTimetable.self, from: JSONEncoder().encode(timetable))
        let offline = try XCTUnwrap(persisted.schedule(date)?.timeline { $0 })
        let raw = #"{"date":"2027-03-08","day":1,"lessons":[],"teaching_slots":[{"start":545,"end":590},{"start":655,"end":700}]}"#
        let direct = try XCTUnwrap(JSONDecoder().decode(CampusSchedule.self, from: Data(raw.utf8)).timeline { $0 })
        XCTAssertEqual(direct.blocks.map(\.id), offline.blocks.map(\.id))
        // The older first vacant bell intersects assembly and isn't a whole free slot anymore.
        XCTAssertEqual(vacancies(direct), [DateInterval(start: moment(655), end: moment(700))])
        XCTAssertEqual(direct.focus(at: moment(582))?.id, .activity(.assembly, moment(570)))
        XCTAssertEqual(persisted.schedule(SchoolClock.date(2027, 3, 9))?.teaching_slots, [.init(start: 804, end: 839)])
        XCTAssertNil(persisted.schedule(SchoolClock.date(2027, 3, 13))?.teaching_slots)
        for field in ["", #","teaching_slots":"unavailable""#] {
            let old = "{\"date\":\"2027-03-08\",\"day\":1,\"lessons\":[]" + field + "}"
            let value = try JSONDecoder().decode(CampusSchedule.self, from: Data(old.utf8))
            XCTAssertTrue(try XCTUnwrap(value.timeline { $0 }).blocks.isEmpty)
        }
        XCTAssertTrue(try XCTUnwrap(CampusSchedule(date: SchoolClock.key(date), day: nil, lessons: [],
                                                  teaching_slots: slots).timeline { $0 }).blocks.isEmpty)
    }
}
