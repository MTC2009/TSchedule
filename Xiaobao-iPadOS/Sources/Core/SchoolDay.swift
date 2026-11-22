import Foundation

public enum SchoolClock {
    public static let calendar: Calendar = {
        var value = Calendar(identifier: .gregorian)
        value.locale = Locale(identifier: "zh_CN")
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        value.firstWeekday = 2
        return value
    }()

    static func parseSchoolDate(_ key: String) -> Date? {
        let parts = key.split(separator: "-")
        guard parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              Self.key(date) == key else { return nil }
        return date
    }

    public static func date(_ year: Int, _ month: Int, _ day: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day,
                                          hour: minute / 60, minute: minute % 60))!
    }

    public static func minute(in date: Date) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    public static func at(minute: Int, on date: Date) -> Date {
        calendar.date(byAdding: .minute, value: minute, to: calendar.startOfDay(for: date))!
    }

    public static func key(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    public static func time(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }
}

public struct SchoolCalendar: Sendable {
    public let anchorDate: Date
    public let anchorDay: Int
    public let cycleLength: Int
    public let closures: Set<String>
    private let anchorMonday: Date
    private let anchorWeekday: Int
    private let closedWeekdays: [Date]
    private let closuresBeforeAnchor: Int
    private let publication: PublishedSchoolCalendar?

    public init(anchorDate: Date = SchoolClock.date(2026, 11, 17), anchorDay: Int = 4,
                cycleLength: Int = 6, closures: Set<String> = []) {
        self.init(anchorDate: anchorDate, anchorDay: anchorDay, cycleLength: cycleLength, closures: closures, publication: nil)
    }

    init(anchorDate: Date = SchoolClock.date(2026, 11, 17), anchorDay: Int = 4,
         cycleLength: Int = 6, closures: Set<String> = [], publication: PublishedSchoolCalendar?) {
        precondition(cycleLength > 0 && (1...cycleLength).contains(anchorDay))
        let calendar = SchoolClock.calendar
        let anchor = calendar.startOfDay(for: anchorDate)
        let weekday = (calendar.component(.weekday, from: anchor) + 5) % 7
        precondition(weekday < 5 && !closures.contains(SchoolClock.key(anchor)), "The rotation anchor must be a school day")
        self.anchorDate = anchor
        self.anchorDay = anchorDay
        self.cycleLength = cycleLength
        self.closures = closures
        self.publication = publication
        anchorWeekday = weekday
        anchorMonday = calendar.date(byAdding: .day, value: -weekday, to: anchor)!
        closedWeekdays = closures.compactMap(SchoolClock.parseSchoolDate).filter { !calendar.isDateInWeekend($0) }.sorted()
        closuresBeforeAnchor = closedWeekdays.prefix { $0 < anchor }.count
    }

    public func isSchoolDay(_ date: Date) -> Bool {
        rotationDay(on: date) != nil
    }

    public func rotationDay(on date: Date) -> Int? {
        if let publication { return publication.day(on: date).teachingDay }
        let target = SchoolClock.calendar.startOfDay(for: date)
        let days = SchoolClock.calendar.dateComponents([.day], from: anchorMonday, to: target).day!
        let weekday = (days % 7 + 7) % 7
        guard weekday < 5 else { return nil }
        var low = 0, high = closedWeekdays.count
        while low < high {
            let mid = low + (high - low) / 2
            if closedWeekdays[mid] < target { low = mid + 1 } else { high = mid }
        }
        guard low == closedWeekdays.count || closedWeekdays[low] != target else { return nil }
        // Both endpoints are school days. Count whole weeks and subtract intervening weekday closures.
        let distance = (days - weekday) / 7 * 5 + weekday - anchorWeekday - (low - closuresBeforeAnchor)
        let index = (anchorDay - 1 + distance) % cycleLength
        return (index < 0 ? index + cycleLength : index) + 1
    }

    func publishedDay(on date: Date) -> SchoolCalendarDay? { publication?.day(on: date) }
}

public struct Course: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let shortName: String
    public let room: String
    public let teacher: String
    /// Kept for source compatibility; the timetable does not provide classroom instructions.
    public let note: String = ""
    public let score: Double
    public let advanced: Bool
}

public struct Lesson: Identifiable, Hashable, Sendable {
    public let course: Course
    public let date: Date
    public let day: Int
    public let startMinute: Int
    public let endMinute: Int
    public var id: String { SchoolClock.key(date) + "." + course.id }
    public var start: Date { SchoolClock.at(minute: startMinute, on: date) }
    public var end: Date { SchoolClock.at(minute: endMinute, on: date) }
    public var timeLabel: String { SchoolClock.time(startMinute) + " – " + SchoolClock.time(endMinute) }
}

