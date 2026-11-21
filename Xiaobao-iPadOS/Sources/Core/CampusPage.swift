import Foundation

enum CampusPage: Hashable, Sendable {
    case courses, schedule(String), calendar(String, String), grades, attendance, work(String, offset: Int = 0), resources(offset: Int = 0)

    var route: String {
        switch self {
        case .courses: "courses"
        case .schedule(let date): "schedule?date=\(date)"
        case .calendar(let from, let to): "calendar?from=\(from)&to=\(to)"
        case .grades: "grades"
        case .attendance: "attendance"
        case .work(let kind, let offset): "work?kind=\(kind)&offset=\(offset)"
        case .resources(let offset): "resources?offset=\(offset)"
        }
    }

    func decode(_ body: Data) throws -> CampusContent {
        let json = JSONDecoder()
        func read<T: Decodable>(_ type: T.Type) throws -> T { try json.decode(CampusEnvelope<T>.self, from: body).data }
        switch self {
        case .courses: return .courses(try read([CampusCourse].self))
        case .schedule: return .schedule(try read(CampusSchedule.self))
        case .calendar: return .calendar(try read(CampusCalendar.self))
        case .grades: return .grades(try read(CampusGrades.self))
        case .attendance: return .attendance(try read(CampusAttendance?.self))
        case .work: return .work(try read(CampusList<CampusWork>.self))
        case .resources: return .resources(try read(CampusList<CampusResource>.self))
        }
    }
}

struct CampusEnvelope<T: Decodable>: Decodable { let data: T }
struct CampusList<T: Decodable & Sendable>: Decodable, Sendable {
    let items: [T]
    let total, offset, limit: Int
    var current_term: String? = nil
    var available_terms: [String]? = nil
}
struct CampusCourse: Codable, Identifiable, Sendable { let id, name: String; let teacher, room: String? }
struct CampusLesson: Codable, Identifiable, Sendable { let id, course_id, start, end: String; let room: String? }
struct CampusSchedule: Decodable, Sendable {
    let date: String
    let day: Int?
    let lessons: [CampusLesson]
    let teaching_slots: [TeachingSlot]?
    let calendarDay: SchoolCalendarDay?

