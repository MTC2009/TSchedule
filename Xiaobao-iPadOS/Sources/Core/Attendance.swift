import Foundation

public struct SchoolDateRange: Equatable, Sendable {
    public let start: Date
    public let end: Date
    public init(start: Date, end: Date) {
        let a = SchoolClock.calendar.startOfDay(for: start)
        let b = SchoolClock.calendar.startOfDay(for: end)
        self.start = min(a, b); self.end = max(a, b)
    }
    public func contains(_ date: Date) -> Bool {
        let day = SchoolClock.calendar.startOfDay(for: date)
        return day >= start && day <= end
    }
    public func contains(_ other: Self) -> Bool { other.start >= start && other.end <= end }
}

public enum AttendanceCategory: String, CaseIterable, Identifiable, Sendable {
    case classroom, daily, activity
    public var id: String { rawValue }
    public var title: String { switch self { case .classroom: String(localized: "上课"); case .daily: String(localized: "日常"); case .activity: String(localized: "活动") } }
}

public enum AttendanceStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case present, late, early, absent
    public var id: String { rawValue }
    public var title: String { switch self { case .present: String(localized: "出勤"); case .late: String(localized: "迟到"); case .early: String(localized: "早退"); case .absent: String(localized: "缺勤") } }
}

public struct AttendanceCounts: Equatable, Sendable {
    public private(set) var present: Int
    public private(set) var late: Int
    public private(set) var early: Int
    public private(set) var absent: Int
    public init(present: Int = 0, late: Int = 0, early: Int = 0, absent: Int = 0) {
        precondition([present, late, early, absent].allSatisfy { $0 >= 0 })
        self.present = present; self.late = late; self.early = early; self.absent = absent
    }
    public var total: Int { present + late + early + absent }
    /// Match the supplied Schoolis screenshot: late is a separate category, not present.
    public var rate: Double? { total == 0 ? nil : Double(present) / Double(total) }
    public subscript(status: AttendanceStatus) -> Int {
        switch status { case .present: present; case .late: late; case .early: early; case .absent: absent }
    }
    public static func sum(_ values: [Self]) -> Self {
        values.reduce(into: Self()) { total, item in
            total.present += item.present
            total.late += item.late
            total.early += item.early
            total.absent += item.absent
        }
    }
    mutating func add(_ status: AttendanceStatus) {
        switch status {
        case .present: present += 1
        case .late: late += 1
        case .early: early += 1
        case .absent: absent += 1
        }
    }
    public static func counting(_ records: [AttendanceRecord]) -> Self {
        records.reduce(into: Self()) { $0.add($1.status) }
    }
}

public struct AttendanceCourseSummary: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let counts: AttendanceCounts
    public init(id: String, name: String, counts: AttendanceCounts) { self.id = id; self.name = name; self.counts = counts }
}

public struct AttendanceRecord: Identifiable, Sendable {
    public let id: String
    public let courseID: String
    public let date: Date
    public let status: AttendanceStatus
    public let note: String
    public init(id: String, courseID: String, date: Date, status: AttendanceStatus, note: String = "") {
        self.id = id; self.courseID = courseID; self.date = date; self.status = status; self.note = note
    }
}

public struct AttendanceReport: Sendable {
    public let category: AttendanceCategory
    public let range: SchoolDateRange
    public let courses: [AttendanceCourseSummary]
    /// nil means unavailable; an empty array means a verified empty set of records.
    public let records: [AttendanceRecord]?
    public let source: String
    public var totals: AttendanceCounts { .sum(courses.map(\.counts)) }
    public init(category: AttendanceCategory, range: SchoolDateRange, courses: [AttendanceCourseSummary],
                records: [AttendanceRecord]?, source: String) {
        self.category = category; self.range = range; self.courses = courses; self.records = records; self.source = source
    }
    public func filtered(category: AttendanceCategory, range: SchoolDateRange) -> Self? {
        guard category == self.category, self.range.contains(range) else { return nil }
        if range == self.range { return self }
        guard let records else { return nil }
        let until = SchoolClock.calendar.date(byAdding: .day, value: 1, to: range.end)!
        var matches: [AttendanceRecord] = []
        var counts: [String: AttendanceCounts] = [:]
        for row in records where range.start <= row.date && row.date < until {
            matches.append(row)
            counts[row.courseID, default: AttendanceCounts()].add(row.status)
        }
        let rows = courses.map { course in
            AttendanceCourseSummary(id: course.id, name: course.name,
                                    counts: counts[course.id] ?? AttendanceCounts())
        }
        return Self(category: category, range: range, courses: rows, records: matches, source: source)
    }

    // Synthetic aggregate only. No student records are bundled in the app.
    public static let demo = Self(
        category: .classroom,
        range: .init(start: SchoolClock.date(2026, 9, 1), end: SchoolClock.date(2027, 1, 22)),
        courses: [
            .init(id: "demo-botany", name: "植物观察", counts: .init(present: 31, late: 2, absent: 1)),
            .init(id: "demo-design", name: "工程设计", counts: .init(present: 22, early: 1, absent: 3)),
            .init(id: "demo-writing", name: "叙事写作", counts: .init(present: 17, absent: 1)),
            .init(id: "demo-astronomy", name: "天文选修", counts: .init(absent: 3))
        ], records: nil, source: "本学期 · 上课考勤汇总")
}

public enum AttendancePeriod: String, CaseIterable, Identifiable {
    case semester, month, lastMonth, week, today, custom
    public var id: String { rawValue }
    public var title: String {
        switch self { case .semester: String(localized: "本学期"); case .month: String(localized: "本月"); case .lastMonth: String(localized: "上月");
        case .week: String(localized: "本周"); case .today: String(localized: "今日"); case .custom: String(localized: "自定义") }
    }
    public func range(now: Date, semester: SchoolDateRange) -> SchoolDateRange? {
        let calendar = SchoolClock.calendar
        switch self {
        case .semester: return semester
        case .custom: return nil
        case .today: return SchoolDateRange(start: now, end: now)
        case .month, .lastMonth:
            let date = self == .lastMonth ? calendar.date(byAdding: .month, value: -1, to: now)! : now
            let interval = calendar.dateInterval(of: .month, for: date)!
            return SchoolDateRange(start: interval.start, end: calendar.date(byAdding: .day, value: -1, to: interval.end)!)
        case .week:
            let day = calendar.startOfDay(for: now)
            let mondayOffset = (calendar.component(.weekday, from: day) + 5) % 7
            let monday = calendar.date(byAdding: .day, value: -mondayOffset, to: day)!
            return SchoolDateRange(start: monday, end: calendar.date(byAdding: .day, value: 6, to: monday)!)
        }
    }
}