/// Optional source display labels. These never affect a bell or the identity
/// of a roster, and the archive can still decode periods saved without them.
struct TimetableLessonMetadata: Codable, Equatable, Sendable {
    var grade: String? = nil
    var className: String? = nil
    var teacher: String? = nil
    var note: String? = nil

    static func agreement(_ values: [Self?], combineHalves: Bool = false) -> Self? {
        func same(_ field: KeyPath<Self, String?>) -> String? {
            let present = values.compactMap { $0?[keyPath: field] }
            guard combineHalves || present.count == values.count, let first = present.first,
                  present.allSatisfy({ $0 == first }) else { return nil }
            return first
        }
        let result = Self(grade: same(\.grade), className: same(\.className), teacher: same(\.teacher),
                          note: combineHalves ? same(\.note) : nil)
        return result.grade == nil && result.className == nil && result.teacher == nil && result.note == nil ? nil : result
    }
}

/// Minutes since school midnight, as published in the school's bell schedule.
struct TeachingSlot: Codable, Hashable, Sendable {
    let start, end: Int
}

/// The bundled campus day, independent of a student's subject assignments.
/// The opening double period is uninterrupted. Unlisted gaps are not teaching slots.
enum CampusBells {
    /// Confirmed profile of this publication; a calendar for another school, division or
    /// year is not evidence that its students use these bells.
    static func applies(to calendar: PublishedSchoolCalendar) -> Bool {
        calendar.campus == "main" && calendar.division == "HS" && calendar.academicYear == "2026-2027"
    }

    static let openingDouble = TeachingSlot(start: 480, end: 560)
    static let openingHalves: (first: TeachingSlot, second: TeachingSlot) = {
        let middle = (openingDouble.start + openingDouble.end) / 2
        return (.init(start: openingDouble.start, end: middle), .init(start: middle, end: openingDouble.end))
    }()
    static let beforeLunch = TeachingSlot(start: 710, end: 750)
    static let dismissal = 15 * 60 + 45
    static let teachingGroups: [[TeachingSlot]] = [
        [openingDouble], [.init(start: 610, end: 650), .init(start: 660, end: 700)],
        [beforeLunch, .init(start: 805, end: 845)], [.init(start: 855, end: 895), .init(start: 905, end: dismissal)]
    ]
    static let teachingSlots = teachingGroups.flatMap { $0 }
    static func isTeachingPeriod(start: Int, end: Int) -> Bool {
        let slot = TeachingSlot(start: start, end: end)
        return teachingSlots.contains(slot) || slot == openingHalves.first || slot == openingHalves.second
    }

    /// Campus-wide time, not an enrollment or an empty instructional slot.
    enum Activity: CaseIterable, Hashable {
        case assembly, lunch
        var minutes: Range<Int> {
            switch self {
            case .assembly: (9 * 60 + 30)..<(10 * 60 + 10)
            case .lunch: (12 * 60 + 30)..<(13 * 60 + 25)
            }
        }
        var title: String { switch self { case .assembly: String(localized: "班会"); case .lunch: String(localized: "午餐") } }
        var detailTitle: String { self == .assembly ? String(localized: "班会／集会") : title }
        var location: String { switch self { case .assembly: String(localized: "班级教室／剧场"); case .lunch: String(localized: "食堂") } }
    }

    /// Breaks are the gaps in the campus bell schedule, not in a student's enrollment.
    static let recessMinutes: [Range<Int>] = {
        let occupied = (teachingSlots.map { $0.start..<$0.end } + Activity.allCases.map(\.minutes))
            .sorted { $0.lowerBound < $1.lowerBound }
        return zip(occupied, occupied.dropFirst()).compactMap { earlier, later in
            guard earlier.upperBound < later.lowerBound else { return nil }
            return earlier.upperBound..<later.lowerBound
        }
    }()
}

/// Read-only periods for the native Today timeline. Both the tiles and the focus card
/// use these same intervals; neither infers lessons from visible labels.
struct LessonTimeline {
    struct Period: Identifiable {
        let id, name, shortName: String
        let room: String?
        let start, end: Date
        var metadata: TimetableLessonMetadata? = nil

    }

