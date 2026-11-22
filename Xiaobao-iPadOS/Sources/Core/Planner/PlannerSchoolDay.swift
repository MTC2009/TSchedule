import Foundation

struct PlannerSchoolEntry: Identifiable {
    enum ID: Hashable {
        case block(LessonTimeline.Block.ID)
        case routine(PlannerCampusPeriod, anchor: Date)
        case event(String)
        case work(kind: String?, id: String)
    }

    enum Kind: Equatable {
        case lesson, freeblock, assembly, lunch, optionalBlock, campusRoutine
        case calendar, activity
        case exam, taskDeadline, examDeadline, evaluationDeadline, deadline

        var isDeadline: Bool {
            switch self {
            case .taskDeadline, .examDeadline, .evaluationDeadline, .deadline: true
            case .lesson, .freeblock, .assembly, .lunch, .optionalBlock, .campusRoutine, .calendar, .activity, .exam: false
            }
        }

        var isReferenceOnly: Bool { self == .optionalBlock || self == .campusRoutine }
        var occupiesTime: Bool { self != .freeblock && !isReferenceOnly && !isDeadline }
    }

    let id: ID
    let kind: Kind
    let title: String
    let location: String?
    let start: Date
    let end: Date?
    let allDay: Bool
    var metadata: TimetableLessonMetadata? = nil

    var lessonID: String? {
        guard case .block(.lesson(let id)) = id else { return nil }
        return id
    }

    var isMeal: Bool {
        if kind == .lunch { return true }
        switch id {
        case .routine(.breakfast, _), .routine(.dinner, _): return true
        default: return false
        }
    }

    /// A previous night's sleep is drawn from midnight but must not pull the
    /// initial day/week viewport away from the first scheduled morning entry.
    var isOvernightContinuation: Bool {
        guard case .routine(.sleep, let night) = id else { return false }
        return !SchoolClock.calendar.isDate(night, inSameDayAs: start)
    }
}

/// Read-only projection. A calendar can be usable even when the daily schedule
/// or bell metadata is not yet present. Only the daily schedule can confirm an empty teaching slot.
struct PlannerSchoolDay {
    let rotationDay: Int?
    let hasTimetable: Bool
    let hasCalendar: Bool
    let entries: [PlannerSchoolEntry]
    private(set) var hasStandardBells = false

    static func local(on date: Date, provider: DemoSchoolProvider, work: [SchoolWork]) -> Self {
        let lessons = provider.lessons(on: date)
        let timeline = provider.timeline(on: date, lessons: lessons)
        var examSlots: Set<String> = []
        let workEntries = work.compactMap { item -> PlannerSchoolEntry? in
            guard SchoolClock.calendar.isDate(item.date, inSameDayAs: date) else { return nil }
            let kind: PlannerSchoolEntry.Kind = switch item.kind {
            case .task: .taskDeadline
            case .exam: .exam
            case .evaluation: .evaluationDeadline
            }
            // Merge only a verified, explicitly linked in-class demo exam. A
            // separate exam may legitimately overlap a lesson and stays visible.
            if kind == .exam, let lessonID = item.inClassLessonID, let lesson = lessons.first(where: { $0.id == lessonID }),
               item.date == lesson.start, item.end == lesson.end, item.course == lesson.course.name {
                examSlots.insert(lessonID)
            }
            return .init(id: .work(kind: item.kind.rawValue, id: item.id), kind: kind, title: item.title,
                         location: item.location, start: item.date, end: item.end, allDay: false)
        }
        let blocks = (timeline?.blocks ?? []).compactMap { block -> PlannerSchoolEntry? in
            if case .lesson(let period) = block, examSlots.contains(period.id) { return nil }
            return blockEntry(block)
        }
        return .init(rotationDay: provider.day(on: date), hasTimetable: timeline != nil, hasCalendar: true,
                     entries: blocks + workEntries, hasStandardBells: timeline != nil && provider.day(on: date) != nil)
    }

    static func connected(on date: Date, schedule: CampusSchedule?, calendar: CampusCalendar?,
                          courseName: (String) -> String) -> Self {
        let clock = SchoolClock.calendar
        let start = clock.startOfDay(for: date)
        let nextDay = clock.date(byAdding: .day, value: 1, to: start)!
        let timeline = schedule.flatMap { schedule in
            schedule.date == SchoolClock.key(date) ? schedule.timeline(courseName: courseName) : nil
        }
        // Use one lesson source, not both: the schedule and calendar cover the same enrollments.
        let timetableEntries = timeline?.blocks.map(blockEntry) ?? (calendar?.lessons.compactMap { lesson in
            guard let begins = campusInstant(lesson.start), let ends = campusInstant(lesson.end),
                  start <= begins, begins < ends, ends <= nextDay else { return nil }
            return PlannerSchoolEntry(id: .block(.lesson(lesson.id)), kind: .lesson,
                                      title: courseName(lesson.course_id), location: lesson.room,
                                      start: begins, end: ends, allDay: false, metadata: lesson.metadata)
        } ?? [])
        let eventEntries = calendar?.events.compactMap { event -> PlannerSchoolEntry? in
            guard let begins = campusInstant(event.start), begins < nextDay else { return nil }
            let ends = event.end.flatMap(campusInstant).flatMap { $0 > begins ? $0 : nil }
            guard ends.map({ $0 > start }) ?? (begins >= start) else { return nil }
            return .init(id: .event(event.id), kind: event.kind == "activity" ? .activity : .calendar,
                         title: event.title, location: nil, start: max(start, begins),
                         end: ends.map { min(nextDay, $0) }, allDay: event.all_day == true)
        } ?? []
        let deadlineEntries = calendar?.deadlines.compactMap { work -> PlannerSchoolEntry? in
            // The service sends due_at, not the start of an exam or evaluation.
            guard let due = campusInstant(work.due_at), start <= due, due < nextDay else { return nil }
            let kind: PlannerSchoolEntry.Kind = switch work.kind {
            case "task": .taskDeadline
            case "exam": .examDeadline
            case "evaluation": .evaluationDeadline
            default: .deadline
            }
            return .init(id: .work(kind: work.kind, id: work.id), kind: kind, title: work.title,
                         location: nil, start: due, end: nil, allDay: false)
        } ?? []
        return .init(rotationDay: timeline == nil ? nil : schedule?.day,
                     hasTimetable: timeline != nil && schedule?.hasConfirmedRoster == true, hasCalendar: calendar != nil,
                     entries: timetableEntries + eventEntries + deadlineEntries,
                     hasStandardBells: timeline != nil && schedule?.teaching_slots?.sorted { $0.start < $1.start } == CampusBells.teachingSlots)
    }

    static func blockEntry(_ block: LessonTimeline.Block) -> PlannerSchoolEntry {
        let kind: PlannerSchoolEntry.Kind = switch block {
        case .lesson: .lesson
        case .freeblock: .freeblock
        case .activity(.assembly, _): .assembly
        case .activity(.lunch, _): .lunch
        case .reference: .campusRoutine
        }
        return .init(id: .block(block.id), kind: kind, title: block.title, location: block.location,
                     start: block.start, end: block.end, allDay: false, metadata: block.metadata)
    }
}
