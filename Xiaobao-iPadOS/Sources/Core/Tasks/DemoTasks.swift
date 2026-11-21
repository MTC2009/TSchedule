import Foundation

/// Adds detail to the existing offline exercises without changing the Planner's school entries.
enum DemoTasks {
    static let currentTerm = "2026-autumn"
    static let previousTerm = "2026-spring"
    static let directory = TaskTermDirectory(current: currentTerm, available: [previousTerm])!

    static let records: [TaskRecord] = {
        let courses = Dictionary(uniqueKeysWithValues: DemoSchoolProvider.courses.map { ($0.name, $0) })
        let active = StudentServices.work.filter { $0.kind == .task }.map { task in
            let course = courses[task.course]
            let details = information[task.id]
            return TaskRecord(
                id: task.id, title: task.title, term: currentTerm, courseID: course?.id, courseName: task.course,
                teacher: course?.teacher, workType: details?.kind, mode: details?.mode,
                publishedAt: details?.published, opensAt: nil, dueAt: task.date, sourceStatus: task.status.rawValue,
                grading: details?.grade ?? .unavailable, sourceMark: details?.mark,
                instructions: .init(text: task.detail, attachments: details?.attachments ?? []),
                answer: details?.answer, submittedAt: details?.submitted, feedback: details?.feedback, isLocalDemo: true
            )
        }
        let archive = TaskRecord(
            id: "demo-archive-market-notes", title: "集市摊位观察", term: previousTerm, courseID: "economics",
            courseName: courses.values.first(where: { $0.id == "economics" })?.name,
            teacher: courses.values.first(where: { $0.id == "economics" })?.teacher,
            workType: "reflection", mode: "offline",
            publishedAt: SchoolClock.date(2026, 4, 7, minute: 610), opensAt: SchoolClock.date(2026, 4, 8, minute: 480),
            dueAt: SchoolClock.date(2026, 4, 19, minute: 1080), sourceStatus: "completed", grading: .graded,
            sourceMark: .letter("B+"),
            instructions: .init(text: "观察一个摊位在开市和收市时的标价，写下价格变化和一种可能的解释。", attachments: []),
            answer: nil, submittedAt: nil,
            feedback: .init(text: "描述简练。可以再比较同一时段其他摊位的标价。", attachments: []), isLocalDemo: true
        )
        return active + [archive]
    }()

    private struct Details {
        let kind, mode: String
        let published: Date
        var grade: TaskGradingState = .pending
        var mark: GradeMark? = nil
        var attachments: [TaskAttachment] = []
        var answer: TaskRecord.Material? = nil
        var submitted: Date? = nil
        var feedback: TaskRecord.Material? = nil
    }

    private static let information: [String: Details] = [
        "physics-lab": Details(kind: "lab_report", mode: "offline", published: SchoolClock.date(2026, 11, 10, minute: 530)),
        "calculus-practice": Details(kind: "practice", mode: "online", published: SchoolClock.date(2026, 11, 13, minute: 600)),
        "literature-reading": Details(
            kind: "reading", mode: "online", published: SchoolClock.date(2026, 11, 11, minute: 570),
            grade: .graded, mark: .numeric(earned: 22, possible: 25),
            attachments: [.init(name: "阅读批注说明.txt", size_bytes: nil)],
            answer: .init(text: "我标出了两处叙述视角的变化，并把前后的语气放在一起比较。", attachments: [
                .init(name: "阅读批注.txt", size_bytes: 1784)
            ]),
            submitted: SchoolClock.date(2026, 11, 16, minute: 935),
            feedback: .init(text: "能把观察和文本联系起来。再解释一下第二处描写为什么会改变读者的判断。", attachments: [])
        )
    ]
}
