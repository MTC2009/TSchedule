import XCTest

@MainActor final class LessonActivityUITests: XCTestCase {
    func testStartsFromTheLoadedSchoolDayAndCanBeStopped() async throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
                               "-xiaobao.portal.selected", "YES", "-xiaobao.cityWeather.followsCity.v1", "NO"]
        app.launch()
        let toggle = app.buttons["lesson-activity-toggle"].firstMatch
        func expect(_ label: String) {
            let ready = NSPredicate { _, _ in toggle.exists && toggle.isEnabled && toggle.label.contains(label) }
            let expectation = XCTNSPredicateExpectation(predicate: ready, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 18), .completed, label)
        }
        expect("在锁屏显示课表")
        toggle.tap()
        expect("结束锁屏课表")

        // The optional host-controlled Lock Screen capture can hold this reply.
        let url = try XCTUnwrap(URL(string: "__ACTIVITY_FIXTURE_ORIGIN__/control/lesson-activity"))
        XCTAssertEqual(url.host, "127.0.0.1")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let (_, reply) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((reply as? HTTPURLResponse)?.statusCode, 200)

        app.activate()
        expect("结束锁屏课表")
        XCTAssertFalse(app.webViews.firstMatch.exists)
        let coverLink = try XCTUnwrap(URL(string: "tschedule-activity-qa://lesson-activity"))
        XCUIDevice.shared.system.open(coverLink)
        let lens = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "课程时间透镜")).firstMatch
        let fullTitle = NSPredicate { _, _ in
            lens.exists && (lens.value as? String)?.contains("Visual Systems Lab: Designing Across Motion, Sound and Generative Fields") == true
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: fullTitle, object: nil)], timeout: 12),
                       .completed, "The card link should focus the next lesson in the loaded timetable.")
        toggle.tap()
        expect("在锁屏显示课表")
    }
}
