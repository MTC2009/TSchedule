import XCTest

@MainActor final class SchoolNavigationUITests: XCTestCase {
    func testListsAreWarmedTermsAreOnDemandAndSlowIdentityCanRetry() async throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages","(zh-Hans)","-AppleLocale","zh_CN","-xiaobao.cityWeather.followsCity.v1","NO"]
        app.launch()
        func tab(_ label: String) {
            let row = app.staticTexts[label].firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 10), label); row.tap()
        }
        func command(_ name: String) async throws -> Int {
            let base = try XCTUnwrap(URL(string:"__FIXTURE_ORIGIN__"))
            guard base.host == "127.0.0.1" else { return 0 }
            var request = URLRequest(url:base.appendingPathComponent("control/"+name)); request.httpMethod = "POST"
            let (_,res) = try await URLSession.shared.data(for:request)
            return (res as? HTTPURLResponse)?.statusCode ?? 0
        }
        var primed = false
        for _ in 0..<35 {
            if try await command("warm-overviews") == 200 { primed = true; break }
            try await Task.sleep(for: .milliseconds(350))
        }
        XCTAssertTrue(primed, "all three overview lists before visiting them; no grades or archive")
        tab("其余项目")
        XCTAssertTrue(app.staticTexts["Cartography practical"].waitForExistence(timeout:6))
        app.buttons["测评"].tap()
        XCTAssertTrue(app.staticTexts["Studio survey"].waitForExistence(timeout:6))
        app.buttons["资料库"].tap()
        XCTAssertTrue(app.staticTexts["Materials guide"].waitForExistence(timeout:6))
        tab("我的任务")
        let picker = app.buttons["school-term-menu"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout:8)); picker.tap()
        let autumn = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "2023–2024")).firstMatch
        XCTAssertTrue(autumn.waitForExistence(timeout:6)); autumn.tap()
        XCTAssertTrue(app.staticTexts["Archive field notes"].waitForExistence(timeout:8))
        tab("GPA")
        let readout = app.descendants(matching:.any).matching(identifier:"gpa-readout").firstMatch
        let value = NSPredicate { _,_ in readout.exists && Double(readout.label) == 3.25 }
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:value, object:nil)],timeout:10),.completed)
        let portal = app.buttons["校宝"].firstMatch
        XCTAssertTrue(portal.exists); portal.tap()
        let done = app.buttons["完成"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout:8)); done.tap()
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:value, object:nil)],timeout:10),.completed)
        portal.tap(); XCTAssertTrue(done.waitForExistence(timeout:8))
        let stall = try await command("hold-identity"); XCTAssertEqual(stall,200)
        done.tap()
        let retry = app.buttons["重试"].firstMatch
        XCTAssertTrue(retry.waitForExistence(timeout:12), "identity deadline exposes retry")
        XCTAssertFalse(app.buttons["打开校宝登录"].exists)
        let release = try await command("resume-identity"); XCTAssertEqual(release,200)
        retry.tap()
        tab("我的任务")
        XCTAssertTrue(picker.waitForExistence(timeout:12))
        XCTAssertFalse(app.webViews.firstMatch.exists)
    }
}
