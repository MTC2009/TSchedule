import Foundation

struct TaskTermDirectory: Equatable, Sendable {
    let current: String
    let available: [String]

    init?(current: String?, available: [String]?) {
        guard let current, Self.validTerm(current) else { return nil }
        var seen = Set<String>()
        self.current = current
        self.available = ([current] + (available ?? [])).filter { Self.validTerm($0) && seen.insert($0).inserted }
    }

    private static func validTerm(_ value: String) -> Bool {
        (1...200).contains(value.count) && value.trimmingCharacters(in: .whitespacesAndNewlines) == value
    }

    static func title(_ term: String) -> String {
        let parts = term.split(separator: "-")
        guard parts.count == 2, parts[0].count == 4, Int(parts[0]) != nil else { return term }
        switch parts[1] {
        case "autumn": return "\(parts[0]) 秋季学期"
        case "spring": return "\(parts[0]) 春季学期"
        default: return term
        }
    }
}

struct TaskReadRequest: Equatable, Sendable {
    var term: String? = nil
    var offset = 0
    var limit = 100

    var route: String {
        var query = URLComponents()
        query.queryItems = [URLQueryItem(name: "kind", value: "task"),
                            URLQueryItem(name: "offset", value: String(offset)),
                            URLQueryItem(name: "limit", value: String(limit))]
        if let term { query.queryItems?.append(URLQueryItem(name: "term", value: term)) }
        // Form-style server query decoding treats an unescaped plus as a space.
        return "work?" + (query.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B")
    }
}

enum TaskCatalog {
    static let metadataVersion = 1

    struct Snapshot: Sendable {
        let rows: [CampusWork]
        let directory: TaskTermDirectory?
    }

    /// A historical list is only published when every page has been read and checked.
    @MainActor static func load(term: String?, read: (TaskReadRequest) async throws -> CampusList<CampusWork>) async throws -> Snapshot {
        var rows: [CampusWork] = []
        var seen = Set<String>()
        var total: Int?
        var directory: TaskTermDirectory?
        for _ in 0..<64 {
            try Task.checkCancellation()
            let page = try await read(TaskReadRequest(term: term, offset: rows.count))
            try Task.checkCancellation()
            let stamp = page.taskTermDirectory
            guard (0...6400).contains(page.total), (1...100).contains(page.limit),
                  page.offset == rows.count, page.offset <= page.total,
                  page.items.count == min(page.limit, page.total - page.offset),
                  total == nil || total == page.total,
                  total == nil || stamp == directory else { throw CampusError.invalidResponse }
            directory = stamp ?? directory
            total = page.total
            for row in page.items {
                // A legacy row without a term belongs to the current term, never an archive.
                let matchesTerm = term.map { row.term == $0 } ??
                    (directory?.current == nil || row.term == nil || row.term == directory?.current)
                guard !row.id.isEmpty, seen.insert(row.id).inserted,
                      row.kind == nil || row.kind == "task", matchesTerm else {
                    throw CampusError.invalidResponse
                }
                rows.append(row)
            }
            if rows.count == page.total { return Snapshot(rows: rows, directory: directory) }
        }
        throw CampusError.invalidResponse
    }
}

extension CampusList where T == CampusWork {
    var taskTermDirectory: TaskTermDirectory? { TaskTermDirectory(current: current_term, available: available_terms) }
}
