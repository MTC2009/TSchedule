import Foundation

/// A course notification crosses the lock-screen boundary with timing only.
struct SchoolLessonReminder: Identifiable, Equatable, Sendable {
    static let prefix = "tschedule.school.lesson."
    static let leads = [0, 5, 10, 15]
    let fireDate: Date
    let lead: Int
    var id: String { Self.prefix + "\(Int(fireDate.timeIntervalSince1970)).\(lead)" }
}

/// The saved timetable is a device document, not permission to read the portal. It contains
/// neither portal credentials nor student, assignment or grade records. Calendar and roster
/// are different inputs: a published Day number on its own cannot establish a course.
struct SchoolTimetable: Codable {
    struct Period: Codable, Equatable {
        let title: String, room: String?
        let start: Int, end: Int
    }
    struct Day {
        let calendarDay: SchoolCalendarDay
        let schedule: CampusSchedule?
        let events: CampusCalendar
        var timeline: LessonTimeline? { schedule?.timeline { $0 } }
        var hasDatedException: Bool {
            (calendarDay.status == .weekend || calendarDay.status == .noClass) && schedule?.lessons.isEmpty == false
        }
    }
    let owner, year, calendarDigest: String
    let savedAt: Date
    private(set) var dated: [String: [Period]] = [:]
    private(set) var rotations: [Int: [Period]] = [:]
    private struct EventSpan: Codable {
        let row: CampusEvent, start: Date, end: Date?
    }
    private var events: [String: EventSpan] = [:]
    private var unconfirmedDates: Set<String> = []

    init(owner: String, calendar: PublishedSchoolCalendar, now: Date) {
        self.owner = owner; year = calendar.academicYear; calendarDigest = calendar.sourceSHA256; savedAt = now
    }

    /// Only use a few nearby teaching weeks, not every week in the year. Start with the current
    /// week so actual dated exceptions remain available. Adjacent months can contain long breaks.
    static func sampleWeeks(near date: Date, calendar: PublishedSchoolCalendar) -> [Date] {
        let key = SchoolClock.key(date), current = TimetableWeek(containing: date).start
        guard calendar.from <= key, key <= calendar.through else { return [] }
        let weeks = Set(calendar.days.compactMap { row -> Date? in
            guard row.teachingDay != nil, let day = SchoolClock.dayDate(row.date) else { return nil }
            return TimetableWeek(containing: day).start
        })
        return [current] + weeks.filter { $0 != current }.sorted {
            let a = abs($0.timeIntervalSince(current)), b = abs($1.timeIntervalSince(current))
            return a == b ? $0 < $1 : a < b
        }.prefix(5)
    }

    mutating func absorb(_ week: SchoolPortalWeek, calendar: PublishedSchoolCalendar) throws {
        var emptyTeaching: Set<String> = [], hasDatedLessons = false
        for key in week.dates where calendar.from <= key && key <= calendar.through {
            guard let date = SchoolClock.dayDate(key), let schedule = week.schedule(on: date) else { continue }
            let periods = try schedule.lessons.map { lesson -> Period in
                guard let start = campusInstant(lesson.start), let end = campusInstant(lesson.end),
                      SchoolClock.key(start) == key, SchoolClock.key(end) == key,
                      SchoolClock.minute(in: end) > SchoolClock.minute(in: start),
                      let name = week.names[lesson.course_id], !name.isEmpty else { throw SchoolPortalIssue.format }
                return Period(title: name, room: lesson.room, start: SchoolClock.minute(in: start), end: SchoolClock.minute(in: end))
            }.sorted { ($0.start, $0.end, $0.title, $0.room ?? "") < ($1.start, $1.end, $1.title, $1.room ?? "") }
            // A missing set of dated lessons can also mean an unpublished week. It is never
            // evidence that all occurrences of a teaching Day are free.
            if !periods.isEmpty { dated[key] = periods; hasDatedLessons = true }
            else if calendar.day(on: date).teachingDay != nil { emptyTeaching.insert(key) }
        }
        // An empty teaching date inside an otherwise populated week can be a cancellation.
        // Don't overwrite that dated evidence with a normal rotating lesson.
        if hasDatedLessons { unconfirmedDates.formUnion(emptyTeaching) }
        for event in week.calendar.events where events[event.id] == nil {
            guard let start = campusInstant(event.start) else { throw SchoolPortalIssue.format }
            events[event.id] = .init(row: event, start: start, end: event.end.flatMap(campusInstant))
        }
        var samples: [Int: [[Period]]] = [:]
        for (key, periods) in dated {
            guard let date = SchoolClock.dayDate(key), let rotation = calendar.day(on: date).teachingDay else { continue }
            samples[rotation, default: []].append(periods)
        }
        // A field trip or an isolated exam is not a recurring template. Compare whole
        // instructional lineups on distinct dates, including times; never pick a majority
        // when observed lineups disagree. A varying room is not a verified recurring room.
        rotations = samples.compactMapValues { rows in
            guard rows.count >= 2, let first = rows.first,
                  rows.dropFirst().allSatisfy({ other in
                      other.count == first.count && zip(first, other).allSatisfy {
                          $0.title == $1.title && $0.start == $1.start && $0.end == $1.end
                      }
                  }) else { return nil }
            return first.enumerated().map { i, period in
                let room = rows.allSatisfy { $0[i].room == period.room } ? period.room : nil
                return .init(title: period.title, room: room, start: period.start, end: period.end)
            }
        }
    }

