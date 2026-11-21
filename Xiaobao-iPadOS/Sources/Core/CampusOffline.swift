import Foundation

enum CampusModule: String, Codable, CaseIterable, CodingKey, Sendable {
    case courses, timetable, events, attendance, tasks, exams, evaluations, resources, grades
    static let ordinary = Set(allCases).subtracting([.grades])
}

struct CampusManifest: Codable, Equatable, Sendable {
    let version: String
    let parts: [String: String]
    var tag: String { "W/\"\(version)\"" }
}

extension SchoolClock {
    static func dayDate(_ key: String) -> Date? {
        guard key.utf8.count == 10, ("2000-01-01"..."2100-12-31").contains(key) else { return nil }
        return parseSchoolDate(key)
    }
}

struct OfflineTimetable: Codable, Sendable {
    struct Rotation: Codable, Sendable { let anchor_date: String; let anchor_day, cycle_length: Int; let closures: [String] }
    struct Period: Codable, Sendable { let course_id: String; let id, room: String?; let start, end: Int }
    let rotation: Rotation
    let days: [[Period]]
    let teachingSlots: [[TeachingSlot]]?
    let schoolCalendar: PublishedSchoolCalendar?
    private let calendar: SchoolCalendar?
    private enum CodingKeys: String, CodingKey {
        case rotation, days
        case teachingSlots = "teaching_slots", schoolCalendar = "school_calendar"
    }

    init(rotation: Rotation, days: [[Period]], teachingSlots: [[TeachingSlot]]? = nil,
         schoolCalendar: PublishedSchoolCalendar? = nil) {
        self.rotation = rotation
        self.days = days
        self.teachingSlots = teachingSlots?.count == days.count ? teachingSlots : nil
        self.schoolCalendar = schoolCalendar
        if let anchor = SchoolClock.dayDate(rotation.anchor_date), (1...255).contains(days.count),
           (1...days.count).contains(rotation.anchor_day), rotation.cycle_length == days.count,
           !SchoolClock.calendar.isDateInWeekend(anchor), !rotation.closures.contains(rotation.anchor_date),
           schoolCalendar?.isCompatible(cycleLength: days.count) != false {
            calendar = SchoolCalendar(anchorDate: anchor, anchorDay: rotation.anchor_day, cycleLength: days.count,
                                      closures: Set(rotation.closures), publication: schoolCalendar)
        } else { calendar = nil }
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(rotation: values.decode(Rotation.self, forKey: .rotation), days: values.decode([[Period]].self, forKey: .days),
                      teachingSlots: try? values.decode([[TeachingSlot]].self, forKey: .teachingSlots),
                      schoolCalendar: try values.decodeIfPresent(PublishedSchoolCalendar.self, forKey: .schoolCalendar))
    }
    var valid: Bool { calendar != nil && days.joined().allSatisfy { (0..<1440).contains($0.start) && ($0.start < $0.end && $0.end <= 1440) } }

    func schedule(_ date: Date) -> CampusSchedule? {
        guard let calendar else { return nil }
        let key = SchoolClock.key(date)
        let calendarDay = calendar.publishedDay(on: date)
        guard let day = calendar.rotationDay(on: date) else {
            return CampusSchedule(date: key, day: nil, lessons: [], calendarDay: calendarDay)
        }
        let lessons = days[day - 1].map { period in
            CampusLesson(id: "\(period.id ?? period.course_id):\(key)", course_id: period.course_id,
                         start: SchoolClock.at(minute: period.start, on: date).ISO8601Format(),
                         end: SchoolClock.at(minute: period.end, on: date).ISO8601Format(), room: period.room)
        }
        return CampusSchedule(date: key, day: day, lessons: lessons, teaching_slots: teachingSlots?[day - 1], calendarDay: calendarDay)
    }
}