    enum Block: Identifiable {
        case lesson(Period)
        case freeblock(DateInterval)
        case activity(CampusBells.Activity, DateInterval)
        /// Locally displayed routine or personal course, with no portal lesson/detail ID.
        case reference(Period, isCourse: Bool)

        enum ID: Hashable { case lesson(String), freeblock(Date), activity(CampusBells.Activity, Date), reference(String) }
        var id: ID {
            switch self {
            case .lesson(let p): .lesson(p.id)
            case .freeblock(let i): .freeblock(i.start)
            case .activity(let kind, let i): .activity(kind, i.start)
            case .reference(let p, _): .reference(p.id)
            }
        }
        var title: String {
            switch self { case .lesson(let p), .reference(let p, _): p.name; case .freeblock: String(localized: "空节"); case .activity(let kind, _): kind.title }
        }
        var location: String? {
            switch self {
            case .lesson(let period), .reference(let period, _): period.room
            case .activity(let kind, _): kind.location
            case .freeblock: nil
            }
        }
        var metadata: TimetableLessonMetadata? { lesson?.metadata }
        var lesson: Period? { if case .lesson(let p) = self { p } else { nil } }
        var start: Date { switch self { case .lesson(let p), .reference(let p, _): p.start; case .freeblock(let i), .activity(_, let i): i.start } }
        var end: Date { switch self { case .lesson(let p), .reference(let p, _): p.end; case .freeblock(let i), .activity(_, let i): i.end } }
        var isCourse: Bool { switch self { case .lesson, .reference(_, true): true; default: false } }

        /// Time elapsed, not academic completion. A live clock and a scrub in either
        /// direction use the same half-open interval, regardless of the block's kind.
        func elapsedFraction(at instant: Date) -> Double {
            guard end > start, instant > start else { return 0 }
            guard instant < end else { return 1 }
            return instant.timeIntervalSince(start) / end.timeIntervalSince(start)
        }
    }

    let blocks: [Block]
    /// Used by the focus card only. Recesses stay in the timeline's existing gutters.
    let recesses: [DateInterval]
    let dayStart: Date
    let bounds: ClosedRange<Int>?

    init?(on date: Date, periods: [Period], teachingSlots: [TeachingSlot]? = nil, includesCampusActivities: Bool = false,
          fixedCampusActivities: Bool = false) {
        let start = SchoolClock.calendar.startOfDay(for: date)
        guard let tomorrow = SchoolClock.calendar.date(byAdding: .day, value: 1, to: start),
              periods.allSatisfy({ $0.start >= start && $0.start < $0.end && $0.end <= tomorrow }) else { return nil }
        let lessons = periods.sorted { $0.start < $1.start }
        let vacancies = Self.freeblocks(on: start, lessons: lessons, slots: teachingSlots)
        let instruction = vacancies.isEmpty ? lessons.map(Block.lesson)
            : (lessons.map(Block.lesson) + vacancies).sorted { $0.start < $1.start }
        let resolved = includesCampusActivities ? Self.addingCampusActivities(to: instruction, on: start, fixed: fixedCampusActivities) : instruction
        self.init(on: start, resolved: resolved, includesRecesses: includesCampusActivities)
    }

    /// A visibility change cannot create a new vacant slot. Only the original
    /// bell/roster initializer is allowed to derive vacancies and campus activities.
    init(on date: Date, resolved: [Block], includesRecesses: Bool) {
        let start = SchoolClock.calendar.startOfDay(for: date)
        dayStart = start
        blocks = resolved.sorted { $0.start < $1.start }
        recesses = includesRecesses ? Self.recesses(between: blocks, on: start) : []
        if let first = blocks.first, let lastEnd = blocks.map(\.end).max() {
            // Round only the drawing area to half hours. School instants remain exact.
            let lower = Int(floor(first.start.timeIntervalSince(start) / 1800)) * 30
            let upper = Int(ceil(lastEnd.timeIntervalSince(start) / 1800)) * 30
            bounds = lower...upper
        } else { bounds = nil }
    }

    private static func recesses(between blocks: [Block], on day: Date) -> [DateInterval] {
        guard let first = blocks.first else { return [] }
        let bells = CampusBells.recessMinutes.map { range in
            DateInterval(start: SchoolClock.at(minute: range.lowerBound, on: day),
                         end: SchoolClock.at(minute: range.upperBound, on: day))
        }
        var coveredUntil = first.end
        var recesses: [DateInterval] = []
        for block in blocks.dropFirst() {
            // Two resolved blocks must bound the gap and the whole gap must be a
            // known recess. Old or incomplete timetables can also have open gaps.
            if coveredUntil < block.start,
               bells.contains(where: { $0.start <= coveredUntil && block.start <= $0.end }) {
                recesses.append(DateInterval(start: coveredUntil, end: block.start))
            }
            coveredUntil = max(coveredUntil, block.end)
        }
        return recesses
    }