    init(date: String, day: Int?, lessons: [CampusLesson], teaching_slots: [TeachingSlot]? = nil,
         calendarDay: SchoolCalendarDay? = nil) {
        self.date = date; self.day = day; self.lessons = lessons; self.teaching_slots = teaching_slots
        self.calendarDay = calendarDay.flatMap { $0.date == date && $0.isValid(cycleLength: 255) ? $0 : nil }
    }
    private enum CodingKeys: String, CodingKey {
        case date, day, lessons, teaching_slots
        case calendarDay = "calendar_day"
    }
    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(date: box.decode(String.self, forKey: .date), day: box.decodeIfPresent(Int.self, forKey: .day),
                      lessons: box.decode([CampusLesson].self, forKey: .lessons),
                      teaching_slots: try? box.decode([TeachingSlot].self, forKey: .teaching_slots),
                      calendarDay: try? box.decode(SchoolCalendarDay.self, forKey: .calendarDay))
    }

    func timeline(courseName: (String) -> String) -> LessonTimeline? {
        guard let dayStart = SchoolClock.dayDate(date) else { return nil }
        if lessons.isEmpty, calendarDay?.status == .unpublished { return nil }
        let periods: [LessonTimeline.Period] = lessons.compactMap { lesson in
            guard let start = campusInstant(lesson.start), let end = campusInstant(lesson.end) else { return nil }
            let title = courseName(lesson.course_id)
            return .init(id: lesson.id, name: title, shortName: title, room: lesson.room, start: start, end: end)
        }
        guard periods.count == lessons.count else { return nil } // An invalid read is not a free day.
        let schoolDay = calendarDay.map { $0.status == .teaching } ?? (day != nil)
        return LessonTimeline(on: dayStart, periods: periods, teachingSlots: schoolDay ? teaching_slots : nil,
                              includesCampusActivities: schoolDay)
    }
}
struct CampusEvent: Codable, Identifiable, Sendable { let id, title, start: String; let end, kind: String?; let all_day: Bool? }
struct CampusCalendar: Decodable, Sendable { let lessons: [CampusLesson]; let events: [CampusEvent]; let deadlines: [CampusWork] }
struct CampusScore: Codable, Equatable, Sendable { let type: String; let earned, possible: Double?; let value: String? }
struct CampusAssessment: Codable, Identifiable, Sendable {
    let id, title, status: String
    let date, feedback: String?
    let score: CampusScore?
    var weight: Double? = nil
}
struct CampusGrade: Codable, Sendable {
    let course_id: String
    let published_score: CampusScore?
    let published_gpa: Double?
    let assessments: [CampusAssessment]
    var published_letter_grade: String? = nil
    var class_name: String? = nil
    var first_published_at: String? = nil
    var gpa_credits: Double? = nil
}
struct CampusGrades: Codable, Sendable {
    let term: String
    let published_gpa: Double?
    let courses: [CampusGrade]
    var gpa_scale: [CampusGPAScaleBand]? = nil
}
struct CampusCounts: Decodable, Sendable { let present, late, early, absent, total: Int; let present_rate: Double? }
struct CampusCourseAttendance: Decodable, Sendable { let course_id: String; let summary: CampusCounts }
struct CampusAttendance: Decodable, Sendable { let totals: CampusCounts; let by_course: [CampusCourseAttendance] }
struct CampusWork: Codable, Identifiable, Sendable {
    let id, title, due_at, status, description: String
    let course_id, kind: String?
    var term: String? = nil
    var work_type: String? = nil
    var published_at: String? = nil
    var task: CampusTaskDetails? = nil
    var exam: CampusExamInfo? = nil
}
struct CampusExamInfo: Codable, Sendable {
    struct Result: Codable, Sendable { let course_id: String }
    let start, end: String?
    // The school result identifies other courses for the filter. Scores stay out of this view.
    let results: [Result]?
}
struct CampusResource: Codable, Identifiable, Sendable {
    let id, title, content: String
    let scope, kind: String?
    var shared_at: String? = nil
}
enum CampusContent: Sendable {
    case courses([CampusCourse]), schedule(CampusSchedule), calendar(CampusCalendar), grades(CampusGrades)
    case attendance(CampusAttendance?), work(CampusList<CampusWork>), resources(CampusList<CampusResource>)
}

struct CachedCampusPage: Codable, Sendable {
    let body: Data
    let tag: String?
    let checked: Date
    let ttl: TimeInterval

    func fresh(at now: Date) -> Bool {
        let age = now.timeIntervalSince(checked)
        return age >= 0 && age < ttl
    }
}

