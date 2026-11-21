// Run through webkit-smoke.py on macOS. This probe can contact only its loopback fixture.
import AppKit
import WebKit

@MainActor final class Probe: NSObject, WKNavigationDelegate {
    let base: URL
    let source: String
    let web: WKWebView
    let entry = SchoolPortalEntry()
    var started = false
    var finished = false
    var passed = false
    lazy var store = SchoolPortalStore(selected: true) { [unowned self] operation, expected in
        switch operation {
        case .identity: return try await self.readData("identity")
        case .grades: return try await self.readData("grades", expected ?? "")
        case .attendance(let q):
            return try await self.readData("attendance", expected ?? "", ["category":q.category.rawValue,"page":q.page])
        case let .attendanceSubject(subject,from,to,page):
            return try await self.readData("attendanceSubject", expected ?? "", ["category":"classroom","subject":subject,
                                                                                  "from":from,"to":to,"page":page])
        default: throw Failure()
        }
    }

    init(base: URL, resources: URL) throws {
        self.base = base
        let projection = try String(contentsOf: resources.appendingPathComponent("PortalProjection.js"), encoding: .utf8)
        let original = try String(contentsOf: resources.appendingPathComponent("PortalRead.js"), encoding: .utf8)
        let local = original.replacingOccurrences(of: "https://tsinglanstudent.schoolis.cn", with: base.absoluteString)
        source = "const p = (" + projection + ")(); const run = (" + local +
            ");return JSON.stringify(await run(op,args,owner,'loopback-fixture',p,'test-navigation'));"
        let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: 640, height: 480), configuration: config)
        super.init(); web.navigationDelegate = self
    }

    func readData(_ op: String, _ owner: String = "", _ args: [String:Any] = [:]) async throws -> Data {
        let input: [String:Any] = ["op":op,"args":args,"owner":owner]
        let raw = try await web.callAsyncJavaScript(source, arguments: input, in: nil, contentWorld: .defaultClient)
        guard let string = raw as? String else { throw Failure() }
        return Data(string.utf8)
    }
    func read(_ op: String, _ owner: String = "", _ args: [String:Any] = [:]) async throws -> [String: Any] {
        let data = try await readData(op,owner,args)
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String:Any] else { throw Failure() }
        return dict
    }
    struct Failure: Error {}

    // The fixture operator revokes its own synthetic session. Production has no such operation.
    func expire(revokingDevice: Bool) async throws {
        let path = revokingDevice ? "/fixture/revoke-device" : "/fixture/expire"
        let ok = try await web.callAsyncJavaScript("return (await fetch(path, {method:'POST'})).ok;",
            arguments: ["path":path], in: nil, contentWorld: .defaultClient)
        guard ok as? Bool == true else { throw Failure() }
    }
    func visitGrades() async {
        await store.openGrades { try await self.entry.reopen(self.web, home: self.base.appendingPathComponent("Home")) }
    }

    func webView(_ web: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let url = action.request.url
        decisionHandler(url?.scheme == base.scheme && url?.host == base.host && url?.port == base.port ? .allow : .cancel)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if entry.owns(navigation) {
            // Replace only the origin when applying the actual native page classifier.
            let equivalent = webView.url.map { SchoolPortalPage.origin.appendingPathComponent($0.path) }
            entry.finish(navigation, issue: SchoolPortalPage.issue(at: equivalent, foreground: true, loading: false))
            return
        }
        guard !started else { return }; started = true
        Task { @MainActor in
            defer { finished = true }
            do {
                await store.verify()
                guard let owner = store.owner, owner.count == 64 else { throw Failure() }
                let date = ["from":"2025-02-16","to":"2025-02-22"]
                await store.loadAttendance(.init())
                guard store.attendance?.counts.native.total == 4, store.attendance?.rate == 0.75, store.grades == nil else { throw Failure() }
                await store.loadAttendanceSubject("51", page:1)
                guard store.attendanceSubject?.records.first?.status == .late else { throw Failure() }
                let week = try await read("week",owner,date)
                guard let rows = week["value"] as? [[String:Any]], rows.first?["room"] as? String == "Loft" else { throw Failure() }
                let plain = try await read("tasks",owner,["includeScores":false])
                guard let plainList = plain["value"] as? [String:Any], let plainRows = plainList["rows"] as? [[String:Any]],
                      plainRows.first?["score"] is NSNull else { throw Failure() }
                await visitGrades()
                guard store.grades?.gpa == 2.75, store.grades?.courses.count == 1 else { throw Failure() }
                let course = try await read("detail", owner, ["term":"5","subject":"3","cls":"9","type":"1"])
                guard let groups = course["value"] as? [[String:Any]], groups.count == 1 else { throw Failure() }
                let tasks = try await read("tasks",owner,["includeScores":true])
                guard let taskList = tasks["value"] as? [String:Any], let tasks = taskList["rows"] as? [[String:Any]],
                      tasks.first?["title"] as? String == "Contour", let mark = tasks.first?["score"] as? [String:Any],
                      mark["earned"] as? Double == 0, mark["possible"] as? Double == 5 else { throw Failure() }
                try await expire(revokingDevice:false)
                guard try await read("identity")["error"] as? String == "expired" else { throw Failure() }
                await visitGrades()
                guard store.owner == owner, store.grades?.gpa == 3.5, store.identityIssue == nil else { throw Failure() }
                try await expire(revokingDevice:true)
                await visitGrades(); await visitGrades()
                guard store.owner == nil, store.grades == nil, store.identityIssue == .login, !entry.pending else { throw Failure() }
                passed = true
            } catch { /* Never print response bodies or WebKit errors. */ }
        }
    }
}

@main struct Smoke {
    @MainActor static func main() throws {
    guard CommandLine.arguments.count == 3, let base = URL(string:CommandLine.arguments[1]),
          base.scheme == "http", base.host == "127.0.0.1" else { exit(2) }
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    let p = try Probe(base:base, resources:URL(fileURLWithPath:CommandLine.arguments[2]))
    p.web.load(URLRequest(url:base.appendingPathComponent("Home")))
    let timeout = Date().addingTimeInterval(35)
    while !p.finished && Date() < timeout { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
    print(p.passed ? "PASS: real WebKit, schedule, tasks, attendance and its course detail, grades, same-student renewal and interactive stop without a visible web view" : "FAIL: WebKit fixture")
    exit(p.passed ? 0 : 1)
    }
}
