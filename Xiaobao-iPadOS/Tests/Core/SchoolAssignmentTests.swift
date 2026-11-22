import XCTest
@testable import XiaobaoCore

@MainActor final class SchoolAssignmentTests: XCTestCase {
    private func row(_ id: String, _ title: String, due: String? = "2030-03-09T06:28:00.000Z",
                     eligible: Bool = true) -> SchoolPortalTasks.Row {
        .init(id: id, title: title, status: "pending", due: due, published: nil, course: "studio",
              courseName: "Design", kind: "essay", grading: "graded",
              score: .init(type: "letter", earned: nil, possible: nil, value: "private-fixture-mark"), deadlineEligible: eligible)
    }
    private func list(_ rows: [SchoolPortalTasks.Row], term: String = "spring") -> SchoolPortalTasks {
        .init(termLabel: .init(id: term, name: term), term: term, rows: rows)
    }

    // One disposable directory per test. No real preferences or student records.
    private func sandbox() throws -> (URL, UserDefaults) {
        let id = UUID().uuidString
        return (FileManager.default.temporaryDirectory.appendingPathComponent(id), try XCTUnwrap(UserDefaults(suiteName: id)))
    }

    func testColdReadAndCommitBoundary() async throws {
        let (dir, defaults) = try sandbox()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = SchoolAssignmentStore(directory: dir, defaults: defaults)
        let input = list([row("7","Raku kiln"), row("6","Clay archive", eligible: false)])
        let t = Date(timeIntervalSince1970: 1500000000)
        XCTAssertTrue(a.accept(input, owner: "a", current: true, at: t))
        let first = try XCTUnwrap(a.terms["spring"])
        XCTAssertTrue(a.accept(input, owner: "a", current: true, at: t.addingTimeInterval(60)))
        XCTAssertEqual(a.terms["spring"]?.fileID, first.fileID, "Unchanged contents should not be rewritten")
        XCTAssertNotEqual(a.terms["spring"]?.checked, first.checked)
        let restored = SchoolAssignmentStore(directory: dir, defaults: defaults)
        XCTAssertEqual(restored.snapshot(for: nil)?.rows.map(\.title), ["Raku kiln","Clay archive"])
        XCTAssertTrue(try XCTUnwrap(restored.snapshot(for: nil)).rows.allSatisfy { $0.score == nil && $0.grading == nil })
        let bytes = try Data(contentsOf: dir.appendingPathComponent(first.fileID.uuidString + ".plist"))
        let stored = try XCTUnwrap(try PropertyListSerialization.propertyList(from: bytes, format: nil) as? [[String: Any]])
        for object in stored { XCTAssertTrue(Set(object.keys).isDisjoint(with: ["score","grading","answer","feedback","attachments"])) }
        XCTAssertFalse(restored.accept(list([row("7","X"),row("7","Y")]), owner: "a", current: true))
        XCTAssertEqual(restored.terms["spring"]?.fileID, first.fileID)
    }

    func testSameCountUpdatesRemovalStableIDAndArchiveBoundaries() async throws {
        let (dir, defaults) = try sandbox()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = SchoolAssignmentStore(directory: dir, defaults: defaults)
        let now = Date(timeIntervalSince1970: 1500000000)
        XCTAssertTrue(a.accept(list([row("1","Silhouette")]), owner:"a", current:true))
        XCTAssertTrue(a.accept(list([row("1","Prior work")],term:"fall"), owner:"a", current:false))
        XCTAssertTrue(a.deadlines(at: now)?.isEmpty == true)
        XCTAssertTrue(a.configure(enabled: true, titles: false, registration: try XCTUnwrap(a.registration)))
        let old = try XCTUnwrap(a.deadlines(at: now)?.first)
        XCTAssertNil(old.title)
        XCTAssertTrue(a.accept(list([row("1","Silhouette revised",due:"2030-03-10T06:28:00.000Z")]), owner:"a", current:true))
        let moved = try XCTUnwrap(a.deadlines(at: now)?.first)
        XCTAssertEqual(old.id, moved.id); XCTAssertEqual(moved.fire.timeIntervalSince(old.fire), 86400)
        XCTAssertTrue(a.configure(enabled:true,titles:true,registration:try XCTUnwrap(a.registration)))
        XCTAssertEqual(a.deadlines(at: now)?.first?.title, "Silhouette revised")
        XCTAssertTrue(a.accept(list([row("2","No confirmed deadline",due:nil)]), owner:"a", current:true))
        XCTAssertTrue(a.deadlines(at:now)?.isEmpty == true)
        XCTAssertEqual(a.snapshot(for:"fall")?.rows.first?.title, "Prior work")
        XCTAssertTrue(a.accept(list([]), owner:"a", current:true))
        XCTAssertEqual(a.snapshot(for:nil)?.rows.count, 0)
    }

