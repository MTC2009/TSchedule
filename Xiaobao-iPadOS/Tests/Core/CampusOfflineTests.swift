import XCTest
@testable import XiaobaoCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private actor OfflineAPI {
    let login: CampusMock
    var revision = 1
    var attendance = 1
    var checks = 0
    var batches: [Set<String>] = []
    var denied: Set<String> = []
    var omitNext = false
    var conflictNext = false
    var disconnected = false
    var denySnapshot = false
    var assessmentWeight: Double?
    var gradeClass: String?
    var taskCategory: String?
    var examCount = 1
    var pause = false
    var waiting: CheckedContinuation<Void, Never>?
    var listener: CheckedContinuation<Void, Never>?

    init(_ start: Date) { login = CampusMock(start) }
    func edit() { revision += 1; attendance += 1 }
    func rejectGradeAccess() { denied.insert("grades"); revision += 1 }
    func omitOne() { omitNext = true }
    func raceNext() { conflictNext = true }
    func disconnect() { disconnected = true }
    func rejectSnapshot() { denySnapshot = true }
    func exposeCachedMetadata(weight: Double, className: String) {
        assessmentWeight = weight
        gradeClass = className
    }
    func exposeTaskCategory(_ category: String) { taskCategory = category }
    func exposeMultipleExamPages() { examCount = 33 }
    func pauseNext() { pause = true }
    func waitForDownload() async { if waiting == nil { await withCheckedContinuation { listener = $0 } } }
    func finishDownload() { waiting?.resume(); waiting = nil }
    func counts() -> [Int] { [checks, batches.count] }
    func lastBatch() -> Set<String>? { batches.last }

    func send(_ req: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if disconnected { throw URLError(.notConnectedToInternet) }
        guard req.url!.path.contains("/offline/") else { return try await login.send(req) }
        let id = req.value(forHTTPHeaderField: "Authorization") ?? ""
        let version = "\(id)-\(revision)"
        let tag = "W/\"\(version)\""
        func reply(_ status: Int, _ data: [String: Any]? = nil) throws -> (Data, HTTPURLResponse) {
            let bytes = try data.map { try JSONSerialization.data(withJSONObject: ["data": $0]) } ?? Data()
            return (bytes, HTTPURLResponse(url: req.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                           headerFields: ["ETag":tag, "Cache-Control":"private, no-cache"])!)
        }
        if req.url!.path.hasSuffix("/versions") {
            checks += 1
            if denySnapshot { return try reply(403) }
            if req.value(forHTTPHeaderField: "If-None-Match") == tag { return try reply(304) }
            var stamps: [String:String] = [:]
            for module in CampusModule.allCases where !denied.contains(module.rawValue) {
                stamps[module.rawValue] = "\(id)-\(module.rawValue)-\(module == .attendance ? attendance : 1)"
            }
            return try reply(200, ["version":version, "parts":stamps])
        }

        let input = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String:Any]
        let keys = input["parts"] as! [String]
        batches.append(Set(keys))
        if pause {
            pause = false
            await withCheckedContinuation { waiting = $0; listener?.resume(); listener = nil }
        }
        if conflictNext { conflictNext = false; edit(); return try reply(409) }
        guard input["version"] as? String == version else { return try reply(409) }
        let score: [String:Any] = ["type":"numeric","earned":18,"possible":20]
        let subject = "\(id)-math"
        let period: [String:Any] = ["course_id":subject,"room":"D301","start":505,"end":545]
        let task = ["id":"t","title":"Test","due_at":"2026-11-18T11:00:00+08:00","status":"pending","description":"Local"]
        var taskRow = task
        if let taskCategory { taskRow["work_type"] = taskCategory }
        var assessment: [String:Any] = ["id": "work-sample", "title": "Work sample", "status": "graded", "score": score]
        if let assessmentWeight { assessment["weight"] = assessmentWeight }
        var grade: [String: Any] = ["course_id":subject, "published_score":score, "assessments":[assessment], "gpa_credits":2.25]
        if let gradeClass { grade["class_name"] = gradeClass }
        let exams = examCount == 1 ? [task] : (0..<examCount).map { index in
            task.merging(["id": String(format: "exam-%02d", index),
                          "course_id": index == examCount - 1 ? subject : "another-course"]) { _, new in new }
        }
        var modules: [String:Any] = [
            "courses":[["id":subject,"name":"Math"]],
            "timetable":["rotation":["anchor_date":"2026-11-16","anchor_day":1,"cycle_length":2,"closures":[]] as [String:Any], "days":[[period],[period]]] as [String:Any],
            "events":[["id":"e","title":"Club","start":"2026-11-18T09:00:00+08:00","end":"2026-11-18T10:00:00+08:00"]],
            "attendance":["coverage":["from":"2026-11-01","to":"2026-11-18"], "course_ids":[subject], "records":[
                ["id":"one","course_id":subject,"date":"2026-11-01","status":"present"],
                ["id":"two","course_id":subject,"date":"2026-11-18","status":attendance == 1 ? "absent" : "present"]]] as [String:Any],
            "tasks":(0..<31).map { n in taskRow.merging(["id":"t\(n)"]) { _, new in new } }, "exams":exams, "evaluations":[],
            "resources":[["id":"r","title":"Study guide","content":"Ch. 1"]],
            "grades":["version":"\(id)-grades","term":"T1","courses":[["course_id":subject,"name":"Math","revision":"m1"]],
                      "changed":[grade],
                      "gpa_scale":[["minimum_percent":0.0,"grade_points":0.0],["minimum_percent":88.0,"grade_points":3.7]]] as [String:Any]
        ]
        modules = modules.filter { keys.contains($0.key) }
        if omitNext, let key = keys.first { modules.removeValue(forKey: key); omitNext = false }
        return try reply(200, ["version":version,"parts":modules])
    }
}

