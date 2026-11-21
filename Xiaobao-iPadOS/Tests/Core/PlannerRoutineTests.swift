import Foundation
import XCTest
@testable import XiaobaoCore

final class PlannerRoutineTests: XCTestCase {
    private let date = SchoolClock.date(2027, 1, 18)
    private var key: String { SchoolClock.key(date) }
    private var weekday: Int { SchoolClock.calendar.component(.weekday, from: date) }

    @MainActor func testReusableBubbleKeepsItsIdentityAndSpawnsIndependentDatedCopies() async throws {
        let owner = PlanOwner.campus(origin: URL(string: "https://demo.example.invalid/")!, profile: "fixture")
        let store = PlanStore(file: temporaryArchive())
        let prototype = try XCTUnwrap(PersonalPlan(day: key, title: "Recharge the audio recorder", time: nil,
                                                    color: .teal, icon: .computer, reminder: .tenMinutes))
        let created = try await store.save(PlanEdit(target: .create, plan: prototype, reusable: true,
                                                   weekday: nil, effectiveDay: key), for: owner)
        XCTAssertTrue(created.plans.isEmpty)
        let next = SchoolClock.key(date.addingTimeInterval(86_400))
        let copyTime = try XCTUnwrap(PlanTime(startMinute: 1015, endMinute: 1060))
        let first = try await store.placeBubble(prototype.id, on: key, at: copyTime, for: owner)
        let second = try await store.placeBubble(prototype.id, on: next, at: copyTime, for: owner)
        let a = try XCTUnwrap(first.plans.first)
        let b = try XCTUnwrap(second.plans.first)
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertEqual(a.color, .teal)
        XCTAssertEqual(b.reminder, .tenMinutes)
        XCTAssertEqual(second.bubbles.first?.prototype, prototype)
        XCTAssertTrue(second.weeklyIDs.isEmpty)
        let other = try await store.readSchedule(for: .local)
        XCTAssertTrue(other.bubbles.isEmpty)
        XCTAssertTrue(other.plans.isEmpty)
    }

    @MainActor func testWeeklyChangesAndCompletionAffectOnlyIntendedOccurrences() async throws {
        let file = temporaryArchive()
        let store = PlanStore(file: file)
        let time = try XCTUnwrap(PlanTime(startMinute: 505, endMinute: 550))
        let original = try XCTUnwrap(PersonalPlan(day: key, title: "Clean drying trays", time: time, color: .orange))
        let first = try await store.save(PlanEdit(target: .create, plan: original, reusable: false,
                                                 weekday: weekday, effectiveDay: key), for: .local)
        let occurrence = try XCTUnwrap(first.plans.first)
        XCTAssertEqual(first.weeklyIDs, [original.id])
        XCTAssertTrue(first.bubbles[0].visibleOnShelf)
        let previous = try await store.readDay(SchoolClock.key(date.addingTimeInterval(-7 * 86_400)), for: .local)
        XCTAssertTrue(previous.plans.isEmpty)
        _ = try await store.complete(true, plan: occurrence, for: .local)
        let later = SchoolClock.key(date.addingTimeInterval(7 * 86_400))
        let nextWeek = try await store.readDay(later, for: .local)
        XCTAssertEqual(nextWeek.plans.first?.isCompleted, false)

        let updated = try XCTUnwrap(PersonalPlan(id: original.id, day: later, title: "Clean labelled trays",
                                               time: PlanTime(startMinute: 580, endMinute: 625)))
        _ = try await store.save(PlanEdit(target: .bubble(original.id), plan: updated, reusable: false,
                                         weekday: weekday, effectiveDay: later), for: .local)
        let restored = PlanStore(file: file)
        let old = try await restored.readDay(key, for: .local)
        let new = try await restored.readDay(later, for: .local)
        XCTAssertEqual(old.plans.first?.title, original.title)
        XCTAssertEqual(old.plans.first?.isCompleted, true)
        XCTAssertEqual(old.plans.first?.time, time)
        XCTAssertEqual(new.plans.first?.time, updated.time)
        let future = SchoolClock.key(date.addingTimeInterval(14 * 86_400))
        _ = try await restored.save(PlanEdit(target: .bubble(original.id), plan: updated, reusable: true,
                                            weekday: nil, effectiveDay: future), for: .local)
        let stopped = try await restored.readDay(future, for: .local)
        XCTAssertTrue(stopped.plans.isEmpty)
        XCTAssertTrue(stopped.bubbles[0].visibleOnShelf)
        let intact = try await restored.readDay(later, for: .local)
        XCTAssertEqual(intact.plans.first?.time, updated.time)
    }

    func testRemindersSkipUntimedCompletedAndPastAndCanCrossMidnight() throws {
        let next = SchoolClock.key(date.addingTimeInterval(86_400))
        let start = try XCTUnwrap(PlanTime(startMinute: 7))
        let late = try XCTUnwrap(PersonalPlan(day: next, title: "Charge field logger", time: start, reminder: .tenMinutes))
        let completed = try XCTUnwrap(PersonalPlan(day: next, title: "Seal the slide box", time: start, isCompleted: true, reminder: .atStart))
        let untimed = try XCTUnwrap(PersonalPlan(day: next, title: "Calibrate the scale", time: nil, reminder: .atStart))
        let past = try XCTUnwrap(PersonalPlan(day: key, title: "Send inventory sheet", time: start, reminder: .atStart))
        let plan = PlanReminderPlanner.make(now: SchoolClock.at(minute: 21 * 60, on: date),
                                           schedule: .init(plans: [completed, late, untimed, past]))
        XCTAssertEqual(plan.map(\.planTitle), [late.title])
        XCTAssertEqual(plan.first?.nextFire, SchoolClock.at(minute: 1437, on: date))
        XCTAssertEqual(plan.first?.timing, .once)
    }

    func testWeeklyNotificationDoesNotStartEarlyAndCarriesLeadIntoPreviousWeekday() throws {
        let futureDate = date.addingTimeInterval(28 * 86_400)
        let futureKey = SchoolClock.key(futureDate)
        let prototype = try XCTUnwrap(PersonalPlan(day: futureKey, title: "Inspect seal alignment",
                                                   time: PlanTime(startMinute: 12), reminder: .thirtyMinutes))
        var bubble = PlanBubble(prototype: prototype, reusable: false)
        bubble.revise(weekday: weekday, effectiveDay: futureKey)
        let schedule = PlanStore.Schedule(bubbles: [bubble])
        let expected = SchoolClock.at(minute: 12, on: futureDate).addingTimeInterval(-30 * 60)
        let distant = PlanReminderPlanner.make(now: date, schedule: schedule)
        XCTAssertEqual(distant.first?.timing, .once)
        XCTAssertEqual(distant.first?.nextFire, expected)
        let near = PlanReminderPlanner.make(now: futureDate.addingTimeInterval(-86_400), schedule: schedule)
        XCTAssertEqual(near.first?.nextFire, expected)
        XCTAssertEqual(near.first?.timing, .weekly(weekday: 1, minute: 1422))
        bubble.revise(weekday: nil, effectiveDay: futureKey)
        XCTAssertTrue(PlanReminderPlanner.make(now: date, schedule: .init(bubbles: [bubble])).isEmpty)
    }

    private func temporaryArchive() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("XiaobaoRoutineTests-\(UUID())", isDirectory: true)
            .appendingPathComponent("plans.plist")
    }
}
