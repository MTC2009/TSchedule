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
    let weekday: Int?
    let effectiveDay: String
}

/// A reusable recipe and a scheduled occurrence can look similar on screen,
/// even sharing an identifier. Their source must travel with the gesture.
struct PlanPlacementItem: Equatable, Sendable {
    enum Source: Equatable, Sendable { case plan, reusableBubble, weeklyBubble, weeklyOccurrence }

    let plan: PersonalPlan
    let source: Source

    var isWeekly: Bool { source == .weeklyBubble || source == .weeklyOccurrence }
}

/// A retained recipe, not a dated plan. Only the compact weekly revisions and
/// explicitly completed dates are stored, never a row for every eventual week.
struct PlanBubble: Codable, Equatable, Identifiable, Sendable {
    struct Week: Codable, Equatable, Sendable {
        let weekday: Int
        let plan: PersonalPlan

        var isValid: Bool { (1...7).contains(weekday) && plan.isValid && plan.time != nil }
    }

    struct Revision: Codable, Equatable, Sendable {
        let effectiveDay: String
        // A nil rule ends the series without rewriting previous weeks.
        let week: Week?
    }

    var prototype: PersonalPlan
    var reusable: Bool
    private(set) var revisions: [Revision] = []
    private(set) var completedDays: Set<String> = []

    var id: UUID { prototype.id }
    var latest: Revision? { revisions.last }
    var visibleOnShelf: Bool { reusable || latest?.week != nil }

    var isValid: Bool {
        prototype.isValid && !prototype.isCompleted &&
            revisions.allSatisfy {
                SchoolClock.dayDate($0.effectiveDay) != nil &&
                    ($0.week.map { $0.isValid && $0.plan.id == id } ?? true)
            } &&
            zip(revisions, revisions.dropFirst()).allSatisfy { $0.effectiveDay < $1.effectiveDay } &&
            completedDays.allSatisfy { SchoolClock.dayDate($0) != nil }
    }

    mutating func revise(weekday: Int?, effectiveDay: String) {
        let week = weekday.map { Week(weekday: $0, plan: prototype) }
        guard revisions.last?.week != week else { return }
        // Edits replace rules from this day forward; earlier revisions stay readable.
        revisions.removeAll { $0.effectiveDay >= effectiveDay }
        revisions.append(Revision(effectiveDay: effectiveDay, week: week))
    }

    func occurrence(on day: String) -> PersonalPlan? {
        guard let date = SchoolClock.dayDate(day), let week = revisions.last(where: { $0.effectiveDay <= day })?.week,
              SchoolClock.calendar.component(.weekday, from: date) == week.weekday else { return nil }
        let plan = week.plan
        return PersonalPlan(id: id, day: day, title: plan.title, time: plan.time,
                            isCompleted: completedDays.contains(day), color: plan.color, icon: plan.icon,
                            reminder: plan.reminder)
    }

    func copy(on day: String, at time: PlanTime) -> PersonalPlan? {
        PersonalPlan(day: day, title: prototype.title, time: time,
                     color: prototype.color, icon: prototype.icon, reminder: prototype.reminder)
    }

    mutating func reschedule(to destination: Date, at time: PlanTime, now: Date) -> Bool {
        guard latest?.week != nil,
              let prototype = prototype.placing(at: time, on: SchoolClock.key(destination)) else {
            return false
        }
        let calendar = SchoolClock.calendar
        let today = calendar.startOfDay(for: now)
        let targetWeek = TimetableWeek(containing: destination)
        var boundary = max(today, targetWeek.start)
        // A weekday change replaces that week's future slot, even when the drop
        // is later in the week. Do not erase an occurrence already held today.
        if boundary == today {
            let existingStarted = occurrence(on: SchoolClock.key(today))?.time.map { $0.start(on: today) <= now } ?? false
            let droppedIntoPastToday = calendar.isDate(destination, inSameDayAs: today) && time.start(on: today) <= now
            if existingStarted || droppedIntoPastToday {
                boundary = calendar.date(byAdding: .day, value: 1, to: today) ?? today
            }
        }
        self.prototype = prototype
        revise(weekday: calendar.component(.weekday, from: destination), effectiveDay: SchoolClock.key(boundary))
        return true
    }

    mutating func setCompleted(_ completed: Bool, on day: String) {
        if completed { completedDays.insert(day) } else { completedDays.remove(day) }
    }
}
