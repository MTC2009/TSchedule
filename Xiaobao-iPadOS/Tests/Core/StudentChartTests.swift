import XCTest
@testable import XiaobaoCore

final class StudentChartTests: XCTestCase {
    func testHistoryUsesDatedGradedPercentsAndBreaksAtGapsAndTies() {
        func item(_ id: String, _ day: String?, _ earned: Double?, _ possible: Double? = 20,
                  _ status: String = "graded", type: String = "numeric") -> CampusAssessment {
            CampusAssessment(id: id, title: id, status: status, date: day, feedback: nil,
                             score: CampusScore(type: type, earned: earned, possible: possible, value: type == "letter" ? "A" : nil))
        }
        let course = CampusGrade(course_id: "math", published_score: nil, published_gpa: nil, assessments: [
            item("last", "2026-11-08", 0), item("first", "2026-11-01", 15), item("second", "2026-11-02", 16),
            item("pending", "2026-11-03", 0, 20, "pending"), item("after", "2026-11-04", 18),
            item("tie2", "2026-11-06", 16), item("tie1", "2026-11-05T16:30:00Z", 20),
            item("letter", "2026-11-07", nil, type: "letter"), item("undated", nil, 19),
            item("no-scale", "2026-11-10", 5, nil), item("zero-scale", "2026-11-12", 0, 0)])
        let points = course.assessmentHistory
        XCTAssertEqual(points.map(\.id), ["first", "second", "after", "tie1", "tie2", "last"])
        XCTAssertEqual(points.map(\.percentage), [75, 80, 90, 100, 80, 0])
        XCTAssertEqual(points[0].segment, points[1].segment)
        XCTAssertEqual(Set(points.dropFirst().map(\.segment)).count, 5)
        XCTAssertEqual(points[3].day, points[4].day)
        let local = Gradebook.demo.reports(termID: "2026-fall").first { $0.courseID == "physics" }!
        let localScores = local.assessmentHistory.map(\.percentage)
        XCTAssertEqual(localScores.count, 4)
        for (score, expected) in zip(localScores, [88.0, 86, 90, 88]) {
            XCTAssertEqual(score, expected, accuracy: 0.0001)
        }
    }

    func testCourseCompositionUsesEachCoursesOwnTotalAndOmitsZeroSegments() {
        let seminar = AttendanceCounts(present: 7, late: 1, absent: 2)
        let studio = AttendanceCounts(present: 1, early: 3)
        let first = AttendanceComposition(counts: seminar).segments
        let second = AttendanceComposition(counts: studio).segments
        XCTAssertEqual(first.map(\.status), [.present, .late, .absent])
        XCTAssertEqual(first.map(\.fractionRange), [0..<0.7, 0.7..<0.8, 0.8..<1])
        XCTAssertEqual(first.map(\.share), [0.7, 0.1, 0.2])
        XCTAssertEqual(second.map(\.status), [.present, .early])
        XCTAssertEqual(second.map(\.fractionRange), [0..<0.25, 0.25..<1])
        XCTAssertTrue(AttendanceComposition(counts: AttendanceCounts()).segments.isEmpty)
    }

    func testConnectedCourseDistinguishesZeroMissingRateAndInvalidTotals() {
        func row(present: Int = 9, late: Int = 0, early: Int = 2, absent: Int = 1,
                 total: Int = 12, rate: Double? = 0.75) -> AttendanceCourseRow {
            AttendanceCourseRow(id: "lab", name: "材料实验",
                                summary: CampusCounts(present: present, late: late, early: early, absent: absent,
                                                      total: total, present_rate: rate))
        }
        let valid = row()
        XCTAssertEqual(valid.counts, AttendanceCounts(present: 9, early: 2, absent: 1))
        XCTAssertEqual(valid.presentRate, 0.75)
        XCTAssertEqual(row(rate: nil).counts, valid.counts)
        XCTAssertNil(row(rate: nil).presentRate)
        XCTAssertNil(row(rate: 1.4).presentRate)
        let empty = row(present: 0, early: 0, absent: 0, total: 0)
        XCTAssertEqual(empty.counts, AttendanceCounts())
        XCTAssertNil(empty.presentRate)
        for invalid in [row(total: 13), row(late: -1), row(present: .max, total: .max)] {
            XCTAssertNil(invalid.counts)
            XCTAssertNil(invalid.presentRate)
        }
    }