    private static func addingCampusActivities(to instruction: [Block], on day: Date, fixed: Bool) -> [Block] {
        // The published campus bells do not depend on individual enrollment. An
        // independent appointment can overlap lunch without shortening lunch for everyone.
        if fixed {
            let activities = CampusBells.Activity.allCases.map { kind in
                Block.activity(kind, .init(start: SchoolClock.at(minute: kind.minutes.lowerBound, on: day),
                                           end: SchoolClock.at(minute: kind.minutes.upperBound, on: day)))
            }
            return (instruction + activities).sorted { $0.start < $1.start }
        }
        guard let first = instruction.first, let lastEnd = instruction.map(\.end).max() else { return instruction }
        var result = instruction
        for kind in CampusBells.Activity.allCases {
            let start = SchoolClock.at(minute: kind.minutes.lowerBound, on: day)
            let end = SchoolClock.at(minute: kind.minutes.upperBound, on: day)
            // Never lengthen a shortened day or synthesize an activity on missing data.
            guard first.start <= start, lastEnd >= end else { continue }
            result.removeAll { block in
                if case .freeblock = block { return block.start < end && block.end > start }
                return false
            }
            // A published subject takes precedence. Only the unoccupied parts of this
            // activity are drawn; never split a stale vacant bell into partial Freeblocks.
            var cursor = start
            for block in instruction {
                if block.start >= end || cursor >= end { break }
                guard block.lesson != nil, block.end > cursor else { continue }
                if cursor < block.start { result.append(.activity(kind, DateInterval(start: cursor, end: block.start))) }
                cursor = max(cursor, block.end)
            }
            if cursor < end { result.append(.activity(kind, DateInterval(start: cursor, end: end))) }
        }
        return result.sorted { $0.start < $1.start }
    }

    /// An unoccupied whole teaching slot is not the same as a gap between lessons.
    /// Reject the optional slot table as a unit if it is inconsistent; keep real lessons.
    private static func freeblocks(on date: Date, lessons: [Period], slots: [TeachingSlot]?) -> [Block] {
        guard let slots, !slots.isEmpty, slots.count <= 1440 else { return [] }
        let ordered = slots.sorted { $0.start < $1.start }
        guard ordered.allSatisfy({ 0 <= $0.start && $0.start < $0.end && $0.end <= 1440 }),
              zip(ordered, ordered.dropFirst()).allSatisfy({ $0.0.end <= $0.1.start }) else { return [] }
        var index = 0
        return ordered.compactMap { slot in
            let start = SchoolClock.at(minute: slot.start, on: date)
            let end = SchoolClock.at(minute: slot.end, on: date)
            while index < lessons.count && lessons[index].end <= start { index += 1 }
            guard index == lessons.count || lessons[index].start >= end else { return nil }
            return .freeblock(DateInterval(start: start, end: end))
        }
    }

    func focus(at instant: Date) -> Block? {
        // A dated class can legitimately overlap the fixed campus lunch. Keep both
        // on the timeline, but surface the student's actual lesson while it is running.
        blocks.first { $0.isCourse && $0.start <= instant && instant < $0.end }
            ?? blocks.first { instant < $0.end }
    }
    func recess(at instant: Date) -> DateInterval? { recesses.first { $0.start <= instant && instant < $0.end } }

    /// A class meeting starts instruction, but a vacant teaching period does not.
    func nextInstructionStart(from earliest: Date) -> Date? {
        blocks.first { block in
            guard block.start >= earliest else { return false }
            switch block {
            case .lesson, .activity(.assembly, _), .reference(_, true): return true
            case .freeblock, .activity(.lunch, _), .reference(_, false): return false
            }
        }?.start
    }

    func minute(of instant: Date) -> Double { instant.timeIntervalSince(dayStart) / 60 }
}

extension LessonTimeline.Period {
    init(_ lesson: Lesson) {
        self.init(id: lesson.id, name: lesson.course.name, shortName: lesson.course.shortName,
                  room: lesson.course.room, start: lesson.start, end: lesson.end,
                  metadata: .init(teacher: lesson.course.teacher))
    }
}

public protocol SchoolScheduleProviding: Sendable {
    func lessons(on date: Date) -> [Lesson]
    func day(on date: Date) -> Int?
}

