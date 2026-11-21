import Foundation

struct PlannedPlanReminder: Identifiable, Equatable, Sendable {
    enum Timing: Equatable, Sendable {
        case once
        case weekly(weekday: Int, minute: Int)
    }

    let id: String
    let planTitle: String
    let lead: PlanReminder
    let nextFire: Date
    let timing: Timing
}

enum PlanReminderPlanner {
    static let identifierPrefix = "xiaobao.plan."
    private static let maximumCandidatesPerSeries = 60
    private static let maximumBridgeWeeks = 4

    static func make(now: Date, schedule: PlanStore.Schedule,
                     calendar: PublishedSchoolCalendar? = nil) -> [PlannedPlanReminder] {
        var result = schedule.plans.compactMap { plan -> PlannedPlanReminder? in
            guard !plan.isCompleted, let lead = plan.reminder, let time = plan.time,
                  let day = SchoolClock.dayDate(plan.day) else { return nil }
            let fire = time.start(on: day).addingTimeInterval(-Double(lead.rawValue * 60))
            guard fire > now else { return nil }
            return PlannedPlanReminder(id: identifierPrefix + "once." + plan.id.uuidString, planTitle: plan.title,
                                       lead: lead, nextFire: fire, timing: .once)
        }
        for bubble in schedule.bubbles {
            result.append(contentsOf: occurrences(for: bubble, now: now, publication: calendar))
        }
        return result.sorted { $0.nextFire == $1.nextFire ? $0.id < $1.id : $0.nextFire < $1.nextFire }
    }

    private static func occurrences(for bubble: PlanBubble, now: Date, publication: PublishedSchoolCalendar?) -> [PlannedPlanReminder] {
        let calendar = SchoolClock.calendar
        let today = calendar.startOfDay(for: now)
        let id = identifierPrefix + "weekly." + bubble.id.uuidString
        var results: [PlannedPlanReminder] = []
        for index in bubble.revisions.indices {
            let revision = bubble.revisions[index]
            let end = bubble.revisions.dropFirst(index + 1).first.flatMap { SchoolClock.dayDate($0.effectiveDay) }
            guard end.map({ $0 > today }) ?? true, let rule = revision.rule, let time = rule.plan.time,
                  let lead = rule.plan.reminder, let effective = SchoolClock.dayDate(revision.effectiveDay) else { continue }
            let search = max(today, effective)
            if case .rotationDay(let day) = rule.recurrence {
                // A system weekly or interval trigger cannot express school holidays or
                // makeup days. Only queue dated, published occurrences of this revision.
                let firstKey = SchoolClock.key(search), endKey = end.map(SchoolClock.key)
                for row in publication?.days ?? [] where row.teachingDay == day && row.date >= firstKey {
                    if results.count >= maximumCandidatesPerSeries || endKey.map({ row.date >= $0 }) == true { break }
                    guard !bubble.completedDays.contains(row.date), let date = SchoolClock.dayDate(row.date) else { continue }
                    let fire = time.start(on: date).addingTimeInterval(-Double(lead.rawValue * 60))
                    guard fire > now else { continue }
                    results.append(.init(id: identifierPrefix + "rotation." + bubble.id.uuidString + "." + row.date,
                                         planTitle: rule.plan.title, lead: lead, nextFire: fire, timing: .once))
                }
                continue
            }
            guard case .weekday(let weekday) = rule.recurrence else { continue }
            let offset = (weekday - calendar.component(.weekday, from: search) + 7) % 7
            guard var date = calendar.date(byAdding: .day, value: offset, to: search) else { continue }
            let hasPendingCompletion = end == nil && bubble.completedDays.contains { day in
                guard let completed = SchoolClock.dayDate(day), completed >= search,
                      calendar.component(.weekday, from: completed) == weekday else { return false }
                return time.start(on: completed).addingTimeInterval(-Double(lead.rawValue * 60)) > now
            }
            var scheduled = 0
            // The old rule must not remain a system repeat when it has an end.
            // Queue valid occurrences before that boundary, then queue the new rule.
            while end.map({ date < $0 }) ?? true, results.count < maximumCandidatesPerSeries {
                let fire = time.start(on: date).addingTimeInterval(-Double(lead.rawValue * 60))
                if fire > now, !bubble.completedDays.contains(SchoolClock.key(date)) {
                    let previous = calendar.date(byAdding: .day, value: -7, to: fire)
                    // A system repeat cannot skip a single completed occurrence.
                    if end == nil, !hasPendingCompletion, scheduled == 0, previous.map({ $0 <= now }) == true {
                        results.append(.init(id: id, planTitle: rule.plan.title, lead: lead, nextFire: fire,
                                             timing: .weekly(weekday: calendar.component(.weekday, from: fire),
                                                             minute: SchoolClock.minute(in: fire))))
                        break
                    }
                    results.append(.init(id: id + "." + SchoolClock.key(date), planTitle: rule.plan.title,
                                         lead: lead, nextFire: fire, timing: .once))
                    scheduled += 1
                    // Delay a distant repeat without firing early. Supply a short
                    // bridge, then promote it to a native repeat on foregrounding.
                    if end == nil, scheduled == maximumBridgeWeeks { break }
                }
                guard let later = calendar.date(byAdding: .day, value: 7, to: date) else { break }
                date = later
            }
        }
        return results
    }
}
