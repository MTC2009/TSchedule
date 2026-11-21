import XCTest
@testable import XiaobaoCore

final class GradeTests: XCTestCase {
    func testDemonstrationGPAs() throws {
        XCTAssertEqual(try GradeCalculator.average(GradeCalculator.demoGrades, weighted: false), 3.6666667, accuracy: 0.000001)
        XCTAssertEqual(try GradeCalculator.average(GradeCalculator.demoGrades, weighted: true), 4.1666667, accuracy: 0.000001)
    }
    func testThresholdsAndAPFailingGrade() throws {
        for (score, expected) in [(0.0, 0.0), (59.999, 0), (60, 1), (69.999, 1), (70, 2), (79.999, 2), (80, 3), (89.999, 3), (90, 4), (100, 4)] {
            XCTAssertEqual(try GradeCalculator.points(score: score, advanced: false, weighted: true), expected)
        }
        XCTAssertEqual(try GradeCalculator.points(score: 59, advanced: true, weighted: true), 0)
        XCTAssertEqual(try GradeCalculator.points(score: 60, advanced: true, weighted: true), 2)
        XCTAssertEqual(try GradeCalculator.points(score: 95, advanced: true, weighted: false), 4)
    }
    func testCreditWeighting() throws {
        let grades = [Grade(id: "a", name: "A", score: 95, credits: 3, advanced: false), Grade(id: "b", name: "B", score: 75, credits: 1, advanced: false)]
        XCTAssertEqual(try GradeCalculator.average(grades, weighted: false), 3.5)
    }
    func testPredictionCrossesGradeBoundary() throws {
        let score = try GradeCalculator.projectedScore(current: 88, assessment: 95, weight: 0.3)
        XCTAssertEqual(score, 90.1, accuracy: 0.00001)
        let grades = GradeCalculator.demoGrades.map { $0.id == "physics" ? Grade(id: $0.id, name: $0.name, score: score, advanced: true) : $0 }
        XCTAssertEqual(try GradeCalculator.average(grades, weighted: true), 4.3333333, accuracy: 0.000001)
    }
    func testRejectsInvalidInputsRatherThanSilentlyDroppingGrades() {
        XCTAssertThrowsError(try GradeCalculator.points(score: .nan, advanced: false, weighted: true))
        XCTAssertThrowsError(try GradeCalculator.points(score: 101, advanced: false, weighted: true))
        XCTAssertThrowsError(try GradeCalculator.average([], weighted: true))
        XCTAssertThrowsError(try GradeCalculator.average([Grade(id: "a", name: "A", score: 80, credits: 0, advanced: false)], weighted: false))
        XCTAssertThrowsError(try GradeCalculator.projectedScore(current: 88, assessment: 95, weight: 1.1))
    }
}
