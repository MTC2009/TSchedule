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
        var metadata: TimetableLessonMetadata? = nil
    }
    struct Day {
        let calendarDay: SchoolCalendarDay
        let schedule: CampusSchedule?
        let events: CampusCalendar
        /// The dated response was incomplete at its future edge; only the displayed daytime rows use the cycle.
        let usesDaytimeRotation: Bool
        var timeline: LessonTimeline? { schedule?.timeline { $0 } }
        let hasDatedException: Bool
        let studyTimePending: Bool
    }
    let owner, year, calendarDigest: String
    let savedAt: Date
    private(set) var dated: [String: [Period]] = [:]
    private(set) var rotations: [Int: [Period]] = [:]
    // Older documents omit this optional field. Keep dated slot evidence for a roster
    // containing no normal class, without treating a partly observed day as entirely free.
    // Absence identifies archives saved before bell alignment. Their original bytes stay untouched.
    private var bellRevision: Int?
    private static let currentBells = 2
    private var needsBellAlignment: Bool { (bellRevision ?? 0) < Self.currentBells }
    private var datedVacancies: [String: [TeachingSlot]]?
    var hasSavedEvidence: Bool { !dated.isEmpty || datedVacancies?.isEmpty == false }
    private struct EventSpan: Codable {
        let row: CampusEvent, start: Date, end: Date?
    }
    private var events: [String: EventSpan] = [:]
    private var unconfirmedDates: Set<String> = []
    // Derived only after reading matching dates and publication. It is deliberately not archived.
    private var daytimeProjectionDates: Set<String> = []
    private var studyWeek = SchoolStudyWeek()
    var hasStudyEnrollment: Bool { studyWeek.hasEnrollment }
    private enum CodingKeys: String, CodingKey {
        case owner, year, calendarDigest, savedAt, dated, rotations, bellRevision, datedVacancies, events, unconfirmedDates
    }

    init(owner: String, calendar: PublishedSchoolCalendar, now: Date) {
        bellRevision = Self.currentBells
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
        var emptyTeaching: Set<String> = [], hasDatedRoster = false
        for key in week.dates where calendar.from <= key && key <= calendar.through {
            guard let date = SchoolClock.dayDate(key), let schedule = week.schedule(on: date) else { continue }
            let records = try schedule.lessons.map { lesson -> (course: String, period: Period) in
                guard let start = campusInstant(lesson.start), let end = campusInstant(lesson.end),
                      SchoolClock.key(start) == key, SchoolClock.key(end) == key,
                      SchoolClock.minute(in: end) > SchoolClock.minute(in: start),
                      let name = week.names[lesson.course_id], !name.isEmpty else { throw SchoolPortalIssue.format }
                return (lesson.course_id, Period(title: name, room: lesson.room, start: SchoolClock.minute(in: start),
                                                 end: SchoolClock.minute(in: end), metadata: lesson.metadata))
            }.sorted { a, b in
                let l = a.period, r = b.period
                return (l.start, l.end, l.title, l.room ?? "") < (r.start, r.end, r.title, r.room ?? "")
            }
            let teachingDay = calendar.day(on: date).teachingDay != nil
            let campusDay = teachingDay && CampusBells.applies(to: calendar)
            let aligned = campusDay ? SchoolBellAlignment(records: records.map {
                // The bridge's [null,…] key identifies an occurrence, not a known enrollment.
                ($0.course.hasPrefix("[null,") ? nil : $0.course, $0.period)
            }, blanks: schedule.teaching_slots ?? []) : nil
            let periods = aligned?.periods ?? records.map(\.period)
            let matching = aligned?.vacancies ?? []
            let complete = matching == CampusBells.teachingSlots
            if !matching.isEmpty && (!complete || !periods.isEmpty) {
                if datedVacancies == nil { datedVacancies = [:] }
                datedVacancies?[key] = matching
            } else if complete || !periods.isEmpty {
                datedVacancies?.removeValue(forKey: key)
            }
            // A missing set of dated lessons can also mean an unpublished week. It is never
            // evidence that all occurrences of a teaching Day are free.
            if !periods.isEmpty || complete { dated[key] = periods; hasDatedRoster = true }
            else if teachingDay { emptyTeaching.insert(key) }
        }
        // An empty teaching date inside an otherwise populated week can be a cancellation.
        // Don't overwrite that dated evidence with a normal rotating lesson.
        if hasDatedRoster { unconfirmedDates.formUnion(emptyTeaching) }
        for event in week.calendar.events where events[event.id] == nil {
            guard let start = campusInstant(event.start) else { throw SchoolPortalIssue.format }
            events[event.id] = .init(row: event, start: start, end: event.end.flatMap(campusInstant))
        }
        rebuildRotations(calendar: calendar)
    }

    /// Rebuild the derived index from the dated source, not just when downloading. An
    /// older offline file may have discarded a whole rotation because of one evening row.
    mutating func rebuildRotations(calendar: PublishedSchoolCalendar) {
        guard year == calendar.academicYear, calendarDigest == calendar.sourceSHA256 else { return }
        let campus = CampusBells.applies(to: calendar)
        studyWeek = SchoolStudyWeek(dated:dated,calendar:calendar)
        var samples: [Int: [SchoolRotationEvidence.Observation]] = [:]
        var lastDaytime: String?
        var incomplete = unconfirmedDates
        let vacancyEvidence = datedVacancies ?? [:]
        for key in Set(dated.keys).union(vacancyEvidence.keys) {
            guard let date = SchoolClock.dayDate(key), let number = calendar.day(on: date).teachingDay else { continue }
            let stored = dated[key], rows = stored ?? []
            let aligned = campus && needsBellAlignment ? SchoolBellAlignment(records: rows.map { (nil, $0) }).periods : rows
            let observation = SchoolRotationEvidence.Observation(periods: aligned, vacancies: vacancyEvidence[key] ?? [], hasDatedRoster: stored != nil)
            samples[number, default: []].append(observation)
            if observation.observesLineup || !observation.vacancies.isEmpty { lastDaytime = max(lastDaytime ?? key, key) }
            else { incomplete.insert(key) }
        }
        for (number, rows) in samples where rows.count >= 2 {
            // Revoke a previously inferred template if a new dated occurrence contradicts
            // its daytime lineup. Preserve verified keys for which this file has no samples.
            rotations[number] = SchoolRotationEvidence.lineup(in: rows, usesCampusBells: campus)
        }
        // A study enrollment has its own weekly clock. Do not let even a perfectly
        // uniform sample of one rotation reintroduce it on unrelated Fridays.
        if campus {
            for (n,lineup) in rotations where lineup.contains(where:SchoolStudyWeek.isEnrollment) {
                let regular=lineup.filter { !SchoolStudyWeek.isEnrollment($0) }
                rotations[n]=regular.isEmpty ? nil : regular
            }
        }
        // An empty day *inside* observed instruction could be cancelled. Only a future
        // suffix beyond all dated daytime evidence can borrow the independently verified
        // daytime rotation, and never over a vacancy, calendar notice or dated event.
        daytimeProjectionDates = []
        guard campus, let lastDaytime else { return }
        let cutoff = max(lastDaytime, SchoolClock.key(savedAt))
        for key in incomplete where key > cutoff {
            guard let date = SchoolClock.dayDate(key) else { continue }
            let day = calendar.day(on: date)
            guard day.notices.isEmpty, let number = day.teachingDay,
                  rotations[number]?.contains(where: { CampusBells.isTeachingPeriod(start: $0.start, end: $0.end) }) == true,
                  events(on: date).isEmpty else { continue }
            daytimeProjectionDates.insert(key)
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

    private func confirmedPeriods(_ entry: SchoolCalendarDay, calendar: PublishedSchoolCalendar) -> [Period]? {
        let rows = dated[entry.date] ?? (datedVacancies?[entry.date] != nil ? [] :
            (unconfirmedDates.contains(entry.date) ? nil : entry.teachingDay.flatMap { rotations[$0] }))
        guard let rows, needsBellAlignment, entry.teachingDay != nil, CampusBells.applies(to: calendar) else { return rows }
        return SchoolBellAlignment(records: rows.map { (nil, $0) }).periods
    }

    /// Seven local school dates, not seven repetitions. Same-time classes need one alert.
    func lessonReminders(now: Date, lead: Int, calendar: PublishedSchoolCalendar) -> [SchoolLessonReminder] {
        guard SchoolLessonReminder.leads.contains(lead) else { return [] }
        let clock = SchoolClock.calendar, today = clock.startOfDay(for: now)
        var fires = Set<Date>()
        for offset in 0..<7 {
            guard let date = clock.date(byAdding: .day, value: offset, to: today),
                  let day = calendarDay(on: date, calendar: calendar) else { continue }
            for period in confirmedPeriods(day, calendar: calendar) ?? [] {
                let fire = SchoolClock.at(minute: period.start, on: date).addingTimeInterval(-Double(lead * 60))
                if fire > now { fires.insert(fire) }
            }
        }
        return fires.sorted().map { .init(fireDate: $0, lead: lead) }
    }

    func day(on date: Date, calendar: PublishedSchoolCalendar) -> Day? {
        guard let entry = calendarDay(on: date, calendar: calendar) else { return nil }
        let key = entry.date
        let confirmed = confirmedPeriods(entry, calendar: calendar)
        let usesDaytimeRotation = daytimeProjectionDates.contains(key)
        var periods: [Period]?
        if usesDaytimeRotation, let number = entry.teachingDay, let rotation = rotations[number] {
            // Do not manufacture optional/evening registrations or alerts at a clipped edge.
            // confirmedPeriods remains the sole input to reminders and retains actual late rows.
            periods = rotation.filter(SchoolRotationEvidence.isDaytime) + (confirmed ?? [])
        } else { periods = confirmed }
        let confirmedOff = entry.status == .weekend || entry.status == .noClass
        let datedEvents=events(on:date)
        var studyTimePending=false
        if dated[key] == nil, datedVacancies?[key] == nil, !unconfirmedDates.contains(key), datedEvents.isEmpty,
           confirmedOff || periods != nil, let study=studyWeek.projection(on:date,calendar:calendar) {
            if let extra=study.period, !(periods ?? []).contains(where:{ $0.start < extra.end && extra.start < $0.end }) {
                periods=((periods ?? []) + [extra]).sorted { ($0.start,$0.end,$0.title)<($1.start,$1.end,$1.title) }
            } else { studyTimePending = true }
        }
        let schedule: CampusSchedule?
        let campusDay = entry.teachingDay != nil && CampusBells.applies(to: calendar)
        if let rows = periods ?? (confirmedOff || campusDay ? [] : nil) {
            let lessons = rows.enumerated().map { i, p -> CampusLesson in
                func stamp(_ minute: Int) -> String { key + "T" + SchoolClock.time(minute) + ":00+08:00" }
                return .init(id: "\(key):\(i)", course_id: p.title, start: stamp(p.start), end: stamp(p.end),
                             room: p.room, metadata: p.metadata)
            }
            // Calendar status confirms campus activities, not a student's vacancies.
            // Only recognized enrollment/slot evidence opens the full instructional grid.
            let knownSlots = campusDay ? datedVacancies?[key] : nil
            let completeVacantDay = periods?.isEmpty == true && knownSlots == nil
            let hasRegularClass = rows.contains { CampusBells.isTeachingPeriod(start: $0.start, end: $0.end) }
            let useBells = campusDay && (completeVacantDay || hasRegularClass)
            schedule = .init(date: key, day: entry.teachingDay, lessons: lessons,
                             teaching_slots: useBells ? CampusBells.teachingSlots : knownSlots,
                             calendarDay: entry, includesCampusBells: campusDay, fixedCampusActivities: campusDay,
                             hasConfirmedRoster: periods != nil || confirmedOff)
        } else { schedule = nil }
        return .init(calendarDay: entry, schedule: schedule, events: .init(lessons: [], events: datedEvents, deadlines: []),
                     usesDaytimeRotation: usesDaytimeRotation, hasDatedException: confirmedOff && dated[key]?.isEmpty == false,
                     studyTimePending: studyTimePending)
    }

    // These entries retain their original dates; never repeat an activity on future Day Ns.
    private func events(on date: Date) -> [CampusEvent] {
        let from = SchoolClock.calendar.startOfDay(for: date)
        let until = SchoolClock.calendar.date(byAdding: .day, value: 1, to: from)!
        return events.values.compactMap { span -> CampusEvent? in
            guard span.start < until, span.end.map({ $0 > from }) ?? (span.start >= from) else { return nil }
            return span.row
        }.sorted { ($0.start, $0.id) < ($1.start, $1.id) }
    }

    func canReplace(_ old: Self?) -> Bool {
        guard hasSavedEvidence else { return false }
        guard let old, old.owner == owner, old.year == year else { return true }
        guard Set(old.rotations.keys).isSubset(of: Set(rotations.keys)) else { return false }
        if dated.isEmpty {
            // A partial blank-only response must not replace better evidence with less.
            guard old.dated.isEmpty else { return false }
            return (old.datedVacancies ?? [:]).allSatisfy { date, slots in
                Set(slots).isSubset(of: Set(datedVacancies?[date] ?? []))
            }
        }
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
