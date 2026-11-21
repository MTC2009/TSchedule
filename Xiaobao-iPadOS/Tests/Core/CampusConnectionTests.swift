import XCTest
@testable import XiaobaoCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class TestVault: CampusVault {
    var data: Data?
    func read() throws -> Data? { data }
    func store(_ data: Data?) throws { self.data = data }
}

actor CampusMock {
    let start: Date
    var offline = false
    var denied = false
    var noStore = false
    var counts: [String: Int] = [:]
    var gradeSlots = Array(0..<6)
    var gradeEdits: [Int: Int] = [:]
    var assessmentWeight: Double?
    var gradeClass: String?
    var omitNextChange = false
    var deliveredGrades: [Int] = []
    var shouldPause = false
    var paused: CheckedContinuation<Void, Never>?
    var observer: CheckedContinuation<Void, Never>?
    init(_ start: Date) { self.start = start }
    func setOffline(_ v: Bool) { offline = v }
    func setDenied() { denied = true }
    func setNoStore() { noStore = true }
    func editGrade(_ slot: Int) { gradeEdits[slot, default: 0] += 1 }
    func exposeCachedMetadata(weight: Double, className: String) {
        assessmentWeight = weight
        gradeClass = className
    }
    func changeRoster(_ slots: [Int]) { gradeSlots = slots }
    func omitChangedRow() { omitNextChange = true }
    func lastDelivery() -> Int? { deliveredGrades.last }
    func pauseNext() { shouldPause = true }
    func waitForPause() async {
        if paused == nil { await withCheckedContinuation { observer = $0 } }
    }
    func resume() { paused?.resume(); paused = nil }
    func count(_ path: String) -> Int { counts[path] ?? 0 }

    func send(_ req: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let path = req.url!.path
        counts[path, default: 0] += 1
        if offline { throw URLError(.notConnectedToInternet) }
        func reply(_ code: Int, _ data: Any?, _ headers: [String: String] = ["Cache-Control":"no-store"]) throws -> (Data, HTTPURLResponse) {
            let bytes = try data.map { try JSONSerialization.data(withJSONObject: ["data":$0]) } ?? Data()
            return (bytes, HTTPURLResponse(url: req.url!, statusCode: code, httpVersion: "HTTP/1.1", headerFields: headers)!)
        }
        // This fixture represents the previous server, without the offline bundle API.
        if path.hasSuffix("/offline/versions") { return try reply(404, nil) }
        if req.httpMethod == "POST", !path.hasSuffix("/grades/sync") {
            let input = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
            let renewal = path.hasSuffix("/refresh")
            if renewal && denied { return try reply(401, nil) }
            let profile = (input["profile"] as? String) ?? (input["refresh_token"] as! String)
            var pair = ["access_token":profile, "expires_at":start.addingTimeInterval(renewal ? 8000 : 900).ISO8601Format()]
            if renewal || input["remember"] as? Bool == true {
                pair["refresh_token"] = profile
                pair["refresh_expires_at"] = start.addingTimeInterval(30 * 86_400).ISO8601Format()
            }
            return try reply(renewal ? 200 : 201, pair)
        }
        if req.httpMethod == "DELETE" { return try reply(204, nil) }
        let id = req.value(forHTTPHeaderField: "Authorization")!.replacingOccurrences(of: "Bearer ", with: "")
        if shouldPause {
            shouldPause = false
            await withCheckedContinuation { paused = $0; observer?.resume(); observer = nil }
        }
        if denied { return try reply(401, nil) }
        if path.hasSuffix("/grades/sync") {
            guard req.httpMethod == "POST" else { return try reply(405, nil) }
            let input = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
            let known = input["known"] as? [String: String] ?? [:]
            let roster = gradeSlots.map { slot in
                ["course_id":"\(id)-\(slot)", "name":"Course \(slot)", "revision":"\(id)-\(slot)-\(gradeEdits[slot] ?? 0)"]
            }
            let version = id + ":" + roster.map { $0["revision"]! }.joined(separator: "|")
            let headers = ["Cache-Control": noStore ? "no-store" : "private, no-cache"]
            if input["version"] as? String == version {
                deliveredGrades.append(0)
                return try reply(204, nil, headers)
            }
            var changed: [[String: Any]] = []
            for (slot, stamp) in zip(gradeSlots, roster) {
                let courseID = stamp["course_id"]!
                if known[courseID] == stamp["revision"] { continue }
                let score: [String: Any] = ["type":"numeric", "earned":80 + slot + (gradeEdits[slot] ?? 0), "possible":100]
                var assessment: [String: Any] = ["id":courseID + "-quiz", "status":"graded", "title":"Quiz",
                                                 "score":score, "feedback":"Reviewed"]
                if let assessmentWeight { assessment["weight"] = assessmentWeight }
                var detail: [String: Any] = ["course_id":courseID, "published_score":score, "assessments":[assessment]]
                if let gradeClass { detail["class_name"] = gradeClass }
                changed.append(detail)
            }
            if omitNextChange && !changed.isEmpty { changed.removeLast(); omitNextChange = false }
            deliveredGrades.append(changed.count)
            return try reply(200, ["version":version, "term":"demo", "courses":roster, "changed":changed] as [String: Any], headers)
        }
        let headers = noStore ? ["Cache-Control":"no-store"] : ["ETag":"W/\"v1-\(id)\"", "Cache-Control":"private, max-age=300"]
        if let tag = headers["ETag"], req.value(forHTTPHeaderField: "If-None-Match") == tag { return try reply(304, nil, headers) }
        if path.hasSuffix("/courses") { return try reply(200, [["id":id, "name":id]], headers) }
        return try reply(200, ["date":"2026-11-18","day":3,"lessons":[]] as [String:Any], headers)
    }
}

