import Foundation

enum PlanEditTarget: Hashable, Sendable {
    case create
    case plan(UUID)
    case bubble(UUID)
}

struct PlanEdit: Sendable {
    let target: PlanEditTarget
    let plan: PersonalPlan
    let reusable: Bool
    let recurrence: PlanRecurrence?
    let effectiveDay: String
}

enum PlanRecurrence: Equatable, Sendable {
    case weekday(Int), rotationDay(Int)

    static let rotationDays = 1...6
    var isValid: Bool {
        switch self {
        case .weekday(let day): (1...7).contains(day)
        case .rotationDay(let day): Self.rotationDays.contains(day)
        }
    }

    func matches(_ date: Date, calendar: PublishedSchoolCalendar?) -> Bool {
        switch self {
        case .weekday(let day): SchoolClock.calendar.component(.weekday, from: date) == day
        case .rotationDay(let day): calendar?.day(on: date).teachingDay == day
        }
    }
}

/// A reusable recipe and a scheduled occurrence can look similar on screen,
/// even sharing an identifier. Their source must travel with the gesture.
struct PlanPlacementItem: Equatable, Sendable {
    enum Source: Equatable, Sendable { case plan, reusableBubble, recurringBubble, occurrence }

    let plan: PersonalPlan
    let source: Source

    var isRecurring: Bool { source == .recurringBubble || source == .occurrence }
}

/// A retained recipe, not a dated plan. The archive stores revisions and explicit
/// completions, not a copy of a student's plan for every date on the calendar.
struct PlanBubble: Codable, Equatable, Identifiable, Sendable {
    struct Rule: Equatable, Sendable {
        let recurrence: PlanRecurrence
        let plan: PersonalPlan
    }

    struct Revision: Codable, Equatable, Sendable {
        let effectiveDay: String
        // Keep the original weekday payload byte-schema compatible. Rotation is an
        // additive alternative; old archives need no rewrite merely to be opened.
        private struct Week: Codable, Equatable, Sendable { let weekday: Int; let plan: PersonalPlan }
        private struct Rotation: Codable, Equatable, Sendable { let day: Int; let plan: PersonalPlan }
        private let week: Week?
        private let rotation: Rotation?

        init(effectiveDay: String, rule: Rule?) {
            self.effectiveDay = effectiveDay
            if let rule, case .weekday(let weekday) = rule.recurrence {
                week = Week(weekday: weekday, plan: rule.plan)
            } else { week = nil }
            if let rule, case .rotationDay(let day) = rule.recurrence {
                rotation = Rotation(day: day, plan: rule.plan)
            } else { rotation = nil }
        }

        var rule: Rule? {
            if let week { return Rule(recurrence: .weekday(week.weekday), plan: week.plan) }
            return rotation.map { Rule(recurrence: .rotationDay($0.day), plan: $0.plan) }
        }

        func isValid(for id: UUID) -> Bool {
            guard SchoolClock.dayDate(effectiveDay) != nil, week == nil || rotation == nil else { return false }
            guard let rule else { return true } // A stopped series retains its earlier occurrences.
            return rule.recurrence.isValid && rule.plan.isValid && rule.plan.id == id && rule.plan.time != nil
        }
    }

    var prototype: PersonalPlan
    var reusable: Bool
    private(set) var revisions: [Revision] = []
    private(set) var completedDays: Set<String> = []
    // Absence means no exclusions in archives saved by earlier versions.
    private var removedDays: Set<String>?

    init(prototype: PersonalPlan, reusable: Bool) {
        self.prototype = prototype
        self.reusable = reusable
    }

    var silentDays: Set<String> { completedDays.union(removedDays ?? []) }

    var id: UUID { prototype.id }
    var latest: Revision? { revisions.last }
    var visibleOnShelf: Bool { reusable || latest?.rule != nil }

    var isValid: Bool {
        prototype.isValid && !prototype.isCompleted &&
            revisions.allSatisfy { $0.isValid(for: id) } &&
            zip(revisions, revisions.dropFirst()).allSatisfy { $0.effectiveDay < $1.effectiveDay } &&
            silentDays.allSatisfy { SchoolClock.dayDate($0) != nil }
    }

    mutating func revise(recurrence: PlanRecurrence?, effectiveDay: String) {
        let rule = recurrence.map { Rule(recurrence: $0, plan: prototype) }
        guard revisions.last?.rule != rule || revisions.last.map({ $0.effectiveDay > effectiveDay }) == true else { return }
        // Edits replace rules from this day forward; earlier revisions stay readable.
        revisions.removeAll { $0.effectiveDay >= effectiveDay }
        revisions.append(Revision(effectiveDay: effectiveDay, rule: rule))
    }

