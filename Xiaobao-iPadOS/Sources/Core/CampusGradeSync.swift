import Foundation

enum CampusUpdatePolicy: String, Codable, CaseIterable, Sendable {
    case manual, onOpen, everyTwoDays, background

    var title: String {
        switch self {
        case .manual: String(localized: "仅手动")
        case .onOpen: String(localized: "每次打开 App")
        case .everyTwoDays: String(localized: "每两天打开时")
        case .background: String(localized: "允许后台检查（约两天）")
        }
    }

    func isDue(lastChecked: Date?, now: Date) -> Bool {
        switch self {
        case .manual: false
        case .onOpen: true
        case .everyTwoDays, .background: lastChecked.map { now.timeIntervalSince($0) >= 48 * 3600 || now < $0 } ?? true
        }
    }
}

struct CampusCourseVersion: Codable, Sendable {
    let course_id, name, revision: String
}

struct SavedCampusGrades: Codable, Sendable {
    // Version 2 also preserves the optional class and first-publication fields.
    static let currentMetadataVersion = 2
    let grades: CampusGrades
    let roster: [CampusCourseVersion]
    let version: String?
    let updated: Date
    var checked: Date
    var metadataVersion: Int? = nil

    // Older full-page caches have no revision. The first permitted check establishes one.
    private var known: [String: String] {
        var values: [String: String] = [:]
        if version != nil { for course in roster { values[course.course_id] = course.revision } }
        return values
    }

    var isComplete: Bool {
        let ids = grades.courses.map(\.course_id)
        guard ids == roster.map(\.course_id), Set(ids).count == ids.count else { return false }
        return version == nil || (version?.isEmpty == false && roster.allSatisfy { !$0.revision.isEmpty })
    }

    func cursor() throws -> Data {
        // Old typed caches discarded optional metadata even for unchanged course revisions.
        guard metadataVersion == Self.currentMetadataVersion else { return Data("{}".utf8) }
        struct Cursor: Encodable { let version: String?; let known: [String: String]? }
        let encoder = JSONEncoder()
        let data = try encoder.encode(Cursor(version: version, known: known))
        // A larger roster can still use its book version within the service's 8 KiB body limit.
        if data.count > 8 * 1024 { return try encoder.encode(Cursor(version: version, known: nil)) }
        return data
    }
}

struct CampusGradeChanges: Codable, Sendable {
    let version, term: String
    let published_gpa: Double?
    let courses: [CampusCourseVersion]
    let changed: [CampusGrade]
    var gpa_scale: [CampusGPAScaleBand]? = nil

    func applying(to previous: SavedCampusGrades?, at time: Date) throws -> SavedCampusGrades {
        var changes: [String: CampusGrade] = [:]
        for row in changed {
            guard changes.updateValue(row, forKey: row.course_id) == nil else { throw CampusError.invalidResponse }
        }
        var retained: [String: (String, CampusGrade)] = [:]
        if let previous, previous.grades.term == term, previous.version != nil,
           previous.metadataVersion == SavedCampusGrades.currentMetadataVersion {
            for (stamp, row) in zip(previous.roster, previous.grades.courses) {
                retained[stamp.course_id] = (stamp.revision, row)
            }
        }
        let rows = try courses.map { stamp -> CampusGrade in
            if let row = changes.removeValue(forKey: stamp.course_id) { return row }
            guard let (revision, row) = retained[stamp.course_id], revision == stamp.revision else {
                throw CampusError.invalidResponse
            }
            return row
        }
        let updated = previous.flatMap { $0.version == version && $0.grades.term == term ? $0.updated : nil } ?? time
        // Do not reuse an older rule if this snapshot omits it.
        let book = CampusGrades(term: term, published_gpa: published_gpa, courses: rows, gpa_scale: gpa_scale)
        let saved = SavedCampusGrades(grades: book,
                                      roster: courses, version: version, updated: updated, checked: time,
                                      metadataVersion: SavedCampusGrades.currentMetadataVersion)
        guard !term.isEmpty, changes.isEmpty, saved.isComplete else { throw CampusError.invalidResponse }
        return saved
    }
}
