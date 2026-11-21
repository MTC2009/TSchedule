import Foundation

struct TaskAttachment: Codable, Hashable, Sendable {
    let name: String
    let size_bytes: UInt64?
}

struct CampusTaskDetails: Codable, Sendable {
    struct Submission: Codable, Sendable {
        let submitted_at: String?
        let text: String?
        let attachments: [TaskAttachment]?
    }
    struct Feedback: Codable, Sendable {
        let text: String?
        let attachments: [TaskAttachment]?
    }
    let mode, grading_status: String?
    let score: CampusScore?
    let attachments: [TaskAttachment]?
    let opens_at: String?
    let submission: Submission?
    let feedback: Feedback?
    // The provider must explicitly release this separate estimate to the
    // current student. The ordinary score field is not a preview source.
    var released_score_estimate: CampusScore? = nil
}

enum TaskSubmissionState: String, CaseIterable, Identifiable, Sendable {
    case pending, overdue, submitted, completed, localCompletion, unavailable
    var id: Self { self }

    var title: String {
        switch self {
        case .pending: "待提交"
        case .overdue: "逾期未交"
        case .submitted: "已提交"
        case .completed: "已完成"
        case .localCompletion: "本地完成"
        case .unavailable: "提交状态未提供"
        }
    }
}

enum TaskGradingState: String, CaseIterable, Identifiable, Sendable {
    case graded, gradedUnpublished = "graded_unpublished", pending, inProgress = "in_progress", missing, excused, unavailable
    var id: Self { self }

    var title: String {
        switch self {
        case .graded: "已批改"
        case .gradedUnpublished: "已批改，待发布"
        case .pending: "未批改"
        case .inProgress: "批改中"
        case .missing: "缺交"
        case .excused: "免评"
        case .unavailable: "批改状态未提供"
        }
    }
}

enum TaskCardStage: Equatable, Sendable {
    case unsubmitted, overdue, awaitingGrading, graded
}

struct TaskRecord: Identifiable, Sendable {
    struct Material: Sendable {
        let text: String?
        let attachments: [TaskAttachment]
    }

    let id, title: String
    let term, courseID, courseName, teacher: String?
    let workType, mode: String?
    let publishedAt, opensAt, dueAt: Date?
    let sourceStatus: String
    let grading: TaskGradingState
    let sourceMark: GradeMark?
    let instructions: Material
    let answer: Material?
    let submittedAt: Date?
    let feedback: Material?
    var isLocalDemo = false
    var releasedEstimate: GradeMark? = nil

    var mark: GradeMark? { grading == .graded ? sourceMark : nil }
    var estimatedMark: GradeMark? { grading == .gradedUnpublished ? releasedEstimate : nil }
    var permitsLocalCompletion: Bool { isLocalDemo && sourceStatus == "pending" }

    func submission(at now: Date, locallyCompleted: Bool) -> TaskSubmissionState {
        if permitsLocalCompletion && locallyCompleted { return .localCompletion }
        switch sourceStatus {
        case "pending": return dueAt.map { $0 < now } == true ? .overdue : .pending
        case "submitted": return .submitted
        case "completed": return .completed
        default: return .unavailable
        }
    }

    /// The corner represents the source, not the device-only completion flag.
    func cardStage(at now: Date) -> TaskCardStage? {
        switch (submission(at: now, locallyCompleted: false), grading) {
        case (_, .graded): .graded
        case (.pending, _): .unsubmitted
        case (.overdue, _): .overdue
        case (.submitted, .pending), (.submitted, .inProgress),
             (.submitted, .gradedUnpublished), (.completed, .gradedUnpublished): .awaitingGrading
        default: nil
        }
    }

    static func workTypeTitle(_ key: String) -> String {
        switch key {
        case "practice": "练习"
        case "reading": "阅读记录"
        case "reflection": "学习回顾"
        case "checkpoint": "小测"
        case "lab_report": "实验报告"
        default: key
        }
    }

    static func modeTitle(_ key: String) -> String {
        switch key {
        case "online": "线上"
        case "offline": "线下"
        default: key
        }
    }
}

extension TaskRecord {
    init(campus row: CampusWork, roster: [String: CampusCourse]) {
        let course = row.course_id.flatMap { roster[$0] }
        let detail = row.task
        let grading = detail?.grading_status.flatMap(TaskGradingState.init(rawValue:)) ?? .unavailable
        let estimate = detail?.released_score_estimate.flatMap { score -> GradeMark? in
            score.percentage == nil ? nil : GradeMark(score: score)
        }
        self.init(
            id: row.id, title: row.title, term: row.term.flatMap(Self.nonblank),
            courseID: row.course_id.flatMap(Self.nonblank), courseName: course.flatMap { Self.nonblank($0.name) },
            teacher: course?.teacher.flatMap(Self.nonblank), workType: row.work_type.flatMap(Self.nonblank),
            mode: detail?.mode.flatMap(Self.nonblank), publishedAt: row.published_at.flatMap(campusInstant),
            opensAt: detail?.opens_at.flatMap(campusInstant), dueAt: campusInstant(row.due_at),
            sourceStatus: row.status, grading: grading,
            sourceMark: grading == .graded ? GradeMark(score: detail?.score) : nil,
            instructions: Material(text: Self.nonblank(row.description), attachments: Self.files(detail?.attachments)),
            answer: detail?.submission.map { Material(text: $0.text.flatMap(Self.nonblank), attachments: Self.files($0.attachments)) },
            submittedAt: detail?.submission?.submitted_at.flatMap(campusInstant),
            feedback: detail?.feedback.map { Material(text: $0.text.flatMap(Self.nonblank), attachments: Self.files($0.attachments)) },
            releasedEstimate: grading == .gradedUnpublished ? estimate : nil
        )
    }

    private static func nonblank(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func files(_ files: [TaskAttachment]?) -> [TaskAttachment] {
        (files ?? []).filter { nonblank($0.name) != nil }
    }
}