@MainActor final class CampusOfflineTests: XCTestCase {
    private let start = SchoolClock.date(2026,11,18), origin = "http://127.0.0.1:3001"
    private func temp() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }

    func testAllViewsAndCalculationsWorkOnARestartedOfflineDevice() async throws {
        let root = temp(); defer { try? FileManager.default.removeItem(at: root) }
        let api = OfflineAPI(start), vault = TestVault()
        var time = start
        func client() -> CampusConnection { CampusConnection(vault: vault, root: root, send: { try await api.send($0) }, now: { time }) }
        let first = client()
        try await first.connect(origin: origin, profile: "a")
        async let course: Void = first.load(.courses)
        async let attendance: Void = first.load(.attendance)
        _ = await (course, attendance)
        let firstBatch = await api.lastBatch()
        XCTAssertEqual(firstBatch, Set(CampusModule.ordinary.map(\.rawValue)))
        XCTAssertNil(first.savedGrades)
        await first.load(.grades, force: true)
        let gradesOnly = await api.lastBatch()
        XCTAssertEqual(gradesOnly, ["grades"])
        let before = await api.counts()
        await api.disconnect()
        time = start.addingTimeInterval(9 * 86400)
        let saved = client()
        try await saved.connect(origin: origin, profile: "a")
        await saved.opened()
        let date = CampusPage.schedule("2026-11-23"), agenda = CampusPage.calendar("2026-11-18","2026-11-18")
        let pages: [CampusPage] = [.courses,date,agenda,.work("task",offset:30),.work("exam"),.work("evaluation"),.attendance,.resources(),.grades]
        for page in pages { await saved.load(page); XCTAssertNil(saved.errors[page]) }
        let after = await api.counts()
        XCTAssertEqual(before, after)
        let gpa = try XCTUnwrap(saved.savedGrades?.grades.gpaSummary)
        XCTAssertEqual(gpa.source, .creditWeightedEstimate)
        XCTAssertEqual(gpa.value, 3.7, accuracy: 0.000001)
        let base = try XCTUnwrap(saved.savedGrades?.grades.courses.first?.published_score?.percentage)
        XCTAssertEqual(try GradeCalculator.projectedScore(current: base, assessment: 100, weight: 0.2),92)
        XCTAssertEqual(saved.attendanceRecords?.report()?.totals.present_rate, 0.5)
        XCTAssertEqual(saved.attendanceRecords?.report(from:"2026-11-12")?.totals.present_rate, 0)
        guard case .schedule(let schedule) = saved.pages[date]?.content,
              case .calendar(let day) = saved.pages[agenda]?.content,
              case .work(let tasks) = saved.pages[.work("task",offset:30)]?.content,
              case .resources(let files) = saved.pages[.resources()]?.content else { return XCTFail("Missing offline pages") }
        XCTAssertEqual(schedule.day,2); XCTAssertEqual(schedule.lessons.first?.room,"D301")
        XCTAssertEqual(day.events.count,1); XCTAssertEqual(day.deadlines.count,32)
        XCTAssertEqual(tasks.items.count,1); XCTAssertEqual(files.items.first?.content,"Ch. 1")
        let logins = await api.login.count("/api/v1/demo/sessions")
        XCTAssertEqual(logins,1)
    }

    func testOneChangedDatasetAtomicRetryAndZeroBodyChecks() async throws {
        let root = temp(); defer { try? FileManager.default.removeItem(at: root) }
        let api = OfflineAPI(start), vault = TestVault()
        var time = start
        let client = CampusConnection(vault:vault,root:root,send:{try await api.send($0)},now:{time})
        try await client.connect(origin:origin,profile:"a")
        _ = await client.checkAll()
        time.addTimeInterval(100)
        await api.edit(); await api.omitOne()
        let failed = await client.checkAll()
        XCTAssertFalse(failed); XCTAssertEqual(client.lastFullCheck,start)
        XCTAssertEqual(client.attendanceRecords?.report()?.totals.present,1)
        await api.raceNext()
        let ok = await client.checkAll()
        XCTAssertTrue(ok)
        XCTAssertEqual(client.attendanceRecords?.report()?.totals.present,2)
        let part = await api.lastBatch()
        XCTAssertEqual(part, ["attendance"])
        let before = await api.counts()
        _ = await client.checkAll()
        let after = await api.counts()
        XCTAssertEqual(after,[before[0]+1,before[1]])
        XCTAssertEqual(client.savedGrades?.updated,start)
        let state = try XCTUnwrap(try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil).first { $0.pathExtension == "offline" })
        let oldFile = try state.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate
        _ = await client.checkAll()
        XCTAssertEqual(oldFile,try state.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate)
    }

    func testCachedGradesBackfillMissingMetadataOnAnAuthorizedCheckOnly() async throws {
        let root = temp(), api = OfflineAPI(start), vault = TestVault()
        var clock = start
        func client() -> CampusConnection { CampusConnection(vault: vault, root: root, send: { try await api.send($0) }, now: { clock }) }
        let initial = client()
        try await initial.connect(origin: origin, profile: "a")
        await initial.load(.grades, force: true)
        let scope = try XCTUnwrap(initial.account?.scope)
        let disk = CampusDiskCache(root: root, scope: scope)
        let previous = try await disk.readOffline()
        var oldCache = try XCTUnwrap(previous)
        oldCache.gradeMetadataVersion = 1
        try await disk.saveOffline(oldCache, changed: true, background: false)
        await api.exposeCachedMetadata(weight: 0.375, className: "Workshop D")
        clock.addTimeInterval(120)

        let upgraded = client()
        let countsBeforeOpening = await api.counts()
        await upgraded.load(.grades)
        let countsAfterOpening = await api.counts()
        XCTAssertEqual(countsAfterOpening, countsBeforeOpening)
        XCTAssertNil(upgraded.savedGrades?.grades.courses.first?.assessments.first?.weight)
        XCTAssertNil(upgraded.savedGrades?.courseGradeDetails.first?.className)
        XCTAssertEqual(upgraded.savedGrades?.updated, start)

        await api.omitOne()
        await upgraded.load(.grades, force: true)
        XCTAssertNotNil(upgraded.errors[.grades])
        XCTAssertNotNil(upgraded.savedGrades)
        XCTAssertNil(upgraded.savedGrades?.grades.courses.first?.assessments.first?.weight)
        XCTAssertNil(upgraded.savedGrades?.courseGradeDetails.first?.className)

        await upgraded.load(.grades, force: true)
        let backfillBatch = await api.lastBatch()
        XCTAssertEqual(backfillBatch, ["grades"])
        XCTAssertEqual(upgraded.savedGrades?.grades.courses.first?.assessments.first?.weight, 0.375)
        XCTAssertEqual(upgraded.savedGrades?.updated, start)
        XCTAssertNil(upgraded.errors[.grades])

        let countsBeforeSecondCheck = await api.counts()
        await upgraded.load(.grades, force: true)
        let countsAfterSecondCheck = await api.counts()
        XCTAssertEqual(countsAfterSecondCheck, [countsBeforeSecondCheck[0] + 1, countsBeforeSecondCheck[1]])
        let reopened = client()
        await reopened.load(.grades)
        XCTAssertEqual(reopened.savedGrades?.grades.courses.first?.assessments.first?.weight, 0.375)
        XCTAssertEqual(reopened.savedGrades?.courseGradeDetails.first?.className, "Workshop D")
    }

    func testCurrentTasksUseTheFullOfflineListAndBackfillOnAnAuthorizedCheck() async throws {
        let root = temp(); defer { try? FileManager.default.removeItem(at: root) }
        let api = OfflineAPI(start), vault = TestVault()
        func client() -> CampusConnection { CampusConnection(vault: vault, root: root, send: { try await api.send($0) }, now: { self.start }) }
        let initial = client()
        try await initial.connect(origin: origin, profile: "a")
        await initial.load(.work("task"))
        let scope = try XCTUnwrap(initial.account?.scope)
        let disk = CampusDiskCache(root: root, scope: scope)
        let saved = try await disk.readOffline()
        var old = try XCTUnwrap(saved)
        old.taskMetadataVersion = nil
        try await disk.saveOffline(old, changed: true, background: false)
        await api.exposeTaskCategory("field_notes")

        let reopened = client()
        let before = await api.counts()
        await reopened.load(.work("task"))
        let afterRead = await api.counts()
        XCTAssertEqual(afterRead, before)
        XCTAssertEqual(reopened.cachedTaskList?.items.count, 31)
        XCTAssertNil(reopened.cachedTaskList?.items.last?.work_type)
        await reopened.load(.work("task"), force: true)
        let batch = await api.lastBatch()
        XCTAssertEqual(batch, ["tasks"])
        XCTAssertEqual(reopened.cachedTaskList?.items.last?.work_type, "field_notes")
        XCTAssertNil(reopened.savedGrades)
        let backfilled = try await disk.readOffline()
        XCTAssertEqual(backfilled?.taskMetadataVersion, TaskCatalog.metadataVersion)
        let generation = reopened.taskReadGeneration
        await api.rejectSnapshot()
        await reopened.load(.work("task"), force: true)
        XCTAssertNil(reopened.cachedTaskList)
        XCTAssertNotEqual(reopened.taskReadGeneration, generation, "Task details must not survive a revoked snapshot")
        let clearedGeneration = reopened.taskReadGeneration
        await reopened.load(.work("task"), force: true)
        XCTAssertEqual(reopened.taskReadGeneration, clearedGeneration, "A repeated denial must not restart the task page")
    }

    func testOtherItemsFilterUsesAllAuthorizedOfflinePagesAndDropsRevokedRows() async throws {
        let root = temp(); defer { try? FileManager.default.removeItem(at: root) }
        let api = OfflineAPI(start)
        await api.exposeMultipleExamPages()
        let client = CampusConnection(vault: TestVault(), root: root, send: { try await api.send($0) }, now: { self.start })
        try await client.connect(origin: origin, profile: "a")
        let page = CampusPage.work("exam")
        await client.load(page)
        await client.load(.courses)
        guard case .work(let slice) = client.pages[page]?.content,
              case .work(let full) = client.cachedOtherItems(for: page),
              case .courses(let roster) = client.pages[.courses]?.content else { return XCTFail("Missing offline records") }
        let course = try XCTUnwrap(roster.first)
        XCTAssertEqual(slice.items.count, 30)
        XCTAssertEqual(full.items.count, 33)
        let records = full.items.map { OtherItem(campus: $0, kind: .exam, courseNames: [course.id: course.name]) }
        let filtered = OtherItemsFilters(course: .course(course.id)).results(in: records, at: start, bookmarks: [])
        XCTAssertEqual(filtered.map(\.id), ["exam-32"])
        XCTAssertNil(client.cachedOtherItems(for: .grades))
        await api.rejectSnapshot()
        await client.load(page, force: true)
        XCTAssertNil(client.cachedOtherItems(for: page))
    }

    func testGradeConsentDuringAnOrdinaryDownloadReusesItsVersionCheck() async throws {
        for serverEditsAttendance in [false, true] {
            let root = temp(); defer { try? FileManager.default.removeItem(at: root) }
            let api = OfflineAPI(start)
            let client = CampusConnection(vault: TestVault(), root: root, send: { try await api.send($0) }, now: { self.start })
            try await client.connect(origin: origin, profile: "a")
            await api.pauseNext()
            let ordinary = Task { await client.load(.attendance) }
            await api.waitForDownload()
            let firstBatch = await api.lastBatch()
            XCTAssertFalse(try XCTUnwrap(firstBatch).contains("grades"))
            if serverEditsAttendance { await api.edit() }
            let resume = Task { await api.finishDownload() }
            let ok = await client.checkAll()
            await ordinary.value
            await resume.value
            XCTAssertTrue(ok)
            let counts = await api.counts(), lastBatch = await api.lastBatch()
            XCTAssertEqual(counts, serverEditsAttendance ? [2, 3] : [1, 2])
            XCTAssertEqual(lastBatch, serverEditsAttendance ? ["grades", "attendance"] : ["grades"])
            XCTAssertNotNil(client.savedGrades)
        }
    }

    func testBackgroundConsentCadenceAndLateReplyAfterLogout() async throws {
        let root = temp(); defer { try? FileManager.default.removeItem(at: root) }
        let api = OfflineAPI(start), vault = TestVault()
        var time = start
        let client = CampusConnection(vault:vault,root:root,send:{try await api.send($0)},now:{time})
        try await client.connect(origin:origin,profile:"a")
        await client.scheduledRefresh()
        try await client.setUpdatePolicy(.everyTwoDays)
        await client.scheduledRefresh()
        let noConsent = await api.counts(); XCTAssertEqual(noConsent,[0,0])
        try await client.setUpdatePolicy(.background)
        await client.scheduledRefresh()
        time.addTimeInterval(48 * 3600 - 1)
        await client.scheduledRefresh()
        let early = await api.counts(); XCTAssertEqual(early,[1,1])
        time.addTimeInterval(1); await api.edit(); await api.pauseNext()
        let pending = Task { await client.scheduledRefresh() }
        await api.waitForDownload()
        XCTAssertEqual(client.attendanceRecords?.report()?.totals.present,1)
        try await client.logout()
        try await client.connect(origin:origin,profile:"b",remember:false)
        await api.finishDownload(); await pending.value
        XCTAssertNil(client.attendanceRecords); XCTAssertNil(client.savedGrades); XCTAssertTrue(client.pages.isEmpty)
        XCTAssertEqual(client.updatePolicy,.manual)
        XCTAssertEqual((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? [],[])
    }

    func testWithdrawnGradesAreClearedEvenIfAnotherDownloadFails() async throws {
        let root = temp(); defer { try? FileManager.default.removeItem(at: root) }
        let api = OfflineAPI(start), vault = TestVault()
        func client() -> CampusConnection { CampusConnection(vault:vault,root:root,send:{try await api.send($0)},now:{self.start}) }
        let first = client()
        try await first.connect(origin:origin,profile:"a")
        _ = await first.checkAll()
        XCTAssertNotNil(first.savedGrades)
        await api.rejectGradeAccess(); await api.edit(); await api.omitOne()
        let ok = await first.checkAll()
        XCTAssertFalse(ok); XCTAssertNil(first.savedGrades); XCTAssertNotNil(first.account)
        let restored = client()
        await restored.load(.grades)
        XCTAssertNil(restored.savedGrades)
        XCTAssertNotNil(restored.account)
    }
}
