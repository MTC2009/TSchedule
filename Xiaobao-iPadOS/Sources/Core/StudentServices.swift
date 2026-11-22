import Foundation

public enum SchoolWorkKind: String, CaseIterable, Identifiable, Sendable {
    case task, exam, evaluation
    public var id: String { rawValue }
    /// Official web navigation labels are stable identifiers, not app display copy.
    var portalSection: String { switch self { case .task: "我的任务"; case .exam: "我的考试"; case .evaluation: "我的测评" } }
    public var title: String { switch self { case .task: String(localized: "我的任务"); case .exam: String(localized: "我的考试"); case .evaluation: String(localized: "我的测评") } }
    public var symbol: String { switch self { case .task: "checklist"; case .exam: "pencil.and.list.clipboard"; case .evaluation: "text.badge.checkmark" } }
}

public enum SchoolWorkStatus: String, Sendable { case pending, submitted, completed }
public struct SchoolWork: Identifiable, Sendable {
    public let id: String
    public let kind: SchoolWorkKind
    public let title: String
    public let course: String
    public let date: Date
    public let end: Date?
    public let location: String?
    public let status: SchoolWorkStatus
    public let detail: String
    // The demo explicitly assigns this exam to the entire lesson; overlapping
    // dates alone do not mean that a class was replaced.
    let inClassLessonID: String?
    public var dateLabel: String { kind == .exam ? String(localized: "考试时间") : String(localized: "截止时间") }

    init(id: String, kind: SchoolWorkKind, title: String, course: String, date: Date, end: Date?,
         location: String?, status: SchoolWorkStatus, detail: String, inClassLessonID: String? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.course = course
        self.date = date
        self.end = end
        self.location = location
        self.status = status
        self.detail = detail
        self.inClassLessonID = inClassLessonID
    }
}

public struct StudyResource: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let course: String
    public let kind: String
    public let date: Date
    public let content: String
}

public enum StudentServices {
    public static let work: [SchoolWork] = makeWork(using: .local)

    private static let otherWork: [SchoolWork] = [
        .init(id: "physics-lab", kind: .task, title: "动量与碰撞实验记录", course: "AP Physics 1", date: SchoolClock.date(2026, 11, 18, minute: 1200), end: nil, location: nil, status: .pending,
              detail: "整理实验数据，写出误差分析与结论。"),
        .init(id: "calculus-practice", kind: .task, title: "微积分：导数应用练习", course: "AP Calculus AB", date: SchoolClock.date(2026, 11, 17, minute: 1080), end: nil, location: nil, status: .pending,
              detail: "完成练习中的应用题，保留推导步骤。"),
        .init(id: "literature-reading", kind: .task, title: "阅读摘记", course: "English Literature", date: SchoolClock.date(2026, 11, 16, minute: 1080), end: nil, location: nil, status: .submitted,
              detail: "选取一段文字，说明修辞与人物塑造之间的联系。"),
        .init(id: "term-reflection", kind: .evaluation, title: "学期学习反思", course: "综合测评", date: SchoolClock.date(2026, 11, 22, minute: 1200), end: nil, location: nil, status: .pending,
              detail: "回顾本学期的学习目标、课堂参与与时间安排。\n\n请在校宝填写并提交问卷。"),
        .init(id: "course-feedback", kind: .evaluation, title: "课程体验反馈", course: "综合测评", date: SchoolClock.date(2026, 11, 12, minute: 1200), end: nil, location: nil, status: .completed,
              detail: "回顾课程内容、作业量与课堂参与。")
    ]

    static func makeWork(using provider: DemoSchoolProvider) -> [SchoolWork] {
        func exam(id: String, title: String, courseID: String, on day: Date, status: SchoolWorkStatus = .pending,
                  detail: String) -> SchoolWork? {
            // A closure or an unassigned course cannot produce a synthetic exam slot.
            guard let lesson = provider.lessons(on: day).first(where: { $0.course.id == courseID }) else { return nil }
            return SchoolWork(id: id, kind: .exam, title: title, course: lesson.course.name,
                              date: lesson.start, end: lesson.end, location: lesson.course.room,
                              status: status, detail: detail, inClassLessonID: lesson.id)
        }
        let exams = [
            exam(id: "physics-exam", title: "力学单元测验", courseID: "physics", on: SchoolClock.date(2026, 11, 19),
                 detail: "范围：动量、冲量、碰撞与机械能。携带文具及允许使用的计算器。"),
            exam(id: "economics-exam", title: "市场与弹性", courseID: "economics", on: SchoolClock.date(2026, 11, 20),
                 detail: "题型：选择题与简答题。"),
            exam(id: "chinese-exam", title: "期中阅读考核", courseID: "chinese", on: SchoolClock.date(2026, 11, 13), status: .completed,
                 detail: "阅读材料后，完成文本分析与简答题。")
        ]
        return otherWork + exams.compactMap { $0 }
    }

    public static let resources: [StudyResource] = [
        .init(id: "momentum-notes", title: "动量与碰撞 · 复习提纲", course: "AP Physics 1", kind: "讲义", date: SchoolClock.date(2026, 11, 16),
              content: "1. 动量\n动量是矢量，p = mv。\n\n2. 冲量\n恒力作用时，冲量 J = FΔt = Δp。\n\n3. 碰撞\n判断系统受外力情况，再使用动量守恒；动能是否守恒取决于碰撞类型。"),
        .init(id: "calculus-notes", title: "导数应用 · 解题步骤", course: "AP Calculus AB", kind: "学习笔记", date: SchoolClock.date(2026, 11, 14),
              content: "明确变量与定义域，建立函数，计算导数。检查临界点与端点，再结合题意解释结果。"),
        .init(id: "reading-rubric", title: "阅读分析 · 检查清单", course: "English Literature", kind: "参考清单", date: SchoolClock.date(2026, 11, 12),
              content: "• 观点是否明确？\n• 是否引用文本证据？\n• 分析是否解释了证据如何支持观点？\n• 结尾是否回应问题？")
    ]

    public static func work(on date: Date) -> [SchoolWork] {
        work.filter { SchoolClock.calendar.isDate($0.date, inSameDayAs: date) }.sorted { $0.date < $1.date }
    }
}
