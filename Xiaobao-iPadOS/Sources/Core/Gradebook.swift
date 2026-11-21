import Foundation

public struct AcademicTerm: Identifiable, Sendable {
    public let id: String
    public let title: String
}

public enum AssessmentStatus: String, CaseIterable, Identifiable, Sendable {
    case graded, pending, missing, excused
    public var id: String { rawValue }
    public var title: String { switch self { case .graded: "已评分"; case .pending: "待评分"; case .missing: "未交"; case .excused: "免交" } }
}

public struct Assessment: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let category: String
    public let date: Date
    public let status: AssessmentStatus
    public let earned: Double?
    public let possible: Double
    public let feedback: String
    public var percentage: Double? {
        guard status == .graded, let earned, earned.isFinite, possible.isFinite,
              possible > 0, earned >= 0, earned <= possible else { return nil }
        return earned / possible * 100
    }
}

public struct CourseReport: Identifiable, Sendable {
    public let termID: String
    public let courseID: String
    public let name: String
    public let teacher: String
    public let credits: Double
    public let advanced: Bool
    public let publishedScore: Double?
    public let assessments: [Assessment]
    public var id: String { termID + "." + courseID }
    public var grade: Grade? {
        guard let publishedScore, publishedScore.isFinite, (0...100).contains(publishedScore), credits.isFinite, credits > 0 else { return nil }
        return Grade(id: id, name: name, score: publishedScore, credits: credits, advanced: advanced)
    }
}

public struct GradeEntry: Identifiable, Sendable {
    public let course: CourseReport
    public let assessment: Assessment
    public var id: String { course.id + "." + assessment.id }
}

public struct Gradebook: Sendable {
    public let terms: [AcademicTerm]
    public let courses: [CourseReport]
    public func reports(termID: String, search: String = "") -> [CourseReport] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return courses.filter { $0.termID == termID && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)) }
    }
    public func entries(termID: String, courseID: String? = nil, status: AssessmentStatus? = nil, search: String = "") -> [GradeEntry] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let courses = reports(termID: termID).filter { courseID == nil || $0.courseID == courseID }
        let all: [GradeEntry] = courses.flatMap { course in
            course.assessments.map { GradeEntry(course: course, assessment: $0) }
        }
        let matching = all.filter { entry in
            if let status, entry.assessment.status != status { return false }
            return query.isEmpty || entry.course.name.localizedCaseInsensitiveContains(query) ||
                entry.assessment.title.localizedCaseInsensitiveContains(query) || entry.assessment.category.localizedCaseInsensitiveContains(query)
        }
        return matching.sorted {
            if $0.assessment.date == $1.assessment.date { return $0.id < $1.id }
            return $0.assessment.date > $1.assessment.date
        }
    }
    public func grades(termID: String) -> [Grade] { reports(termID: termID).compactMap(\.grade) }

    public static let demo: Gradebook = {
        let terms = [AcademicTerm(id: "2026-fall", title: "2026 秋季学期"), AcademicTerm(id: "2026-spring", title: "2026 春季学期")]
        let reports = terms.flatMap { term in
            DemoSchoolProvider.courses.enumerated().map { index, course in
                let fall = term.id == "2026-fall"
                let score = fall ? course.score : course.score - 2
                let month = fall ? 11 : 5
                var items: [Assessment] = [
                    .init(id: "participation", title: "课堂参与", category: "平时表现", date: SchoolClock.date(2026, month, 3),
                          status: .graded, earned: score / 10, possible: 10, feedback: "准备充分，继续保持。"),
                    .init(id: "quiz", title: "单元小测", category: "测验", date: SchoolClock.date(2026, month, 6),
                          status: .graded, earned: (score - 2) / 5, possible: 20, feedback: "复习错题中的关键概念。"),
                    .init(id: "assignment", title: "单元作业", category: "作业", date: SchoolClock.date(2026, month, 10),
                          status: .graded, earned: score + 2, possible: 100, feedback: "表达清楚，注意过程书写。"),
                    .init(id: "midterm", title: "期中考核", category: "考试", date: SchoolClock.date(2026, month, 13),
                          status: .graded, earned: score, possible: 100, feedback: "请核对错题的订正。")
                ]
                if fall {
                    let status: AssessmentStatus = index == 1 ? .missing : index == 5 ? .excused : .pending
                    items.append(.init(id: "project", title: "专题练习", category: "作业", date: SchoolClock.date(2026, 11, 16),
                                       status: status, earned: nil, possible: 100, feedback: status == .pending ? "等待老师评分。" : status == .excused ? "本次免交。" : "尚未提交。"))
                }
                return CourseReport(termID: term.id, courseID: course.id, name: course.name, teacher: course.teacher,
                                    credits: 1, advanced: course.advanced, publishedScore: score, assessments: items)
            }
        }
        return Gradebook(terms: terms, courses: reports)
    }()
}
