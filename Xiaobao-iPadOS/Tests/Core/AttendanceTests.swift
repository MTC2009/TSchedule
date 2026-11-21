import XCTest
@testable import XiaobaoCore

final class AttendanceTests: XCTestCase {
    func testDemoTotalsAndRate() throws {
        let report = AttendanceReport.demo
        XCTAssertEqual(report.courses.count, 4)
        XCTAssertEqual(report.totals, AttendanceCounts(present: 70, late: 2, early: 1, absent: 8))
        XCTAssertEqual(report.totals.total, 81)
        XCTAssertEqual(try XCTUnwrap(report.totals.rate), 70.0 / 81, accuracy: 0.000001)
        XCTAssertNil(report.records)
    }
    func testCourseRatesKeepLateSeparate() throws {
        let rows = AttendanceReport.demo.courses
        let course = try XCTUnwrap(rows.first { $0.id == "demo-botany" })
        XCTAssertEqual(course.counts.total, 34)
        XCTAssertEqual(try XCTUnwrap(course.counts.rate), 31.0 / 34, accuracy: 0.000001)
        XCTAssertEqual(rows.last?.counts.rate, 0)
    }
    func testNoRecordsIsNotZeroPercentAttendance() {
        XCTAssertNil(AttendanceCounts().rate)
        XCTAssertEqual(AttendanceCounts(absent: 1).rate, 0)
        XCTAssertEqual(AttendanceCounts(present: 1).rate, 1)
    }
    func testAggregateCannotPretendToKnowDailyOrOtherCategoryData() {
        let report = AttendanceReport.demo
        XCTAssertNotNil(report.filtered(category: .classroom, range: report.range))
        XCTAssertNil(report.filtered(category: .daily, range: report.range))
        XCTAssertNil(report.filtered(category: .activity, range: report.range))
        let day = SchoolDateRange(start: SchoolClock.date(2026, 11, 17), end: SchoolClock.date(2026, 11, 17))
        XCTAssertNil(report.filtered(category: .classroom, range: day))
    }
    func testRecordFilteringIncludesTheWholeShanghaiEndDay() throws {
        let full = SchoolDateRange(start: SchoolClock.date(2026, 11, 1), end: SchoolClock.date(2026, 11, 30))
        let day = SchoolDateRange(start: SchoolClock.date(2026, 11, 17), end: SchoolClock.date(2026, 11, 17))
        let records: [AttendanceRecord] = [
            .init(id: "a", courseID: "math", date: SchoolClock.date(2026, 11, 16, minute: 1439), status: .absent),
            .init(id: "b", courseID: "math", date: SchoolClock.date(2026, 11, 17, minute: 0), status: .present),
            .init(id: "c", courseID: "math", date: SchoolClock.date(2026, 11, 17, minute: 1439), status: .late),
            .init(id: "d", courseID: "math", date: SchoolClock.date(2026, 11, 18, minute: 0), status: .early)
        ]
        let report = AttendanceReport(category: .classroom, range: full,
                                      courses: [.init(id: "math", name: "Math", counts: .counting(records))], records: records, source: "test")
        let filtered = try XCTUnwrap(report.filtered(category: .classroom, range: day))
        XCTAssertEqual(filtered.records?.map(\.id), ["b", "c"])
        XCTAssertEqual(filtered.totals, AttendanceCounts(present: 1, late: 1))
        let outside = SchoolDateRange(start: SchoolClock.date(2026, 10, 31), end: SchoolClock.date(2026, 11, 30))
        XCTAssertNil(report.filtered(category: .classroom, range: outside))
    }
    func testVerifiedEmptyRangeReturnsEmptyRecordsRatherThanMissingData() throws {
        let full = SchoolDateRange(start: SchoolClock.date(2026, 11, 1), end: SchoolClock.date(2026, 11, 30))
        let report = AttendanceReport(category: .classroom, range: full, courses: [], records: [], source: "test")
        let filtered = try XCTUnwrap(report.filtered(category: .classroom, range: .init(start: full.start, end: full.start)))
        XCTAssertNotNil(filtered.records)
        XCTAssertEqual(filtered.records?.count, 0)
        XCTAssertNil(filtered.totals.rate)
    }
    func testPresetsRespectMonthYearBoundaryAndMondayWeek() throws {
        let now = SchoolClock.date(2027, 1, 3, minute: 1439)
        let term = AttendanceReport.demo.range
        let previous = try XCTUnwrap(AttendancePeriod.lastMonth.range(now: now, semester: term))
        XCTAssertEqual(SchoolClock.key(previous.start), "2026-12-01")
        XCTAssertEqual(SchoolClock.key(previous.end), "2026-12-31")
        let week = try XCTUnwrap(AttendancePeriod.week.range(now: now, semester: term))
        XCTAssertEqual(SchoolClock.key(week.start), "2026-12-28")
        XCTAssertEqual(SchoolClock.key(week.end), "2027-01-03")
        XCTAssertEqual(AttendancePeriod.semester.range(now: now, semester: term), term)
        XCTAssertNil(AttendancePeriod.custom.range(now: now, semester: term))
    }
    func testDateRangeNormalizesOrderAndTimeOfDay() {
        let a = SchoolClock.date(2026, 11, 17, minute: 1200)
        let b = SchoolClock.date(2026, 11, 16, minute: 1200)
        let range = SchoolDateRange(start: a, end: b)
        XCTAssertEqual(range.start, SchoolClock.date(2026, 11, 16))
        XCTAssertEqual(range.end, SchoolClock.date(2026, 11, 17))
        XCTAssertTrue(range.contains(SchoolClock.date(2026, 11, 17, minute: 1439)))
        XCTAssertFalse(range.contains(SchoolClock.date(2026, 11, 18)))
    }
}