    func occurrence(on day: String, calendar: PublishedSchoolCalendar? = nil) -> PersonalPlan? {
        guard removedDays?.contains(day) != true, let date = SchoolClock.dayDate(day),
              let rule = revisions.last(where: { $0.effectiveDay <= day })?.rule,
              rule.recurrence.matches(date, calendar: calendar) else { return nil }
        let plan = rule.plan
        return PersonalPlan(id: id, day: day, title: plan.title, time: plan.time,
                            isCompleted: completedDays.contains(day), color: plan.color, icon: plan.icon,
                            reminder: plan.reminder, courseKind: plan.courseKind)
    }

    func copy(on day: String, at time: PlanTime) -> PersonalPlan? {
        PersonalPlan(day: day, title: prototype.title, time: time,
                     color: prototype.color, icon: prototype.icon, reminder: prototype.reminder, courseKind: prototype.courseKind)
    }

    /// A shelf bubble has no occurrence of its own. Bind destructive choices to the
    /// first actual date on or after the selected day, and display that date before removal.
    func nextOccurrence(from first: String, calendar: PublishedSchoolCalendar?) -> PersonalPlan? {
        for (index, revision) in revisions.enumerated() {
            let start = max(first, revision.effectiveDay)
            let end = revisions.dropFirst(index + 1).first?.effectiveDay
            guard let rule = revision.rule, end.map({ start < $0 }) ?? true else { continue }
            switch rule.recurrence {
            case .rotationDay(let day):
                for row in calendar?.days ?? [] where row.date >= start && row.teachingDay == day {
                    if let end, row.date >= end { break }
                    if let item = occurrence(on: row.date, calendar: calendar) { return item }
                }
            case .weekday(let weekday):
                let clock = SchoolClock.calendar
                guard let initial = SchoolClock.dayDate(start) else { return nil }
                let offset = (weekday - clock.component(.weekday, from: initial) + 7) % 7
                var next = clock.date(byAdding: .day, value: offset, to: initial)
                while let date = next {
                    let key = SchoolClock.key(date)
                    if let end, key >= end { break }
                    if let item = occurrence(on: key, calendar: calendar) { return item }
                    next = clock.date(byAdding: .day, value: 7, to: date)
                }
            }
        }
        return nil
    }

    mutating func reschedule(to destination: Date, at time: PlanTime, now: Date,
                             calendar publication: PublishedSchoolCalendar? = nil) -> Bool {
        guard let rule = latest?.rule,
              let prototype = prototype.placing(at: time, on: SchoolClock.key(destination)) else {
            return false
        }
        let calendar = SchoolClock.calendar
        let today = calendar.startOfDay(for: now)
        let recurrence: PlanRecurrence, periodStart: Date
        switch rule.recurrence {
        case .weekday:
            recurrence = .weekday(calendar.component(.weekday, from: destination))
            periodStart = TimetableWeek(containing: destination).start
        case .rotationDay:
            guard let publication, let day = publication.day(on: destination).teachingDay,
                  PlanRecurrence.rotationDays.contains(day) else { return false }
            recurrence = .rotationDay(day)
            // Replace this rotation's future slot, not a Gregorian week's slot. Only
            // walk the published portion of the cycle; never bridge an unknown date.
            var cursor = calendar.startOfDay(for: destination), first = cursor, number = day
            while number > 1, let previous = calendar.date(byAdding: .day, value: -1, to: cursor) {
                let row = publication.day(on: previous)
                cursor = previous
                if row.status == .weekend || row.status == .noClass { continue }
                guard let earlier = row.teachingDay, earlier < number else { break }
                first = previous; number = earlier
            }
            periodStart = first
        }
        var boundary = max(today, periodStart)
        // A weekday change replaces that week's future slot, even when the drop
        // is later in the week. Do not erase an occurrence already held today.
        if boundary == today {
            let existingStarted = occurrence(on: SchoolClock.key(today), calendar: publication)?.time.map { $0.start(on: today) <= now } ?? false
            let droppedIntoPastToday = calendar.isDate(destination, inSameDayAs: today) && time.start(on: today) <= now
            if existingStarted || droppedIntoPastToday {
                boundary = calendar.date(byAdding: .day, value: 1, to: today) ?? today
            }
        }
        self.prototype = prototype
        revise(recurrence: recurrence, effectiveDay: SchoolClock.key(boundary))
        return true
    }

    mutating func setCompleted(_ completed: Bool, on day: String) {
        if completed { completedDays.insert(day) } else { completedDays.remove(day) }
    }

    mutating func excludeOccurrence(on day: String) {
        if removedDays == nil { removedDays = [] }
        removedDays?.insert(day)
    }
}
