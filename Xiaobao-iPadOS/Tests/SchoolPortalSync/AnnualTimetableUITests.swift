import XCTest

@MainActor final class AnnualTimetableUITests: XCTestCase {
    private func command(_ path: String) async throws -> Bool {
        let base = try XCTUnwrap(URL(string:"__ANNUAL_FIXTURE_ORIGIN__"))
        guard base.host == "127.0.0.1" else { return false }
        var req = URLRequest(url:base.appendingPathComponent("control/annual/"+path)); req.httpMethod = "POST"
        let (_,res) = try await URLSession.shared.data(for:req)
        return (res as? HTTPURLResponse)?.statusCode == 200
    }

    private func check(_ name: String) async throws {
        for _ in 0..<25 {
            if try await command(name) { return }
            try await Task.sleep(for:.milliseconds(200))
        }
        XCTFail("Unexpected fixture state: "+name)
    }

    func testBackgroundRemindersAndPrivacyCleanup() async throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication(), system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        app.launchArguments += ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-xiaobao.cityWeather.followsCity.v1", "NO"]
        app.launch()
        func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
            XCTAssertTrue(element.waitForExistence(timeout: 12), file: file, line: line)
            element.tap()
        }
        for _ in 0..<70 {
            if try await command("baseline") { break }
            try await Task.sleep(for: .milliseconds(300))
        }
        try await check("baseline")
        tap(app.staticTexts["设置"].firstMatch); tap(app.buttons["settings-reminders-page"].firstMatch)
        let toggle = app.switches["settings-school-lesson-reminders"].firstMatch
        func tapSwitch() {
            XCTAssertTrue(toggle.waitForExistence(timeout: 8))
            XCTAssertTrue(toggle.isEnabled)
            // SwiftUI exposes the full Form row as one element; the thumb is trailing.
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.5)).tap()
        }
        XCTAssertEqual(toggle.value as? String, "0")
        tapSwitch()
        let labels = NSPredicate(format: "label IN %@", ["Allow","允许","允許"])
        let allow = system.buttons.matching(labels).firstMatch
        if allow.waitForExistence(timeout: 15) { allow.tap() }
        else if app.alerts.buttons.matching(labels).firstMatch.exists { app.alerts.buttons.matching(labels).firstMatch.tap() }
        try await check("qa-armed"); try await check("unchanged")
        XCUIDevice.shared.press(.home)
        // Wait offscreen. Reading delivered notifications later, rather than just pending,
        // distinguishes OS delivery from an app that quietly re-queues on activation.
        let deadline = Date().addingTimeInterval(145)
        while Date() < deadline {
            if try await command("qa-due") { break }
            try await Task.sleep(for: .seconds(1))
        }
        try await check("qa-due")
        app.activate()
        try await check("qa-delivered")
        // Relaunch after a failed identity read: do not read private plans or erase their queue.
        try await check("offline"); app.terminate(); app.launch()
        try await check("qa-cold-delivered")
        tap(app.staticTexts["设置"].firstMatch); tap(app.buttons["settings-reminders-page"].firstMatch)
        XCTAssertEqual(toggle.value as? String, "1"); tapSwitch()
        try await check("qa-personal-only"); try await check("unchanged")
        tap(app.navigationBars.buttons["设置"].firstMatch)
        tap(app.buttons["settings-personal-info-page"].firstMatch)
        tap(app.buttons["清除本机校宝登录资料"].firstMatch); tap(app.buttons["清除登录资料"].firstMatch)
        try await check("qa-cleared")
    }

    func testSavedYearDrivesTodayAndPlannerWhileLiveRecordsRefresh() async throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages","(zh-Hans)","-AppleLocale","zh_CN","-xiaobao.cityWeather.followsCity.v1","NO"]
        func tab(_ name: String) {
            let row = app.staticTexts[name].firstMatch
            XCTAssertTrue(row.waitForExistence(timeout:12),name); row.tap()
        }
        func course() -> XCUIElement {
            app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@", "Ceramics 2")).firstMatch
        }
        app.launch()
        XCTAssertTrue(course().waitForExistence(timeout:25))
        let nextDayPlan = app.buttons["today-next-school-day-plan"].firstMatch
        XCTAssertFalse(nextDayPlan.exists, "The after-school action is hidden during a lesson")
        try await check("baseline")
        tab("计划")
        let next = app.buttons["下一周"].firstMatch
        XCTAssertTrue(next.waitForExistence(timeout:8)); next.tap(); next.tap()
        try await check("unchanged")
        tab("今日"); XCTAssertTrue(course().waitForExistence(timeout:8))
        try await check("live")
        tab("设置"); try await check("deny")
        let refresh = app.buttons["settings-refresh-timetable"].firstMatch
        XCTAssertTrue(refresh.waitForExistence(timeout:8)); refresh.tap()
        let retained = app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@", "已保留上次的课表")).firstMatch
        XCTAssertTrue(retained.waitForExistence(timeout:10)); try await check("failed-once")
        try await check("offline"); app.terminate(); app.launch()
        XCTAssertTrue(course().waitForExistence(timeout:9))
        XCTAssertFalse(app.webViews.firstMatch.exists)
        tab("计划"); XCTAssertTrue(next.waitForExistence(timeout:8)); next.tap()
        try await check("failed-once") // Neither cold launch nor browsing attempted a schedule read.
        for scenario in ["-AnnualAfterSchool", "-AnnualHoliday"] {
            app.terminate()
            app.launchArguments.removeAll { $0 == "-AnnualAfterSchool" }
            app.launchArguments.append(scenario)
            app.launch()
            XCTAssertTrue(nextDayPlan.waitForExistence(timeout:9))
            let preview = app.descendants(matching:.any)["today-next-school-day"].firstMatch
            for text in ["10月8日", "Day 4", "Ceramics 4", "East studio"] {
                XCTAssertTrue(preview.label.contains(text), preview.label)
            }
            nextDayPlan.tap()
            let selected = app.buttons["planner-date"].firstMatch
            XCTAssertTrue(selected.waitForExistence(timeout:6))
            XCTAssertTrue((selected.value as? String)?.contains("10月8日") == true)
            try await check("failed-once")
        }
        tab("设置")
        let personal = app.buttons["settings-personal-info-page"].firstMatch
        XCTAssertTrue(personal.waitForExistence(timeout:8)); personal.tap()
        let clear = app.buttons["清除本机校宝登录资料"].firstMatch
        XCTAssertTrue(clear.waitForExistence(timeout:8)); clear.tap()
        let confirm = app.buttons["清除登录资料"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout:8)); confirm.tap()
        tab("今日")
        XCTAssertFalse(course().waitForExistence(timeout:2))
        XCTAssertFalse(nextDayPlan.exists)
        app.terminate(); app.launch()
        XCTAssertFalse(course().waitForExistence(timeout:2))
        try await check("failed-once")
    }

    func testPersonalPlanCanSwitchBetweenRotationAndWeekday() async throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages","(zh-Hans)","-AppleLocale","zh_CN","-xiaobao.cityWeather.followsCity.v1","NO"]
        app.launch()
        let loaded = app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@", "Ceramics 2")).firstMatch
        XCTAssertTrue(loaded.waitForExistence(timeout:25))
        try await check("baseline")

        func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
            XCTAssertTrue(element.waitForExistence(timeout: 8), file: file, line: line)
            element.tap()
        }
        let button = { (id: String) in app.buttons[id].firstMatch }
        tap(app.staticTexts["计划"].firstMatch); tap(button("planner-edit-mode")); tap(button("planner-add"))
        tap(button("按分钟设置时间"))
        let mode = button("plan-repeat-mode"), rotation = button("plan-rotation-day")
        tap(mode); tap(button("按星期"))
        XCTAssertTrue(button("plan-weekday").exists); XCTAssertFalse(rotation.exists)
        tap(mode); tap(button("按轮转 Day")); tap(rotation); tap(button("Day 3"))
        let title = app.textFields["plan-title"]
        tap(title); title.typeText("Sort paper proofs\n")
        tap(button("plan-save"))
        let prefix = "planner-shelf-plan-"
        let shelf = app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@", prefix)).firstMatch
        XCTAssertTrue(shelf.waitForExistence(timeout: 6))
        let occurrence = button("planner-plan-label-" + shelf.identifier.dropFirst(prefix.count))
        tap(button("planner-edit-mode"))
        XCUIDevice.shared.orientation = .portrait
        func show(_ date: String) {
            tap(button("planner-date")); tap(button("planner-month-" + date))
        }
        show("2026-09-11") // Friday, Day 3
        XCTAssertTrue(occurrence.waitForExistence(timeout: 6))
        show("2026-09-18") // Same weekday, different rotation
        XCTAssertTrue(occurrence.waitForNonExistence(timeout: 4))
        show("2026-09-21") // Monday, Day 3
        XCTAssertTrue(occurrence.waitForExistence(timeout: 6))
        show("2026-09-10"); tap(button("planner-edit-mode"))
        tap(shelf)
        XCTAssertTrue((rotation.value as? String) == "Day 3" || rotation.label.contains("Day 3"))
        tap(mode); tap(button("按星期"))
        tap(button("plan-weekday")); tap(button("星期二"))
        tap(button("plan-save")); tap(shelf)
        XCTAssertFalse(rotation.exists)
        let weekday = button("plan-weekday")
        XCTAssertTrue((weekday.value as? String) == "星期二" || weekday.label.contains("星期二"))
        tap(mode); tap(button("不重复")); tap(button("plan-save"))
        XCTAssertTrue(shelf.waitForNonExistence(timeout:5))
        try await check("unchanged")
    }
}
