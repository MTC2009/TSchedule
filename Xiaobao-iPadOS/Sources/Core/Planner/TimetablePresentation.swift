import Foundation

/// One local display projection for Today and Planner. The unfiltered roster
/// and plan store remain the authorities for school data and notifications.
struct TimetablePresentation {
    let date: Date
    let school: PlannerSchoolDay
    let plans: [PersonalPlan]
    let placementSchool: PlannerSchoolDay

    init(on date: Date, school source: PlannerSchoolDay, plans records: [PersonalPlan], settings: LocalPersonalization,
         editingPersonalCourses: Bool = false) {
        self.date = date
        let dayPlans = records.filter { $0.day == SchoolClock.key(date) }
        let supplements = dayPlans.filter { $0.courseKind != nil && $0.time?.endMinute != nil }
        // Resolve occupancy first, even when the covering course itself will be hidden.
        // A local course does not erase a real school lesson, lunch or calendar event.
        let occupied = source.entries.filter { entry in
            let placeholder: Bool = switch entry.id {
            case .routine(.block9, _), .routine(.block10, _), .routine(.firstStudy, _),
                 .routine(.secondStudy, _), .routine(.sport, _): true
            default: entry.kind == .freeblock
            }
            guard placeholder, let end = entry.end else { return true }
            return !supplements.contains { plan in
                guard let time = plan.time, let finish = time.end(on: date) else { return false }
                return time.start(on: date) < end && entry.start < finish
            }
        }
        func schoolDay(_ entries: [PlannerSchoolEntry]) -> PlannerSchoolDay {
            .init(rotationDay: source.rotationDay, hasTimetable: source.hasTimetable, hasCalendar: source.hasCalendar,
                  entries: entries, hasStandardBells: source.hasStandardBells)
        }
        placementSchool = schoolDay(occupied)
        var entries = [PlannerSchoolEntry]()
        // Two concurrent TSSA groups may resolve to the same anonymous study interval.
        var studyIntervals = Set<DateInterval>()
        let actualStudy = occupied.filter { $0.kind == .lesson && Self.category(for: $0) == .study }
        for entry in actualStudy {
            if let end = entry.end { studyIntervals.insert(.init(start: entry.start, end: end)) }
        }
        for plan in supplements where plan.courseKind == .study {
            if let time = plan.time, let end = time.end(on: date) { studyIntervals.insert(.init(start: time.start(on: date), end: end)) }
        }
        func showStudy(start: Date, end: Date?, key: String) {
            guard settings.shows(.study), let end, studyIntervals.insert(.init(start: start, end: end)).inserted else { return }
            entries.append(.init(id: .block(.reference(key)), kind: .campusRoutine, title: TimetableCategory.study.title,
                                 location: PlannerCampusPeriod.firstStudy.location,
                                 start: start, end: end, allDay: false))
        }
        for entry in occupied {
            let category = Self.category(for: entry)
            guard let category, !settings.shows(category) else {
                if category == .study && (entry.location?.isEmpty ?? true) {
                    entries.append(.init(id: entry.id, kind: entry.kind, title: entry.title,
                        location: PlannerCampusPeriod.firstStudy.location, start: entry.start, end: entry.end, allDay: entry.allDay,
                        metadata: entry.metadata))
                } else { entries.append(entry) }
                continue
            }
            if category == .tssa, let id = entry.lessonID { showStudy(start: entry.start, end: entry.end, key: "study:" + id) }
        }
        let enrolled = occupied.filter { $0.kind == .lesson }
        plans = dayPlans.filter { plan in
            guard let kind = plan.courseKind, let time = plan.time else { return true }
            // The editor must remain able to manage a hidden or superseded local record.
            if editingPersonalCourses { return true }
            let start = time.start(on: date), end = time.end(on: date)
            if enrolled.contains(where: { entry in
                entry.start == start && entry.end == end && (entry.title.localizedCaseInsensitiveCompare(plan.title) == .orderedSame ||
                       (kind == .tssa && Self.category(for: entry) == .tssa))
            }) { return false }
            if kind == .tssa && !settings.shows(.tssa) {
                showStudy(start: start, end: end, key: "study:plan:" + plan.id.uuidString)
                return false
            }
            return settings.shows(kind.category)
        }
        school = schoolDay(entries)
    }

