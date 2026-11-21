import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#endif
@testable import XiaobaoCore

final class PlannerPlacementTests: XCTestCase {
    private let date = SchoolClock.date(2027, 2, 3)

    func testUsesRealMinuteCoordinatesBeforeBetweenAndAfterClasses() throws {
        for height in [72.0, 96, 162] {
            let scale = PlannerTimeScale(hourHeight: height)
            for minute in [0.0, 328.2, 605, 977.8, 1340, 1439] {
                XCTAssertEqual(try XCTUnwrap(scale.minute(at: scale.position(at: minute))), minute, accuracy: 0.0001)
            }
            XCTAssertNil(scale.minute(at: -1))
            XCTAssertNil(scale.minute(at: scale.height))
            XCTAssertEqual(scale.minute(at: scale.height, includingDayEnd: true), 1440)
            XCTAssertNil(scale.minute(at: scale.height + 1, includingDayEnd: true))
            XCTAssertNil(scale.minute(at: .infinity))
        }
    }

    func testNewPlanInAConfirmedVacancyTakesTheWholeSlotButOtherSpaceSetsOnlyStart() throws {
        let free = entry("published-slot", .freeblock, 747, 787)
        let lunch = entry("midday", .lunch, 684, 725)
        let day = makeDay([free, lunch])
        let inside = try XCTUnwrap(PlannerPlacement(at: 768.4, moving: nil, in: day))
        XCTAssertEqual(inside.time, PlanTime(startMinute: 747, endMinute: 787))
        XCTAssertTrue(inside.conflicts.isEmpty)
        XCTAssertEqual(PlannerPlacement(at: 787, moving: nil, in: day)?.time, PlanTime(startMinute: 785))
        XCTAssertEqual(PlannerPlacement(at: 743.1, moving: nil, in: day)?.time, PlanTime(startMinute: 745))
        XCTAssertEqual(PlannerPlacement(at: 700, moving: nil, in: day)?.conflicts.map(\.id), [lunch.id])
        XCTAssertEqual(PlannerPlacement(at: 768.4, moving: nil, in: makeDay([]))?.time, PlanTime(startMinute: 770))
    }

    func testMovePreservesTheOriginalDurationAndAdvisesAboutOverlap() throws {
        let existing = try XCTUnwrap(PlanTime(startMinute: 455, endMinute: 490))
        let workshop = entry("workshop", .lesson, 600, 660)
        let free = entry("vacancy", .freeblock, 715, 760)
        let day = makeDay([free, workshop])
        let newTime = try XCTUnwrap(PlannerPlacement(at: 579, moving: existing, in: day))
        XCTAssertEqual(newTime.time, PlanTime(startMinute: 580, endMinute: 615))
        XCTAssertEqual(newTime.conflicts.map(\.id), [workshop.id])
        XCTAssertEqual(PlannerPlacement(at: 729, moving: existing, in: day)?.time, PlanTime(startMinute: 730, endMinute: 765))
        XCTAssertEqual(PlannerPlacement(at: 729, moving: PlanTime(startMinute: 455), in: day)?.time, PlanTime(startMinute: 730))
    }

    func testRejectsDropsOutsideTheDayAndDoesNotShortenAPlanToFit() throws {
        let day = makeDay([])
        let hour = try XCTUnwrap(PlanTime(startMinute: 750, endMinute: 810))
        XCTAssertNil(PlannerPlacement(at: -1, moving: nil, in: day))
        XCTAssertNil(PlannerPlacement(at: .nan, moving: nil, in: day))
        XCTAssertNil(PlannerPlacement(at: 1440, moving: nil, in: day))
        XCTAssertEqual(PlannerPlacement(at: 1439, moving: nil, in: day)?.time, PlanTime(startMinute: 1435))
        XCTAssertEqual(PlannerPlacement(at: 1380, moving: hour, in: day)?.time, PlanTime(startMinute: 1380, endMinute: 1440))
        XCTAssertNil(PlannerPlacement(at: 1383, moving: hour, in: day))
    }

    func testOverlappingRecordsGetIndependentLanesWithoutMovingTheirClock() throws {
        let scale = PlannerTimeScale(hourHeight: 96)
        let workshop = entry("workshop", .lesson, 531, 586)
        let notice = entry("courtyard-announcement", .calendar, 564, nil)
        let other = entry("other-course", .lesson, 575, 630)
        let next = entry("next-course", .lesson, 630, 685)
        let day = makeDay([next, other, notice, workshop])
        let layout = PlannerTimelineLayout(day: day, scale: scale, minimumHeight: 48)
        XCTAssertEqual(layout.school.items.map(\.id), [.school(workshop.id), .school(other.id), .school(next.id)])
        XCTAssertEqual(layout.school.items.map(\.lane), [0, 1, 0])
        XCTAssertEqual(layout.school.items.map(\.laneCount), [2, 2, 1])
        XCTAssertEqual(layout.school.items.map(\.top), [531, 575, 630].map { scale.position(at: Double($0)) })
        XCTAssertEqual(layout.school.items.map(\.height), Array(repeating: scale.position(at: 55) - PlannerTimelineLayout.cardGap, count: 3))
        XCTAssertEqual(layout.school.markGroups.flatMap(\.marks).map(\.id), [.school(notice.id)])
    }

