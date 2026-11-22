import Foundation

/// A what-if with OpenGCalc's published credit and conversion model.
/// It does not try to replace, duplicate or infer the school's official GPA policy.
enum TermForecastGPA {
    struct Course {
        let title: String
        let published: Double?
        /// A saved course is nil until its forecasts can be computed from the current detail.
        let prediction: Double?
        let hasForecast: Bool
    }

    static func calculate(_ courses: [Course]) -> GPASummary? {
        var points = 0.0, weight = 0.0, languagePercent = 0.0, languageWeight = 0.0
        var usedForecast = false
        for item in courses {
            let title = item.title
            let chinese = title.contains("Chinese") && !title.localizedCaseInsensitiveContains("second langua")
            let advanced = !title.localizedCaseInsensitiveContains("IGCSE") && inList(title, advancedCourses)
            let factor = title.localizedCaseInsensitiveContains("IGCSE") || advanced ? 1 :
                (inList(title, excludedCourses) ? 0 : inList(title, halfCreditCourses) ? 0.5 : 1)
            if !chinese && factor == 0 { continue }
            // Do not present a partly applied forecast while an included course is still loading.
            let value = item.hasForecast ? item.prediction : item.published
            guard let score = value, score.isFinite, (0...100).contains(score) else {
                if item.hasForecast { return nil }
                continue
            }
            usedForecast = usedForecast || item.hasForecast
            if chinese {
                let part = inList(title, ["History", "Humani", "geogra"]) ? 1.0 / 3 : 2.0 / 3
                languagePercent += score * part
                languageWeight += part
            } else {
                let base = gradePoint(score)
                points += (base + (advanced && base > 0 ? 0.5 : 0)) * factor
                weight += factor
            }
        }
        if languageWeight > 0 {
            points += gradePoint(languagePercent / languageWeight)
            weight += 1
        }
        guard usedForecast, weight > 0 else { return nil }
        return .init(value: points / weight, source: .forecast)
    }

    private static func inList(_ title: String, _ list: [String]) -> Bool {
        list.contains { $0.count < 5 ? title.contains($0) : title.localizedCaseInsensitiveContains($0) }
    }

    private static func gradePoint(_ score: Double) -> Double {
        bands.first(where: { score >= $0.minimum })?.point ?? 0
    }

    private static let bands: [(minimum: Double, point: Double)] = [
        (97,4.3), (93,4), (90,3.7), (87,3.3), (83,3), (80,2.7), (77,2.3),
        (73,2), (70,1.7), (67,1.3), (63,1), (60,0.7), (0,0)
    ]
    private static let halfCreditCourses = [
        "Fine Art", "IT ", "Electi", "Drama", "Chinese Painting", "Architectural", "Dance",
        "Percussion", "Vocal", "Media", "Programming", "Spanish", "Philosophy", "Skills", "Journalism", "Creative"
    ]
    private static let excludedCourses = ["TSSA", "IELTS", "TOFEL", "Student", "Clubs", "Homeroom"]
    private static let advancedCourses = ["AP", "AS", "A2", "A Level", "ALevel"]
}