struct OfflineAttendance: Codable, Sendable {
    struct Coverage: Codable, Equatable, Sendable {
        let from, to: String
        func recentWeek(on date: Date) -> Self? {
            let day = SchoolClock.calendar.startOfDay(for: date)
            let first = SchoolClock.calendar.date(byAdding: .day, value: -6, to: day)!
            let start = max(from, SchoolClock.key(first)), end = min(to, SchoolClock.key(day))
            return start <= end ? Self(from: start, to: end) : nil
        }
    }
    struct Row: Codable, Sendable { let id, course_id, date: String; let status: AttendanceStatus }
    let coverage: Coverage
    let course_ids: [String]
    let records: [Row]

    func report(from: String? = nil, to: String? = nil) -> CampusAttendance? {
        let first = from ?? coverage.from, last = to ?? coverage.to
        guard first >= coverage.from, last <= coverage.to, first <= last else { return nil }
        var counts: [String: AttendanceCounts] = [:]
        for record in records where record.date >= first && record.date <= last {
            counts[record.course_id, default: AttendanceCounts()].add(record.status)
        }
        let grouped = course_ids.map { counts[$0] ?? AttendanceCounts() }
        func summary(_ value: AttendanceCounts) -> CampusCounts {
            CampusCounts(present: value.present, late: value.late, early: value.early, absent: value.absent,
                         total: value.total, present_rate: value.rate)
        }
        return CampusAttendance(totals: summary(.sum(grouped)), by_course: zip(course_ids, grouped).map { CampusCourseAttendance(course_id: $0, summary: summary($1)) })
    }
}

enum CampusDataset: Codable, Sendable {
    case courses([CampusCourse]), timetable(OfflineTimetable), events([CampusEvent]), attendance(OfflineAttendance)
    case work([CampusWork]), resources([CampusResource]), grades(CampusGradeChanges)
}

struct CampusDownload: Decodable, Sendable {
    nonisolated static func unpack(_ body: Data) async throws -> CampusDownload {
        try JSONDecoder().decode(CampusEnvelope<CampusDownload>.self, from: body).data
    }

    let version: String
    let parts: [CampusModule: CampusDataset]
    enum Keys: CodingKey { case version, parts }
    init(from decoder: Decoder) throws {
        let outer = try decoder.container(keyedBy: Keys.self)
        version = try outer.decode(String.self, forKey: .version)
        let box = try outer.nestedContainer(keyedBy: CampusModule.self, forKey: .parts)
        var values: [CampusModule: CampusDataset] = [:]
        for key in box.allKeys {
            switch key {
            case .courses: values[key] = .courses(try box.decode([CampusCourse].self, forKey: key))
            case .timetable:
                let timetable = try box.decode(OfflineTimetable.self, forKey: key)
                guard timetable.valid else { throw CampusError.invalidResponse }
                values[key] = .timetable(timetable)
            case .events: values[key] = .events(try box.decode([CampusEvent].self, forKey: key))
            case .attendance:
                let value = try box.decode(OfflineAttendance.self, forKey: key)
                let ids = Set(value.course_ids)
                guard ids.count == value.course_ids.count, SchoolClock.dayDate(value.coverage.from) != nil,
                      SchoolClock.dayDate(value.coverage.to) != nil, value.coverage.from <= value.coverage.to,
                      value.records.allSatisfy({ ids.contains($0.course_id) && value.coverage.from <= $0.date && $0.date <= value.coverage.to }) else { throw CampusError.invalidResponse }
                values[key] = .attendance(value)
            case .tasks, .exams, .evaluations:
                let rows = try box.decode([CampusWork].self, forKey: key)
                values[key] = .work(rows.sorted { ($0.due_at, $0.id) < ($1.due_at, $1.id) })
            case .resources: values[key] = .resources(try box.decode([CampusResource].self, forKey: key).sorted { $0.id < $1.id })
            case .grades:
                let value = try box.decode(CampusGradeChanges.self, forKey: key)
                _ = try value.applying(to: nil, at: .distantPast)
                values[key] = .grades(value)
            }
        }
        parts = values
    }
}