    func testAttendanceRingPaintAndTapUseTheSameSharesAndBoundaries() {
        let counts = AttendanceCounts(present: 24, late: 3, early: 1, absent: 4)
        let layout = AttendanceRingLayout(counts: counts)
        XCTAssertEqual(layout.segments.map(\.fractionRange), [0..<0.75, 0.75..<0.84375, 0.84375..<0.875, 0.875..<1])
        XCTAssertEqual(layout.segments.map(\.share), [0.75, 3.0 / 32, 1.0 / 32, 0.125])
        let center = CGPoint(x: 113, y: 89)
        let radius: CGFloat = 72
        func tap(_ point: CGPoint) -> AttendanceStatus? {
            layout.hit(at: point, center: center, radius: radius, hitWidth: 44)?.segment.status
        }
        for segment in layout.segments {
            let direction = AttendanceRingLayout.direction(at: segment.midpoint)
            let point = CGPoint(x: center.x + radius * direction.dx, y: center.y + radius * direction.dy)
            XCTAssertEqual(tap(point), segment.status)
        }
        XCTAssertEqual(tap(CGPoint(x: center.x - radius, y: center.y)), .late)
        XCTAssertEqual(tap(CGPoint(x: center.x, y: center.y - radius)), .present)
        XCTAssertEqual(tap(CGPoint(x: center.x - 1, y: center.y - radius)), .absent)
        XCTAssertEqual(tap(CGPoint(x: center.x + radius + 20, y: center.y)), .present)
        XCTAssertNil(tap(center))
        XCTAssertNil(tap(CGPoint(x: center.x + radius + 23, y: center.y)))
        XCTAssertNil(tap(CGPoint(x: center.x + radius - 23, y: center.y)))
    }

    func testAttendanceRingDoesNotCreateSegmentsForZeroAndUnknownRecords() {
        let center = CGPoint(x: 72, y: 72)
        let point = CGPoint(x: 72, y: 12)
        let empty = AttendanceRingLayout(counts: AttendanceCounts())
        XCTAssertTrue(empty.segments.isEmpty)
        XCTAssertNil(empty.hit(at: point, center: center, radius: 60, hitWidth: 44))

        let single = AttendanceRingLayout(counts: AttendanceCounts(early: 5))
        XCTAssertEqual(single.segments.map(\.status), [.early])
        XCTAssertEqual(single.segments.map(\.share), [1])
        XCTAssertEqual(single.segments.map(\.fractionRange), [0..<1])
        XCTAssertEqual(single.hit(at: point, center: center, radius: 60, hitWidth: 44)?.segment.status, .early)
    }

    func testHistoryRangeIncludesBothSchoolDatesAndPreservesGaps() throws {
        let start = SchoolClock.date(2027, 4, 3)
        let missing = SchoolClock.date(2027, 4, 4)
        let end = SchoolClock.date(2027, 4, 5)
        func record(_ id: String, _ date: Date, _ pct: Double?) -> AssessmentReading {
            AssessmentReading(id: id, title: id, date: date, percentage: pct)
        }
        let points = AssessmentPoint.history([
            record("before", start.addingTimeInterval(-1), 85),
            record("start", start, 72), record("pending", missing, nil),
            record("end", end.addingTimeInterval(86_399), 96),
            record("after", end.addingTimeInterval(86_400), 88)
        ])
        let range = try XCTUnwrap(AssessmentHistoryRange(start: start.addingTimeInterval(12 * 3600), end: end))
        let shown = points.filter(range.contains)
        XCTAssertEqual(shown.map(\.id), ["start", "end"])
        XCTAssertNotEqual(shown.first?.segment, shown.last?.segment, "Filtering must not reconnect a broken line")
        let empty = try XCTUnwrap(AssessmentHistoryRange(start: missing, end: missing))
        XCTAssertFalse(points.contains(where: empty.contains))
        XCTAssertNil(AssessmentHistoryRange(start: end, end: start))
    }

    func testRecentWeekIntersectsCoverageUsingTheCurrentSchoolDay() {
        let covered = OfflineAttendance.Coverage(from: "2026-11-01", to: "2026-11-18")
        XCTAssertEqual(covered.recentWeek(on: SchoolClock.date(2026, 11, 16)), .init(from: "2026-11-10", to: "2026-11-16"))
        XCTAssertEqual(covered.recentWeek(on: SchoolClock.date(2026, 11, 21)), .init(from: "2026-11-15", to: "2026-11-18"))
        XCTAssertNil(covered.recentWeek(on: SchoolClock.date(2026, 12, 1)))
        XCTAssertNil(covered.recentWeek(on: SchoolClock.date(2026, 10, 31)))
    }
}
