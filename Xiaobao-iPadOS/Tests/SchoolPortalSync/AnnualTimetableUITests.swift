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
        let free = app.buttons["planner-free-660"].firstMatch
        func checkSchoolCards(_ name: String) {
            let teaching = app.buttons["Drafting"].firstMatch
            XCTAssertTrue(free.waitForExistence(timeout: 8))
            XCTAssertTrue(teaching.waitForExistence(timeout: 8))
            XCTAssertEqual(free.label, "空节")
            XCTAssertGreaterThanOrEqual(free.frame.height, 44)
            XCTAssertEqual(free.frame.height, teaching.frame.height, accuracy: 1)
            XCTAssertEqual(free.frame.width, teaching.frame.width, accuracy: 1)
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = name; shot.lifetime = .keepAlways; add(shot)
        }
        checkSchoolCards("Published school cards – week")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.buttons["Block 10"].firstMatch.waitForExistence(timeout:8))
        for title in ["班会","午餐","Print lab","晚餐"] {
            XCTAssertTrue(app.buttons[title].firstMatch.exists, title)
        }
        checkSchoolCards("Published school cards – day")
        func checkRange(_ button: XCUIElement, _ expected: String) {
            XCTAssertTrue(button.waitForExistence(timeout: 8))
            button.tap()
            let interval = app.staticTexts["planner-school-time-range"].firstMatch
            XCTAssertTrue(interval.waitForExistence(timeout: 5))
            XCTAssertEqual(interval.label, expected)
            XCTAssertTrue(app.staticTexts["timetable-detail-teacher"].firstMatch.exists)
            app.buttons["完成"].firstMatch.tap()
            XCTAssertTrue(interval.waitForNonExistence(timeout: 6))
        }
        checkRange(app.buttons["Ceramics 2"].firstMatch, "08:00 – 09:20")
        checkRange(free, "11:00 – 11:40")
        checkRange(app.buttons["Drafting"].firstMatch, "11:50 – 12:30")
        checkRange(app.buttons["午餐"].firstMatch, "12:30 – 13:25")
        XCTAssertFalse(app.buttons["Block 9"].firstMatch.exists)
        XCTAssertFalse(app.buttons["晚自习"].firstMatch.exists)
        XCUIDevice.shared.orientation = .landscapeLeft
        tab("设置")
        app.buttons["settings-appearance-page"].firstMatch.tap()
        app.buttons["settings-appearance"].firstMatch.tap()
        XCTAssertTrue(app.switches["weather-automatic"].firstMatch.waitForExistence(timeout:8))
        XCTAssertTrue(app.descendants(matching:.any)["weather-picker"].firstMatch.exists)
        XCTAssertFalse(app.descendants(matching:.any)["sky-season-picker"].firstMatch.exists)
        app.buttons["完成"].firstMatch.tap()
        app.navigationBars.buttons["设置"].firstMatch.tap()
        app.buttons["settings-personal-info-page"].firstMatch.tap()
        let boarding = app.switches["settings-boarding-routine"].firstMatch
        XCTAssertTrue(boarding.waitForExistence(timeout:8))
        XCTAssertEqual(boarding.value as? String, "0")
        boarding.coordinate(withNormalizedOffset: CGVector(dx:0.96, dy:0.5)).tap()
        XCTAssertEqual(boarding.value as? String, "1")
        app.navigationBars.buttons["设置"].firstMatch.tap()
        tab("计划")
        XCTAssertTrue(app.buttons["晚自习"].firstMatch.waitForExistence(timeout:8))
        XCUIDevice.shared.orientation = .portrait
        func showDate(_ key: String) {
            app.buttons["planner-date"].firstMatch.tap()
            let day = app.buttons["planner-month-"+key].firstMatch
            XCTAssertTrue(day.waitForExistence(timeout:8), "Month picker must offer "+key); day.tap()
        }
        showDate("2026-09-11") // Friday: Thursday night's breakfast, no Friday evening stay
        XCTAssertTrue(app.buttons["早餐"].firstMatch.waitForExistence(timeout:8), "Friday retains a labeled breakfast")
        XCTAssertFalse(app.buttons["晚自习"].firstMatch.exists, "No Friday overnight stay")
        showDate("2026-09-13") // Sunday return is not a Sunday teaching day.
        XCTAssertTrue(app.buttons["晚自习"].firstMatch.waitForExistence(timeout:8), "Sunday return is visible without lessons")
        XCTAssertFalse(app.buttons["早餐"].firstMatch.exists)
        XCTAssertFalse(app.buttons["Block 10"].firstMatch.exists)
        showDate("2026-09-17")
        XCTAssertTrue(app.buttons["Ceramics 1"].firstMatch.waitForExistence(timeout:8))
        XCTAssertTrue(app.buttons["Guest recital"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["白天按轮转课表显示"].firstMatch.exists)
        showDate("2026-09-18")
        XCTAssertTrue(app.buttons["Ceramics 2"].firstMatch.waitForExistence(timeout:8))
        XCTAssertFalse(app.buttons["Guest recital"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["白天按轮转课表显示"].firstMatch.exists)
        XCUIDevice.shared.orientation = .landscapeLeft
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
        app.terminate(); app.launchArguments.append("-AnnualPartialDay"); app.launch()
        XCTAssertTrue(app.staticTexts["白天按轮转课表显示"].firstMatch.waitForExistence(timeout:9))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@", "Ceramics 1")).firstMatch.exists)
        app.launchArguments.removeAll { $0 == "-AnnualPartialDay" }
        // Cold offline launch in a different term, well beyond all sampled weeks.
        app.terminate(); app.launchArguments.append("-AnnualNextTerm"); app.launch()
        let springLesson = app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@", "Ceramics 1")).firstMatch
        XCTAssertTrue(springLesson.waitForExistence(timeout:9))
        tab("计划")
        let springDate = app.buttons["planner-week-day-2027-05-14"].firstMatch
        XCTAssertTrue(springDate.waitForExistence(timeout:8))
        XCTAssertFalse(springDate.label.contains("未载入"))
        XCTAssertTrue(app.buttons["Ceramics 1"].firstMatch.exists)
        try await check("failed-once") // No portal fetch to restore or move into another term.
        app.launchArguments.removeAll { $0 == "-AnnualNextTerm" }
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

    func testSharedDisplayAndPersonalCourse() async throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-DisplayEvening",
                               "-xiaobao.cityWeather.followsCity.v1", "NO"]
        app.launch()
        func tap(_ item: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
            XCTAssertTrue(item.waitForExistence(timeout: 12), file: file, line: line); item.tap()
        }
        func tab(_ name: String) { tap(app.staticTexts[name].firstMatch) }
        func button(_ id: String) -> XCUIElement { app.buttons[id].firstMatch }
        func flip(_ id: String, to value: String, file: StaticString = #filePath, line: UInt = #line) {
            let item = app.switches[id].firstMatch
            XCTAssertTrue(item.waitForExistence(timeout: 8), file: file, line: line)
            item.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.5)).tap()
            XCTAssertEqual(item.value as? String, value, file: file, line: line)
        }
        func settings(_ page: String) { tab("设置"); tap(button(page)) }
        func back() { tap(app.navigationBars.buttons["设置"].firstMatch) }
        func todayHas(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
            let lens = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "课程时间透镜")).firstMatch
            let ready = NSPredicate { _, _ in lens.exists && (lens.value as? String)?.contains(text) == true }
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: nil)], timeout: 12),
                           .completed, "Current timeline should say " + text, file: file, line: line)
        }
        XCTAssertTrue(app.descendants(matching: .any)["verified-school-today"].firstMatch.waitForExistence(timeout: 25))
        try await check("baseline")
        settings("settings-personal-info-page"); flip("settings-boarding-routine", to: "1"); back()
        tab("今日"); todayHas("晚自习")
        XCTAssertTrue(app.staticTexts["晚自习教室"].firstMatch.exists)
        XCTAssertFalse(app.buttons["today-next-school-day-plan"].firstMatch.exists)
        tap(button("today-timetable-detail"))
        let teacher = app.staticTexts["timetable-detail-teacher"].firstMatch
        XCTAssertTrue(teacher.waitForExistence(timeout: 7))
        XCTAssertEqual(teacher.label, "教师：—")
        tap(button("完成"))
        tab("计划"); tap(button("planner-edit-mode")); tap(button("planner-add"))
        tap(button("plan-course-kind")); tap(button("外考课程"))
        let name = "Field sketch", title = app.textFields["plan-title"]
        tap(title); title.typeText(name + "\n")
        tap(button("plan-save"))
        XCTAssertTrue(title.waitForNonExistence(timeout: 12))
        tap(button("planner-edit-mode"))
        tab("今日"); todayHas(name)
        settings("settings-timetable-page"); flip("timetable-shows-examCourse", to: "0"); back()
        tab("今日")
        // The covered first study is not recreated when the personal course is hidden.
        todayHas("TSSA")
        settings("settings-timetable-page"); flip("timetable-shows-tssa", to: "0"); back()
        tab("今日"); todayHas("晚自习")
        tab("计划")
        XCTAssertTrue(button("晚自习").waitForExistence(timeout: 8))
        XCTAssertFalse(button("TSSA / Sound design").exists)
        app.terminate(); app.launchArguments.removeAll { $0 == "-DisplayEvening" }
        app.launchArguments.append("-DisplaySession"); app.launch()
        todayHas("晚自习")
        try await check("unchanged")
    }

    func testScopedRemovalFromTheEditorAndUndo() async throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages","(zh-Hans)","-AppleLocale","zh_CN","-xiaobao.cityWeather.followsCity.v1","NO"]
        app.launch()
        let lesson = app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@", "Ceramics 2")).firstMatch
        XCTAssertTrue(lesson.waitForExistence(timeout:25))
        try await check("baseline")
        func tap(_ b: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
            let ready = NSPredicate { _, _ in b.exists && b.isEnabled && b.isHittable }
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: nil)], timeout: 12),
                           .completed, b.description, file: file, line: line)
            b.tap()
        }
        func button(_ id: String) -> XCUIElement { app.buttons[id].firstMatch }
        func waitForBoard(file: StaticString = #filePath, line: UInt = #line) {
            // A shelf hidden behind the editor is not evidence that a record was removed.
            XCTAssertTrue(app.textFields["plan-title"].waitForNonExistence(timeout: 14), file: file, line: line)
        }
        func openPlan(_ name: String, repeats: Bool) {
            tap(button("planner-add"))
            let title = app.textFields["plan-title"]; tap(title); title.typeText(name + "\n")
            if repeats {
                tap(button("按分钟设置时间"))
                tap(button("plan-repeat-mode")); tap(button("按轮转 Day"))
                tap(button("plan-rotation-day")); tap(button("Day 3"))
            }
            tap(button("plan-save")); waitForBoard()
        }
        tap(app.staticTexts["计划"].firstMatch); tap(button("planner-edit-mode"))
        func saved(_ name: String) -> XCUIElement {
            app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "planner-shelf-plan-", name)).firstMatch
        }
        let ordinary = saved("Press check"), series = saved("Print rack")
        openPlan("Press check", repeats: false)
        tap(ordinary); tap(button("plan-editor-remove")); XCTAssertFalse(button("这次及以后").exists)
        tap(button("确认移除")); waitForBoard(); XCTAssertTrue(ordinary.waitForNonExistence(timeout:8))
        tap(button("planner-undo")); XCTAssertTrue(ordinary.waitForExistence(timeout:8))

        openPlan("Print rack", repeats: true)
        tap(series); tap(button("plan-editor-remove"))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@", "2026-09-11")).firstMatch.exists)
        tap(button("仅这次")); waitForBoard()
        tap(series); tap(button("plan-editor-remove"))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@", "2026-09-21")).firstMatch.exists)
        tap(button("这次及以后")); waitForBoard(); XCTAssertTrue(series.waitForNonExistence(timeout:8))
        XCTAssertTrue(ordinary.exists)
        tap(button("planner-undo")); XCTAssertTrue(series.waitForExistence(timeout:8))
        try await check("unchanged")
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
