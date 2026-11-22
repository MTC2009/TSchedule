import Foundation
import XCTest
@testable import XiaobaoCore

final class PlannerEditingTests: XCTestCase {
    func testSilentPlanRemovalDoesNotWaitForUnrelatedNotifications() throws {
        let day = SchoolClock.date(2032, 3, 16), key = SchoolClock.key(day)
        let alarm = try makePlan(on: day, start: 825)
        let note = try XCTUnwrap(PersonalPlan(day: key, title: "Label the drawers", time: nil))
        let remaining = PlanStore.Schedule(plans: [alarm])
        let both = PlanStore.Schedule(plans: [alarm, note])
        XCTAssertFalse(PlanReminderPlanner.inputsChanged(from: both, to: remaining))
        XCTAssertFalse(PlanReminderPlanner.inputsChanged(from: remaining, to: both))
        XCTAssertTrue(PlanReminderPlanner.inputsChanged(from: remaining, to: .init()))

        var repeated = PlanBubble(prototype: alarm, reusable: true)
        repeated.revise(recurrence: .weekday(3), effectiveDay: key)
        let before = PlanStore.Schedule(bubbles: [repeated])
        let next = SchoolClock.key(after(7, day))
        repeated.revise(recurrence: nil, effectiveDay: next)
        let afterStop = PlanStore.Schedule(bubbles: [repeated])
        XCTAssertTrue(PlanReminderPlanner.inputsChanged(from: before, to: afterStop))
        XCTAssertTrue(PlanReminderPlanner.inputsChanged(from: afterStop, to: before))
    }

    @MainActor func testRemovingSavedPlanByIdentityIsDurableReversibleAndCancelsOnlyItsReminder() async throws {
        let file = temporaryArchive(), store = PlanStore(file: file), session = UUID()
        let day = SchoolClock.date(2034, 2, 13)
        let keep = try makePlan(on: day, start: 565), remove = try makePlan(on: day, start: 565)
        let other = PlanOwner.campus(origin: URL(string: "https://example.invalid")!, profile: "separate")
        _ = try await store.create(remove, for: other)
        _ = try await store.create(keep, for: .local)
        _ = try await store.create(remove, for: .local)
        do {
            _ = try await store.apply(.remove(remove, .thisAndLater), for: .local, session: session)
            XCTFail("A one-off record cannot be treated as a series")
        } catch PlanStore.StoreError.invalidPlan {}
        do {
            let stale = try XCTUnwrap(remove.placing(at: nil))
            _ = try await store.apply(.remove(stale, .onlyThis), for: .local, session: session)
            XCTFail("A stale editor cannot remove a changed plan")
        } catch PlanStore.StoreError.missingPlan {}
        let new = try await store.apply(.remove(remove, .onlyThis), for: .local, session: session)
        XCTAssertEqual(new.schedule.plans, [keep])
        XCTAssertEqual(PlanReminderPlanner.make(now: day, schedule: new.schedule).map(\.id),
                       [PlanReminderPlanner.identifierPrefix + "once." + keep.id.uuidString])
        let reopened = PlanStore(file: file)
        let survivor = try await reopened.readSchedule(for: .local), untouched = try await reopened.readSchedule(for: other)
        XCTAssertEqual(survivor, new.schedule)
        XCTAssertEqual(untouched.plans, [remove])
        let undo = try await store.step(.undo, for: .local, session: session)
        XCTAssertEqual(undo.schedule.plans, [keep, remove])
        let redo = try await store.step(.redo, for: .local, session: session)
        XCTAssertEqual(redo.schedule, new.schedule)
    }

