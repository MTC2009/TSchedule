import Foundation
import Observation

/// The last successful published grade reads are an offline display document.
/// Its registration is local, never authority for a portal request or account changes.
@Observable @MainActor final class SchoolGradeCache {
    struct Snapshot: Codable {
        let overview: SchoolPortalGrades
        let checked: Date
        var groups: [String: [SchoolPortalGrades.Group]]
    }

    private struct Archive: Codable {
        let version: Int
        let owner: String
        let registration: String
        var currentTerm: String?
        var terms: [String: Snapshot]
    }

    private enum Key {
        static let registration = "tschedule.grades.cache.registration.v1"
        static let review = "tschedule.grades.cache.review.v1"
    }

    private let file: URL
    private let defaults: UserDefaults
    private var archive: Archive?
    private var reviewing: Bool
    private(set) var writeFailed = false
    private static let byteLimit = 12_000_000

    init(file: URL, defaults: UserDefaults = .standard) {
        self.file = file
        self.defaults = defaults
        reviewing = defaults.bool(forKey: Key.review)
        restore()
    }

    var owner: String? { reviewing ? nil : archive?.owner }
    var currentTerm: String? { owner == nil ? nil : archive?.currentTerm }

    func snapshot(term: String?, verifiedOwner: String?) -> Snapshot? {
        guard let archive, canShow(archive, to: verifiedOwner) else { return nil }
        if let term = term ?? archive.currentTerm { return archive.terms[term] }
        return archive.terms.values.max { $0.checked < $1.checked }
    }

    func cachedTerms(verifiedOwner: String?) -> [SchoolPortalTerms.Term] {
        guard let archive, canShow(archive, to: verifiedOwner) else { return [] }
        return archive.terms.values.sorted { $0.checked > $1.checked }.map {
            $0.overview.termLabel ?? .init(id: $0.overview.termID, name: $0.overview.term)
        }
    }

    private func canShow(_ archive: Archive, to verifiedOwner: String?) -> Bool {
        !reviewing && (verifiedOwner == nil || verifiedOwner == archive.owner)
    }

    func restore() {
        guard archive == nil, let registration = defaults.string(forKey: Key.registration),
              let data = try? Data(contentsOf: file), data.count <= Self.byteLimit,
              let restored = try? PropertyListDecoder().decode(Archive.self, from: data),
              restored.registration == registration, restored.version == 1,
              !restored.owner.isEmpty,
              restored.terms.allSatisfy({ $0.key == $0.value.overview.termID }) else { return }
        archive = restored
    }

    func reviewAccount() {
        reviewing = true
        defaults.set(true, forKey: Key.review)
    }

    func verified(_ owner: String) {
        restore()
        if let previous = archive?.owner, previous != owner { forget() }
        reviewing = false
        defaults.removeObject(forKey: Key.review)
    }

    func forget() {
        // Revoke first so the file cannot reappear even if storage is locked.
        defaults.removeObject(forKey: Key.registration)
        defaults.removeObject(forKey: Key.review)
        reviewing = false
        writeFailed = false
        archive = nil
        if FileManager.default.fileExists(atPath: file.path) { try? FileManager.default.removeItem(at: file) }
    }

    func accept(_ book: SchoolPortalGrades, owner: String, current: Bool, checked: Date) {
        guard !reviewing, !owner.isEmpty, !book.termID.isEmpty, book.courses.count <= 768,
              archive?.owner == nil || archive?.owner == owner else { return }
        var next = archive ?? .init(version: 1, owner: owner, registration: UUID().uuidString, currentTerm: nil, terms: [:])
        let old = next.terms[book.termID]
        let roster = Set(book.courses.map(\.id))
        next.terms[book.termID] = .init(overview: book.retainingGPA(from: old?.overview), checked: checked,
                                      groups: old?.groups.filter { roster.contains($0.key) } ?? [:])
        if current { next.currentTerm = book.termID }
        commit(next)
    }

    func accept(groups: [SchoolPortalGrades.Group], course: String, term: String, owner: String) {
        guard !reviewing, var next = archive, next.owner == owner,
              var snapshot = next.terms[term], snapshot.overview.courses.contains(where: { $0.id == course }),
              groups.count <= 500 else { return }
        snapshot.groups[course] = groups.map { group in
            let items = group.items.map { row in
                CampusAssessment(id: row.id, title: row.title, status: row.status,
                                 date: row.date, feedback: nil, score: row.status == "graded" ? row.score : nil)
            }
            return .init(id: group.id, title: group.title, nested: group.nested, weight: group.weight, mark: group.mark, items: items)
        }
        next.terms[term] = snapshot
        commit(next)
    }

    func revoke(_ read: SchoolPortalRead) {
        guard var next = archive else { return }
        switch read {
        case .grades:
            if let current = next.currentTerm { next.terms[current] = nil }
            else { return }
        case .archivedGrades(let id):
            next.terms[id] = nil
        case .detail(let term, let subject, let cls, let type):
            guard var snapshot = next.terms[term],
                  let course = snapshot.overview.courses.first(where: { $0.subject == subject && $0.cls == cls && $0.type == type })
            else { return }
            snapshot.groups[course.id] = nil; next.terms[term] = snapshot
        default: return
        }
        // A confirmed denial may not leave that data accessible after relaunch.
        if !commit(next) { forget() }
    }

    @discardableResult private func commit(_ next: Archive) -> Bool {
        do {
            let data = try PropertyListEncoder().encode(next)
            guard data.count <= Self.byteLimit, next.terms.count <= 128 else {
                writeFailed = true
                return false
            }
            let directory = file.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            #if os(iOS)
            var local = directory, values = URLResourceValues()
            values.isExcludedFromBackup = true
            try local.setResourceValues(values)
            try data.write(to: file, options: [.atomic, .completeFileProtection])
            #else
            try data.write(to: file, options: .atomic)
            #endif
            defaults.set(next.registration, forKey: Key.registration)
            archive = next; writeFailed = false
            return true
        } catch {
            writeFailed = true
            return false
        }
    }
}
