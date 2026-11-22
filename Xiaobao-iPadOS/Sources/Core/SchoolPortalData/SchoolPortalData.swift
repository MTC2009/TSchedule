import Foundation

/// A successful reply covers exactly one Sunday–Saturday range. An unknown week is
/// represented by no snapshot, never by a snapshot with an empty lesson array.
struct SchoolPortalWeek {
    struct Row: Decodable {
        enum Kind: String, Decodable { case lesson, vacant, activity, calendar }
        let id, name, start, course: String
        let kind: Kind
        let end, room: String?
        let allDay: Bool
        var metadata: TimetableLessonMetadata? = nil
    }
    let dates: Set<String>
    let names: [String: String]
    private let lessons: [String: [CampusLesson]]
    private let vacantSlots: [String: Set<TeachingSlot>]
    let calendar: CampusCalendar

    init(week: TimetableWeek, rows: [Row]) throws {
        dates = Set(week.dates.map(SchoolClock.key))
        let bounds = week.start..<SchoolClock.calendar.date(byAdding: .day, value: 1, to: week.end)!
        var byDay: [String: [CampusLesson]] = [:], slots: [String: Set<TeachingSlot>] = [:], events: [CampusEvent] = []
        var roster: [String: String] = [:], seen = Set<String>()
        for row in rows {
            guard !row.id.isEmpty, row.kind == .vacant || !row.name.isEmpty, let start = campusInstant(row.start),
                  row.end == nil || row.end.flatMap(campusInstant) != nil else { throw SchoolPortalIssue.format }
            let end = row.end.flatMap(campusInstant)
            guard seen.insert(row.id).inserted else { continue } // repeated calendar occurrence
            if row.kind == .vacant {
                guard !row.allDay, row.course.isEmpty, row.name.isEmpty, let end, start < end,
                      SchoolClock.key(start) == SchoolClock.key(end) else { throw SchoolPortalIssue.format }
                if bounds.contains(start) {
                    slots[SchoolClock.key(start), default: []].insert(.init(start: SchoolClock.minute(in: start), end: SchoolClock.minute(in: end)))
                }
            } else if row.kind == .lesson {
                guard let end, let rawEnd = row.end, start < end, !row.course.isEmpty else { throw SchoolPortalIssue.format }
                guard bounds.contains(start) else { continue }
                byDay[SchoolClock.key(start), default: []].append(.init(id: row.id, course_id: row.course,
                    start: row.start, end: rawEnd, room: row.room, metadata: row.metadata))
                roster[row.course] = row.name
            } else if start < bounds.upperBound, (end ?? start) >= bounds.lowerBound {
                events.append(.init(id: row.id, title: row.name, start: row.start, end: row.end,
                                    kind: row.kind.rawValue, all_day: row.allDay))
            }
        }
        names = roster; lessons = byDay; vacantSlots = slots
        calendar = .init(lessons: [], events: events, deadlines: [])
    }

    func schedule(on date: Date) -> CampusSchedule? {
        let key = SchoolClock.key(date)
        guard dates.contains(key) else { return nil }
        return .init(date: key, day: nil, lessons: lessons[key] ?? [],
                     teaching_slots: vacantSlots[key]?.sorted { $0.start < $1.start })
    }
}

struct SchoolPortalGrades: Codable {
    struct Course: Codable {
        let id, subject, name: String
        let cls, className: String?
        let type: Int
        let score: CampusScore?
        var evaluationName: String? = nil

        var forecastPercentage: Double? {
            guard type == 1, let score, score.type == "numeric" else { return nil }
            if let percentage = score.percentage { return percentage }
            // Numeric Schoolis subject scores without a denominator are percentages.
            guard score.possible == nil, let value = score.earned, (0...100).contains(value) else { return nil }
            return value
        }
    }
    struct Group: Codable {
        let id, title: String
        let nested: Bool
        let weight: Double?
        let mark: CampusScore?
        let items: [CampusAssessment]
    }
    var displayTerm: String { termLabel?.displayName ?? term }
    var termLabel: SchoolPortalTerms.Term? = nil
    let term, termID: String
    var gpa: Double?
    let gpaUnavailable: Bool?
    let courses: [Course]

    func retainingGPA(from previous: Self?) -> Self {
        guard gpaUnavailable == true, gpa == nil, let previous, previous.termID == termID else { return self }
        var merged = self
        merged.gpa = previous.gpa
        return merged
    }