    @MainActor func testCreatingAndEditingHaveSeparateUndoSteps() async throws {
        let date = SchoolClock.date(2033, 2, 17)
        let original = try makePlan(on: date, start: 658)
        let edited = try XCTUnwrap(PersonalPlan(id: original.id, day: original.day, title: "Catalog archived slides",
                                               time: PlanTime(startMinute: 805), reminder: .atStart))
        let session = UUID()
        let store = PlanStore(file: temporaryArchive())
        let created = try await store.apply(.save(.init(target: .create, plan: original, reusable: false,
            recurrence: nil, effectiveDay: original.day)), for: .local, session: session)
        let changed = try await store.apply(.save(.init(target: .plan(original.id), plan: edited, reusable: false,
            recurrence: nil, effectiveDay: original.day)), for: .local, session: session)
        XCTAssertEqual(changed.schedule.plans, [edited])
        let beforeEdit = try await store.step(.undo, for: .local, session: session)
        XCTAssertEqual(beforeEdit.schedule, created.schedule)
        let beforeCreate = try await store.step(.undo, for: .local, session: session)
        XCTAssertTrue(beforeCreate.schedule.plans.isEmpty)
        XCTAssertTrue(PlanReminderPlanner.make(now: date, schedule: beforeCreate.schedule).isEmpty)
        _ = try await store.step(.redo, for: .local, session: session)
        let restored = try await store.step(.redo, for: .local, session: session)
        XCTAssertEqual(restored.schedule.plans, [edited])
        XCTAssertEqual(PlanReminderPlanner.make(now: date, schedule: restored.schedule).first?.nextFire,
                       SchoolClock.at(minute: 805, on: date))
    }

    @MainActor func testWeeklyHandleChangesSeriesAndHistoryAsOneWrite() async throws {
        let session = UUID()
        let first = SchoolClock.date(2032, 3, 8)
        let oldDay = after(7, first)
        let destination = after(9, first)
        let now = SchoolClock.at(minute: 419, on: oldDay)
        let original = try makePlan(on: first, start: 549)
        let moved = try XCTUnwrap(PlanTime(startMinute: 925, endMinute: 971))
        let store = PlanStore(file: temporaryArchive())
        let weekday = SchoolClock.calendar.component(.weekday, from: first)
        let created = try await store.apply(.save(.init(target: .create, plan: original, reusable: true,
                                                 recurrence: .weekday(weekday), effectiveDay: original.day)), for: .local, session: session)
        let source = try XCTUnwrap(created.schedule.day(SchoolClock.key(oldDay)).plans.first)
        let placed = try await store.apply(.place(.init(plan: source, source: .occurrence),
                                                  on: SchoolClock.key(destination), at: moved, now: now),
                                           for: .local, session: session)
        XCTAssertEqual(placed.schedule.day(original.day).plans.first?.time, original.time)
        XCTAssertTrue(placed.schedule.day(SchoolClock.key(oldDay)).plans.isEmpty)
        XCTAssertEqual(placed.schedule.day(SchoolClock.key(destination)).plans.first?.time, moved)
        XCTAssertEqual(placed.schedule.day(SchoolClock.key(after(7, destination))).plans.first?.time, moved)
        XCTAssertEqual(placed.schedule.bubbles.first?.prototype.id, original.id)
        XCTAssertTrue(placed.schedule.plans.isEmpty)
        let reminders = PlanReminderPlanner.make(now: now, schedule: placed.schedule)
        XCTAssertEqual(reminders.count, 1)
        XCTAssertEqual(reminders.first?.nextFire, SchoolClock.at(minute: 915, on: destination))

        let undone = try await store.step(.undo, for: .local, session: session)
        XCTAssertEqual(undone.schedule, created.schedule)
        XCTAssertTrue(undone.canUndo && undone.canRedo)
        let oldReminder = PlanReminderPlanner.make(now: now, schedule: undone.schedule)
        XCTAssertEqual(oldReminder.first?.nextFire, SchoolClock.at(minute: 539, on: oldDay))
        let redone = try await store.step(.redo, for: .local, session: session)
        XCTAssertEqual(redone.schedule, placed.schedule)
        XCTAssertFalse(redone.canRedo)
    }

