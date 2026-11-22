import Foundation
import Observation

/// A random revocable device registration, not a login grant. Generated filenames never
/// contain a student, semester or task identifier. Only a complete verified read may commit.
@MainActor @Observable final class SchoolAssignmentStore {
    struct Term: Codable {
        let label: SchoolPortalTerms.Term
        let fileID: UUID
        let checked: Date
    }
    private struct Index: Codable {
        let version: Int, registration: UUID, owner: String
        var current: String?, terms: [String: Term] = [:]
        var reminders = false, showTitles = false
    }
    private enum Key {
        static let registration = "tschedule.assignments.v1.registration"
        static let review = "tschedule.assignments.v1.review"
    }
    private let directory: URL, defaults: UserDefaults
    private var index: Index?
    @ObservationIgnored private var contents: [UUID: [SavedAssignment]] = [:]
    private(set) var reviewing: Bool
    private(set) var writeFailed = false
    var owner: String? { index?.owner }
    var hasRegistration: Bool { index != nil || defaults.string(forKey: Key.registration) != nil }
    var registration: UUID? { reviewing ? nil : index?.registration }
    var current: String? { reviewing ? nil : index?.current }
    var terms: [String: Term] { reviewing ? [:] : index?.terms ?? [:] }
    var enabled: Bool { !reviewing && index?.reminders == true }
    var showsTitles: Bool { enabled && index?.showTitles == true }

    init(directory: URL, defaults: UserDefaults = .standard) {
        self.directory = directory; self.defaults = defaults
        reviewing = defaults.bool(forKey: Key.review)
        restore()
    }

    private var manifest: URL { directory.appendingPathComponent("index.plist") }
    private func file(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + ".plist") }

    func restore() {
        guard index == nil else { return }
        guard let id = defaults.string(forKey: Key.registration) else { prune(keeping: []); return }
        guard let bytes = try? Data(contentsOf: manifest), bytes.count < 1_000_000,
              let saved = try? PropertyListDecoder().decode(Index.self, from: bytes), saved.version == 1,
              saved.registration.uuidString == id, !saved.owner.isEmpty, saved.terms.count <= 128 else { return }
        index = saved
        prune(keeping: Set(saved.terms.values.map { file($0.fileID).lastPathComponent }).union(["index.plist"]))
    }

    // Only delete files owned by this store. A failed cleanup is retried on restore; a
    // revoked registration cannot load them even if the device was locked during logout.
    private func prune(keeping: Set<String>) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        for name in names where !keeping.contains(name) && (name == "index.plist" ||
            (name.hasSuffix(".plist") && UUID(uuidString: String(name.dropLast(6))) != nil)) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    func reviewAccount() { reviewing = true; defaults.set(true, forKey: Key.review) }
    func verified(_ newOwner: String) {
        if index == nil && hasRegistration { restore() }
        // An unreadable old document cannot prove which student owns it. Never let
        // delayed protected-data availability resurrect it under a different account.
        if hasRegistration && owner != newOwner { forget() }
        reviewing = false; defaults.removeObject(forKey: Key.review)
    }
    func forget() {
        defaults.removeObject(forKey: Key.registration)
        index = nil; contents = [:]; writeFailed = false
        reviewing = false; defaults.removeObject(forKey: Key.review)
        prune(keeping: [])
    }

    private func write<T: Encodable>(_ value: T, to destination: URL) throws {
        let data = try PropertyListEncoder().encode(value)
        guard data.count <= 12_000_000 else { throw SchoolPortalIssue.format }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #if os(iOS)
        var folder = directory, flags = URLResourceValues()
        flags.isExcludedFromBackup = true
        try folder.setResourceValues(flags)
        try data.write(to: destination, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: destination, options: .atomic)
        #endif
    }

    private func rows(_ term: Term) -> [SavedAssignment]? {
        if let cached = contents[term.fileID] { return cached }
        guard let bytes = try? Data(contentsOf: file(term.fileID)), bytes.count <= 12_000_000,
              let rows = try? PropertyListDecoder().decode([SavedAssignment].self, from: bytes),
              rows.count <= 3200, Set(rows.map(\.id)).count == rows.count else { return nil }
        contents[term.fileID] = rows
        return rows
    }
    func snapshot(for id: String?) -> SchoolPortalTasks? {
        guard let id = id ?? current, let term = terms[id], let rows = rows(term) else { return nil }
        return .init(termLabel: term.label, term: term.label.name, rows: rows.map(\.displayRow))
    }

    /// Content is staged first. Publishing one small atomic index commits both the new
    /// deadline set and the check time. An unchanged semester only updates that timestamp.
    @discardableResult func accept(_ list: SchoolPortalTasks, owner: String, current: Bool, at date: Date = Date()) -> Bool {
        guard !reviewing, !owner.isEmpty, index?.owner == nil || index?.owner == owner,
              let label = list.termLabel, !label.id.isEmpty, list.rows.count <= 3200,
              Set(list.rows.map(\.id)).count == list.rows.count else { return false }
        let newRegistration = index == nil
        var next = index ?? Index(version: 1, registration: UUID(), owner: owner)
        guard next.terms[label.id] != nil || next.terms.count < 128 else { writeFailed = true; return false }
        let prior = next.terms[label.id]
        let before = prior.flatMap(rows)
        let previous = Dictionary(uniqueKeysWithValues: (before ?? []).map { ($0.id, $0) })
        let entries = list.rows.map { SavedAssignment($0, preserving: previous[$0.id]) }
        let changed = before != entries
        let id = changed ? UUID() : (prior?.fileID ?? UUID())
        if current { next.current = label.id }
        next.terms[label.id] = Term(label: label, fileID: id, checked: date)
        do {
            if changed { try write(entries, to: file(id)) }
            try write(next, to: manifest)
        } catch {
            if changed { try? FileManager.default.removeItem(at: file(id)) }
            writeFailed = true; return false
        }
        defaults.set(next.registration.uuidString, forKey: Key.registration)
        index = next; writeFailed = false
        if changed {
            contents[id] = entries
            if let old = prior?.fileID { contents[old] = nil; try? FileManager.default.removeItem(at: file(old)) }
        }
        if newRegistration { prune(keeping: [file(id).lastPathComponent, "index.plist"]) }
        return true
    }

    @discardableResult func configure(enabled: Bool, titles: Bool, registration: UUID) -> Bool {
        guard self.registration == registration, var next = index else { return false }
        next.reminders = enabled; next.showTitles = enabled && titles
        do { try write(next, to: manifest); index = next; return true } catch { writeFailed = true; return false }
    }

    /// Only the current semester is armed. Browsing a saved archive does not enable its reminders.
    func deadlines(at now: Date, currentTerm: String? = nil) -> [AssignmentDeadline]? {
        guard enabled, let id = currentTerm ?? current, let term = terms[id] else { return [] }
        return rows(term).map { AssignmentDeadline.make($0, now: now, showTitles: showsTitles) }
    }
}
