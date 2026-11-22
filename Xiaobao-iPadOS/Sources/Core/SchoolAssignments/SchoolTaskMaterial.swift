import Foundation

/// Only the student's displayable material crosses the reader/cache boundary. File tickets
/// and marks are intentionally different types and cannot be encoded as cached details.
struct SchoolTaskMaterial: Codable, Equatable {
    enum Section: String, CaseIterable { case instructions, answer, feedback }
    struct File: Codable, Equatable, Identifiable {
        let key, name: String
        let downloadable: Bool
        var id: String { key }
    }
    struct Part: Codable, Equatable {
        enum State: String, Codable { case available, hidden, unknown }
        let state: State
        let text: String?
        let files: [File]
    }
    let instructions, answer, feedback: Part
    let submitted: String?
    subscript(_ section: Section) -> Part {
        switch section {
        case .instructions: instructions
        case .answer: answer
        case .feedback: feedback
        }
    }
    func validate(feedbackReleased: Bool? = nil) throws {
        // A verified list can already have withdrawn publication while the detail
        // still looks released. The stricter of the two always wins.
        guard feedbackReleased != false || feedback.state != .available else { throw SchoolPortalIssue.format }
        guard answer.state != .hidden || submitted == nil else { throw SchoolPortalIssue.format }
        for section in Section.allCases {
            let part = self[section]
            guard (part.text?.utf8.count ?? 0) <= 512_000, part.files.count <= 128,
                part.state == .available || (part.text == nil && part.files.isEmpty),
                Set(part.files.map(\.key)).count == part.files.count,
                part.files.allSatisfy({
                    !$0.name.isEmpty && !$0.key.isEmpty && $0.name.utf8.count <= 1024 && $0.key.utf8.count <= 1050
                })
            else { throw SchoolPortalIssue.format }
        }
        guard submitted == nil || submitted.flatMap(campusInstant) != nil else { throw SchoolPortalIssue.format }
    }
}

struct SchoolTaskFileLink: Decodable {
    let url: URL
    let name: String
}

/// A file is eligible only if a freshly verified detail named it. This further
/// restricts transport: never navigate to arbitrary portal actions or local hosts.
enum SchoolTaskFilePolicy {
    static let limit: Int64 = 100 * 1024 * 1024
    static func permits(_ url: URL, task: String, section: SchoolTaskMaterial.Section, key: String) -> Bool {
        guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
            url.port == nil || url.port == 443, let host = url.host?.lowercased()
        else { return false }
        if SchoolPortalPage.isOfficial(url) {
            let path = url.path.lowercased()
            if path == "/api/learningtask/downloaddocument",
                let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
            {
                guard Set(items.map(\.name)) == ["documentId", "learningTaskId", "documentType"], items.count == 3,
                    section != .feedback
                else { return false }
                let q = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
                return q["learningTaskId"] == task && q["documentType"] == (section == .answer ? "2" : "1")
                    && key == "id:" + (q["documentId"] ?? "")
            }
            return !path.hasPrefix("/api/") && !path.hasPrefix("/v2/") && !path.hasPrefix("/account")
                && !url.pathExtension.isEmpty
        }
        // Only school-linked storage, not arbitrary student-supplied web pages or an IP literal.
        return [
            ".schoolis.cn", ".xiaobao100.com", ".schoolpal.cn", ".xiaobaoonline.com", ".aliyuncs.com", ".alicdn.com",
        ].contains { host.hasSuffix($0) }
    }
}