    func testVacanciesAndShortMarksNeverTakeASecondColumnOrChangeSpacing() throws {
        let scale = PlannerTimeScale(hourHeight: 96)
        let early = entry("first-class", .lesson, 505, 545)
        let adjacent = entry("following-class", .lesson, 545, 585)
        let slot = entry("open-instructional-slot", .freeblock, 610, 655)
        let brief = entry("hand-in", .activity, 541, 551)
        let point = entry("guest-arrival", .activity, 543, nil)
        let plan = try XCTUnwrap(PersonalPlan(day: SchoolClock.key(date), title: "Inventory sample folders",
                                             time: PlanTime(startMinute: 610, endMinute: 655)))
        let baseline = PlannerTimelineLayout(day: makeDay([early, adjacent], plans: [plan]), scale: scale, minimumHeight: 48)
        let withMarks = PlannerTimelineLayout(day: makeDay([early, brief, point, adjacent, slot], plans: [plan]),
                                              scale: scale, minimumHeight: 48)
        XCTAssertEqual(withMarks.school.items.map(\.laneCount), [1, 1])
        XCTAssertEqual(withMarks.personal.items.map(\.laneCount), [1])
        XCTAssertEqual(withMarks.school.items.map(\.top), baseline.school.items.map(\.top))
        XCTAssertEqual(withMarks.school.items.map(\.height), baseline.school.items.map(\.height))
        XCTAssertEqual(withMarks.school.items[1].top - withMarks.school.items[0].bottom, 0)
        XCTAssertEqual(withMarks.freeBlocks.map(\.id), [slot.id])
        XCTAssertEqual(withMarks.school.markGroups.map { $0.marks.map(\.id) }, [[.school(brief.id), .school(point.id)]])
        XCTAssertEqual(withMarks.school.markGroups[0].marks[0].bottom, scale.position(at: 551))
    }

    func testPersonalOverlapCannotMoveSchoolCardsOrGroupSchoolMarks() throws {
        let scale = PlannerTimeScale(hourHeight: 96)
        let first = entry("field-studies", .lesson, 515, 565)
        let second = entry("laboratory", .lesson, 565, 610)
        let event = entry("assessment", .exam, 580, 650)
        let notice = entry("shared-lab-briefing", .calendar, 640, nil)
        let key = SchoolClock.key(date)
        let bridge = try XCTUnwrap(PersonalPlan(day: key, title: "Catalogue instrument cases",
                                                time: PlanTime(startMinute: 530, endMinute: 675)))
        let overlap = try XCTUnwrap(PersonalPlan(day: key, title: "Review observations",
                                                 time: PlanTime(startMinute: 585, endMinute: 665)))
        let point = try XCTUnwrap(PersonalPlan(day: key, title: "Collect locker key", time: PlanTime(startMinute: 638)))
        let school = [first, second, event, notice]
        let baseline = PlannerTimelineLayout(day: makeDay(school), scale: scale, minimumHeight: 48)
        let layered = PlannerTimelineLayout(day: makeDay(school, plans: [bridge, overlap, point]), scale: scale, minimumHeight: 48)
        XCTAssertEqual(layered.school.items.map(\.id), baseline.school.items.map(\.id))
        XCTAssertEqual(layered.school.items.map(\.top), baseline.school.items.map(\.top))
        XCTAssertEqual(layered.school.items.map(\.height), baseline.school.items.map(\.height))
        XCTAssertEqual(layered.school.items.map(\.lane), baseline.school.items.map(\.lane))
        XCTAssertEqual(layered.school.items.map(\.laneCount), [1, 2, 2])
        XCTAssertEqual(layered.school.markGroups.flatMap(\.marks).map(\.id), [.school(notice.id)])
        XCTAssertEqual(layered.personal.items.map(\.laneCount), [2, 2])
        XCTAssertEqual(layered.personal.markGroups.flatMap(\.marks).map(\.id), [.personal(point.id)])
        XCTAssertEqual(layered.height, baseline.height)
    }

    func testDrawnRangeWorksInBothDirectionsAndDoesNotExpandToASchoolSlot() throws {
        let activity = entry("event", .activity, 906, 935)
        let slot = entry("open-period", .freeblock, 935, 980)
        let day = makeDay([activity, slot])
        let selection = try XCTUnwrap(PlannerPlacement(from: 921.1, to: 954.5, in: day))
        XCTAssertEqual(selection.time, PlanTime(startMinute: 920, endMinute: 955))
        XCTAssertEqual(selection.conflicts.map(\.id), [activity.id])
        XCTAssertEqual(PlannerPlacement(from: 954.5, to: 921.1, in: day)?.time, selection.time)
        XCTAssertEqual(PlannerPlacement(from: 941.2, to: 955.3, in: day)?.time,
                       PlanTime(startMinute: 940, endMinute: 955))
        XCTAssertEqual(PlannerPlacement(from: 1440, to: 1403, in: day)?.time,
                       PlanTime(startMinute: 1405, endMinute: 1440))
        XCTAssertNil(PlannerPlacement(from: 410.5, to: 411, in: day))
        XCTAssertNil(PlannerPlacement(from: -2, to: 80, in: day))
        XCTAssertNil(PlannerPlacement(from: 100, to: 1440.1, in: day))
    }