    func courseDetail(_ course: Course, groups: [Group]?) -> CourseGradeDetail {
        let grade = CampusGrade(course_id: course.id, published_score: course.score, published_gpa: nil,
                                assessments: groups?.flatMap(\.items) ?? [], class_name: course.className)
        let directory = ForecastGroups((groups ?? []).map { group in
            // PortalProjection assigns a dotted position to each node while walking the school tree.
            // Display names can repeat or contain slashes; they are not identifiers or parent links.
            let parent = group.nested ? group.id.lastIndex(of: ".").map { String(group.id[..<$0]) } : nil
            let graded = group.items.filter { $0.status == "graded" }
            let samples = ForecastSamples(released: graded.map { GradeMark(score: $0.score) },
                                          excludesUnreleased: graded.count != group.items.count)
            let percent = group.mark.flatMap { mark -> Double? in
                guard course.type == 1, mark.type == "numeric" else { return nil }
                if let normalized = mark.percentage { return normalized }
                guard mark.possible == nil, let value = mark.earned, (0...100).contains(value) else { return nil }
                return value
            }
            return ForecastGroup(id: group.id, title: group.title, parentID: parent,
                weight: AssessmentWeight(group.weight, scope: group.nested ? .group : .course),
                published: GradeMark(score: group.mark), hasItems: !group.items.isEmpty, samples: samples, reportedPercentage: percent)
        }, supportsNumericForecast: course.type == 1)
        return CourseGradeDetail(term: termID, name: course.name, grade: grade, publishedRows: groups?.map { group in
            let weight = AssessmentWeight(group.weight, scope: group.nested ? .group : .course)
            let items = group.items.map { item in
                let released = item.status == "graded"
                return AssessmentResult(id: item.id, title: item.title, status: item.status,
                    mark: released ? GradeMark(score: item.score) : nil, weight: nil,
                    date: item.date.flatMap(campusInstant), feedback: nil, percentage: released ? item.score?.percentage : nil)
            }
            // A category without children isn't an expandable task, but its published weight still matters.
            if items.isEmpty {
                let mark = GradeMark(score: group.mark)
                return .assessment(.init(id: "category:" + group.id, title: group.title,
                    status: mark == nil ? "pending" : "graded", mark: mark, weight: weight,
                    date: nil, feedback: nil, percentage: nil))
            }
            return .group(title: group.title, weight: weight, mark: GradeMark(score: group.mark), items: items)
        }, forecastGroups: directory, numericBaseline: course.forecastPercentage)
    }
}

enum SchoolPortalCollection: String, CaseIterable { case exams, evaluations, resources }

struct SchoolPortalListItem: Decodable, Identifiable {
    let id, title: String
    let detail: String?
    var submitted: Bool? = nil
    var detailLabel: String? { submitted.map { $0 ? String(localized: "已完成") : String(localized: "未完成") } ?? detail }
}

struct SchoolPortalTerms: Decodable {
    struct Term: Codable, Equatable, Identifiable {
        let id, name: String
        var year: Int? = nil
        var semester: Int? = nil
        var displayName: String {
            guard let year, (1...9999).contains(year), let semester, (1...32).contains(semester) else { return name }
            return String(localized: "\(String(year))–\(String(year + 1)) 学年 · 第 \(semester) 学期")
        }
    }
    let current: String
    let terms: [Term]
}

struct SchoolPortalTasks: Decodable, Equatable {
    struct Row: Decodable, Equatable {
        let id, title, status: String
        let due, published, course, courseName, kind, grading: String?
        let score: CampusScore?
        var deadlineEligible: Bool? = nil
        var detailReadable: Bool? = nil, feedbackReleased: Bool? = nil
    }
    var displayTerm: String { termLabel?.displayName ?? term }
    var termLabel: SchoolPortalTerms.Term? = nil
    let term: String
    let rows: [Row]

    var records: [TaskRecord] {
        rows.map { row in
            let task = CampusTaskDetails(mode: nil, grading_status: row.grading, score: row.score, attachments: nil,
                                         opens_at: nil, submission: nil, feedback: nil)
            let work = CampusWork(id: row.id, title: row.title, due_at: row.due ?? "", status: row.status,
                description: "", course_id: row.course, kind: "task", term: term,
                work_type: row.kind, published_at: row.published, task: task)
            var roster: [String: CampusCourse] = [:]
            if let id = row.course, let name = row.courseName { roster[id] = .init(id: id, name: name, teacher: nil, room: nil) }
            var record = TaskRecord(campus: work, roster: roster)
            record.usesSchoolWorkType = true
            return record
        }
    }
}