@MainActor final class CampusConnectionTests: XCTestCase {
    private let start = SchoolClock.date(2026, 11, 18)
    private let schedule = CampusPage.schedule("2026-11-18")
    private let origin = "http://127.0.0.1:3001"
    private func temp() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }

    func testLegacyCacheRevalidationAndOfflineRetention() async throws {
        let root = temp(); defer { try? FileManager.default.removeItem(at: root) }
        let api = CampusMock(start), vault = TestVault()
        var clock = start
        func client() -> CampusConnection {
            CampusConnection(vault: vault, root: root, send: { try await api.send($0) }, now: { clock })
        }
        let first = client()
        try await first.connect(origin: origin, profile: "a", remember: true)
        await first.load(schedule)
        let restored = client()
        await restored.load(schedule)
        let warmGets = await api.count("/api/v1/schedule")
        XCTAssertEqual(warmGets, 1)
        XCTAssertNotNil(restored.pages[schedule])
        let page = schedule
        async let automatic: Void = restored.load(page)
        async let manual: Void = restored.load(page, force: true)
        _ = await (automatic, manual)
        let manualGets = await api.count("/api/v1/schedule")
        XCTAssertEqual(manualGets, 2, "a manual refresh must survive a concurrent fresh-cache hit")
        clock = clock.addingTimeInterval(301)
        let reopened = client()
        await api.pauseNext()
        let one = Task { await reopened.load(schedule) }
        await api.waitForPause()
        XCTAssertEqual(reopened.pages[schedule]?.cache.checked, start, "cached rows visible while GET is suspended")
        let two = Task { await reopened.load(schedule) }
        await Task.yield()
        await api.resume(); await one.value; await two.value
        let conditionalGets = await api.count("/api/v1/schedule")
        XCTAssertEqual(conditionalGets, 3)
        XCTAssertEqual(reopened.pages[schedule]?.cache.checked, clock)
        let untouchedGrades = await api.count("/api/v1/grades/sync")
        XCTAssertEqual(untouchedGrades, 0)
        await api.setOffline(true)
        clock = clock.addingTimeInterval(301)
        let offline = client()
        await offline.load(schedule)
        XCTAssertNotNil(offline.pages[schedule]); XCTAssertNotNil(offline.errors[schedule])
        clock = clock.addingTimeInterval(7 * 86_400 + 1)
        await offline.load(schedule)
        XCTAssertNotNil(offline.pages[schedule], "an authorized device retains its last usable page beyond seven days")
    }

    func testRenewalCoalescesAndRevocationErasesSession() async throws {
        let root = temp(); defer { try? FileManager.default.removeItem(at: root) }
        let api = CampusMock(start), vault = TestVault()
        var clock = start
        let connection = CampusConnection(vault: vault, root: root, send: { try await api.send($0) }, now: { clock })
        try await connection.connect(origin: origin, profile: "a", remember: true)
        clock = clock.addingTimeInterval(901)
        async let a: Void = connection.load(.grades, force: true)
        async let b: Void = connection.load(.courses)
        _ = await (a,b)
        let refreshes = await api.count("/api/v1/session/refresh")
        XCTAssertEqual(refreshes, 1)
        XCTAssertNotNil(connection.savedGrades); XCTAssertNotNil(connection.pages[.courses])
        await api.setDenied()
        await connection.load(.courses, force: true)
        XCTAssertNil(connection.account); XCTAssertNil(vault.data); XCTAssertTrue(connection.pages.isEmpty)
    }

    func testLateResponseCannotRepopulateAfterLogoutOrAccountSwitch() async throws {
        let root = temp(); defer { try? FileManager.default.removeItem(at: root) }
        let api = CampusMock(start), vault = TestVault()
        let connection = CampusConnection(vault: vault, root: root, send: { try await api.send($0) }, now: { self.start })
        try await connection.connect(origin: origin, profile: "a", remember: true)
        await connection.load(.grades, force: true)
        let oldScope = try XCTUnwrap(connection.account?.scope)
        await api.pauseNext()
        let old = Task { await connection.load(.courses) }
        await api.waitForPause()
        try await connection.logout()
        try await connection.connect(origin: origin, profile: "b", remember: false)
        XCTAssertNil(vault.data)
        await connection.load(.courses)
        await api.resume(); await old.value
        guard case .courses(let courses) = connection.pages[.courses]?.content else { return XCTFail("missing account B") }
        XCTAssertEqual(courses.first?.id, "b")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(oldScope.uuidString).path))
        XCTAssertNil(connection.savedGrades)
        XCTAssertEqual((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? [], [])
    }

    func testNoStoreNeverRestoresFromDiskAndOriginIsBound() async throws {
        XCTAssertThrowsError(try campusOrigin("http://example.com"))
        XCTAssertThrowsError(try campusOrigin("https://student:password@example.com"))
        XCTAssertThrowsError(try campusOrigin("https://example.com/?token=123"))
        let root = temp(); defer { try? FileManager.default.removeItem(at: root) }
        let api = CampusMock(start), vault = TestVault()
        func client() -> CampusConnection {
            CampusConnection(vault: vault, root: root, send: { try await api.send($0) }, now: { self.start })
        }
        let connection = client()
        try await connection.connect(origin: origin, profile: "a", remember: true)
        await connection.load(.courses)
        await api.setNoStore(); await connection.load(.courses, force: true)
        await api.setOffline(true)
        let new = client(); await new.load(.courses)
        XCTAssertNil(new.pages[.courses])
    }

    private func assertGradeChecks(_ mock: CampusMock, _ expected: Int, file: StaticString = #filePath, line: UInt = #line) async {
        let checks = await mock.count("/api/v1/grades/sync")
        XCTAssertEqual(checks, expected, file: file, line: line)
    }

    func testManualGradesOpenLocallyAndSurviveOfflineBeyondPageTTL() async throws {
        let root = temp(); defer { try? FileManager.default.removeItem(at: root) }
        let api = CampusMock(start), vault = TestVault()
        var clock = start
        func client() -> CampusConnection {
            CampusConnection(vault: vault, root: root, send: { try await api.send($0) }, now: { clock })
        }
        let first = client()
        try await first.connect(origin: origin, profile: "a", remember: true)
        await first.opened(); await first.load(.grades)
        XCTAssertEqual(first.updatePolicy, .manual)
        XCTAssertNil(first.savedGrades)
        await assertGradeChecks(api, 0)
        await first.load(.grades, force: true)
        XCTAssertEqual(first.savedGrades?.grades.courses.count, 6)
        XCTAssertEqual(first.savedGrades?.roster.first?.name, "Course 0")
        await first.load(.grades); await first.load(.grades)
        await assertGradeChecks(api, 1)

        clock = clock.addingTimeInterval(9 * 86_400)
        await api.setOffline(true)
        let restored = client()
        await restored.opened(); await restored.load(.grades)
        XCTAssertEqual(restored.savedGrades?.grades.courses.first?.assessments.first?.feedback, "Reviewed")
        XCTAssertEqual(restored.savedGrades?.checked, start)
        await assertGradeChecks(api, 1)
        await restored.load(.grades, force: true)
        XCTAssertEqual(restored.savedGrades?.checked, start)
        XCTAssertNotNil(restored.errors[.grades])
        let names = await api.count("/api/v1/courses")
        XCTAssertEqual(names, 0)
    }

    func testGradeConsentPersistsAndAutomaticChecksRunOncePerOpeningWhenDue() async throws {
        let root = temp(); defer { try? FileManager.default.removeItem(at: root) }
        let api = CampusMock(start), vault = TestVault()
        var clock = start
        func client() -> CampusConnection {
            CampusConnection(vault: vault, root: root, send: { try await api.send($0) }, now: { clock })
        }
        let first = client()
        try await first.connect(origin: origin, profile: "a", remember: true)
        try await first.setUpdatePolicy(.everyTwoDays)
        await first.opened()
        await assertGradeChecks(api, 1)
        let restored = client()
        XCTAssertEqual(restored.updatePolicy, .everyTwoDays)
        clock = start.addingTimeInterval(48 * 3600 - 1)
        await restored.opened(); await restored.load(.grades)
        await assertGradeChecks(api, 1)
        clock = start.addingTimeInterval(48 * 3600)
        restored.enteredBackground()
        await restored.opened(); await restored.opened(); await restored.load(.grades)
        await assertGradeChecks(api, 2)
        XCTAssertEqual(restored.savedGrades?.checked, clock)
        XCTAssertEqual(restored.savedGrades?.updated, start)
        XCTAssertEqual(restored.gradeCheckMessage, "上次检查没有新成绩")
        await restored.load(.grades, force: true)
        await assertGradeChecks(api, 3)
        try await restored.setUpdatePolicy(.onOpen)
        restored.enteredBackground()
        async let one: Void = restored.opened()
        async let two: Void = restored.opened()
        _ = await (one, two)
        await restored.load(.grades); await restored.opened()
        await assertGradeChecks(api, 4)
        try await restored.setUpdatePolicy(.manual)
        let manual = client()
        await manual.opened(); await manual.load(.grades)
        await assertGradeChecks(api, 4)
    }

    func testGradeDeltasApplyAtomicallyAndRecoverWithoutLosingTheCursor() async throws {
        let root = temp(); defer { try? FileManager.default.removeItem(at: root) }
        let api = CampusMock(start), vault = TestVault()
        var clock = start
        let client = CampusConnection(vault: vault, root: root, send: { try await api.send($0) }, now: { clock })
        try await client.connect(origin: origin, profile: "a", remember: true)
        await client.load(.grades, force: true)
        let original = try XCTUnwrap(client.savedGrades)
        clock = clock.addingTimeInterval(10)
        await api.editGrade(2); await api.omitChangedRow()
        await client.load(.grades, force: true)
        XCTAssertNotNil(client.errors[.grades]); XCTAssertEqual(client.savedGrades?.version, original.version)
        XCTAssertEqual(client.savedGrades?.checked, start)

        await api.pauseNext()
        let update = Task { await client.load(.grades, force: true) }
        await api.waitForPause()
        XCTAssertEqual(client.savedGrades?.grades.courses[2].published_score?.earned, 82)
        let duplicate = Task { await client.load(.grades, force: true) }
        await Task.yield(); await api.resume(); await update.value; await duplicate.value
        await assertGradeChecks(api, 3)
        let delivered = await api.lastDelivery()
        XCTAssertEqual(delivered, 1)
        XCTAssertEqual(client.gradeCheckMessage, "Course 2 的成绩已更新")
        XCTAssertEqual(client.savedGrades?.grades.courses[2].published_score?.earned, 83)
        XCTAssertEqual(client.savedGrades?.grades.courses.first?.published_score?.earned, 80)
        XCTAssertNil(client.errors[.grades])
        await api.changeRoster([6, 0, 1, 2, 3, 4])
        await client.load(.grades, force: true)
        XCTAssertEqual(client.savedGrades?.grades.courses.map(\.course_id), ["a-6","a-0","a-1","a-2","a-3","a-4"])
        let newCourse = await api.lastDelivery()
        XCTAssertEqual(newCourse, 1)
    }

    func testLateGradeCheckCannotWriteToTheNextAccount() async throws {
        let root = temp(); defer { try? FileManager.default.removeItem(at: root) }
        let api = CampusMock(start), vault = TestVault()
        let client = CampusConnection(vault: vault, root: root, send: { try await api.send($0) }, now: { self.start })
        try await client.connect(origin: origin, profile: "a", remember: true)
        try await client.setUpdatePolicy(.onOpen)
        await api.pauseNext()
        let old = Task { await client.opened() }
        await api.waitForPause(); try await client.logout()
        try await client.connect(origin: origin, profile: "b", remember: false)
        await api.resume(); await old.value
        XCTAssertNil(client.savedGrades)
        XCTAssertEqual(client.updatePolicy, .manual)
        await client.load(.grades, force: true)
        XCTAssertEqual(client.savedGrades?.grades.courses.first?.course_id, "b-0")
        XCTAssertNil(vault.data)
        XCTAssertEqual((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? [], [])
    }

    func testPreviousFullGradePageMigratesWithoutNetwork() async throws {
        let root = temp(); defer { try? FileManager.default.removeItem(at: root) }
        let api = CampusMock(start), vault = TestVault()
        let client = CampusConnection(vault: vault, root: root, send: { try await api.send($0) }, now: { self.start })
        try await client.connect(origin: origin, profile: "a", remember: true)
        let scope = try XCTUnwrap(client.account?.scope)
        let oldStore = CampusDiskCache(root: root, scope: scope)
        let raw = Data(#"{"data":{"term":"previous","courses":[{"course_id":"one","assessments":[]}]}}"#.utf8)
        await oldStore.write(CachedCampusPage(body: raw, tag: "v1", checked: start, ttl: 300), for: .grades)
        await client.load(.grades)
        XCTAssertEqual(client.savedGrades?.grades.term, "previous")
        XCTAssertNil(client.savedGrades?.version)
        await assertGradeChecks(api, 0)
        await client.load(.grades, force: true)
        XCTAssertEqual(client.savedGrades?.grades.term, "demo")
        XCTAssertEqual(client.savedGrades?.roster.count, 6)
    }

    func testLegacyGradeCursorRebuildsOldMetadataWithoutAcceptingPartialBackfill() async throws {
        let root = temp(), api = CampusMock(start), vault = TestVault()
        var clock = start
        func client() -> CampusConnection { CampusConnection(vault: vault, root: root, send: { try await api.send($0) }, now: { clock }) }
        let first = client()
        try await first.connect(origin: origin, profile: "a", remember: true)
        await first.load(.grades, force: true)
        var old = try XCTUnwrap(first.savedGrades)
        let scope = try XCTUnwrap(first.account?.scope)
        old.metadataVersion = 1
        try await CampusDiskCache(root: root, scope: scope).writeGrades(old)
        await api.exposeCachedMetadata(weight: 0.285, className: "Studio C")
        clock.addTimeInterval(120)

        let reopened = client()
        await reopened.load(.grades)
        await assertGradeChecks(api, 1)
        XCTAssertNil(reopened.savedGrades?.grades.courses.first?.assessments.first?.weight)
        XCTAssertNil(reopened.savedGrades?.grades.courses.first?.class_name)
        await api.omitChangedRow()
        await reopened.load(.grades, force: true)
        XCTAssertNotNil(reopened.errors[.grades])
        XCTAssertEqual(reopened.savedGrades?.version, old.version)
        XCTAssertEqual(reopened.savedGrades?.metadataVersion, 1)

        await reopened.load(.grades, force: true)
        XCTAssertNil(reopened.errors[.grades])
        XCTAssertEqual(reopened.savedGrades?.grades.courses.first?.assessments.first?.weight, 0.285)
        XCTAssertEqual(reopened.savedGrades?.courseGradeDetails.first?.className, "Studio C")
        XCTAssertEqual(reopened.savedGrades?.metadataVersion, SavedCampusGrades.currentMetadataVersion)
        XCTAssertEqual(reopened.savedGrades?.updated, old.updated)
        await reopened.load(.grades, force: true)
        let delivered = await api.lastDelivery()
        XCTAssertEqual(delivered, 0)
    }

    func testSwiftClientAgainstRustHTTP() async throws {
        guard let origin = ProcessInfo.processInfo.environment["XIAOBAO_TEST_ORIGIN"] else { throw XCTSkip("Set XIAOBAO_TEST_ORIGIN to run the live Rust/Swift integration") }
        actor Probe {
            let transport = campusTransport()
            var responses: [(Int, Int)] = []
            func send(_ req: URLRequest) async throws -> (Data, HTTPURLResponse) {
                let result = try await transport(req)
                responses.append((result.1.statusCode, result.0.count))
                return result
            }
            func count() -> Int { responses.count }
            func last() -> (Int, Int)? { responses.last }
        }
        let root = temp(); defer { try? FileManager.default.removeItem(at: root) }
        let vault = TestVault(), probe = Probe()
        func client() -> CampusConnection { CampusConnection(vault: vault, root: root, send: { try await probe.send($0) }) }
        let first = client()
        try await first.connect(origin: origin, profile: "demo-b", remember: true)
        let beforeGrades = await probe.count()
        await first.opened()
        await first.load(.grades)
        let afterVisit = await probe.count()
        XCTAssertEqual(afterVisit, beforeGrades)
        await first.load(.work("task"))
        let scope = try XCTUnwrap(first.account?.scope)
        let currentTasks = try XCTUnwrap(first.cachedTaskList)
        XCTAssertEqual(currentTasks.items.count, currentTasks.total)
        XCTAssertTrue(currentTasks.items.contains { $0.task?.feedback?.text != nil && $0.published_at != nil })
        let teaser = try await first.readTaskPage(TaskReadRequest(limit: 1), scope: scope)
        let terms = try XCTUnwrap(teaser.taskTermDirectory)
        let pastTerm = try XCTUnwrap(terms.available.first { $0 != terms.current })
        let archive = try await TaskCatalog.load(term: pastTerm) { try await first.readTaskPage($0, scope: scope) }
        XCTAssertFalse(archive.rows.isEmpty)
        XCTAssertTrue(archive.rows.allSatisfy { $0.term == pastTerm })
        XCTAssertNil(first.savedGrades, "Reading tasks or their term directory does not refresh grades")
        do {
            _ = try await first.readTaskPage(TaskReadRequest(), scope: UUID())
            XCTFail("Task history must not be returned under a different account scope")
        } catch CampusError.changed {}
        await first.load(.grades, force: true)
        XCTAssertEqual(first.savedGrades?.grades.courses.count, 6, first.errors[.grades] ?? "missing gradebook")
        XCTAssertEqual(first.savedGrades?.grades.courses.first?.assessments.first?.weight, 0.25)
        XCTAssertNotNil(first.savedGrades?.grades.courses.first?.published_letter_grade)
        XCTAssertNotNil(first.savedGrades?.courseGradeDetails.first?.className)
        XCTAssertNotNil(first.savedGrades?.courseGradeDetails.first?.firstPublishedAt)
        await first.load(.grades, force: true)
        let unchanged = await probe.last()
        XCTAssertEqual(unchanged?.0, 304)
        XCTAssertEqual(unchanged?.1, 0)
        let day = SchoolClock.key(Date())
        let endpoints: [CampusPage] = [.schedule(day), .courses, .attendance, .work("task"), .work("exam"), .work("evaluation"), .calendar(day,day), .resources()]
        for page in endpoints {
            await first.load(page)
            XCTAssertNotNil(first.pages[page], first.errors[page] ?? page.route)
        }
        let account = try XCTUnwrap(first.account)
        func reference(_ page: CampusPage) async throws -> CampusContent {
            var req = URLRequest(url: try XCTUnwrap(URL(string: "api/v1/" + page.route, relativeTo: account.origin)))
            req.setValue("Bearer " + account.access, forHTTPHeaderField: "Authorization")
            let (bytes, http) = try await campusTransport()(req)
            XCTAssertEqual(http.statusCode, 200)
            return try page.decode(bytes)
        }
        guard case .attendance(let saved?) = first.pages[.attendance]?.content,
              case .attendance(let original?) = try await reference(.attendance) else { return XCTFail("Missing attendance comparison") }
        XCTAssertEqual(saved.totals.total, original.totals.total)
        XCTAssertEqual(saved.totals.present_rate, original.totals.present_rate)
        let anInstructionDate = SchoolClock.date(2027, 5, 18)
        let anotherDay = CampusPage.schedule(SchoolClock.key(anInstructionDate))
        await first.load(anotherDay)
        guard case .schedule(let local) = first.pages[anotherDay]?.content,
              case .schedule(let remote) = try await reference(anotherDay) else { return XCTFail("Missing timetable comparison") }
        XCTAssertEqual(local.day, remote.day)
        // Compare both Rust publications with the standalone native campus table.
        // The app can ship independently, but its fallback bells must not drift.
        XCTAssertEqual(local.teaching_slots, remote.teaching_slots)
        XCTAssertEqual(remote.teaching_slots, CampusBells.teachingSlots)
        XCTAssertEqual(local.lessons.map(\.id), remote.lessons.map(\.id))
        XCTAssertEqual(local.lessons.map { campusInstant($0.start) }, remote.lessons.map { campusInstant($0.start) })
        XCTAssertEqual(local.lessons.map { campusInstant($0.end) }, remote.lessons.map { campusInstant($0.end) })
        XCTAssertEqual(local.lessons.map(\.room), remote.lessons.map(\.room))
        for kind in CampusBells.Activity.allCases {
            let start = SchoolClock.at(minute: kind.minutes.lowerBound, on: anInstructionDate)
            XCTAssertEqual(local.timeline { $0 }?.focus(at: start)?.id, .activity(kind, start))
            XCTAssertEqual(remote.timeline { $0 }?.focus(at: start)?.id, .activity(kind, start))
        }
        let localDay = try XCTUnwrap(local.timeline { $0 })
        let remoteDay = try XCTUnwrap(remote.timeline { $0 })
        XCTAssertEqual(localDay.recesses, remoteDay.recesses)
        XCTAssertEqual(localDay.recesses.count, 5)
        let afterLunch = SchoolClock.at(minute: CampusBells.Activity.lunch.minutes.upperBound, on: anInstructionDate)
        XCTAssertEqual(localDay.nextInstructionStart(from: afterLunch), remoteDay.nextInstructionStart(from: afterLunch))

        let before = await probe.count()
        let second = client()
        await second.load(.schedule(day)); await second.load(.courses)
        await second.opened(); await second.load(.grades)
        XCTAssertEqual(second.savedGrades?.grades.courses.count, 6)
        if remote.calendarDay != nil {
            let week = TimetableWeek(containing: SchoolClock.date(2027, 4, 26))
            let days = week.dates.compactMap { second.cachedSchedule(on: $0) }
            XCTAssertEqual(days.count, 7)
            let closed = try XCTUnwrap(days.first { $0.date == "2027-04-26" })
            XCTAssertEqual(closed.calendarDay?.day, 2)
            XCTAssertEqual(closed.calendarDay?.status, .noClass)
            XCTAssertNil(closed.day)
            XCTAssertTrue(closed.lessons.isEmpty)
            for cached in days {
                guard case .schedule(let direct) = try await reference(.schedule(cached.date)) else { return XCTFail("Missing direct date") }
                XCTAssertEqual(cached.calendarDay, direct.calendarDay)
                XCTAssertEqual(cached.lessons.map(\.id), direct.lessons.map(\.id))
            }
        }
        let after = await probe.count()
        XCTAssertEqual(after, before, "a warm home screen makes zero HTTP requests")
        await second.load(.schedule(day), force: true)
        let last = await probe.last()
        XCTAssertEqual(last?.0, 304); XCTAssertEqual(last?.1, 0)
        try await second.logout()
        XCTAssertNil(second.cachedSchedule(on: anInstructionDate))
        XCTAssertNil(vault.data)
    }
}
