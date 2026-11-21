import Foundation
import XCTest
@testable import XiaobaoCore

final class PlannerRotationTests: XCTestCase {
    private let start = SchoolClock.date(2031, 5, 12)
    private func date(_ offset: Int) -> Date { SchoolClock.calendar.date(byAdding: .day, value: offset, to: start)! }
    private func key(_ offset: Int) -> String { SchoolClock.key(date(offset)) }

    private func publication() throws -> PublishedSchoolCalendar {
        let entries: [(SchoolCalendarDay.Status, Int?)] = [
            (.teaching, 5), (.noClass, 5), (.teaching, 6), (.teaching, 1), (.teaching, 2),
            (.teaching, 5), (.weekend, nil), (.teaching, 6), (.unpublished, nil), (.teaching, 1),
            (.teaching, 3), (.teaching, 5), (.weekend, nil), (.weekend, nil)
        ]
        let days = entries.enumerated().map { index, entry -> [String: Any] in
            var row: [String: Any] = ["date": key(index), "status": entry.0.rawValue, "notices": []]
            if let day = entry.1 { row["day"] = day }
            return row
        }
        return try JSONDecoder().decode(PublishedSchoolCalendar.self, from: JSONSerialization.data(withJSONObject:
            ["campus": "main", "division": "HS", "academic_year": "test", "source_sha256": "local",
             "from": key(0), "through": key(entries.count - 1), "days": days]))
    }

    func testRotationMatchesPublishedTeachingDatesNotWeekdaysOrClosureLabels() throws {
        let cal = try publication()
        let plan = try XCTUnwrap(PersonalPlan(day: key(0), title: "Check the print rack", time: PlanTime(startMinute: 512)))
        var bubble = PlanBubble(prototype: plan, reusable: false)
        bubble.revise(recurrence: .rotationDay(5), effectiveDay: key(0))
        let schedule = PlanStore.Schedule(bubbles: [bubble])
        XCTAssertEqual((-1...15).filter { !schedule.day(key($0), calendar: cal).plans.isEmpty }, [0, 5, 11])
        XCTAssertTrue(schedule.day(key(0)).plans.isEmpty, "No calendar must not degrade to a weekday rule")
    }