public struct DemoSchoolProvider: SchoolScheduleProviding {
    /// The timetable and in-class work fixtures must use the same publication.
    static let local = DemoSchoolProvider(schoolCalendar: .init(publication: PublishedSchoolCalendar.bundledHS))

    public let schoolCalendar: SchoolCalendar
    public init(schoolCalendar: SchoolCalendar = SchoolCalendar()) { self.schoolCalendar = schoolCalendar }

    public static let courses: [Course] = [
        Course(id: "english", name: "English Literature", shortName: "英文", room: "A205", teacher: "Ms. Morgan", score: 91, advanced: false),
        Course(id: "math", name: "AP Calculus AB", shortName: "微积分", room: "A301", teacher: "Mr. Chen", score: 92, advanced: true),
        Course(id: "physics", name: "AP Physics 1", shortName: "物理", room: "B302", teacher: "Mr. Wang", score: 88, advanced: true),
        Course(id: "chinese", name: "Chinese Literature", shortName: "中文", room: "A202", teacher: "刘老师", score: 88, advanced: false),
        Course(id: "economics", name: "AP Microeconomics", shortName: "经济", room: "B206", teacher: "Ms. Lee", score: 94, advanced: true),
        Course(id: "pe", name: "Physical Education", shortName: "体育", room: "体育馆", teacher: "张老师", score: 97, advanced: false)
    ]

    public func day(on date: Date) -> Int? { schoolCalendar.rotationDay(on: date) }

    func timeline(on date: Date, lessons: [Lesson]) -> LessonTimeline? {
        if lessons.isEmpty, schoolCalendar.publishedDay(on: date)?.status == .unpublished { return nil }
        let schoolDay = day(on: date) != nil
        return LessonTimeline(on: date, periods: lessons.map(LessonTimeline.Period.init),
                              teachingSlots: schoolDay ? CampusBells.teachingSlots : nil, includesCampusActivities: schoolDay)
    }

    public func lessons(on date: Date) -> [Lesson] {
        guard let day = day(on: date) else { return [] }
        let shift = (day - 4 + 6) % 6
        // Six existing assignments in their original rotation; bells alone never assign a subject.
        return zip(Self.courses.indices, CampusBells.teachingSlots).map { index, period in
            Lesson(course: Self.courses[(index + shift) % Self.courses.count],
                   date: SchoolClock.calendar.startOfDay(for: date), day: day,
                   startMinute: period.start, endMinute: period.end)
        }
    }
}

public struct Agenda: Sendable {
    public enum Status: Equatable, Sendable { case freeDay, beforeSchool, teaching, recess, assembly, lunch, finished }
    public let status: Status
    public let focus: Lesson?
    public let upcoming: [Lesson]
    public let remainingMinutes: Int

    public init(lessons: [Lesson], minute: Int) {
        let sorted = lessons.sorted { $0.startMinute < $1.startMinute }
        if let current = sorted.first(where: { $0.startMinute <= minute && minute < $0.endMinute }) {
            status = .teaching; focus = current
            upcoming = sorted.filter { $0.startMinute > current.startMinute }
            remainingMinutes = current.endMinute - minute
        } else if let next = sorted.first(where: { $0.startMinute > minute }) {
            focus = next; upcoming = sorted.filter { $0.startMinute > next.startMinute }
            remainingMinutes = next.startMinute - minute
            if minute < (sorted.first?.startMinute ?? 480) { status = .beforeSchool }
            else if CampusBells.Activity.assembly.minutes.contains(minute) { status = .assembly }
            else if CampusBells.Activity.lunch.minutes.contains(minute) { status = .lunch }
            else { status = .recess }
        } else {
            status = sorted.isEmpty ? .freeDay : .finished
            focus = nil; upcoming = []; remainingMinutes = 0
        }
    }

    public var label: String {
        switch status {
        case .freeDay: String(localized: "今天没有课程")
        case .beforeSchool: String(localized: "还有 \(remainingMinutes) 分钟，开始今天")
        case .teaching: String(localized: "上课中 · \(remainingMinutes) 分钟后下课")
        case .recess: String(localized: "课间 · \(remainingMinutes) 分钟后上课")
        case .assembly: String(localized: "\(CampusBells.Activity.assembly.title) · \(remainingMinutes) 分钟后上课")
        case .lunch: String(localized: "午餐 · \(remainingMinutes) 分钟后上课")
        case .finished: String(localized: "今天的课都结束了")
        }
    }
}
