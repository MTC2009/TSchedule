import Foundation

public struct Grade: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let score: Double
    public let credits: Double
    public let advanced: Bool
    public init(id: String, name: String, score: Double, credits: Double = 1, advanced: Bool) {
        self.id = id; self.name = name; self.score = score; self.credits = credits; self.advanced = advanced
    }
}

public enum GradeError: Error, Equatable { case invalidScore, invalidCredits, invalidWeight, emptyGrades }

/// Demonstration grading policy. Replace with a verified school policy in the live adapter.
public enum GradeCalculator {
    public static func points(score: Double, advanced: Bool, weighted: Bool) throws -> Double {
        guard score.isFinite && (0...100).contains(score) else { throw GradeError.invalidScore }
        let base: Double = score >= 90 ? 4 : score >= 80 ? 3 : score >= 70 ? 2 : score >= 60 ? 1 : 0
        return base + (weighted && advanced && base > 0 ? 1 : 0)
    }

    public static func average(_ grades: [Grade], weighted: Bool) throws -> Double {
        guard !grades.isEmpty else { throw GradeError.emptyGrades }
        var total = 0.0
        var credits = 0.0
        for grade in grades {
            guard grade.credits.isFinite && grade.credits > 0 else { throw GradeError.invalidCredits }
            total += try points(score: grade.score, advanced: grade.advanced, weighted: weighted) * grade.credits
            credits += grade.credits
        }
        return total / credits
    }

    public static func projectedScore(current: Double, assessment: Double, weight: Double) throws -> Double {
        guard current.isFinite && assessment.isFinite && (0...100).contains(current) && (0...100).contains(assessment) else { throw GradeError.invalidScore }
        guard weight.isFinite && (0...1).contains(weight) else { throw GradeError.invalidWeight }
        return current * (1 - weight) + assessment * weight
    }

    public static var demoGrades: [Grade] {
        DemoSchoolProvider.courses.map { Grade(id: $0.id, name: $0.name, score: $0.score, advanced: $0.advanced) }
    }
}
