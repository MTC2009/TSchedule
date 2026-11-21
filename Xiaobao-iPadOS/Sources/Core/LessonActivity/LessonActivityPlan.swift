import Foundation

/// Project a single ongoing lesson from an already resolved school day.
/// The clock here is the real clock, never the time selected on the timeline lens.
struct LessonActivityPlan: Equatable, Sendable {
    struct Next: Equatable, Sendable {
        let id, title: String
        let startsAt: Date
    }

    let lessonID: String
    let startsAt, endsAt: Date
    let next: Next?

    init?(timeline: LessonTimeline, at instant: Date) {
        let periods = timeline.blocks.compactMap(\.lesson)
        let active = periods.filter { $0.start <= instant && instant < $0.end }
        guard active.count == 1, let current = active.first else { return nil }
        lessonID = current.id
        startsAt = current.start
        endsAt = current.end
        let later = periods.filter { instant < $0.start }
        if let first = later.first, current.end <= first.start,
           later.dropFirst().first?.start != first.start,
           !first.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            next = .init(id: first.id, title: first.name, startsAt: first.start)
        } else {
            next = nil
        }
    }

    /// The widget link carries no content. Recheck the original period in the
    /// current owner's loaded day before moving the existing timetable lens.
    func focusMinute(in timeline: LessonTimeline, at instant: Date) -> Int? {
        guard let next, let lesson = timeline.blocks.compactMap(\.lesson).first(where: {
            $0.id == next.id && $0.start == next.startsAt && $0.name == next.title && instant < $0.end
        }) else { return nil }
        let minute = Int(ceil(timeline.minute(of: lesson.start)))
        let focus = SchoolClock.at(minute: minute, on: timeline.dayStart)
        guard (0..<1440).contains(minute), lesson.start <= focus, focus < lesson.end,
              timeline.focus(at: focus)?.lesson?.id == lesson.id else { return nil }
        return minute
    }
}
