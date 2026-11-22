import Foundation

struct OtherItem: Identifiable, Sendable {
    struct Course: Identifiable, Sendable {
        let id: String
        let name: String?
    }

    struct Work: Sendable {
        let description, sourceStatus: String
        let startsAt, endsAt, dueAt: Date?
        let room: String?
        let isLocal: Bool
    }

    struct Resource: Sendable {
        let body: String
        let kind, scope: String?
        let date: Date?
        let permitsLocalBookmark: Bool
    }

    enum Detail: Sendable {
        case exam(Work)
        case evaluation(Work)
        case resource(Resource)
    }

    struct Status: Equatable, Sendable {
        let title: String
        let finished: Bool?
    }

    let id, title: String
    let courses: [Course]
    private let sourceCourseLabel: String?
    let detail: Detail

    var courseTitle: String {
        if let sourceCourseLabel { return sourceCourseLabel }
        let names = courses.compactMap(\.name)
        if !names.isEmpty { return names.joined(separator: " / ") }
        return courses.isEmpty ? String(localized: "未分科") : String(localized: "课程名称待载入")
    }

    private var work: Work? {
        switch detail {
        case .exam(let item), .evaluation(let item): item
        case .resource: nil
        }
    }

    init?(local item: SchoolWork) {
        guard item.kind != .task else { return nil }
        id = item.id
        title = item.title
        courses = Self.localCourses(item.course)
        sourceCourseLabel = item.course.isEmpty ? nil : item.course
        let isExam = item.kind == .exam
        let work = Work(description: item.detail, sourceStatus: item.status.rawValue,
                        startsAt: isExam ? item.date : nil, endsAt: isExam ? item.end : nil,
                        dueAt: isExam ? nil : item.date, room: item.location, isLocal: true)
        detail = isExam ? .exam(work) : .evaluation(work)
    }

    init(local item: StudyResource) {
        id = item.id
        title = item.title
        courses = Self.localCourses(item.course)
        sourceCourseLabel = item.course.isEmpty ? nil : item.course
        detail = .resource(.init(body: item.content, kind: item.kind, scope: nil,
                                 date: item.date, permitsLocalBookmark: true))
    }

    init(campus item: CampusWork, kind: SchoolWorkKind, courseNames: [String: String]) {
        id = item.id
        title = item.title
        let exam = kind == .exam ? item.exam : nil
        var seen = Set<String>()
        let ids = [item.course_id].compactMap { $0 } + (exam?.results ?? []).map(\.course_id)
        courses = ids.compactMap { id in
            guard !id.isEmpty, seen.insert(id).inserted else { return nil }
            return Course(id: id, name: courseNames[id])
        }
        sourceCourseLabel = nil
        let work = Work(description: item.description, sourceStatus: item.status,
                        startsAt: exam?.start.flatMap(campusInstant), endsAt: exam?.end.flatMap(campusInstant),
                        dueAt: campusInstant(item.due_at), room: nil, isLocal: false)
        detail = kind == .exam ? .exam(work) : .evaluation(work)
    }

    init(campus item: CampusResource) {
        id = item.id
        title = item.title
        // The connected resource contract has no course association. Titles and sharers are not course IDs.
        courses = []
        sourceCourseLabel = nil
        detail = .resource(.init(body: item.content, kind: item.kind, scope: item.scope,
                                 date: item.shared_at.flatMap(campusInstant), permitsLocalBookmark: false))
    }

    private static func localCourses(_ name: String) -> [Course] {
        // General labels such as 综合测评 are useful display text but not roster subjects.
        guard let course = DemoSchoolProvider.courses.first(where: { $0.name == name }) else { return [] }
        return [Course(id: course.id, name: course.name)]
    }

    func status(at now: Date) -> Status? {
        guard let work else { return nil }
        if case .exam = detail {
            if work.isLocal {
                let ended = work.sourceStatus != "pending" || (work.endsAt ?? work.startsAt).map { $0 < now } == true
                return Status(title: ended ? String(localized: "已结束") : String(localized: "待考试"), finished: ended)
            }
            if work.sourceStatus == "pending", let end = work.endsAt, end < now {
                return Status(title: String(localized: "已结束"), finished: true)
            }
        }
        switch work.sourceStatus {
        case "pending":
            let title = work.isLocal ? (work.dueAt.map { $0 < now } == true ? String(localized: "已逾期") : String(localized: "待完成")) : String(localized: "待处理")
            return Status(title: title, finished: false)
        case "submitted": return Status(title: String(localized: "已提交"), finished: true)
        case "completed": return Status(title: String(localized: "已完成"), finished: true)
        case "graded": return Status(title: String(localized: "已评分"), finished: true)
        case "missing": return Status(title: String(localized: "未交"), finished: false)
        case "excused": return Status(title: String(localized: "免交"), finished: nil)
        default: return Status(title: work.sourceStatus, finished: nil)
        }
    }

    func isBookmarked(in ids: Set<String>) -> Bool {
        guard case .resource(let resource) = detail, resource.permitsLocalBookmark else { return false }
        return ids.contains(id)
    }

    func matchesSearch(_ query: String) -> Bool {
        query.isEmpty || title.localizedCaseInsensitiveContains(query) ||
            sourceCourseLabel?.localizedCaseInsensitiveContains(query) == true ||
            courses.contains { $0.name?.localizedCaseInsensitiveContains(query) == true }
    }
}

struct OtherItemsFilters: Equatable {
    enum Course: Hashable { case all, course(String), unassigned }
    enum Status: CaseIterable, Hashable { case all, open, finished }

    var course: Course = .all
    var status: Status = .all
    var query = ""
    var bookmarksOnly = false

    func results(in records: [OtherItem], at now: Date, bookmarks: Set<String>) -> [OtherItem] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return records.filter { item in
            switch course {
            case .all: break
            case .course(let id): guard item.courses.contains(where: { $0.id == id }) else { return false }
            case .unassigned: guard item.courses.isEmpty else { return false }
            }
            if status != .all, item.status(at: now)?.finished != (status == .finished) { return false }
            return item.matchesSearch(search) && (!bookmarksOnly || item.isBookmarked(in: bookmarks))
        }
    }
}

enum OtherItemsCatalog {
    static func courses(in records: [OtherItem]) -> [OtherItem.Course] {
        var known: [String: OtherItem.Course] = [:]
        for course in records.flatMap(\.courses) where course.name != nil {
            known[course.id] = course
        }
        return known.values.sorted { a, b in
            let order = (a.name ?? "").localizedStandardCompare(b.name ?? "")
            return order == .orderedSame ? a.id < b.id : order == .orderedAscending
        }
    }

    static func localWork(_ work: [SchoolWork], kind: SchoolWorkKind, at now: Date) -> [OtherItem] {
        work.filter { $0.kind == kind }.compactMap { source in
            OtherItem(local: source).map { (item: $0, date: source.date, finished: $0.status(at: now)?.finished == true) }
        }.sorted { a, b in
            if a.finished != b.finished { return !a.finished }
            if a.date == b.date { return a.item.id < b.item.id }
            return a.finished ? a.date > b.date : a.date < b.date
        }.map(\.item)
    }
}
