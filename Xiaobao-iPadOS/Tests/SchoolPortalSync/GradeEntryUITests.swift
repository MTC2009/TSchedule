import XCTest

private let fixtureOriginURL = "__FIXTURE_ORIGIN__"

/// Built only by ipad-smoke.py in a separate fixture application and XCTest runner.
@MainActor final class GradeEntryUITests: XCTestCase {
    func testNativeAttendanceAndExplicitGPARefresh() async throws {
        continueAfterFailure = false; XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages","(zh-Hans)","-AppleLocale","zh_CN",
                               "-xiaobao.portal.selected","YES","-xiaobao.cityWeather.followsCity.v1","NO"]
        app.launch()
        func tap(_ title: String) {
            let item = app.staticTexts[title].firstMatch; XCTAssertTrue(item.waitForExistence(timeout:15)); item.tap()
        }
        func expect(_ score: Double) {
            let readout = app.descendants(matching:.any).matching(identifier:"gpa-readout").firstMatch
            let updated = NSPredicate { _,_ in readout.exists && Double(readout.label) == score }
            XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:updated,object:nil)],timeout:18),.completed)
            XCTAssertFalse(app.buttons["允许获取成绩"].exists); XCTAssertFalse(app.webViews.firstMatch.exists)
        }
        tap("GPA"); expect(2.75)
        let refresh = app.buttons["gpa-check-grades"].firstMatch
        XCTAssertTrue(refresh.label.contains("刷新 GPA")); refresh.tap(); expect(3.25)
        tap("我的考勤")
        XCTAssertTrue(app.descendants(matching:.any).matching(identifier:"attendance-ring").firstMatch.waitForExistence(timeout:16))
        XCTAssertFalse(app.webViews.firstMatch.exists); XCTAssertFalse(app.buttons["打开校宝"].exists)
        let course = app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@", "色彩观察")).firstMatch
        XCTAssertTrue(course.waitForExistence(timeout:8))
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "native-attendance"; shot.lifetime = .keepAlways; add(shot)
        course.tap()
        XCTAssertTrue(app.descendants(matching:.any).matching(identifier:"school-attendance-records").firstMatch.waitForExistence(timeout:10))
        XCTAssertFalse(app.webViews.firstMatch.exists)
        tap("GPA"); expect(3.25)
        checkGroupForecast(in: app)
        tap("设置"); tap("GPA")
        let edited = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "gpa-course-")).firstMatch
        let showsForecast = NSPredicate { _, _ in edited.exists && (edited.value as? String)?.contains("87.5%") == true }
        func expectForecast() {
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: showsForecast, object: nil)], timeout: 12), .completed)
        }
        expectForecast()
        refresh.tap()
        XCTAssertTrue(refresh.waitForExistence(timeout: 10))
        let finished = NSPredicate { _, _ in refresh.exists && refresh.isEnabled && refresh.label.contains("刷新 GPA") }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: finished, object: nil)], timeout: 18), .completed)
        expectForecast()
        let restore = app.buttons["gpa-restore-actual"].firstMatch
        XCTAssertTrue(restore.waitForExistence(timeout: 8)); restore.tap()
        XCTAssertTrue(restore.waitForNonExistence(timeout: 6))
        expect(3.25)
        XCTAssertFalse((edited.value as? String)?.contains("预测成绩") == true)
        tap("我的考勤")
        let daily = app.buttons["日常"].firstMatch
        XCTAssertTrue(daily.waitForExistence(timeout:10)); daily.tap()
        let retry = app.buttons["重试"]
        XCTAssertTrue(retry.waitForExistence(timeout:12))
        XCTAssertFalse(app.staticTexts["暂无考勤记录"].exists)
        XCTAssertFalse(app.buttons["打开校宝登录"].exists); XCTAssertFalse(app.webViews.firstMatch.exists)
        retry.tap()
        XCTAssertTrue(app.staticTexts["暂无考勤记录"].waitForExistence(timeout:12))
        XCTAssertFalse(retry.exists); XCTAssertFalse(app.webViews.firstMatch.exists)

        let origin = try XCTUnwrap(URL(string: fixtureOriginURL))
        XCTAssertEqual(origin.host, "127.0.0.1")
        var request = URLRequest(url: origin.appendingPathComponent("control/fail-grade-refresh"))
        request.httpMethod = "POST"
        let (_, reply) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((reply as? HTTPURLResponse)?.statusCode, 200)
        tap("GPA"); expect(3.25); refresh.tap()
        XCTAssertTrue(app.staticTexts["school-grade-sync-issue"].firstMatch.waitForExistence(timeout: 15))
        expect(3.25)
        app.terminate()
        app.launchArguments.append("-GradeFixtureOffline")
        app.launch()
        tap("GPA"); expect(3.25)
        XCTAssertTrue(app.staticTexts["当前未联网，显示上次保存的成绩。"].firstMatch.exists)
        XCTAssertTrue(edited.waitForExistence(timeout: 6))
        edited.tap()
        XCTAssertTrue(app.descendants(matching: .any)["course-published-total"].firstMatch.waitForExistence(timeout: 8))
        // Atelier itself is a subtotal row; the group with released items has a disclosure.
        let cachedGroup = app.descendants(matching: .any)["gpa-assessment-group-Atelier / Palette"].firstMatch
        if !cachedGroup.exists { app.swipeUp() }
        XCTAssertTrue(cachedGroup.waitForExistence(timeout: 6))
    }
    private func checkGroupForecast(in app: XCUIApplication) {
        func element(_ id: String) -> XCUIElement {
            app.descendants(matching: .any).matching(identifier: id).firstMatch
        }
        let course = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "gpa-course-")).firstMatch
        XCTAssertTrue(course.waitForExistence(timeout: 10), "Course tile"); course.tap()
        let add = element("course-forecast-add")
        XCTAssertTrue(add.waitForExistence(timeout: 12), "Course detail add"); add.tap()
        let menu = app.buttons["course-forecast-category"], save = app.buttons["course-forecast-save"]
        XCTAssertTrue(menu.waitForExistence(timeout: 8), "Group menu"); XCTAssertFalse(save.isEnabled)
        XCTAssertFalse(app.textFields["course-forecast-weight"].exists)
        let mark = app.textFields["course-forecast-mark"]
        mark.tap(); mark.typeText("75\n")
        XCTAssertFalse(save.isEnabled, "An available group must be selected")
        func share(_ expected: String, id: String = "course-forecast-group-share",
                   file: StaticString = #filePath, line: UInt = #line) {
            let row = element(id)
            XCTAssertTrue(row.waitForExistence(timeout: 4), id, file: file, line: line)
            XCTAssertEqual(row.value as? String, expected, id, file: file, line: line)
        }
        func selectGroup(_ title: String) {
            menu.tap()
            // A populated group's disclosure behind the sheet has the same spoken
            // name; the picker options, unlike the disclosure, are menu cells.
            let option = app.collectionViews.cells.buttons.matching(NSPredicate(
                format: "label == %@ AND NOT (identifier BEGINSWITH %@)", title, "gpa-assessment-group-"
            )).firstMatch
            XCTAssertTrue(option.waitForExistence(timeout: 5)); option.tap()
        }
        selectGroup("Atelier"); share("64%"); XCTAssertFalse(save.isEnabled, "Parents aggregate their child groups")
        selectGroup("Atelier / Palette")
        share("25%"); share("16%", id: "course-forecast-course-share")
        selectGroup("Critique")
        share("36%")
        XCTAssertTrue(save.isEnabled, "A numeric score and selected group enable saving")
        save.tap()
        XCTAssertTrue(menu.waitForNonExistence(timeout: 5), "Saving closes the active forecast editor")
        let result = element("course-forecast-result")
        XCTAssertTrue(result.waitForExistence(timeout: 6), "Calculated local forecast"); XCTAssertEqual(result.value as? String, "81.4%")
        let draft = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "course-forecast-item-")).firstMatch
        draft.tap(); XCTAssertTrue(menu.label.contains("Critique") || (menu.value as? String) == "Critique")
        // Saving an existing value with the score field focused must take one tap, not
        // one tap on a modal number pad and another on the actual toolbar button.
        mark.tap(); save.tap()
        XCTAssertTrue(menu.waitForNonExistence(timeout: 5), "A focused score does not intercept Save")
        draft.tap()
        app.buttons["course-forecast-remove"].tap()
        XCTAssertTrue(result.waitForNonExistence(timeout: 6))
        func addToGradedLeaf(_ text: String) {
            add.tap(); XCTAssertTrue(menu.waitForExistence(timeout: 8))
            selectGroup("Atelier / Palette")
            mark.tap(); mark.typeText(text + "\n"); save.tap()
            XCTAssertTrue(menu.waitForNonExistence(timeout: 6))
        }
        // Only the two released task percentages (including zero) are eligible.
        // This leaf is nested; the other root is genuinely ungraded, not a zero.
        addToGradedLeaf("100")
        XCTAssertTrue(result.waitForExistence(timeout: 8)); XCTAssertEqual(result.value as? String, "90.0%")
        addToGradedLeaf("20"); XCTAssertEqual(result.value as? String, "87.5%")
    }

    func testOpeningGradesRenewsOnceWithoutPresentingAWebsite() async throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
                                "-xiaobao.portal.selected", "YES", "-xiaobao.cityWeather.followsCity.v1", "NO"]
        app.launch()
        let readout = app.descendants(matching: .any).matching(identifier: "gpa-readout").firstMatch
        func tap(_ tab: String) {
            let label = app.staticTexts[tab].firstMatch
            XCTAssertTrue(label.waitForExistence(timeout: 12)); label.tap()
        }
        func expectGrade(_ grade: Double) {
            let visible = NSPredicate { _, _ in readout.exists && Double(readout.label) == grade }
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: visible, object: nil)], timeout: 22), .completed)
            XCTAssertFalse(app.webViews.firstMatch.exists)
        }
        // Only the test runner can release the fixture's first page or revoke its synthetic session.
        func control(_ mode: String) async throws {
            let root = try XCTUnwrap(URL(string: fixtureOriginURL))
            XCTAssertEqual(root.host, "127.0.0.1")
            var request = URLRequest(url: root.appendingPathComponent("control").appendingPathComponent(mode))
            request.httpMethod = "POST"
            let (_, response) = try await URLSession.shared.data(for: request)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        }
        tap("GPA")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "school-identity-pending").firstMatch.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["打开校宝登录"].exists); XCTAssertFalse(app.webViews.firstMatch.exists)
        try await control("ready"); expectGrade(2.75)
        tap("设置"); try await control("expire")
        tap("GPA"); app.buttons["gpa-check-grades"].tap(); expectGrade(3.5)
        tap("设置"); try await control("revoke-device")
        tap("GPA"); app.buttons["gpa-check-grades"].tap()
        XCTAssertTrue(app.buttons["打开校宝登录"].waitForExistence(timeout: 22))
        XCTAssertFalse(readout.exists); XCTAssertFalse(app.webViews.firstMatch.exists)
        tap("设置"); tap("GPA")
        XCTAssertTrue(app.buttons["打开校宝登录"].exists); XCTAssertFalse(app.webViews.firstMatch.exists)
    }

    func testExplicitlyEnrolledPasswordStartsANewSession() async throws {
        continueAfterFailure = false; XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages","(zh-Hans)","-AppleLocale","zh_CN",
                                "-xiaobao.portal.selected","YES","-xiaobao.cityWeather.followsCity.v1","NO"]
        app.launch()
        func tap(_ tab: String) {
            let item = app.staticTexts[tab].firstMatch
            XCTAssertTrue(item.waitForExistence(timeout:12), tab); item.tap()
        }
        func control(_ path: String, _ input: String? = nil) async throws {
            let base = try XCTUnwrap(URL(string:"__FIXTURE_STUDENT_ORIGIN__"))
            guard base.host == "127.0.0.1" else { return XCTFail("Non-fixture destination") }
            var req = URLRequest(url:base.appendingPathComponent("control/"+path)); req.httpMethod = "POST"
            if let input { req.httpBody = Data(input.utf8) }
            let (_,res) = try await URLSession.shared.data(for:req); XCTAssertEqual((res as? HTTPURLResponse)?.statusCode,200)
        }
        let readout = app.descendants(matching:.any).matching(identifier:"gpa-readout").firstMatch
        func expect(_ grade: Double) {
            let match = NSPredicate { _,_ in readout.exists && Double(readout.label) == grade }
            XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:match,object:nil)],timeout:25),.completed)
            XCTAssertFalse(app.webViews.firstMatch.exists)
        }
        let sample = UUID().uuidString // random QA input; no real account ever participates
        func openPersonalInfo() {
            let entry = app.descendants(matching: .any).matching(identifier: "settings-personal-info-page").firstMatch
            XCTAssertTrue(entry.waitForExistence(timeout: 10)); entry.tap()
        }
        try await control("test-input",sample); try await control("ready")
        tap("GPA"); expect(2.75); tap("设置"); openPersonalInfo()
        let remove = app.buttons["school-login-remove"]
        let setup = app.buttons.matching(NSPredicate(format:"label CONTAINS %@", "本机代登录")).firstMatch
        func expectStatus(_ status: String) {
            let matches = NSPredicate { _,_ in
                setup.exists && (setup.label.contains(status) || (setup.value as? String)?.contains(status) == true ||
                                 setup.staticTexts[status].exists)
            }
            XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:matches,object:nil)],timeout:8),.completed)
        }
        XCTAssertTrue(setup.waitForExistence(timeout:12)); setup.tap()
        if remove.exists { remove.tap(); setup.tap() } // Prior QA run only; dedicated bundle.
        let password = app.secureTextFields["school-login-password"]
        XCTAssertTrue(password.waitForExistence(timeout:8)); password.tap(); password.typeText(sample)
        app.buttons["school-login-enable"].tap()
        expectStatus("已开启")
        XCTAssertFalse(password.exists); XCTAssertFalse(remove.exists)
        try await control("revoke-device")
        try await control("no-submissions"); tap("GPA"); app.buttons["gpa-check-grades"].tap(); expect(3.5)
        tap("设置"); try await control("revoke-device")
        app.terminate(); app.launch()
        // Do not tap a tab or open the website: only an already verified owner reaches Today.
        let today = app.descendants(matching:.any).matching(identifier:"verified-school-today").firstMatch
        XCTAssertTrue(today.waitForExistence(timeout:22), "foreground cold launch must recover identity on Today")
        XCTAssertFalse(app.webViews.firstMatch.exists)
        try await control("recovered-on-launch")
        tap("GPA"); expect(3.75)
        tap("设置"); try await control("test-input",UUID().uuidString); try await control("revoke-device")
        tap("GPA"); app.buttons["gpa-check-grades"].tap()
        XCTAssertTrue(app.buttons["打开校宝登录"].waitForExistence(timeout:25)); XCTAssertFalse(readout.exists)
        XCTAssertTrue(app.staticTexts["校宝未接受这次登录。请打开校宝查看提示。"].exists)
        app.buttons["打开校宝登录"].tap()
        XCTAssertTrue(app.webViews.staticTexts["密码错误"].firstMatch.waitForExistence(timeout:8),
                      "Manual handoff should preserve the school's inline error, not reload its entry")
        app.buttons["完成"].tap()
        tap("设置"); tap("GPA"); XCTAssertFalse(app.webViews.firstMatch.exists)
        tap("设置"); openPersonalInfo(); expectStatus("已暂停"); setup.tap()
        XCTAssertTrue(remove.waitForExistence(timeout:8)); remove.tap()
        XCTAssertFalse(remove.exists); XCTAssertFalse(password.exists)
    }
}
