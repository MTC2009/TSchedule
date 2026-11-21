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
        if let issue = session.documentIssue(loading: session.loading || web.isLoading) { throw issue }
        let generation = session.readGeneration
        let op: String, params: [String: Any]
        switch request {
        case .identity: (op, params) = ("identity", [:])
        case .enrollmentName: (op, params) = ("enrollmentName", [:])
        case .week(let from, let to): (op, params) = ("week", ["from":from, "to":to])
        case .collection(let kind): (op, params) = (kind.rawValue, [:])
        case .terms: (op, params) = ("terms", [:])
        case .grades: (op, params) = ("grades", [:])
        case .archivedGrades(let term): (op, params) = ("grades", ["term":term])
        case let .archivedTasks(term, scores): (op, params) = ("tasks", ["term":term, "includeScores":scores])
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
        let arguments: [String: Any] = ["operation":op, "parameters":params, "expected":expected ?? "",
                                             "salt":salt, "generation":generation.uuidString]
        let value: Any?
        let timeout: Duration? = switch request {
        case .identity: .seconds(8)
        case .week: .seconds(16)
        default: nil
        }
        do {
            if let timeout {
                // A detached web document can suspend JS timers. A hung calendar read
                // must not leave the sole manual update action permanently disabled.
                value = try await withCheckedThrowingContinuation { continuation in
                    let wait = BoundedReply(continuation)
                    let deadline = Task {
                        do { try await Task.sleep(for: timeout) } catch { return }
                        wait.finish(.failure(SchoolPortalIssue.network))
                    }
                    web.callAsyncJavaScript(script, arguments: arguments, in: nil, in: .defaultClient) { result in
                        deadline.cancel()
                        wait.finish(result)
                    }
                }
            } else {
                value = try await web.callAsyncJavaScript(script, arguments: arguments, in: nil, contentWorld: .defaultClient)
            }
        } catch { throw SchoolPortalIssue.network }
        guard session.webView === web, session.revision == revision, session.readGeneration == generation,
              session.foreground, !session.loading, !web.isLoading, Self.isHome(web.url) else {
            throw SchoolPortalIssue.notReady
        }
        guard let text = value as? String, text.utf8.count <= 8_000_000 else { throw SchoolPortalIssue.format }
        return Data(text.utf8)
    }

    @MainActor private final class BoundedReply {
        private var continuation: CheckedContinuation<Any?, Error>?
        init(_ continuation: CheckedContinuation<Any?, Error>) { self.continuation = continuation }
        func finish(_ result: Result<Any, Error>) {
            let previous = continuation
            continuation = nil
            previous?.resume(with: result.map { Optional($0) })
        }
    }
}