    func testUnreadablePriorRegistrationCannotReturnAfterSwitch() async throws {
        let (dir, defaults) = try sandbox()
        defer { try? FileManager.default.removeItem(at: dir) }
        let old = SchoolAssignmentStore(directory: dir, defaults: defaults)
        XCTAssertTrue(old.accept(list([row("1","Pigment trial")]), owner: "first", current: true))
        // Model an unavailable protected index without changing permissions outside the fixture.
        let path = dir.appendingPathComponent("index.plist")
        let temporary = dir.appendingPathComponent("held-test-index")
        try FileManager.default.moveItem(at: path, to: temporary)
        let relaunch = SchoolAssignmentStore(directory: dir, defaults: defaults)
        XCTAssertTrue(relaunch.hasRegistration); XCTAssertNil(relaunch.owner)
        relaunch.verified("second")
        XCTAssertFalse(relaunch.hasRegistration)
        try FileManager.default.moveItem(at: temporary, to: path)
        relaunch.restore()
        XCTAssertNil(relaunch.snapshot(for: nil))
    }

    func testDeclaredFailureOrLossOfPermissionDoesNotCommitAnEmptyList() async throws {
        let (dir, defaults) = try sandbox()
        defer { try? FileManager.default.removeItem(at: dir) }
        let disk = SchoolAssignmentStore(directory: dir, defaults: defaults)
        let student = String(repeating: "9", count: 64)
        var issue: SchoolPortalIssue?
        let store = SchoolPortalStore(selected: true) { op, _ in
            if op == .identity { return try JSONSerialization.data(withJSONObject: ["owner":student]) }
            if let issue { throw issue }
            let term = ["id":"spring","name":"Studio term"]
            let rows = [["id":"3","title":"Paper binding","status":"pending"]]
            return try JSONSerialization.data(withJSONObject: ["owner":student,"value":["term":"Studio term","termLabel":term,"rows":rows]])
        }
        store.onCompleteTasks = { list, owner, current in _ = disk.accept(list, owner:owner, current:current) }
        store.onRevokeTasks = { disk.forget() }
        await store.verify(); await store.loadTasks()
        let confirmed = try XCTUnwrap(disk.terms["spring"]?.checked)
        issue = .format; await store.loadTasks(force: true)
        XCTAssertNil(store.tasks)
        XCTAssertEqual(disk.terms["spring"]?.checked, confirmed)
        XCTAssertEqual(disk.snapshot(for:nil)?.rows.first?.id, "3")
        issue = .denied; await store.loadTasks(force: true)
        XCTAssertNil(disk.snapshot(for: nil)); XCTAssertFalse(disk.hasRegistration)
        issue = nil; await store.loadTasks(force: true)
        store.invalidate(.expired); XCTAssertNil(disk.snapshot(for: nil))
    }

    func testReviewPersistsAcrossRestartAndSwitchDoesNotInheritFilesOrPreferences() async throws {
        let (dir, defaults) = try sandbox()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = SchoolAssignmentStore(directory:dir, defaults:defaults)
        XCTAssertTrue(a.accept(list([row("3","Glaze trial")]),owner:"a",current:true))
        let token = try XCTUnwrap(a.registration)
        XCTAssertTrue(a.configure(enabled:true,titles:true,registration:token))
        a.reviewAccount()
        let b = SchoolAssignmentStore(directory:dir, defaults:defaults)
        XCTAssertTrue(b.reviewing); XCTAssertNil(b.snapshot(for:nil)); XCTAssertFalse(b.enabled)
        b.verified("b")
        XCTAssertNil(b.snapshot(for:nil)); XCTAssertFalse(b.configure(enabled:true,titles:true,registration:token))
        XCTAssertTrue(b.accept(list([row("3","Mosaic")]),owner:"b",current:true))
        XCTAssertFalse(b.enabled); XCTAssertNotEqual(token,b.registration)
        XCTAssertFalse(b.accept(list([row("3","Stale reply")]),owner:"a",current:true))
        XCTAssertEqual(b.snapshot(for:nil)?.rows.first?.title,"Mosaic")
        b.forget()
        XCTAssertNil(SchoolAssignmentStore(directory:dir,defaults:defaults).snapshot(for:nil))
    }
}
