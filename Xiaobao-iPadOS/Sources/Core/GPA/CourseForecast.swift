import Foundation

/// A hypothetical assessment, separate from the school's grade records.
struct AssessmentForecast: Identifiable, Equatable {
    let id: UUID
    let name: String?
    let category: String?
    let mark: Double
    let courseWeight: Double?

    init(id: UUID = UUID(), name: String? = nil, category: String? = nil, mark: Double, courseWeight: Double? = nil) throws {
        guard mark.isFinite, (0...100).contains(mark) else { throw GradeError.invalidScore }
        if let courseWeight, !courseWeight.isFinite || !(0...1).contains(courseWeight) {
            throw GradeError.invalidWeight
        }
        let name = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.id = id
        self.name = name.flatMap { $0.isEmpty ? nil : $0 }
        self.category = category
        self.mark = mark
        self.courseWeight = courseWeight
    }
}

enum CourseForecast {
    enum Result: Equatable {
        case noEstimates
        case missingCourseTotal
        case missingWeight
        case excessiveWeight
        case estimated(Double)
    }

    /// The published total represents the work outside the explicitly supplied hypothetical course shares.
    static func calculate(current: Double?, estimates: [AssessmentForecast]) -> Result {
        guard !estimates.isEmpty else { return .noEstimates }
        var sum = 0.0
        var contribution = 0.0
        for estimate in estimates {
            guard let weight = estimate.courseWeight else { return .missingWeight }
            sum += weight
            contribution += estimate.mark * weight
        }
        // Shares such as tenths can exceed exactly 1 by a rounding bit.
        guard sum <= 1 + 1e-12 else { return .excessiveWeight }
        guard let current, current.isFinite, (0...100).contains(current) else { return .missingCourseTotal }
        return .estimated(min(100, current * max(0, 1 - sum) + contribution))
    }
}
