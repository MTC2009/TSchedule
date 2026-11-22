import XCTest

@MainActor final class AssignmentCacheUITests: XCTestCase {
    private func control(_ name: String) async throws -> Bool {
        let url = try XCTUnwrap(URL(string: "__ASSIGNMENT_FIXTURE_ORIGIN__"))
        guard url.host == "127.0.0.1" else { return false }
        var req = URLRequest(url: url.appendingPathComponent("control/assignments/" + name))
        req.httpMethod = "POST"
        return try await (URLSession.shared.data(for: req).1 as? HTTPURLResponse)?.statusCode == 200
    }

    private func check(_ name: String, file: StaticString = #filePath, line: UInt = #line) async throws {
        let until = Date().addingTimeInterval(30)
        repeat {
            if try await control(name) { return }
            try await Task.sleep(for: .milliseconds(250))
        } while Date() < until
        XCTFail("Fixture did not confirm " + name, file: file, line: line)
    }

    func testOfflineReopenRetimingWithdrawalAndAccountChange() async throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication(), system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let english = "__ASSIGNMENT_LANGUAGE__" == "en"
        let labels = ["设置":"Settings", "计划":"Planner", "我的任务":"My Tasks", "重试":"Try again", "完整校宝":"Xiaobao website"]
        func label(_ zh: String) -> String { english ? (labels[zh] ?? zh) : zh }
        app.launchArguments = ["-AppleLanguages",english ? "(en)" : "(zh-Hans)","-AppleLocale",english ? "en_US" : "zh_CN","-xiaobao.cityWeather.followsCity.v1","NO"]
        func tap(_ node: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
            XCTAssertTrue(node.waitForExistence(timeout: 15), file: file, line: line); node.tap()
        }
        func tab(_ zh: String) { tap(app.staticTexts[label(zh)].firstMatch) }
        func find(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
        func see(_ id: Int, _ text: String, file: StaticString = #filePath, line: UInt = #line) {
            let match = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "task-card-\(id)", text)).firstMatch
            XCTAssertTrue(match.waitForExistence(timeout: 20), text, file: file, line: line)
        }
        func note(_ name: String) {
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = name
            shot.lifetime = .keepAlways; add(shot)
        }
        func toggle(_ id: String) {
            let button = app.switches[id].firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 10)); XCTAssertTrue(button.isEnabled)
            button.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.5)).tap()
        }
        func settings() { tab("设置"); tap(find("settings-reminders-page")) }
        func pickArchive() {
            tap(app.buttons["school-term-menu"].firstMatch)
            tap(app.buttons.matching(NSPredicate(format:"label CONTAINS %@", "Print archive")).firstMatch)
        }
        app.launch(); tab("我的任务"); see(81,"Copperplate study")
        XCTAssertTrue(find("assignment-last-check").exists)
        settings(); toggle("assignment-alert-enable")
        let allowLabel = NSPredicate(format: "label IN %@", ["Allow","允许","允許"])
        let allow = system.buttons.matching(allowLabel).firstMatch
        if allow.waitForExistence(timeout: 15) { allow.tap() }
        else if app.alerts.buttons.matching(allowLabel).firstMatch.exists { app.alerts.buttons.matching(allowLabel).firstMatch.tap() }
        try await check("armed")
        try await check("archive-unread")
        // Both details were fetched while Settings was open. A file request must still be zero.
        try await check("lazily-read")
        tab("我的任务"); tap(find("task-card-82"))
        for text in ["Arrange the four samples","Mounted on linen","The edge is even"] {
            XCTAssertTrue(app.staticTexts[text].firstMatch.waitForExistence(timeout:15),text)
        }
        tap(app.buttons["mounting.txt"].firstMatch)
        try await check("downloaded")
        let cancel = app.buttons.matching(NSPredicate(format:"label IN %@", ["Cancel","取消"])).firstMatch
        tap(cancel)
        tap(app.navigationBars.buttons[label("我的任务")].firstMatch)

        pickArchive(); see(83,"Etching plate")
        tap(app.buttons["task-filter-reset"].firstMatch); see(81,"Copperplate study")

        try await check("offline"); app.terminate(); app.launch(); tab("我的任务")
        see(81, "Copperplate study"); see(82, "Ink inventory")
        XCTAssertTrue(find("assignment-last-check").exists)
        tap(find("task-card-82"))
        for text in ["Arrange the four samples","Mounted on linen","The edge is even"] {
            XCTAssertTrue(app.staticTexts[text].firstMatch.waitForExistence(timeout:15),text)
        }
        XCTAssertFalse(app.buttons["mounting.txt"].firstMatch.isEnabled)
        tap(app.navigationBars.buttons[label("我的任务")].firstMatch)
        try await check("offline-verified"); note("Cold relaunch without school network")
        pickArchive(); see(83,"Etching plate"); try await check("archive-local")
        tap(app.buttons["task-filter-reset"].firstMatch); see(81,"Copperplate study")

        try await check("moved"); try await check("online")
        tap(app.buttons[label("重试")].firstMatch); try await check("retimed")
        // Navigating back to Tasks uses the shipping foreground refresh, not a test driver.
        try await check("malformed"); tab("计划"); tab("我的任务")
        try await check("retained"); see(81, "Copperplate study")
        XCTAssertTrue(find("assignment-update-issue").exists)
        try await check("moved"); tap(app.buttons[label("重试")].firstMatch)
        settings(); toggle("assignment-alert-titles"); try await check("named")
        try await check("withdrawn"); tab("我的任务"); see(84, "Pigment notes")
        XCTAssertFalse(find("task-card-81").exists); try await check("removed")
        // Restore a live named reminder, then interrupt a website account review.
        try await check("moved"); tab("计划"); tab("我的任务")
        try await check("rearmed"); see(81,"Copperplate study")
        tap(app.buttons.matching(NSPredicate(format:"label == %@", label("完整校宝"))).firstMatch)
        try await check("other"); try await check("offline")
        app.terminate(); app.launch(); tab("我的任务"); try await check("held")
        XCTAssertFalse(find("task-card-81").exists); XCTAssertFalse(find("task-card-82").exists)
        try await check("online"); app.terminate(); app.launch(); tab("我的任务")
        see(81, "Bookbinding draft"); XCTAssertFalse(find("task-card-82").exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format:"label CONTAINS %@", "Copperplate study")).firstMatch.exists)
        tap(find("task-card-81"))
        XCTAssertTrue(app.staticTexts["Cut a square window"].firstMatch.waitForExistence(timeout:15))
        XCTAssertFalse(app.staticTexts["Arrange the four samples"].firstMatch.exists)
        tap(app.navigationBars.buttons[label("我的任务")].firstMatch)
        try await check("isolated"); note("Second student with overlapping task ID")
        try await check("offline"); app.terminate(); app.launch(); tab("我的任务")
        see(81, "Bookbinding draft"); XCTAssertFalse(find("task-card-82").exists)
        try await check("other-offline")
        tap(app.buttons["school-term-menu"].firstMatch)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format:"label CONTAINS %@", "Print archive")).firstMatch.exists)
    }
}
