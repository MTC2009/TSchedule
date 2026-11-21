import XCTest
@testable import XiaobaoCore

final class ReminderTests: XCTestCase {
    let provider = DemoSchoolProvider()
    func testNoPastWeekendOrDuplicateNotifications() {
        let now = SchoolClock.date(2026, 11, 17, minute: 656)
        let plan = ReminderPlanner.make(now: now, provider: provider, leadMinutes: 5, morningMinute: 435)
        XCTAssertTrue(plan.allSatisfy { $0.fireDate > now })
        XCTAssertTrue(plan.allSatisfy { !SchoolClock.calendar.isDateInWeekend($0.schoolDate) })
        XCTAssertEqual(Set(plan.map(\.id)).count, plan.count)
        XCTAssertFalse(plan.contains { $0.id.contains("2026-11-17.physics") })
        XCTAssertEqual(plan.first?.lessonID, "2026-11-17.chinese")
        XCTAssertEqual(plan.map(\.fireDate), plan.map(\.fireDate).sorted())
    }
    func testMorningNotificationContainsDayAndRoom() {
        let plan = ReminderPlanner.make(now: SchoolClock.date(2026, 11, 17, minute: 360), provider: provider, leadMinutes: 5, morningMinute: 435)
        let morning = plan.first { $0.id.contains("morning.2026-11-17") }
        XCTAssertEqual(morning?.title, "今天是 Day 4")
        XCTAssertTrue(morning?.body.contains("A205") == true)
        XCTAssertTrue(morning?.body.hasPrefix("本机课表 · 第一节") == true)
        XCTAssertEqual(morning.map { SchoolClock.minute(in: $0.fireDate) }, 435)
    }
    func testLeadTimeAndPendingRequestBudget() {
        let now = SchoolClock.date(2026, 11, 17)
        let five = ReminderPlanner.make(now: now, provider: provider, leadMinutes: 5)
        let ten = ReminderPlanner.make(now: now, provider: provider, leadMinutes: 10)
        XCTAssertEqual(five.first!.fireDate.timeIntervalSince(ten.first!.fireDate), 300)
        let long = ReminderPlanner.make(now: now, provider: provider, leadMinutes: 0, morningMinute: 435, days: 14)
        XCTAssertLessThanOrEqual(long.count, 60)
        XCTAssertTrue(ReminderPlanner.make(now: now, provider: provider, leadMinutes: 5, days: 0).isEmpty)
    }
}
