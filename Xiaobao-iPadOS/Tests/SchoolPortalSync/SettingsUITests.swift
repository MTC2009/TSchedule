import XCTest

/// UI only. The fixture starts with synthetic school data; Settings must never fetch grades or submit a password.
@MainActor final class SettingsUITests: XCTestCase {
    func testShippingSettingsIgnoreLegacySourceAndNeverOfferFixtures() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        let defaults = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-xiaobao.cityWeather.followsCity.v1", "NO"]
        func openSettings(school: Bool, largeText: Bool = false) {
            app.launchArguments = defaults + ["-xiaobao.portal.selected", school ? "YES" : "NO"]
            if !school { app.launchArguments += ["-tschedule.qa.campusSource", "localFixture"] }
            if largeText {
                app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXL",
                                        "-SettingsFixtureNarrow"]
            }
            app.launch()
            let settings = app.staticTexts["设置"].firstMatch
            if largeText {
                // At accessibility XXL the final rows are below the sidebar's viewport.
                let sidebar = app.collectionViews["边栏"].firstMatch
                if sidebar.waitForExistence(timeout:4) {
                    for _ in 0..<3 where !settings.isHittable { sidebar.swipeUp() }
                }
            }
            XCTAssertTrue(settings.waitForExistence(timeout: 12), "open Settings after cold launch"); settings.tap()
        }
        func row(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
        func page(_ id: String) {
            let link = row(id)
            XCTAssertTrue(link.waitForExistence(timeout: 10), id)
            link.tap()
        }
        func back() {
            let button = app.navigationBars.buttons["设置"].firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 6))
            button.tap()
        }
        func enter(_ id: String, _ value: String) {
            let field = app.textFields[id]
            XCTAssertTrue(field.waitForExistence(timeout: 8))
            if (field.value as? String) != value {
                field.tap()
                if let old = field.value as? String, old != field.placeholderValue, !old.isEmpty {
                    field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count))
                }
                field.typeText(value + "\n")
            }
            XCTAssertEqual(field.value as? String, value)
        }
        func capture(_ name: String) {
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = name; shot.lifetime = .keepAlways
            add(shot)
        }

        openSettings(school: true)
        let brand = row("sidebar-brand")
        XCTAssertTrue(brand.waitForExistence(timeout: 10))
        XCTAssertEqual(brand.label, "TSchedule")
        let trial = row("settings-school-trial-hint")
        XCTAssertTrue(trial.exists)
        XCTAssertFalse(trial.label.contains("允许"))
        XCTAssertFalse(row("settings-school-portal").exists)
        capture("settings-overview")
        page("settings-personal-info-page")
        let account = row("settings-school-status")
        XCTAssertTrue(account.waitForExistence(timeout: 14))
        let enrollment = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "本机代登录")).firstMatch
        XCTAssertTrue(enrollment.waitForExistence(timeout: 14))
        XCTAssertFalse(app.secureTextFields["school-login-password"].exists)
        let web = app.buttons["settings-school-portal"]
        XCTAssertTrue(web.exists); XCTAssertFalse(app.buttons["打开完整校宝"].exists)
        capture("settings-school")
        enrollment.tap()
        XCTAssertTrue(app.secureTextFields["school-login-password"].waitForExistence(timeout: 6))
        XCTAssertFalse(app.buttons["school-login-enable"].isEnabled)
        capture("settings-enrollment")
        enrollment.tap()
        XCTAssertFalse(app.secureTextFields["school-login-password"].exists)
        enter("settings-nickname", "North Star")
        back()
        page("settings-reminders-page")
        XCTAssertFalse(row("settings-lesson-reminders-paused").exists)
        XCTAssertFalse(app.switches["课前提醒"].exists)
        enter("settings-reminder-subtitle", "Studio session")
        back()
        page("settings-appearance-page")
        XCTAssertTrue(app.buttons["settings-appearance"].waitForExistence(timeout: 8))
        capture("settings-appearance")
        back()
        page("settings-activity-page")
        XCTAssertTrue(row("settings-activity-preview").waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["视觉叙事工作坊"].exists)
        let background = row("settings-activity-background")
        background.tap()
        app.buttons["校园蓝"].tap()
        enter("settings-activity-heading", "Coming up")
        XCTAssertEqual(app.textFields["settings-activity-heading"].value as? String, "Coming up")
        capture("settings-activity")
        back()
        page("settings-privacy-page")
        XCTAssertTrue(app.navigationBars["隐私说明"].exists)
        XCTAssertTrue(app.staticTexts["校宝登录与学习资料"].exists)
        XCTAssertFalse(app.webViews.firstMatch.exists)
        app.terminate()

        openSettings(school: false)
        page("settings-personal-info-page")
        XCTAssertEqual(app.buttons.matching(identifier: "settings-school-portal").count, 1)
        XCTAssertTrue(account.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["查看演示资料"].exists)
        XCTAssertFalse(app.buttons["连接演示资料服务"].exists)
        XCTAssertFalse(app.buttons["打开完整校宝"].exists)
        XCTAssertEqual(app.textFields["settings-nickname"].value as? String, "North Star")
        back()
        page("settings-reminders-page")
        XCTAssertTrue(app.textFields["settings-reminder-subtitle"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.switches["课前提醒"].exists)
        XCTAssertFalse(row("settings-lesson-reminders-paused").exists)
        XCTAssertEqual(app.textFields["settings-reminder-subtitle"].value as? String, "Studio session")
        capture("settings-after-legacy-upgrade")
        back()
        page("settings-activity-page")
        XCTAssertEqual(app.textFields["settings-activity-heading"].value as? String, "Coming up")
        let selectedBackground = row("settings-activity-background")
        XCTAssertTrue(app.staticTexts["校园蓝"].exists || selectedBackground.label.contains("校园蓝") ||
                      (selectedBackground.value as? String)?.contains("校园蓝") == true)
        app.terminate()

        openSettings(school: true, largeText: true)
        XCUIDevice.shared.orientation = .portrait
        let personal = row("settings-personal-info-page")
        XCTAssertTrue(personal.waitForExistence(timeout: 8))
        XCTAssertLessThanOrEqual(personal.frame.width, 420)
        capture("settings-portrait-accessibility")
        if !personal.isHittable { app.swipeUp() }
        page("settings-personal-info-page")
        // The fixture's session cookies do not survive a process relaunch. Never show a password input here.
        let unavailable = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "登录后可设置")).firstMatch
        XCTAssertTrue(unavailable.waitForExistence(timeout: 12), "show enrollment availability after expiry")
        XCTAssertFalse(app.secureTextFields["school-login-password"].exists)
        XCTAssertTrue(app.buttons["清除本机校宝登录资料"].exists, "explicit school cleanup")
        XCTAssertFalse(app.buttons["退出校宝登录"].exists)
        XCTAssertTrue(web.exists)
        XCTAssertLessThanOrEqual(web.frame.maxX, app.frame.maxX)
        XCUIDevice.shared.orientation = .landscapeLeft
    }
}