    /// The toolbar needs only a calendar label; don't materialize lessons or scan events for it.
    func calendarDay(on date: Date, calendar: PublishedSchoolCalendar) -> SchoolCalendarDay? {
        let key = SchoolClock.key(date)
        guard year == calendar.academicYear, calendarDigest == calendar.sourceSHA256,
              calendar.from <= key, key <= calendar.through else { return nil }
        return calendar.day(on: date)
    }

    func nextSchoolDay(after date: Date, calendar: PublishedSchoolCalendar) -> NextSchoolDay? {
        guard calendarDay(on: date, calendar: calendar) != nil else { return nil }
        return NextSchoolDay(after: date) { candidate in
            guard let row = calendarDay(on: candidate, calendar: calendar) else { return (nil, nil) }
            // Only a dated lesson can override a closure. Don't build a timeline or scan
            // events for every empty day of a long holiday.
            guard row.teachingDay != nil || dated[row.date]?.isEmpty == false else { return (row, nil) }
            return (row, day(on: candidate, calendar: calendar)?.timeline)
        }
    }

    private func confirmedPeriods(_ entry: SchoolCalendarDay) -> [Period]? {
        dated[entry.date] ?? (unconfirmedDates.contains(entry.date) ? nil : entry.teachingDay.flatMap { rotations[$0] })
    }

    /// Seven local school dates, not seven repetitions. Same-time classes need one alert.
    func lessonReminders(now: Date, lead: Int, calendar: PublishedSchoolCalendar) -> [SchoolLessonReminder] {
        guard SchoolLessonReminder.leads.contains(lead) else { return [] }
        let clock = SchoolClock.calendar, today = clock.startOfDay(for: now)
        var fires = Set<Date>()
        for offset in 0..<7 {
            guard let date = clock.date(byAdding: .day, value: offset, to: today),
                  let day = calendarDay(on: date, calendar: calendar) else { continue }
            for period in confirmedPeriods(day) ?? [] {
                let fire = SchoolClock.at(minute: period.start, on: date).addingTimeInterval(-Double(lead * 60))
                if fire > now { fires.insert(fire) }
            }
        }
        return fires.sorted().map { .init(fireDate: $0, lead: lead) }
    }

    func day(on date: Date, calendar: PublishedSchoolCalendar) -> Day? {
        guard let entry = calendarDay(on: date, calendar: calendar) else { return nil }
        let key = entry.date
        let periods = confirmedPeriods(entry)
        let confirmedOff = entry.status == .weekend || entry.status == .noClass
        let schedule: CampusSchedule?
        if let rows = periods ?? (confirmedOff ? [] : nil) {
            let lessons = rows.enumerated().map { i, p -> CampusLesson in
                func stamp(_ minute: Int) -> String { key + "T" + SchoolClock.time(minute) + ":00+08:00" }
                return .init(id: "\(key):\(i)", course_id: p.title, start: stamp(p.start), end: stamp(p.end), room: p.room)
            }
            schedule = .init(date: key, day: entry.teachingDay, lessons: lessons, calendarDay: entry, includesCampusBells: false)
        } else { schedule = nil }
        // These entries retain their original dates; never repeat an activity on future Day Ns.
        let from = SchoolClock.calendar.startOfDay(for: date)
        let until = SchoolClock.calendar.date(byAdding: .day, value: 1, to: from)!
        let dailyEvents = events.values.compactMap { span -> CampusEvent? in
            guard span.start < until, span.end.map({ $0 > from }) ?? (span.start >= from) else { return nil }
            return span.row
        }.sorted { ($0.start, $0.id) < ($1.start, $1.id) }
        return .init(calendarDay: entry, schedule: schedule, events: .init(lessons: [], events: dailyEvents, deadlines: []))
    }

    func canReplace(_ old: Self?) -> Bool {
        guard !dated.isEmpty else { return false }
        guard let old, old.owner == owner, old.year == year else { return true }
        guard Set(old.rotations.keys).isSubset(of: Set(rotations.keys)) else { return false }
        // If neither side has a full rotation, don't replace a richer set of dated evidence
        // with a near-empty response just because the confirmed rotation keys still match.
        return rotations.count > old.rotations.count || rotations.count == 6 || dated.count >= old.dated.count
    }
}

/// Calendar status answers *when*; only this student's lessons can answer *what and where*.
struct NextSchoolDay {
    let date: Date
    let rotation: Int?
    let firstLessons: [LessonTimeline.Period]

    init?(after today: Date, read: (Date) -> (SchoolCalendarDay?, LessonTimeline?)) {
        let clock = SchoolClock.calendar
        var cursor = clock.startOfDay(for: today)
        // A published school year covers at most 366 dates. A missing row ends the
        // search: a later known lesson can't prove what happens during an unknown gap.
        for _ in 0..<366 {
            guard let candidate = clock.date(byAdding: .day, value: 1, to: cursor) else { return nil }
            let (row, timeline) = read(candidate)
            guard let row, row.date == SchoolClock.key(candidate) else { return nil }
            let lessons = timeline?.dayStart == candidate ? timeline?.blocks.compactMap(\.lesson) ?? [] : []
            if row.teachingDay != nil || !lessons.isEmpty {
                date = candidate
                rotation = row.teachingDay
                firstLessons = Array(lessons.prefix { $0.start == lessons.first?.start })
                return
            }
            guard row.status == .weekend || row.status == .noClass else { return nil }
            cursor = candidate
        }
        return nil
    }
}