    @MainActor func testOrdinaryPlanCrossesDayAndCompletesWithoutCrossingAccountsOrRedoBranches() async throws {
        let date = SchoolClock.date(2033, 10, 4)
        let next = SchoolClock.key(after(1, date))
        let original = try makePlan(on: date, start: 630)
        let moved = try XCTUnwrap(PlanTime(startMinute: 840))
        let session = UUID()
        let store = PlanStore(file: temporaryArchive())
        _ = try await store.apply(.save(.init(target: .create, plan: original, reusable: false, recurrence: nil,
                                             effectiveDay: original.day)), for: .local, session: session)
        let placed = try await store.apply(.place(.init(plan: original, source: .plan), on: next,
                                                  at: moved, now: date), for: .local, session: session)
        let record = try XCTUnwrap(placed.schedule.day(next).plans.first)
        XCTAssertEqual(record.id, original.id)
        XCTAssertTrue(placed.schedule.day(original.day).plans.isEmpty)
        let finished = try await store.apply(.complete(true, plan: record), for: .local, session: session)
        XCTAssertTrue(try XCTUnwrap(finished.schedule.plans.first?.isCompleted))
        let undo = try await store.step(.undo, for: .local, session: session)
        XCTAssertEqual(undo.schedule, placed.schedule)
        let undoMove = try await store.step(.undo, for: .local, session: session)
        XCTAssertEqual(undoMove.schedule.plans.first, original)
        let scopedOut = try await store.readEditor(for: .local, session: UUID())
        XCTAssertFalse(scopedOut.canUndo || scopedOut.canRedo)
        let other = PlanOwner.campus(origin: URL(string: "https://example.invalid")!, profile: "fixture")
        let otherState = try await store.readEditor(for: other, session: session)
        XCTAssertFalse(otherState.canUndo || otherState.canRedo)
        XCTAssertTrue(otherState.schedule.plans.isEmpty)
        let diverged = try await store.apply(.complete(true, plan: original), for: .local, session: session)
        XCTAssertFalse(diverged.canRedo)
    }

    func testFutureRuleKeepsOldEligibleRemindersButNeverRepeatsTheObsoleteTime() throws {
        let first = SchoolClock.date(2034, 6, 12)
        let effective = after(14, first)
        let destination = after(16, first)
        let old = try makePlan(on: first, start: 735)
        var bubble = PlanBubble(prototype: old, reusable: false)
        bubble.revise(recurrence: .weekday(SchoolClock.calendar.component(.weekday, from: first)), effectiveDay: old.day)
        XCTAssertTrue(bubble.reschedule(to: destination, at: try XCTUnwrap(PlanTime(startMinute: 1015)), now: first))
        // A delayed move uses explicit requests up to the cutover. It must not
        // leave one unlimited repeating request at the obsolete weekday/time.
        let plan = PlanReminderPlanner.make(now: first, schedule: .init(bubbles: [bubble]))
        XCTAssertEqual(plan.map(\.nextFire).filter { $0 < effective }, [SchoolClock.at(minute: 725, on: first),
                                                                         SchoolClock.at(minute: 725, on: after(7, first))])
        XCTAssertTrue(plan.allSatisfy { $0.timing == .once })
        XCTAssertTrue(plan.contains { $0.nextFire == SchoolClock.at(minute: 1005, on: destination) })
    }

    @MainActor func testCompletingAWeeklyOccurrenceSkipsOnlyItsReminderUntilUndone() async throws {
        let first = SchoolClock.date(2035, 8, 13)
        let second = after(7, first)
        let plan = try makePlan(on: first, start: 555)
        let session = UUID()
        let store = PlanStore(file: temporaryArchive())
        let weekday = SchoolClock.calendar.component(.weekday, from: first)
        let saved = try await store.apply(.save(.init(target: .create, plan: plan, reusable: false,
            recurrence: .weekday(weekday), effectiveDay: plan.day)), for: .local, session: session)
        let current = try XCTUnwrap(saved.schedule.day(plan.day).plans.first)
        let completed = try await store.apply(.complete(true, plan: current), for: .local, session: session)
        let nextReminders = PlanReminderPlanner.make(now: first, schedule: completed.schedule)
        XCTAssertEqual(nextReminders.first?.nextFire, SchoolClock.at(minute: 545, on: second))
        XCTAssertEqual(nextReminders.first?.timing, .once)
        XCTAssertEqual(completed.schedule.day(SchoolClock.key(second)).plans.first?.isCompleted, false)
        let undone = try await store.step(.undo, for: .local, session: session)
        let restored = PlanReminderPlanner.make(now: first, schedule: undone.schedule)
        XCTAssertEqual(restored.first?.nextFire, SchoolClock.at(minute: 545, on: first))
        XCTAssertEqual(restored.first?.timing, .weekly(weekday: weekday, minute: 545))
        let redone = try await store.step(.redo, for: .local, session: session)
        XCTAssertEqual(PlanReminderPlanner.make(now: first, schedule: redone.schedule), nextReminders)
    }

