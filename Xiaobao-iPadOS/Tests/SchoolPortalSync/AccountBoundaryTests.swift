import WebKit
import XCTest
@testable import Xiaobao

/// Hosted only in the isolated, opt-in fixture bundle (including its own Keychain and WebKit store).
@MainActor final class AccountBoundaryTests: XCTestCase {
    func testServiceActionsLeaveSchoolSessionIntactAndNeverFallBackAfterExpiry() async throws {
        let model = AppModel()
        let marker = UUID().uuidString
        let web = model.portal.webView
        let cookies = web.configuration.websiteDataStore.httpCookieStore
        let cookie = try XCTUnwrap(HTTPCookie(properties: [.domain: "boundary.invalid", .path: "/",
            .name: "scope-check", .value: marker]))
        await cookies.setCookie(cookie)
        try model.schoolLogin.enable(owner: String(repeating: "a", count: 64), name: "qa", password: UUID().uuidString)
        defer { try? model.schoolLogin.disable() }
        let binding = try XCTUnwrap(model.schoolLogin.binding?.id)
        XCTAssertNotEqual(model.schoolLogin.binding?.restoresOnLaunch, true)
        try model.schoolLogin.setRestoresOnLaunch(true)
        let reopenedVault = SchoolPortalLoginVault()
        XCTAssertEqual(reopenedVault.binding?.id, binding)
        XCTAssertEqual(reopenedVault.binding?.restoresOnLaunch, true)
        model.selectLocalFixture()
        XCTAssertTrue(model.usesLocalTimetable)
        try await model.connectFixture(origin: "__FIXTURE_ORIGIN__", profile: "qa", remember: false)
        try await model.disconnectFixture()
        XCTAssertNil(model.campus.account)
        let retained = await cookies.allCookies()
        XCTAssertTrue(model.portal.webView === web)
        XCTAssertTrue(web.configuration.websiteDataStore.isPersistent)
        XCTAssertTrue(retained.contains { $0.name == cookie.name && $0.value == marker })
        XCTAssertEqual(model.schoolLogin.binding?.id, binding)

        try await model.connectFixture(origin: "__FIXTURE_ORIGIN__", profile: "qa", remember: true)
        // The local HTTP server rejects this read and its refresh; no school request is involved.
        await model.campus.load(.courses, force: true)
        XCTAssertNil(model.campus.account)
        XCTAssertNotNil(model.campus.notice)
        XCTAssertNil(model.activePlanOwner)
        XCTAssertFalse(model.usesLocalTimetable)
        model.preferences.remindersEnabled = true
        await model.refreshReminders()
        XCTAssertEqual(model.notifications.status, "课表提醒已关闭")
        XCTAssertNil(model.lessonActivitySource)
        let relaunched = AppModel()
        XCTAssertEqual(relaunched.campusSource, .fixtureService)
        XCTAssertFalse(relaunched.usesLocalTimetable)
        XCTAssertNil(relaunched.activePlanOwner)
        relaunched.openNotification(.init(lessonID: "retired", date: Date()))
        XCTAssertEqual(relaunched.tab, .today)
        XCTAssertNil(relaunched.selectedLesson)
        await relaunched.refreshReminders()
        XCTAssertEqual(relaunched.notifications.status, "课表提醒已关闭")
        await cookies.deleteCookie(cookie)
    }
}