    private func archiveURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("PlannerRotation-\(UUID()).plist")
    }

    @MainActor func testExistingWeekdayArchiveOpensUnchangedAndSwitchesFromEffectiveDate() async throws {
        // These keys are the shipping pre-rotation format, not an encode/decode
        // round-trip through the new Revision model.
        struct Week: Encodable { let weekday: Int; let plan: PersonalPlan }
        struct Revision: Encodable { let effectiveDay: String; let week: Week }
        struct Bubble: Encodable {
            let prototype: PersonalPlan, reusable = false, revisions: [Revision], completedDays: Set<String>
        }
        struct Schedule: Encodable { let plans: [PersonalPlan], bubbles: [Bubble] }
        struct Archive: Encodable { let owners: [PlanOwner: Schedule] }
        let cal = try publication(), file = archiveURL(), session = UUID()
        let plan = try XCTUnwrap(PersonalPlan(day: key(0), title: "Press samples", time: PlanTime(startMinute: 735), reminder: .tenMinutes))
        let old = Bubble(prototype: plan, revisions: [.init(effectiveDay: key(0), week: .init(weekday: 2, plan: plan))],
                         completedDays: [key(0)])
        let bytes = try PropertyListEncoder().encode(Archive(owners: [.local: .init(plans: [], bubbles: [old])]))
        try bytes.write(to: file)
        let store = PlanStore(file: file)
        let previous = try await store.readSchedule(for: .local)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        XCTAssertTrue(previous.day(key(0)).plans.first?.isCompleted == true)
        XCTAssertEqual(previous.day(key(7)).plans.first?.id, plan.id)
        let state = try await store.apply(.save(.init(target: .bubble(plan.id), plan: plan, reusable: false,
             recurrence: .rotationDay(5), effectiveDay: key(3))), for: .local, session: session, calendar: cal)
        XCTAssertEqual(state.schedule.day(key(0), calendar: cal).plans, previous.day(key(0)).plans)
        XCTAssertEqual(state.schedule.day(key(5), calendar: cal).plans.map(\.id), [plan.id])
        XCTAssertTrue(state.schedule.day(key(7), calendar: cal).plans.isEmpty)
        let cold = PlanStore(file: file)
        let restored = try await cold.readSchedule(for: .local)
        XCTAssertEqual(restored, state.schedule)
        let other = try await cold.readSchedule(for: .campus(origin: URL(string: "https://example.invalid")!, profile: "other"))
        XCTAssertTrue(other.bubbles.isEmpty)
        let undone = try await store.step(.undo, for: .local, session: session)
        XCTAssertEqual(undone.schedule, previous)
        let redone = try await store.step(.redo, for: .local, session: session)
        XCTAssertEqual(redone.schedule, restored)
        let stopped = try await store.apply(.save(.init(target: .bubble(plan.id), plan: plan, reusable: false,
            recurrence: nil, effectiveDay: key(9))), for: .local, session: session, calendar: cal)
        XCTAssertEqual(stopped.schedule.day(key(5), calendar: cal).plans.count, 1)
        XCTAssertTrue(stopped.schedule.day(key(11), calendar: cal).plans.isEmpty)
        XCTAssertFalse(stopped.schedule.bubbles[0].visibleOnShelf)
    }

    @MainActor func testRotationReminderIsDatedCanCrossMidnightAndSkipsOnlyTheCompletedDate() async throws {
        let cal = try publication(), store = PlanStore(file: archiveURL()), session = UUID(), now = date(-1)
        let time = try XCTUnwrap(PlanTime(startMinute: 12))
        let plan = try XCTUnwrap(PersonalPlan(day: key(0), title: "Reset the timer", time: time, reminder: .thirtyMinutes))
        let initial = try await store.apply(.save(.init(target: .create, plan: plan, reusable: false,
            recurrence: .rotationDay(5), effectiveDay: key(0))), for: .local, session: session, calendar: cal)
        func reminders(_ state: PlanStore.EditorState) -> [PlannedPlanReminder] {
            PlanReminderPlanner.make(now: now, schedule: state.schedule, calendar: cal)
        }
        func fires(_ offsets: [Int]) -> [Date] { offsets.map { time.start(on: date($0)).addingTimeInterval(-1800) } }
        let all = reminders(initial)
        XCTAssertEqual(all.map(\.nextFire), fires([0, 5, 11]))
        XCTAssertEqual(Set(all.map(\.id)).count, 3)
        XCTAssertTrue(all.allSatisfy { $0.timing == .once })
        XCTAssertTrue(PlanReminderPlanner.make(now: now, schedule: initial.schedule).isEmpty)
        let makeup = try XCTUnwrap(initial.schedule.day(key(5), calendar: cal).plans.first)
        let marked = try await store.apply(.complete(true, plan: makeup), for: .local, session: session, calendar: cal)
        XCTAssertEqual(reminders(marked).map(\.nextFire), fires([0, 11]))
        let undo = try await store.step(.undo, for: .local, session: session)
        XCTAssertEqual(reminders(undo), all)
        // A change of mode must not leave a stale Saturday or a prematurely repeating weekday request.
        let switched = try await store.apply(.save(.init(target: .bubble(plan.id), plan: plan, reusable: false,
            recurrence: .weekday(2), effectiveDay: key(6))), for: .local, session: session, calendar: cal)
        let cutover = reminders(switched)
        XCTAssertEqual(Array(cutover.prefix(3)).map(\.nextFire), fires([0, 5, 7]))
        XCTAssertFalse(cutover.map(\.nextFire).contains(fires([11])[0]))
    }

    @MainActor func testMovingRotationUsesTheDestinationTeachingDayAndCannotTargetAClosure() async throws {
        let cal = try publication(), store = PlanStore(file: archiveURL()), session = UUID()
        let plan = try XCTUnwrap(PersonalPlan(day: key(0), title: "Scan contact sheets", time: PlanTime(startMinute: 500)))
        let initial = try await store.apply(.save(.init(target: .create, plan: plan, reusable: false,
            recurrence: .rotationDay(5), effectiveDay: key(0))), for: .local, session: session, calendar: cal)
        let source = try XCTUnwrap(initial.schedule.day(key(5), calendar: cal).plans.first)
        let item = PlanPlacementItem(plan: source, source: .occurrence), moved = try XCTUnwrap(PlanTime(startMinute: 640))
        for target in [1, 6, 8, 14] {
            do {
                _ = try await store.apply(.place(item, on: key(target), at: moved, now: date(5)),
                                         for: .local, session: session, calendar: cal)
                XCTFail("A rotation cannot move onto a date without a teaching Day")
            } catch PlanStore.StoreError.invalidPlan {}
        }
        let changed = try await store.apply(.place(item, on: key(7), at: moved, now: date(5)),
                                            for: .local, session: session, calendar: cal)
        XCTAssertEqual(changed.schedule.day(key(0), calendar: cal).plans.first?.time, plan.time)
        XCTAssertTrue(changed.schedule.day(key(5), calendar: cal).plans.isEmpty)
        XCTAssertEqual(changed.schedule.day(key(7), calendar: cal).plans.first?.time, moved)
        XCTAssertEqual(changed.schedule.bubbles.first?.latest?.rule?.recurrence, .rotationDay(6))
        let undo = try await store.step(.undo, for: .local, session: session)
        XCTAssertEqual(undo.schedule, initial.schedule)
    }

    @MainActor func testInvalidOrUntimedRotationIsNotWritten() async throws {
        let store = PlanStore(file: archiveURL()), cal = try publication()
        for (day, time) in [(0, PlanTime(startMinute: 700)), (7, PlanTime(startMinute: 700)), (3, nil)] {
            let plan = try XCTUnwrap(PersonalPlan(day: key(0), title: "Fold endpapers", time: time))
            do {
                _ = try await store.save(.init(target: .create, plan: plan, reusable: false, recurrence: .rotationDay(day),
                                               effectiveDay: key(0)), for: .local, calendar: cal)
                XCTFail("Invalid rotation saved")
            } catch PlanStore.StoreError.invalidPlan {}
        }
        let state = try await store.readSchedule(for: .local)
        XCTAssertTrue(state.bubbles.isEmpty && state.plans.isEmpty)
    }
}
