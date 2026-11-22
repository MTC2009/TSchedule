import Foundation

/// Compares occurrences of one published Day number, after aligning source bells.
/// A dated evening or elective variation is not evidence against daytime instruction.
enum SchoolRotationEvidence {
    typealias Period = SchoolTimetable.Period

    static func isDaytime(_ period: Period) -> Bool { period.start < CampusBells.dismissal }

    struct Observation {
        let periods: [Period]
        let vacancies: [TeachingSlot]
        let hasDatedRoster: Bool
        // A stored empty complete roster is not the same as a date with just one
        // explicit vacancy, or with no daytime response at all.
        var fullyVacant: Bool { (hasDatedRoster && periods.isEmpty && vacancies.isEmpty) || vacancies == CampusBells.teachingSlots }
        var observesLineup: Bool { fullyVacant || periods.contains(where: isDaytime) }
    }

    static func lineup(in observations: [Observation], usesCampusBells: Bool) -> [Period]? {
        guard observations.count >= 2 else { return nil }
        let occurrences = observations.map(\.periods)
        guard usesCampusBells else { return agreement(occurrences) }
        let daytimeObservations = observations.filter(\.observesLineup)
        // Identical late-only exports can both be incomplete. A recurring lineup needs
        // two dated daytime observations, including explicitly all-vacant days.
        guard daytimeObservations.count >= 2 else { return nil }

        let vacancies = Set(observations.flatMap(\.vacancies))
        func respectsVacancies(_ lessons: [Period]) -> Bool {
            !lessons.contains { p in vacancies.contains { $0.start < p.end && p.start < $0.end } }
        }
        if let wholeDay = agreement(occurrences), respectsVacancies(wholeDay) { return wholeDay }

        // Compare all actual daytime observations (not a majority); absence of daytime
        // rows at the publication edge must not veto several independently matching days.
        let daytime = daytimeObservations.map { $0.periods.filter(isDaytime) }
        guard let instruction = agreement(daytime), respectsVacancies(instruction),
              instruction.contains(where: { CampusBells.isTeachingPeriod(start: $0.start, end: $0.end) }) else { return nil }

        let late = occurrences.map { $0.filter { !isDaytime($0) } }
        // Each late slot stands on its own. A recurring elective can survive a
        // separate one-date event, while the event still appears on its real date.
        let clocks = Set(late[0].map { TeachingSlot(start: $0.start, end: $0.end) })
        return instruction + clocks.sorted { ($0.start, $0.end) < ($1.start, $1.end) }.flatMap { slot in
            agreement(late.map { $0.filter { $0.start == slot.start && $0.end == slot.end } }) ?? []
        }
    }

    /// Inputs are ordered by time, title and room. A change of room alone does
    /// not change the teaching assignment; it does make the recurring room unknown.
    private static func agreement(_ rows: [[Period]]) -> [Period]? {
        guard let first = rows.first, rows.dropFirst().allSatisfy({ other in
            first.count == other.count && zip(first, other).allSatisfy {
                $0.start == $1.start && $0.end == $1.end && $0.title == $1.title
            }
        }) else { return nil }
        return first.enumerated().map { index, p in
            .init(title: p.title, room: rows.allSatisfy { $0[index].room == p.room } ? p.room : nil,
                  start: p.start, end: p.end, metadata: .agreement(rows.map { $0[index].metadata }))
        }
    }
}
