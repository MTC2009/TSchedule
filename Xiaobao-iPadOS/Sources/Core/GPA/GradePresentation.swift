import Foundation

struct GPASummary: Equatable {
    enum Source: Equatable { case published, localEstimate(weighted: Bool), creditWeightedEstimate, forecast }
    let value: Double
    let source: Source
}

extension Gradebook {
    func gpaSummary(termID: String, weighted: Bool) -> GPASummary? {
        let reports = reports(termID: termID)
        let grades = reports.compactMap(\.grade)
        guard grades.count == reports.count,
              let value = try? GradeCalculator.average(grades, weighted: weighted) else { return nil }
        return GPASummary(value: value, source: .localEstimate(weighted: weighted))
    }
}

extension SavedCampusGrades {
    var courseGradeDetails: [CourseGradeDetail] {
        let names = Dictionary(roster.map { ($0.course_id, $0.name) }, uniquingKeysWith: { first, _ in first })
        return grades.courses.map { grade in
            let name = names[grade.course_id]?.trimmingCharacters(in: .whitespacesAndNewlines)
            let label = name.flatMap { $0.isEmpty || $0 == grade.course_id ? nil : $0 } ?? String(localized: "课程名称待载入")
            return CourseGradeDetail(term: grades.term, name: label, grade: grade)
        }
    }
}

enum GradeMark: Equatable, Sendable {
    case numeric(earned: Double, possible: Double?, letter: String? = nil)
    case letter(String)

    init?(score: CampusScore?, letter: String? = nil) {
        let letter = letter.flatMap { $0.isEmpty ? nil : $0 }
        if let score, score.type == "numeric", let earned = score.earned, earned.isFinite,
           score.possible.map({ $0.isFinite }) != false {
            self = .numeric(earned: earned, possible: score.possible, letter: letter)
        } else if let value = score?.type == "letter" ? score?.value ?? letter : letter, !value.isEmpty {
            self = .letter(value)
        } else {
            return nil
        }
    }

    var displayText: String {
        switch self {
        case .letter(let value): value
        case .numeric(let earned, let possible, let letter):
            earned.formatted(.number) + (possible.map { " / " + $0.formatted(.number) } ?? "") +
                (letter.map { " · " + $0 } ?? "")
        }
    }
}

struct AssessmentWeight: Equatable {
    enum Scope: Equatable { case course, group }
    let fraction: Double
    let scope: Scope

    init?(_ fraction: Double?, scope: Scope) {
        guard let fraction, fraction.isFinite, (0...1).contains(fraction) else { return nil }
        self.fraction = fraction
        self.scope = scope
    }
}

struct AssessmentResult: Identifiable {
    let id, title: String
    let status: String
    let mark: GradeMark?
    let weight: AssessmentWeight?
    let date: Date?
    let feedback: String?
    let percentage: Double?

    private var knownStatus: AssessmentStatus? { AssessmentStatus(rawValue: status) }
    var statusTitle: String {
        switch status {
        case "unpublished": String(localized: "未发布")
        case "absent": String(localized: "缺考")
        case "no_mark": String(localized: "未提供成绩")
        default: knownStatus?.title ?? status
        }
    }

    func matches(query: String, status selected: AssessmentStatus?) -> Bool {
        (selected == nil || knownStatus == selected) &&
            (query.isEmpty || title.localizedCaseInsensitiveContains(query))
    }
}

enum GradeBreakdownRow: Identifiable {
    enum ID: Hashable { case group(String), assessment(String) }
    case group(title: String, weight: AssessmentWeight?, mark: GradeMark?, items: [AssessmentResult])
    case assessment(AssessmentResult)

    var id: ID {
        switch self {
        case .group(let title, _, _, _): .group(title)
        case .assessment(let item): .assessment(item.id)
        }
    }

    var items: [AssessmentResult] {
        switch self {
        case .group(_, _, _, let items): items
        case .assessment(let item): [item]
        }
    }
}