    @MainActor func testWeeklyShelfMoveCanAdvanceFirstOccurrenceWithoutMakingACopy() async throws {
        let monday = SchoolClock.date(2032, 3, 8)
        let initialDate = after(4, monday)
        let earlier = after(2, monday)
        let plan = try makePlan(on: initialDate, start: 975)
        let session = UUID()
        let store = PlanStore(file: temporaryArchive())
        _ = try await store.apply(.save(.init(target: .create, plan: plan, reusable: true,
            recurrence: .weekday(SchoolClock.calendar.component(.weekday, from: initialDate)), effectiveDay: plan.day)),
            for: .local, session: session)
        let newDay = SchoolClock.key(earlier)
        let changed = try await store.apply(.place(.init(plan: plan, source: .recurringBubble),
            on: newDay, at: plan.time, now: monday), for: .local, session: session)
        XCTAssertEqual(changed.schedule.day(newDay).recurringIDs, [plan.id])
        XCTAssertTrue(changed.schedule.day(plan.day).plans.isEmpty)
        XCTAssertTrue(changed.schedule.plans.isEmpty)
        XCTAssertEqual(changed.schedule.bubbles.count, 1)
    }

    func testPublishedClosuresSpanMonthsWithoutTurningAnEventIntoAClosure() throws {
        let first = SchoolClock.date(2036, 12, 30)
        func row(_ date: Date, _ status: String, _ notice: String) -> [String: Any] {
            ["date": SchoolClock.key(date), "status": status, "notices": [notice]]
        }
        let days = [row(first, "no_class", "Campus maintenance"),
                    row(after(1, first), "no_class", "Campus maintenance"),
                    row(after(2, first), "no_class", "Campus maintenance"),
                    row(after(3, first), "weekend", "Robotics showcase")]
        let publication = try JSONDecoder().decode(PublishedSchoolCalendar.self, from: JSONSerialization.data(withJSONObject: [
            "campus": "main", "academic_year": "fixture", "division": "HS", "source_sha256": "fixture",
            "from": SchoolClock.key(first), "through": SchoolClock.key(after(3, first)), "days": days
        ]))
        let month = PlannerCalendarMonth(containing: after(2, first), publication: publication)
        XCTAssertEqual(month.cells.count % 7, 0)
        let closure = try XCTUnwrap(month.notices(on: after(2, first)).first)
        XCTAssertEqual(closure.first, first)
        XCTAssertEqual(closure.last, after(2, first))
        XCTAssertTrue(closure.isClosed)
        XCTAssertEqual(month.notices(on: after(3, first)).first?.isClosed, false)
        XCTAssertEqual(month.schoolDay(after(4, first))?.status, .unpublished)
    }

    private func after(_ days: Int, _ date: Date) -> Date {
        SchoolClock.calendar.date(byAdding: .day, value: days, to: date)!
    }

    private func makePlan(on date: Date, start: Int) throws -> PersonalPlan {
        try XCTUnwrap(PersonalPlan(day: SchoolClock.key(date), title: "Reconcile sensor inventory",
                                  time: PlanTime(startMinute: start, endMinute: start + 46), reminder: .tenMinutes))
    }

    private func temporaryArchive() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("XiaobaoEdit-\(UUID())", isDirectory: true)
            .appendingPathComponent("plans.plist")
    }
}