struct OfflineCheck: Codable, Sendable {
    var generation = UUID()
    var manifest: CampusManifest?
    var checked: Date?
    var allChecked: Date?
    var gradesChecked: Date?
    var gradesUpdated: Date?
}

struct CampusOfflineState: Codable, Sendable {
    var manifest: CampusManifest? {
        get { check.manifest }
        set { check.manifest = newValue }
    }
    var versions: [CampusModule: String] = [:]
    var data: [CampusModule: CampusDataset] = [:]
    var gradeMetadataVersion: Int? = nil
    var taskMetadataVersion: Int? = nil
    var check = OfflineCheck()

    func content(_ page: CampusPage) -> CampusContent? {
        switch page {
        case .courses:
            if case .courses(let rows) = data[.courses] { return .courses(rows) }
        case .schedule(let key):
            if case .timetable(let table) = data[.timetable], let date = SchoolClock.dayDate(key),
               let schedule = table.schedule(date) { return .schedule(schedule) }
        case .attendance:
            if case .attendance(let info) = data[.attendance] { return .attendance(info.report()) }
        case .work(let kind, let offset):
            let key: CampusModule
            switch kind { case "task": key = .tasks; case "exam": key = .exams; case "evaluation": key = .evaluations; default: return nil }
            if case .work(let rows) = data[key] { return .work(slice(rows, offset)) }
        case .resources(let offset):
            if case .resources(let rows) = data[.resources] { return .resources(slice(rows, offset)) }
        case .calendar(let from, let to):
            guard case .timetable(let table) = data[.timetable], case .events(let events) = data[.events],
                  let first = SchoolClock.dayDate(from), let last = SchoolClock.dayDate(to),
                  let span = SchoolClock.calendar.dateComponents([.day], from: first, to: last).day, (0..<42).contains(span) else { return nil }
            let end = SchoolClock.calendar.date(byAdding: .day, value: 1, to: last)!
            let lessons = (0...span).flatMap { offset in
                table.schedule(SchoolClock.calendar.date(byAdding: .day, value: offset, to: first)!)?.lessons ?? []
            }
            let visible = events.filter { event in
                guard let start = campusInstant(event.start), let finish = campusInstant(event.end ?? event.start) else { return false }
                return start < end && (finish > first || start >= first)
            }
            var deadlines: [CampusWork] = []
            for group in [CampusModule.tasks, .exams, .evaluations] {
                guard case .work(let rows) = data[group] else { return nil }
                deadlines += rows.filter { campusInstant($0.due_at).map { first <= $0 && $0 < end } ?? false }
            }
            return .calendar(CampusCalendar(lessons: lessons, events: visible, deadlines: deadlines.sorted { $0.due_at < $1.due_at }))
        case .grades: break
        }
        return nil
    }

    private func slice<T>(_ rows: [T], _ offset: Int) -> CampusList<T> where T: Decodable & Sendable {
        let start = min(max(0, offset), rows.count), limit = 30
        return CampusList(items: Array(rows[start..<min(rows.count, start + limit)]), total: rows.count, offset: offset, limit: limit)
    }
}

extension CampusPage {
    var modules: [CampusModule] {
        switch self {
        case .courses: [.courses]
        case .schedule: [.timetable]
        case .calendar: [.timetable, .events, .tasks, .exams, .evaluations]
        case .grades: [.grades]
        case .attendance: [.attendance]
        case .work(let kind, _): [kind == "exam" ? .exams : kind == "evaluation" ? .evaluations : .tasks]
        case .resources: [.resources]
        }
    }
}

extension CampusScore {
    var percentage: Double? {
        guard type == "numeric", let earned, let possible, earned.isFinite, possible.isFinite, possible > 0 else { return nil }
        let result = earned / possible * 100
        return (0...100).contains(result) ? result : nil
    }
}

