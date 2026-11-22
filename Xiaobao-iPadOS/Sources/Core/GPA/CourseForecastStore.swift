import Foundation
import CryptoKit
import Observation

/// Device-only, user-authored what-ifs. Published marks, calculated results and
/// session credentials never enter the archive. The UI must supply a live, verified scope.
@Observable @MainActor final class CourseForecastStore {
    struct Scope: Hashable {
        let owner, term: String
        let session: UUID
    }
    typealias Term = [String: [AssessmentForecast]]
    private struct Archive: Codable {
        let version: Int
        let courses: Term
    }
    enum Failure: Error { case scopeChanged, invalidArchive }

    private let directory: URL
    private var active: Scope?
    private var values: Term?
    private(set) var failedScope: Scope?
    private static let byteLimit = 1_048_576

    init(directory: URL = URL.applicationSupportDirectory.appending(path: "CourseForecasts", directoryHint: .isDirectory)) {
        self.directory = directory
    }

    func endSession(unless owner: String?, session: UUID) {
        if let active, active.owner != owner || active.session != session { open(nil) }
    }

    func open(_ scope: Scope?) {
        guard scope != active || failedScope != nil else { return }
        active = scope
        values = nil
        failedScope = nil
        guard let scope else { return }
        do {
            let file = try archiveURL(for: scope)
            let data = try Data(contentsOf: file)
            guard data.count <= Self.byteLimit else { throw Failure.invalidArchive }
            let input = try PropertyListDecoder().decode(Archive.self, from: data)
            guard input.version == 1, Self.valid(input.courses) else { throw Failure.invalidArchive }
            values = input.courses
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            values = [:]
        } catch {
            // Inaccessible/corrupt is not empty. Never replace it with a new draft or reset.
            failedScope = scope
        }
    }

    func read(in scope: Scope) -> Term? { active == scope ? values : nil }

    func save(_ draft: AssessmentForecast, course: String, in scope: Scope) throws {
        guard var next = read(in: scope) else { throw Failure.scopeChanged }
        var rows = next[course] ?? []
        if let index = rows.firstIndex(where: { $0.id == draft.id }) { rows[index] = draft }
        else { rows.append(draft) }
        next[course] = rows
        try commit(next, in: scope)
    }

    func remove(_ id: UUID, course: String, in scope: Scope) throws {
        guard var next = read(in: scope) else { throw Failure.scopeChanged }
        guard let old = next[course], old.contains(where: { $0.id == id }) else { return }
        let remaining = old.filter { $0.id != id }
        next[course] = remaining.isEmpty ? nil : remaining
        try commit(next, in: scope)
    }

    func restore(in scope: Scope) throws {
        guard read(in: scope) != nil else { throw Failure.scopeChanged }
        try commit([:], in: scope)
    }

    private static func valid(_ rows: Term) -> Bool {
        rows.count <= 256 && rows.allSatisfy { key, drafts in
            !key.isEmpty && drafts.count <= 128 && Set(drafts.map(\.id)).count == drafts.count &&
                drafts.allSatisfy { $0.mark.isFinite && (0...100).contains($0.mark) &&
                    ($0.groupID == nil) == ($0.groupAnchor == nil) }
        }
    }

    private func archiveURL(for scope: Scope) throws -> URL {
        let data = try JSONEncoder().encode([scope.owner, scope.term])
        let key = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return directory.appending(path: key + ".plist")
    }

    private func commit(_ next: Term, in scope: Scope) throws {
        guard Self.valid(next) else { throw Failure.invalidArchive }
        let data = try PropertyListEncoder().encode(Archive(version: 1, courses: next))
        guard data.count <= Self.byteLimit else { throw Failure.invalidArchive }
        let file = try archiveURL(for: scope)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #if os(iOS)
        var location = directory, flags = URLResourceValues()
        flags.isExcludedFromBackup = true
        try location.setResourceValues(flags)
        try data.write(to: file, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: file, options: .atomic)
        #endif
        values = next
    }
}
