import XCTest
@testable import XiaobaoCore

final class LessonActivityPlanTests: XCTestCase {
    private let day = Date(timeIntervalSince1970: 1_752_076_800)

    private func period(_ id: String, _ name: String, _ start: Int, _ end: Int) -> LessonTimeline.Period {
        .init(id: id, name: name, shortName: name, room: nil,
              start: SchoolClock.at(minute: start, on: day), end: SchoolClock.at(minute: end, on: day))
    }

    func testShowsTheCurrentEndAndTheNextClassRatherThanAnEmptySlot() throws {
        let studio = period("1", "Print Studio", 505, 550)
        let critique = period("2", "Field Recording and Critique", 620, 670)
        let timeline = try XCTUnwrap(LessonTimeline(on: day, periods: [critique, studio],
                                                   teachingSlots: [.init(start: 560, end: 600)]))
        let plan = try XCTUnwrap(LessonActivityPlan(timeline: timeline, at: studio.start))
        XCTAssertEqual(plan.endsAt, studio.end)
        XCTAssertEqual(plan.next?.title, critique.name)
        XCTAssertEqual(plan.next?.startsAt, critique.start)
        XCTAssertNil(LessonActivityPlan(timeline: timeline, at: studio.end))
        XCTAssertNil(LessonActivityPlan(timeline: timeline, at: studio.start.addingTimeInterval(-1)))
        XCTAssertNil(LessonActivityPlan(timeline: timeline, at: critique.start)?.next)
    }

    func testSimultaneousClassesDoNotInventAnEndOrAChosenNextClass() throws {
        let workshop = period("1", "Workshop", 510, 560)
        let lab = period("2", "Lab", 580, 625)
        let ensemble = period("3", "Ensemble", 580, 615)
        let timeline = try XCTUnwrap(LessonTimeline(on: day, periods: [workshop, lab, ensemble]))
        XCTAssertNil(LessonActivityPlan(timeline: timeline, at: lab.start))
        XCTAssertNil(LessonActivityPlan(timeline: timeline, at: workshop.start)?.next)
    }

    func testLinkMatchesOnlyTheOriginalNextClassInTheCurrentlyLoadedTimeline() throws {
        let photo = period("1", "Photography", 495, 540)
        let studio = period("2", "Material Studio", 560, 605)
        let original = try XCTUnwrap(LessonTimeline(on: day, periods: [photo, studio]))
        let plan = try XCTUnwrap(LessonActivityPlan(timeline: original, at: photo.start))
        XCTAssertEqual(plan.focusMinute(in: original, at: photo.start), 560)
        let moved = try XCTUnwrap(LessonTimeline(on: day, periods: [photo, period("2", studio.name, 610, 650)]))
        XCTAssertNil(plan.focusMinute(in: moved, at: photo.start))
        XCTAssertNil(plan.focusMinute(in: original, at: studio.end))
    }
}
