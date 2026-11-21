import XCTest

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
            let root = try XCTUnwrap(URL(string: "__FIXTURE_ORIGIN__"))
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
        tap("设置"); tap("GPA"); XCTAssertFalse(app.webViews.firstMatch.exists)
        tap("设置"); openPersonalInfo(); expectStatus("已暂停"); setup.tap()
        XCTAssertTrue(remove.waitForExistence(timeout:8)); remove.tap()
        XCTAssertFalse(remove.exists); XCTAssertFalse(password.exists)
    }
}