    /// Derive neither free blocks nor enrollments from the filtered list. In particular,
    /// a known bedtime or personal course may exist even when the school roster is unknown.
    func timeline(original: LessonTimeline?) -> LessonTimeline? {
        let periods = Dictionary((original?.blocks.compactMap(\.lesson) ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var blocks = school.entries.compactMap { entry -> LessonTimeline.Block? in
            guard let end = entry.end, end > entry.start else { return nil }
            let interval = DateInterval(start: entry.start, end: end)
            switch entry.id {
            case .block(.lesson(let id)):
                let source = periods[id]
                return .lesson(.init(id: id, name: source?.name ?? entry.title, shortName: source?.shortName ?? entry.title,
                                     room: entry.location, start: entry.start, end: end, metadata: entry.metadata ?? source?.metadata))
            case .block(.activity(let kind, _)): return .activity(kind, interval)
            case .block(.freeblock): return .freeblock(interval)
            case .block(.reference(let id)):
                return .reference(.init(id: id, name: entry.title, shortName: entry.title, room: entry.location, start: entry.start, end: end), isCourse: false)
            case .routine(let period, let anchor):
                let id = "routine:" + period.rawValue + ":" + SchoolClock.key(anchor)
                return .reference(.init(id: id, name: entry.title, shortName: entry.title, room: entry.location, start: entry.start, end: end), isCourse: false)
            case .event, .work: return nil
            }
        }
        for plan in plans {
            guard let kind = plan.courseKind, let time = plan.time, let end = time.end(on: date) else { continue }
            blocks.append(.reference(.init(id: "plan:" + plan.id.uuidString, name: plan.title, shortName: plan.title,
                                            room: kind == .study ? PlannerCampusPeriod.firstStudy.location : nil,
                                            start: time.start(on: date), end: end), isCourse: kind != .study))
        }
        guard original != nil || !blocks.isEmpty else { return nil }
        return .init(on: date, resolved: blocks, includesRecesses: school.hasStandardBells || original?.recesses.isEmpty == false)
    }

    static func category(for entry: PlannerSchoolEntry) -> TimetableCategory? {
        if case .routine(let period, _) = entry.id {
            switch period {
            case .sleep: return .sleep
            case .morningWash, .eveningWash: return .wash
            case .breakfast: return .breakfast
            case .dinner: return .dinner
            case .block9, .block10: return .optionalBlock
            case .firstStudy, .secondStudy: return .study
            case .sport: return .sport
            }
        }
        switch entry.kind {
        case .assembly: return .assembly
        case .lunch: return .lunch
        case .freeblock: return .freeblock
        case .lesson: return courseCategory(title: entry.title, start: entry.start)
        default: return nil  // An examination event is not an external-exam course.
        }
    }

    private static let program = try! NSRegularExpression(pattern:
        #"(?i)(?<![a-z0-9])(?:IGCSE|IG|AP|AL|A2|A[ -]?levels?|AS[ -]?levels?|advanced placement|international GCSE)(?![a-z0-9])"#)
    private static let eveningStudy = try! NSRegularExpression(pattern:
        #"(?i)晚[间間]?自[习習]|(?<![a-z])evening[ -]+(?:self[ -]+)?study(?![a-z])|(?<![a-z])study[ -]+hall(?![a-z])"#)

    static func courseCategory(title: String, start: Date) -> TimetableCategory {
        let minute = SchoolClock.minute(in: start)
        if SchoolStudyWeek.isEnrollment(title: title, start: minute) { return .tssa }
        let label = title.folding(options: [.widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let range = NSRange(label.startIndex..., in: label)
        if program.firstMatch(in: label, range: range) != nil { return .examCourse }
        if minute >= CampusBells.dismissal, eveningStudy.firstMatch(in: label, range: range) != nil { return .study }
        return .schoolCourse
    }

}