actor CampusDiskCache {
    static let maxPages = 32
    static let maxBody = 512 * 1024
    private let folder: URL
    private let gradeFile: URL
    private var closed = false

    init(root: URL, scope: UUID, gradeRoot: URL? = nil) {
        folder = root.appendingPathComponent(scope.uuidString, isDirectory: true)
        gradeFile = (gradeRoot ?? root).appendingPathComponent(scope.uuidString).appendingPathExtension("grades")
    }

    private var writeOptions: Data.WritingOptions {
        #if os(iOS)
        [.atomic, .completeFileProtection]
        #else
        .atomic
        #endif
    }

    private var offlineFile: URL { gradeFile.deletingPathExtension().appendingPathExtension("offline") }
    private var checkFile: URL { gradeFile.deletingPathExtension().appendingPathExtension("checked") }

    func readOffline() throws -> CampusOfflineState? {
        guard !closed, FileManager.default.fileExists(atPath: offlineFile.path) else { return nil }
        let bytes = try Data(contentsOf: offlineFile)
        guard var saved = try? PropertyListDecoder().decode(CampusOfflineState.self, from: bytes) else { return nil }
        if let bytes = try? Data(contentsOf: checkFile),
           let stamp = try? PropertyListDecoder().decode(OfflineCheck.self, from: bytes),
           stamp.generation == saved.check.generation { saved.check = stamp }
        return saved
    }

    func saveOffline(_ state: CampusOfflineState, changed: Bool, background: Bool) throws {
        guard !closed else { throw CampusError.changed }
        let manager = FileManager.default
        var directory = offlineFile.deletingLastPathComponent()
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        var options: Data.WritingOptions = .atomic
        #if os(iOS)
        var flags = URLResourceValues()
        flags.isExcludedFromBackup = true
        try directory.setResourceValues(flags)
        options.insert(background ? .completeFileProtectionUntilFirstUserAuthentication : .completeFileProtection)
        #endif
        if changed || !manager.fileExists(atPath: offlineFile.path) {
            try PropertyListEncoder().encode(state).write(to: offlineFile, options: options)
        } else {
            try PropertyListEncoder().encode(state.check).write(to: checkFile, options: options)
        }
    }

    func setBackgroundProtection(_ enabled: Bool) throws {
        #if os(iOS)
        guard !closed else { return }
        for file in [offlineFile, checkFile] where FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.setAttributes([.protectionKey: enabled ? FileProtectionType.completeUntilFirstUserAuthentication : .complete], ofItemAtPath: file.path)
        }
        #endif
    }

    func readGrades() -> SavedCampusGrades? {
        guard !closed else { return nil }
        if let bytes = try? Data(contentsOf: gradeFile),
           let value = try? PropertyListDecoder().decode(SavedCampusGrades.self, from: bytes), value.isComplete {
            return value
        }
        // Upgrade an existing account's private page on device, including its available course names.
        guard let old = read(.grades),
              case let .grades(grades)? = try? CampusPage.grades.decode(old.body) else { return nil }
        var names: [String: String] = [:]
        if let directory = read(.courses),
           case let .courses(rows)? = try? CampusPage.courses.decode(directory.body) {
            for row in rows { names[row.id] = row.name }
        }
        let roster = grades.courses.map { CampusCourseVersion(course_id: $0.course_id, name: names[$0.course_id] ?? $0.course_id, revision: "") }
        let saved = SavedCampusGrades(grades: grades, roster: roster, version: nil, updated: old.checked, checked: old.checked)
        guard saved.isComplete else { return nil }
        try? writeGrades(saved)
        return saved
    }

    func writeGrades(_ value: SavedCampusGrades) throws {
        guard !closed else { return }
        var directory = gradeFile.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #if os(iOS)
        var flags = URLResourceValues()
        flags.isExcludedFromBackup = true
        try directory.setResourceValues(flags)
        #endif
        try PropertyListEncoder().encode(value).write(to: gradeFile, options: writeOptions)
        remove(.grades)
    }

    func removeGrades() {
        try? FileManager.default.removeItem(at: gradeFile)
        remove(.grades)
    }
    private func file(_ page: CampusPage) -> URL {
        let name = Data(page.route.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_")
        return folder.appendingPathComponent(name).appendingPathExtension("plist")
    }
    func read(_ page: CampusPage) -> CachedCampusPage? {
        guard !closed else { return nil }
        let path = file(page)
        guard let bytes = try? Data(contentsOf: path),
              let entry = try? PropertyListDecoder().decode(CachedCampusPage.self, from: bytes),
              entry.body.count <= Self.maxBody else {
            try? FileManager.default.removeItem(at: path)
            return nil
        }
        return entry
    }
    func write(_ entry: CachedCampusPage, for page: CampusPage) {
        guard !closed else { return }
        guard entry.body.count <= Self.maxBody else { remove(page); return }
        do {
            let fm = FileManager.default
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            try PropertyListEncoder().encode(entry).write(to: file(page), options: writeOptions)
            let files = try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])
            if files.count > Self.maxPages {
                let oldest = files.sorted {
                    (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast <
                    (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                }
                for url in oldest.prefix(files.count - Self.maxPages) { try? fm.removeItem(at: url) }
            }
        } catch { /* Disk cache is optional; the in-memory response remains usable. */ }
    }
    func remove(_ page: CampusPage) { try? FileManager.default.removeItem(at: file(page)) }
    func removeLegacyPages() { try? FileManager.default.removeItem(at: folder) }

    func clearData() {
        try? FileManager.default.removeItem(at: offlineFile)
        try? FileManager.default.removeItem(at: checkFile)
        removeGrades()
        removeLegacyPages()
    }

    func clear() { closed = true; clearData() }
}
