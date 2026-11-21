import XCTest
@testable import XiaobaoCore

final class CourseForecastTests: XCTestCase {
    func testMultipleHypotheticalSharesOnlyReplaceTheirPortionOfThePublishedTotal() throws {
        let practical = try AssessmentForecast(name: "  Clay sample  ", category: "Studio", mark: 68, courseWeight: 0.15)
        let review = try AssessmentForecast(mark: 94, courseWeight: 0.25)
        XCTAssertEqual(practical.name, "Clay sample")
        XCTAssertEqual(practical.category, "Studio")
        XCTAssertNil(review.name)
        XCTAssertNotEqual(practical.id, review.id)
        guard case .estimated(let value) = CourseForecast.calculate(current: 82, estimates: [practical, review]) else {
            return XCTFail("The assumptions define a complete forecast")
        }
        XCTAssertEqual(value, 82.9, accuracy: 0.0001)
    }

    func testMissingInputIsNotZero() throws {
        let unspecified = try AssessmentForecast(name: "  ", mark: 0)
        let excluded = try AssessmentForecast(mark: 0, courseWeight: 0)
        XCTAssertNil(unspecified.name)
        XCTAssertEqual(CourseForecast.calculate(current: 73, estimates: []), .noEstimates)
        XCTAssertEqual(CourseForecast.calculate(current: 73, estimates: [excluded, unspecified]), .missingWeight)
        XCTAssertEqual(CourseForecast.calculate(current: 73, estimates: [excluded]), .estimated(73))
        for current: Double? in [nil, -.infinity, .nan, 140] {
            XCTAssertEqual(CourseForecast.calculate(current: current, estimates: [excluded]), .missingCourseTotal)
        }
    }

    func testHandlesExactFullAllocationButRejectsMoreThanOneHundredPercent() throws {
        let all = try (0..<10).map { _ in try AssessmentForecast(mark: 100, courseWeight: 0.1) }
        XCTAssertEqual(CourseForecast.calculate(current: 67, estimates: all), .estimated(100))
        XCTAssertEqual(CourseForecast.calculate(current: 67, estimates: all + [all[0]]), .excessiveWeight)
    }

    func testRejectsInvalidMarksAndCourseWeights() {
        for mark in [-1, 101, .nan, .infinity] {
            XCTAssertThrowsError(try AssessmentForecast(mark: mark))
        }
        for weight in [-0.001, 1.01, .nan, .infinity] {
            XCTAssertThrowsError(try AssessmentForecast(mark: 80, courseWeight: weight))
        }
        XCTAssertNoThrow(try AssessmentForecast(mark: 0, courseWeight: 1))
    }
}
