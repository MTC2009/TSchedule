import Foundation

/// Published campus return policy, independent of student enrollment. A parent
/// conference, unpublished date or an ordinary Saturday is not a holiday return.
enum SchoolResidenceNight {
    enum Kind { case ordinary, returning }
    static func kind(on date: Date, calendar: PublishedSchoolCalendar) -> Kind? {
        guard CampusBells.applies(to: calendar),
            let tomorrow = SchoolClock.calendar.date(byAdding: .day, value: 1, to: date),
            calendar.day(on: tomorrow).teachingDay != nil
        else { return nil }
        let row = calendar.day(on: date)
        let weekday = SchoolClock.calendar.component(.weekday, from: date)
        guard weekday != 6 else { return nil }  // Friday departure, even beside a printed Day.
        if weekday == 1 && row.status == .weekend || holiday(row) { return .returning }
        return (2...5).contains(weekday) && row.teachingDay != nil ? .ordinary : nil
    }
    static func holiday(_ row: SchoolCalendarDay) -> Bool {
        row.status == .noClass
            && row.notices.contains {
                $0.contains("假") || $0.localizedCaseInsensitiveContains("holiday")
                    || $0.localizedCaseInsensitiveContains("break")
            }
    }
}

/// Dated participation and the week's time slot are separate evidence. Nothing
/// here is shared across students, persisted as school data, or used for alerts.
struct SchoolStudyWeek {
    typealias Period = SchoolTimetable.Period
    struct Projection {
        let period: Period?
        let pending: Bool
    }
    private struct Slot: Hashable {
        let title: String
        let start, end: Int
    }
    private struct Observation {
        let week, weekday, rotation, segment: Int
        let slots: [Slot]
    }
    private var weekdays = Set<Int>()
    private var fixed: Slot?
    private var phases: [Int: [Slot]] = [:]
    private var knownWeeks: [Int: [Int: Slot]] = [:]
    private var segmentByDate: [String: Int] = [:]
    private var rooms: [Slot: String] = [:]
    private(set) var hasEnrollment = false

    /// The school names this program in the student roster; match a complete token,
    /// not a student's name, group, a particular date, the first study slot or an arbitrary evening class.
    static func isEnrollment(_ p: Period) -> Bool {
        isEnrollment(title: p.title, start: p.start)
    }
    static func isEnrollment(title: String, start: Int) -> Bool {
        start >= CampusBells.dismissal
            && title.folding(
                options: [.widthInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX")
            )
            .range(of: #"(?i)(?<![a-z])t[ .]*s[ .]*s[ .]*a(?![a-z])"#, options: .regularExpression) != nil
    }
    private static func week(_ date: Date) -> Int {
        SchoolClock.calendar.dateComponents(
            [.day], from: SchoolClock.date(2000, 1, 2), to: TimetableWeek(containing: date).start
        ).day! / 7
    }
    init() {}
    init(dated: [String: [Period]], calendar: PublishedSchoolCalendar) {
        guard CampusBells.applies(to: calendar), dated.values.contains(where: { $0.contains(where: Self.isEnrollment) })
        else { return }
        hasEnrollment = true
        var observations: [Observation] = []
        var allRooms: [Slot: Set<String?>] = [:]
        var segment = 0
        var interrupted = false
        for row in calendar.days {
            guard let date = SchoolClock.dayDate(row.date) else { continue }
            let weekday = SchoolClock.calendar.component(.weekday, from: date)
            if row.status == .unpublished || SchoolResidenceNight.holiday(row) && (2...6).contains(weekday) {
                interrupted = true
            }
            guard let rotation = row.teachingDay else { continue }
            if interrupted {
                segment += 1
                interrupted = false
            }
            segmentByDate[row.date] = segment
            guard SchoolResidenceNight.kind(on: date, calendar: calendar) == .ordinary, let periods = dated[row.date]
            else { continue }
            let actual = periods.filter(Self.isEnrollment)
            guard !actual.isEmpty || periods.contains(where: SchoolRotationEvidence.isDaytime) else { continue }
            let slots = actual.map { p in
                let slot = Slot(title: p.title, start: p.start, end: p.end)
                allRooms[slot, default: []].insert(p.room)
                return slot
            }
            observations.append(
                .init(week: Self.week(date), weekday: weekday, rotation: rotation, segment: segment, slots: slots))
        }
        for (day, obs) in Dictionary(grouping: observations, by: \.weekday)
        where
            Set(obs.map(\.week)).count >= 2 && Set(obs.map(\.rotation)).count >= 2
            && obs.allSatisfy({ !$0.slots.isEmpty })
        {
            weekdays.insert(day)
        }
        let positives = observations.filter { !$0.slots.isEmpty }
        guard Set(positives.map(\.week)).count >= 2 else { return }
        for (slot, values) in allRooms where values.count == 1 { rooms[slot] = values.first ?? nil }
        if allRooms.count == 1 {
            fixed = allRooms.keys.first
            return
        }
        for (seg, items) in Dictionary(grouping: positives, by: \.segment) {
            let weeks = Dictionary(grouping: items, by: \.week).mapValues { Set($0.flatMap(\.slots)) }
            // A clash within the week is a possible dated exception. Never choose
            // a winner or use it as proof of an alternating schedule.
            for (week, slots) in weeks where slots.count == 1 { knownWeeks[seg, default: [:]][week] = slots.first }
            guard weeks.values.allSatisfy({ $0.count == 1 }) else { continue }
            for length in [2, 3] where weeks.count >= 2 * length {
                var sequence: [Slot] = []
                for phase in 0..<length {
                    let matching = weeks.filter { $0.key % length == phase }
                    let candidates = Set(matching.values.flatMap { $0 })
                    guard matching.count >= 2, candidates.count == 1, let slot = candidates.first else { break }
                    sequence.append(slot)
                }
                if sequence.count == length {
                    phases[seg] = sequence
                    break
                }
            }
        }
    }
    func projection(on date: Date, calendar: PublishedSchoolCalendar) -> Projection? {
        guard hasEnrollment else { return nil }
        let row = calendar.day(on: date)
        let weekday = SchoolClock.calendar.component(.weekday, from: date)
        let target: Date
        if row.teachingDay != nil && weekdays.contains(weekday)
            && SchoolResidenceNight.kind(on: date, calendar: calendar) == .ordinary
        {
            target = date
        } else if SchoolResidenceNight.kind(on: date, calendar: calendar) == .returning,
            let next = SchoolClock.calendar.date(byAdding: .day, value: 1, to: date)
        {
            target = next
        } else {
            return nil
        }
        let week = Self.week(target)
        let slot =
            fixed
            ?? segmentByDate[SchoolClock.key(target)].flatMap { segment in
                knownWeeks[segment]?[week] ?? phases[segment].map { $0[week % $0.count] }
            }
        guard let slot else { return .init(period: nil, pending: true) }
        return .init(
            period: .init(title: slot.title, room: rooms[slot], start: slot.start, end: slot.end), pending: false)
    }
}