    func testPersonalLabelMovesOffSchoolTextWithoutMovingItsRange() throws {
        let scale = PlannerTimeScale(hourHeight: 96)
        let plan = try XCTUnwrap(PersonalPlan(day: SchoolClock.key(date), title: "Check instrument seals",
                                             time: PlanTime(startMinute: 516, endMinute: 572), icon: .pencil))
        let day = makeDay([entry("lab", .lesson, 511, 562)], plans: [plan])
        let layout = PlannerTimelineLayout(day: day, scale: scale, minimumHeight: 48)
        let top = scale.position(at: 516)
        let text = CGRect(x: 3, y: top + 4, width: 94, height: 33)
        let overlay = PlannerAnnotationLayout(personal: layout.personal, track: CGRect(x: 0, y: 0, width: 110, height: layout.height),
                                              labelHeight: 23, avoiding: [text])
        let label = try XCTUnwrap(overlay.annotations.first)
        XCTAssertTrue(label.showsTitle)
        XCTAssertFalse(label.frame.intersects(text))
        XCTAssertGreaterThanOrEqual(label.frame.minY, top)
        XCTAssertLessThanOrEqual(label.frame.maxY, scale.position(at: 572))
        XCTAssertEqual(label.marks.first?.top, top)
        XCTAssertEqual(label.marks.first?.bottom, scale.position(at: 572))
    }

    func testDenseGroupsKeepTheirMembersAndLeaveDistantTimesIndependent() throws {
        func plan(_ title: String, minute: Int, icon: PlanIcon) throws -> PersonalPlan {
            try XCTUnwrap(PersonalPlan(day: SchoolClock.key(date), title: title,
                                       time: PlanTime(startMinute: minute, endMinute: minute + 29), icon: icon))
        }
        let a = try plan("File notes", minute: 581, icon: .book)
        let b = try plan("Check calibration", minute: 584, icon: .computer)
        let c = try plan("Record labels", minute: 588, icon: .pencil)
        let later = try plan("Return lens", minute: 671, icon: .errands)
        let scale = PlannerTimeScale(hourHeight: 96)
        let layout = PlannerTimelineLayout(day: makeDay([], plans: [later, c, a, b]), scale: scale, minimumHeight: 48)
        let overlay = PlannerAnnotationLayout(personal: layout.personal, track: CGRect(x: 0, y: 0, width: 112, height: layout.height),
                                              labelHeight: 23, avoiding: [])
        XCTAssertEqual(overlay.annotations.map { $0.marks.map(\.id) }, [[.personal(a.id), .personal(b.id), .personal(c.id)], [.personal(later.id)]])
        XCTAssertEqual(overlay.annotations.first?.marks.map(\.top), [581, 584, 588].map { scale.position(at: Double($0)) })
        XCTAssertEqual(overlay.annotations.map(\.showsTitle), [false, true])
    }

    func testCrowdedSinglePlanKeepsAnIconWithoutCoveringTheSchoolLabel() throws {
        let plan = try XCTUnwrap(PersonalPlan(day: SchoolClock.key(date), title: "Inspect specimen", time: PlanTime(startMinute: 588), icon: .flag))
        let layout = PlannerTimelineLayout(day: makeDay([], plans: [plan]), scale: .init(hourHeight: 96), minimumHeight: 48)
        let mark = try XCTUnwrap(layout.personal.markGroups.first?.marks.first)
        let text = CGRect(x: 0, y: mark.top - 22, width: 69, height: 77)
        let overlay = PlannerAnnotationLayout(personal: layout.personal, track: CGRect(x: 0, y: 0, width: 107, height: layout.height),
                                              labelHeight: 23, avoiding: [text])
        let label = try XCTUnwrap(overlay.annotations.first)
        XCTAssertFalse(label.showsTitle)
        XCTAssertEqual(label.marks.map(\.id), [.personal(plan.id)])
        XCTAssertFalse(label.frame.intersects(text))
    }

    private func entry(_ id: String, _ kind: PlannerSchoolEntry.Kind, _ start: Int, _ end: Int?) -> PlannerSchoolEntry {
        .init(id: .event(id), kind: kind, title: "Synthetic school entry", location: nil,
              start: SchoolClock.at(minute: start, on: date),
              end: end.map { SchoolClock.at(minute: $0, on: date) }, allDay: false)
    }

    private func makeDay(_ entries: [PlannerSchoolEntry], plans: [PersonalPlan] = []) -> PlannerDay {
        PlannerDay(on: date, school: PlannerSchoolDay(rotationDay: 3, hasTimetable: true, hasCalendar: true, entries: entries),
                   plans: plans)
    }
}
