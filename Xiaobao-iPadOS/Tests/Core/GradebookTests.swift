import XCTest
@testable import XiaobaoCore

final class GradebookTests: XCTestCase {
    func testUnscoredFeedbackMatchesTheActualState() {
        let entries = Gradebook.demo.entries(termID: "2026-fall").map(\.assessment)
        for (state, feedback): (AssessmentStatus, String) in [
            (.excused, "本次免交。"), (.missing, "尚未提交。"), (.pending, "等待老师评分。")
        ] {
            let matches = entries.filter { $0.status == state }
            XCTAssertFalse(matches.isEmpty)
            XCTAssertTrue(matches.allSatisfy { $0.earned == nil && $0.feedback == feedback })
        }
    }
    func testTermScopeAndPublishedGPA() throws {
        let book = Gradebook.demo
        XCTAssertEqual(book.reports(termID: "2026-fall").count, 6)
        XCTAssertEqual(book.entries(termID: "2026-fall").count, 30)
        XCTAssertEqual(book.entries(termID: "2026-spring").count, 24)
        XCTAssertEqual(try GradeCalculator.average(book.grades(termID: "2026-fall"), weighted: true), 4.166666667, accuracy: 0.000001)
        XCTAssertEqual(book.entries(termID: "unloaded").count, 0)
    }
    func testFiltersCombineCourseStatusAndText() throws {
        let entries = Gradebook.demo.entries(termID: "2026-fall", courseID: "physics", status: .graded, search: "  小测  ")
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.assessment.title, "单元小测")
        XCTAssertEqual(entries.first?.course.courseID, "physics")
        XCTAssertEqual(Gradebook.demo.entries(termID: "2026-fall", status: .pending).count, 4)
        XCTAssertEqual(Gradebook.demo.entries(termID: "2026-fall", status: .missing).count, 1)
        XCTAssertEqual(Gradebook.demo.entries(termID: "2026-fall", status: .excused).count, 1)
        XCTAssertFalse(Gradebook.demo.entries(termID: "2026-fall", search: "PHYSICS").isEmpty)
    }
    func testPercentageRespectsMaximumAndUngradedStatuses() throws {
        let quiz = try XCTUnwrap(Gradebook.demo.entries(termID: "2026-fall", courseID: "physics").first { $0.assessment.id == "quiz" }?.assessment)
        XCTAssertEqual(quiz.possible, 20)
        XCTAssertEqual(try XCTUnwrap(quiz.percentage), 86, accuracy: 0.000001)
        for entry in Gradebook.demo.entries(termID: "2026-fall") where entry.assessment.status != .graded {
            XCTAssertNil(entry.assessment.earned)
            XCTAssertNil(entry.assessment.percentage)
        }
    }
    func testRejectsInvalidOrUnpublishedScores() {
        for (earned, maximum) in [(Double.nan, 100.0), (10, 0), (-1, 100), (101, 100)] {
            let item = Assessment(id: "x", title: "x", category: "x", date: Date(), status: .graded, earned: earned, possible: maximum, feedback: "")
            XCTAssertNil(item.percentage)
        }
        let course = CourseReport(termID: "x", courseID: "x", name: "x", teacher: "x", credits: 1, advanced: true, publishedScore: nil, assessments: [])
        XCTAssertNil(course.grade)
        XCTAssertTrue(Gradebook(terms: [], courses: [course]).grades(termID: "x").isEmpty)
    }
    func testStableUniqueIDsAndNewestFirstAcrossSubjects() {
        let book = Gradebook.demo
        let all = book.terms.flatMap { book.entries(termID: $0.id) }
        XCTAssertEqual(Set(all.map(\.id)).count, all.count)
        XCTAssertEqual(Set(book.courses.map(\.id)).count, book.courses.count)
        let sorted = book.entries(termID: "2026-fall")
        for (a, b) in zip(sorted, sorted.dropFirst()) { XCTAssertGreaterThanOrEqual(a.assessment.date, b.assessment.date) }
    }
}
