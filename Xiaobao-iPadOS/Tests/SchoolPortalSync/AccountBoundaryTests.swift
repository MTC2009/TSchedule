import WebKit
import XCTest
@testable import Xiaobao

/// Hosted only in the isolated, opt-in fixture bundle (including its own Keychain and WebKit store).
@MainActor final class AccountBoundaryTests: XCTestCase {
    func testMaintenanceAtEntryDoesNotRevokePreviouslyScheduledReminders() async throws {
        let root = SchoolPortalPage.origin
        guard root.scheme == "http", root.host == "127.0.0.1" else { return XCTFail("Requires loopback") }
        let previous = UserDefaults.standard.string(forKey: CampusSource.preferenceKey)
        UserDefaults.standard.set(CampusSource.school.rawValue, forKey: CampusSource.preferenceKey)
        defer { UserDefaults.standard.set(previous, forKey: CampusSource.preferenceKey) }
        let model = AppModel()
        let web = model.portal.webView
        let url = root.appending(queryItems: [.init(name: "fixture-maintenance", value: "1")])
        web.load(URLRequest(url: url))
        let deadline = ContinuousClock.now.advanced(by: .seconds(12))
        while model.school.identityIssue != .network, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(model.school.identityIssue, .network)
        XCTAssertNil(model.activePlanOwner, "A maintenance page cannot authorize reading plans")
        XCTAssertEqual(model.reminderAccess, .waiting, "It also cannot revoke the device's queued reminders")
        model.timetable.reviewAccount()
        XCTAssertEqual(model.reminderAccess, .revoked, "An explicit account review is a real privacy boundary")
        model.timetable.forget()
    }

    func testUnansweredSubmissionTimesOutOnceAndAFramedLoginNeverClaims() async throws {
        let root = SchoolPortalPage.origin
        guard root.scheme == "http", root.host == "127.0.0.1" else { return XCTFail("Requires the isolated fixture") }
        let url = root.appendingPathComponent("Account/Login")
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 700, height: 600))
        web.load(URLRequest(url: url))
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while (web.url != url || web.isLoading), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        guard web.url == url, !web.isLoading else { return XCTFail("Fixture did not load") }
        // The local click only changes the UI; no credentials leave this test page.
        _ = try await web.evaluateJavaScript("""
          document.body.innerHTML='<input placeholder="请输入用户名"><input type="password" placeholder="请输入密码"><button>登录</button>';
          window.fixtureClicks=0; document.querySelector('button').onclick=function(){window.fixtureClicks++;this.disabled=true;}; true;
          """)
        let entry = SchoolPortalPasswordEntry()
        var claims = 0
        func attempt() async throws {
            try await entry.run(web, allowed: { true }) {
                claims += 1; return .init(name: UUID().uuidString, password: UUID().uuidString)
            }
        }
        do { try await attempt(); XCTFail("An unresolved form is not a verified login") }
        catch let reason as SchoolPortalIssue { XCTAssertEqual(reason, .signInTimeout) }
        let clicks = try await web.evaluateJavaScript("window.fixtureClicks")
        XCTAssertEqual(clicks as? Int, 1); XCTAssertEqual(claims, 1)
        _ = try await web.evaluateJavaScript("""
          document.querySelector('button').disabled=false;
          document.body.appendChild(document.createElement('iframe')); true;
          """)
        do { try await attempt(); XCTFail("A frame on the login form is not a normal Home subframe") }
        catch let reason as SchoolPortalIssue { XCTAssertEqual(reason, .interaction) }
        XCTAssertEqual(claims, 1)
    }

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
