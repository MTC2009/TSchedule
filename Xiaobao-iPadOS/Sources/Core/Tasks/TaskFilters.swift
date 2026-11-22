import Foundation

struct TaskDeadlineRange: Equatable, Sendable {
    let start, end: Date

    init?(start: Date, end: Date) {
        let first = SchoolClock.calendar.startOfDay(for: start)
        let last = SchoolClock.calendar.startOfDay(for: end)
        guard first <= last else { return nil }
        self.start = first
        self.end = last
    }

    func contains(_ date: Date?) -> Bool {
        guard let date else { return false }
        return (start...end).contains(SchoolClock.calendar.startOfDay(for: date))
    }
}

enum TaskFacetValue: Hashable, Sendable {
    case known(String), unavailable
}

struct TaskFacetOption: Identifiable {
    let value: TaskFacetValue
    let title: String
    var id: TaskFacetValue { value }
}

struct TaskFilters: Equatable {
    var course, workType, mode: TaskFacetValue?
    var submission: TaskSubmissionState?
    var grading: TaskGradingState?
    var deadlines: TaskDeadlineRange?
    var query = ""

    func results(in tasks: [TaskRecord], at now: Date, completed: Set<String>,
                 preservingUndatedSourceOrder: Bool = false) -> [TaskRecord] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return tasks.filter { task in
            (course == nil || course == Self.courseFacet(task)) &&
                (workType == nil || workType == Self.facet(task.workType)) &&
                (mode == nil || mode == Self.facet(task.mode)) &&
                (submission == nil || submission == task.submission(at: now, locallyCompleted: completed.contains(task.id))) &&
                (grading == nil || grading == task.grading) &&
                (deadlines == nil || deadlines?.contains(task.dueAt) == true) &&
                (query.isEmpty || task.title.localizedCaseInsensitiveContains(query))
        }.sorted { a, b in
            switch (a.publishedAt, b.publishedAt) {
            case (let first?, let second?) where first != second: return first > second
            case (_?, nil): return true
            case (nil, _?): return false
            // The school list may omit publication timestamps. Swift's stable
            // sort then keeps its paged order, without treating an ID as a date.
            case (nil, nil) where preservingUndatedSourceOrder: return false
            default: return a.id < b.id
            }
        }
    }

    static func courses(in tasks: [TaskRecord]) -> [TaskFacetOption] {
        options(tasks.map { (courseFacet($0), $0.courseName ?? String(localized: "课程未提供")) })
    }

    static func workTypes(in tasks: [TaskRecord]) -> [TaskFacetOption] {
        options(tasks.map { (facet($0.workType), $0.workTypeLabel ?? String(localized: "类型未提供")) })
    }

    static func modes(in tasks: [TaskRecord]) -> [TaskFacetOption] {
        options(tasks.map { (facet($0.mode), $0.mode.map(TaskRecord.modeTitle) ?? String(localized: "模式未提供")) })
    }

    private static func courseFacet(_ task: TaskRecord) -> TaskFacetValue {
        guard task.courseName != nil, let id = task.courseID else { return .unavailable }
        return .known(id)
    }

    private static func facet(_ value: String?) -> TaskFacetValue {
        value.map(TaskFacetValue.known) ?? .unavailable
    }

    private static func options(_ rows: [(TaskFacetValue, String)]) -> [TaskFacetOption] {
        // Use an ordered list so two different IDs with the same course title stay addressable.
        var seen = Set<TaskFacetValue>()
        return rows.compactMap { (value, title) in
            seen.insert(value).inserted ? TaskFacetOption(value: value, title: title) : nil
        }.sorted { a, b in
            if a.value == .unavailable { return false }
            if b.value == .unavailable { return true }
            return a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
    }
}
