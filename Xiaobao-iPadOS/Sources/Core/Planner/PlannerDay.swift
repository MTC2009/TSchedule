import Foundation

struct PlannerDay {
    enum TimedRow: Identifiable {
        enum ID: Hashable { case school(PlannerSchoolEntry.ID), personal(UUID) }
        case school(PlannerSchoolEntry)
        case personal(PersonalPlan, start: Date, end: Date?)

        var id: ID {
            switch self {
            case .school(let entry): .school(entry.id)
            case .personal(let plan, _, _): .personal(plan.id)
            }
        }
        var start: Date {
            switch self {
            case .school(let entry): entry.start
            case .personal(_, let start, _): start
            }
        }
        var end: Date? {
            switch self {
            case .school(let entry): entry.end
            case .personal(_, _, let end): end
            }
        }
        var canBeFocus: Bool {
            switch self {
            case .school(let entry): entry.kind != .freeblock
            case .personal(let plan, _, _): !plan.isCompleted
            }
        }
    }

    enum Focus: Equatable {
        case next(TimedRow.ID), ongoing(TimedRow.ID)
        var id: TimedRow.ID {
            switch self { case .next(let id), .ongoing(let id): id }
        }
    }

    let date: Date
    let allDay: [PlannerSchoolEntry]
    let timed: [TimedRow]
    let unscheduled: [PersonalPlan]

    init(on date: Date, school: PlannerSchoolDay, plans: [PersonalPlan]) {
        self.date = SchoolClock.calendar.startOfDay(for: date)
        let key = SchoolClock.key(date)
        let mine = plans.filter { $0.day == key }
        // Keep due-only records in their original pages. Exclude them before
        // ordering the timetable so an invisible entry cannot become its focus.
        let visibleSchoolEntries = school.entries.filter { !$0.kind.isDeadline }
        allDay = visibleSchoolEntries.filter(\.allDay)
        unscheduled = mine.filter { $0.time == nil }
        let rows = visibleSchoolEntries.filter { !$0.allDay }.map(TimedRow.school) + mine.compactMap { plan in
            plan.time.map { .personal(plan, start: $0.start(on: date), end: $0.end(on: date)) }
        }
        // Equal-time records stay independent and preserve their source order.
        timed = rows.enumerated().sorted {
            $0.element.start == $1.element.start ? $0.offset < $1.offset : $0.element.start < $1.element.start
        }.map(\.element)
    }

    func focus(at now: Date) -> Focus? {
        guard SchoolClock.calendar.isDate(now, inSameDayAs: date) else { return nil }
        if let next = timed.first(where: { $0.canBeFocus && $0.start >= now }) { return .next(next.id) }
        if let current = timed.first(where: { $0.canBeFocus && $0.start <= now && ($0.end.map { now < $0 } ?? false) }) {
            return .ongoing(current.id)
        }
        return nil
    }

    /// Advisory only. A deadline and an all-day notice do not occupy the timetable;
    /// an event with an exact start but no end can still collide with a plan.
    func conflicts(with time: PlanTime) -> [PlannerSchoolEntry] {
        let start = time.start(on: date)
        let end = time.end(on: date)
        return timed.compactMap { row in
            guard case .school(let entry) = row, entry.kind.occupiesTime else { return nil }
            let overlaps: Bool
            switch (end, entry.end) {
            case (let a?, let b?): overlaps = start < b && entry.start < a
            case (let a?, nil): overlaps = start <= entry.start && entry.start < a
            case (nil, let b?): overlaps = entry.start <= start && start < b
            case (nil, nil): overlaps = start == entry.start
            }
            return overlaps ? entry : nil
        }
    }
}
