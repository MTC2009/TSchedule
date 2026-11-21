import Foundation
@preconcurrency import WebKit

/// Cookies stay entirely under WebKit's control. No WKScriptMessageHandler,
/// authentication form hooks, URLSession credential copying, or third-party frames.
@MainActor
final class SchoolPortalReader {
    private weak var session: PortalSession?
    private let salt: String
    private let script: String?

    init(session: PortalSession, salt: String) {
        self.session = session; self.salt = salt
        func resource(_ name: String) -> String? {
            Bundle.main.url(forResource: name, withExtension: "js").flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        }
        if let projection = resource("PortalProjection"), let reader = resource("PortalRead") {
            script = "const project = (" + projection + ")(); const run = (" + reader +
                "); return JSON.stringify(await run(operation, parameters, expected, salt, project, generation));"
        } else { script = nil }
    }

    static func isHome(_ url: URL?) -> Bool {
        SchoolPortalPage.issue(at: url, foreground: true, loading: false) == nil
    }

    func read(_ request: SchoolPortalRead, expected: String?) async throws -> Data {
        guard let session, let script else { throw SchoolPortalIssue.unavailable }
        let web = session.webView, revision = session.revision
        if let issue = SchoolPortalPage.issue(at: web.url, foreground: session.foreground,
                                             loading: session.loading || web.isLoading) { throw issue }
        let generation = session.readGeneration
        let op: String, params: [String: Any]
        switch request {
        case .identity: (op, params) = ("identity", [:])
        case .enrollmentName: (op, params) = ("enrollmentName", [:])
        case .week(let from, let to): (op, params) = ("week", ["from":from, "to":to])
        case .grades: (op, params) = ("grades", [:])
        case .tasks(let includeScores): (op, params) = ("tasks", ["includeScores": includeScores])
        case .attendance(let query):
            var dates: [String: Any] = ["category":query.category.rawValue, "page":query.page]
            if let from = query.from { dates["from"] = from }
            if let to = query.to { dates["to"] = to }
            if let status = query.status { dates["status"] = status.rawValue }
            (op, params) = ("attendance", dates)
        case let .attendanceSubject(subject, from, to, page):
            (op, params) = ("attendanceSubject", ["category":"classroom","from":from,"to":to,"subject":subject,"page":page])
        case let .detail(term, subject, cls, type):
            (op, params) = ("detail", ["term":term, "subject":subject, "cls":cls, "type":String(type)])
        }
        let value: Any?
        do {
            value = try await web.callAsyncJavaScript(script,
                arguments: ["operation":op, "parameters":params, "expected":expected ?? "", "salt":salt,
                            "generation":generation.uuidString],
                in: nil, contentWorld: .defaultClient)
        } catch { throw SchoolPortalIssue.network }
        guard session.webView === web, session.revision == revision, session.readGeneration == generation,
              session.foreground, !session.loading, !web.isLoading, Self.isHome(web.url) else {
            throw SchoolPortalIssue.notReady
        }
        guard let text = value as? String, text.utf8.count <= 8_000_000 else { throw SchoolPortalIssue.format }
        return Data(text.utf8)
    }
}