struct CourseGradeDetail: Identifiable {
    struct ID: Hashable { let term, course: String }
    let id: ID
    let name: String
    let total: GradeMark?
    let totalPercentage: Double?
    let teacher: String?
    let credits: Double?
    let className: String?
    let publishedGPA: Double?
    let firstPublishedAt: Date?
    let forecastGroups: ForecastGroups
    let rows: [GradeBreakdownRow]
    let history: () -> [AssessmentPoint]

    init(report: CourseReport) {
        id = ID(term: report.termID, course: report.courseID)
        name = report.name
        total = report.publishedScore.flatMap { $0.isFinite ? .numeric(earned: $0, possible: nil) : nil }
        totalPercentage = report.publishedScore.flatMap { (0...100).contains($0) ? $0 : nil }
        teacher = report.teacher
        credits = report.credits
        className = nil
        publishedGPA = nil
        firstPublishedAt = nil
        // Existing categories are labels, not published aggregate scores or weights.
        let sorted = report.assessments.sorted { ($0.date, $0.id) > ($1.date, $1.id) }
        let byCategory = Dictionary(grouping: sorted, by: \.category)
        let names = byCategory.keys.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        forecastGroups = ForecastGroups(names.map { name in
            let items = byCategory[name] ?? [], graded = items.filter { $0.status == .graded }
            let marks = graded.map { item in item.earned.map { GradeMark.numeric(earned: $0, possible: item.possible) } }
            return ForecastGroup(id: name, title: name, parentID: nil, weight: nil, published: nil, hasItems: true,
                                 samples: .init(released: marks, excludesUnreleased: graded.count != items.count))
        })
        var seen: Set<String> = []
        rows = sorted.compactMap { assessment in
            let category = assessment.category
            guard !category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let grouped = byCategory[category], grouped.count > 1 else {
                return .assessment(Self.localResult(assessment))
            }
            guard seen.insert(category).inserted else { return nil }
            return .group(title: category, weight: nil, mark: nil, items: grouped.map(Self.localResult))
        }
        history = { report.assessmentHistory }
    }

    init(term: String, name: String, grade: CampusGrade, publishedRows: [GradeBreakdownRow]? = nil,
         forecastGroups: ForecastGroups = ForecastGroups(), numericBaseline: Double? = nil) {
        id = ID(term: term, course: grade.course_id)
        self.name = name
        total = GradeMark(score: grade.published_score, letter: grade.published_letter_grade)
        totalPercentage = grade.published_score?.percentage ?? numericBaseline
        teacher = nil
        credits = nil
        className = grade.class_name.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        publishedGPA = grade.published_gpa.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        firstPublishedAt = grade.first_published_at.flatMap(campusInstant)
        self.forecastGroups = forecastGroups
        // The service currently supplies a flat breakdown. Titles are not a nesting contract.
        rows = publishedRows ?? grade.assessments.map { item in
            let graded = item.status == AssessmentStatus.graded.rawValue
            return .assessment(AssessmentResult(
                id: item.id, title: item.title, status: item.status,
                mark: graded ? GradeMark(score: item.score) : nil, weight: AssessmentWeight(item.weight, scope: .course),
                date: item.date.flatMap { SchoolClock.dayDate($0) ?? campusInstant($0) },
                feedback: item.feedback, percentage: graded ? item.score?.percentage : nil
            ))
        }
        history = { grade.assessmentHistory }
    }

    func matches(query: String, status: AssessmentStatus?) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let courseMatches = query.isEmpty || name.localizedCaseInsensitiveContains(query)
        if courseMatches && status == nil { return true }
        return rows.contains { row in
            let groupMatches: Bool
            if case .group(let title, _, _, _) = row { groupMatches = title.localizedCaseInsensitiveContains(query) }
            else { groupMatches = false }
            return row.items.contains { $0.matches(query: courseMatches || groupMatches ? "" : query, status: status) }
        }
    }

    private static func localResult(_ item: Assessment) -> AssessmentResult {
        let percentage = item.percentage
        let mark: GradeMark? = percentage != nil
            ? item.earned.map { .numeric(earned: $0, possible: item.possible) } : nil
        return AssessmentResult(id: item.id, title: item.title, status: item.status.rawValue,
                                mark: mark, weight: nil, date: item.date, feedback: item.feedback, percentage: percentage)
    }
}
