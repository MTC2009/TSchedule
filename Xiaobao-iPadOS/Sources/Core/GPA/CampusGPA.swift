import Foundation

/// The source declares this scale for the term's published numeric totals.
struct CampusGPAScaleBand: Codable, Equatable, Sendable {
    let minimum_percent: Double
    let grade_points: Double
}

enum CampusGPAReadout: Equatable {
    enum MissingInput: Equatable {
        case courseList, credits, publishedTotals, conversionRule, invalidConversionRule, invalidValues
    }

    case available(GPASummary)
    case unavailable([MissingInput])

    var summary: GPASummary? {
        if case .available(let summary) = self { return summary }
        return nil
    }
}

extension CampusGrades {
    var gpaSummary: GPASummary? { gpaReadout.summary }

    /// Only published grade data enters the calculation. Eligibility and
    /// weighting are explicit: zero GPA credits exclude a course; nil is unknown.
    var gpaReadout: CampusGPAReadout {
        if let official = Self.verifiedPoints(published_gpa) {
            return .available(.init(value: official, source: .published))
        }

        let ids = courses.map { $0.course_id.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !ids.isEmpty, !ids.contains(""), Set(ids).count == ids.count else {
            return .unavailable([.courseList])
        }
        let included = courses.filter { $0.gpa_credits != 0 }
        guard !included.isEmpty else { return .unavailable([.courseList]) }

        var missing: [CampusGPAReadout.MissingInput] = []
        if included.contains(where: { Self.verifiedPoints($0.gpa_credits) == nil }) {
            missing.append(.credits)
        }

        // A published per-course point value already incorporates the source's
        // conversion; do not apply the term scale again to that course.
        let needsConversion = included.filter { Self.verifiedPoints($0.published_gpa) == nil }
        let scale = Self.validatedScale(gpa_scale)
        if needsConversion.contains(where: { $0.published_score?.percentage == nil }) {
            missing.append(.publishedTotals)
        }
        if !needsConversion.isEmpty, scale == nil {
            missing.append(gpa_scale == nil ? .conversionRule : .invalidConversionRule)
        }
        guard missing.isEmpty else { return .unavailable(missing) }

        var weightedPoints = 0.0
        var totalCredits = 0.0
        for course in included {
            let converted = course.published_score?.percentage.flatMap { percent in
                scale?.last { $0.minimum_percent <= percent }?.grade_points
            }
            guard let credits = course.gpa_credits, let points = Self.verifiedPoints(course.published_gpa) ?? converted
                else { return .unavailable([.invalidValues]) }
            weightedPoints += points * credits
            totalCredits += credits
        }
        guard weightedPoints.isFinite, totalCredits.isFinite, totalCredits > 0,
              let result = Self.verifiedPoints(weightedPoints / totalCredits) else { return .unavailable([.invalidValues]) }
        return .available(.init(value: result, source: .creditWeightedEstimate))
    }

    private static func verifiedPoints(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }

    private static func validatedScale(_ bands: [CampusGPAScaleBand]?) -> [CampusGPAScaleBand]? {
        guard let bands, bands.allSatisfy({
            (0...100).contains($0.minimum_percent) && verifiedPoints($0.grade_points) != nil
        }) else { return nil }
        let sorted = bands.sorted { $0.minimum_percent < $1.minimum_percent }
        guard sorted.first?.minimum_percent == 0,
              zip(sorted, sorted.dropFirst()).allSatisfy({
                  $0.0.minimum_percent < $0.1.minimum_percent && $0.0.grade_points <= $0.1.grade_points
              }) else { return nil }
        return sorted
    }
}
