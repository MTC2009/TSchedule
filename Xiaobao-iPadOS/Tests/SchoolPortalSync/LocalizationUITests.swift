import XCTest

/// The same isolated school account and data across launches. Neither run contacts a school.
@MainActor final class LocalizationUITests: XCTestCase {
    func testSchoolRecordsStayVerbatimAcrossAppLanguages() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        for english in [true, false] {
            func wording(_ en: String, _ zh: String) -> String { english ? en : zh }
            func tab(_ en: String, _ zh: String) {
                let row = app.staticTexts[wording(en, zh)].firstMatch
                XCTAssertTrue(row.waitForExistence(timeout: 12), "Sidebar: \(en)")
                row.tap()
            }
            func element(_ id: String) -> XCUIElement {
                app.descendants(matching: .any).matching(identifier: id).firstMatch
            }
            func check(_ id: String, _ en: String, _ zh: String) {
                let item = element(id)
                XCTAssertTrue(item.waitForExistence(timeout: 15), id)
                let phrase = wording(en, zh)
                let matches = NSPredicate { _, _ in
                    item.exists && (item.label.contains(phrase) || (item.value as? String)?.contains(phrase) == true)
                }
                XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: matches, object: nil)],
                                              timeout: 10), .completed, "\(id): \(item.label) / \(item.value ?? "")")
            }
            func capture(_ page: String) {
                let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                attachment.name = page + (english ? "-en" : "-zh-Hans")
                attachment.lifetime = .keepAlways
                self.add(attachment)
            }
            app.launchArguments = ["-AppleLanguages", english ? "(en)" : "(zh-Hans)", "-AppleLocale",
                                   english ? "en_US" : "zh_CN", "-xiaobao.cityWeather.followsCity.v1", "NO"]
            app.launch()
            XCTAssertTrue(app.staticTexts[wording("Today", "今日")].firstMatch.waitForExistence(timeout: 15))
            tab("My Tasks", "我的任务")
            check("task-filter-dates", "Any date", "不限日期")
            check("task-filter-type", "All types", "全部类型")
            check("task-filter-reset", "Reset", "重置")
            check("task-card-35", "飞羽观测 / Étude", "飞羽观测 / Étude")
            check("task-card-35", "设置", "设置") // school course happens to match an interface key
            check("task-card-35", "practice", "practice") // actual school type, not our "practice" code
            check("school-term-menu", "Semester 2", "第 2 学期")
            capture("tasks")
            element("task-filter-dates").tap()
            XCTAssertTrue(app.navigationBars[wording("Filter by due date", "筛选截止日期")].waitForExistence(timeout: 8))
            app.buttons[wording("Cancel", "取消")].firstMatch.tap()
            element("school-term-menu").tap()
            let archive = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "冬日工作坊")).firstMatch
            XCTAssertTrue(archive.waitForExistence(timeout: 8)); archive.tap()
            check("school-term-menu", "冬日工作坊", "冬日工作坊")
            check("task-card-35", "风铃归档 / Índice", "风铃归档 / Índice")
            tab("GPA", "GPA")
            check("school-term-menu", "冬日工作坊", "冬日工作坊")
            tab("More from School", "其余项目")
            let exams = app.staticTexts["Cartography practical"].firstMatch
            XCTAssertTrue(exams.waitForExistence(timeout: 12))
            app.buttons[wording("Assessments", "测评")].tap()
            XCTAssertTrue(app.staticTexts["Studio survey"].firstMatch.waitForExistence(timeout: 12))
            XCTAssertTrue(app.staticTexts[wording("Completed", "已完成")].firstMatch.exists)
            tab("My Attendance", "我的考勤")
            XCTAssertTrue(element("attendance-ring").waitForExistence(timeout: 12))
            tab("Planner", "计划")
            check("planner-edit-mode", "Edit", "编辑")
            element("planner-edit-mode").tap()
            let add = element("planner-add")
            XCTAssertTrue(add.waitForExistence(timeout: 8)); add.tap()
            XCTAssertTrue(element("plan-title").waitForExistence(timeout: 8))
            XCTAssertTrue(app.navigationBars[wording("New plan", "新建计划")].exists)
            capture("plan-editor")
            app.buttons[wording("Cancel", "取消")].firstMatch.tap()
            tab("Settings", "设置")
            check("settings-refresh-timetable", "Update timetable", "更新课表")
            check("settings-reminders-page", "Reminders", "提醒")
            element("settings-reminders-page").tap()
            XCTAssertTrue(app.staticTexts[wording("Class reminder", "课前提醒")].firstMatch.waitForExistence(timeout: 8))
            app.navigationBars.buttons[wording("Settings", "设置")].firstMatch.tap()
            element("settings-personal-info-page").tap()
            let enrollment = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", wording("Sign in with this iPad", "本机代登录"))).firstMatch
            XCTAssertTrue(enrollment.waitForExistence(timeout: 8)); enrollment.tap()
            XCTAssertTrue(app.secureTextFields["school-login-password"].waitForExistence(timeout: 8))
            check("school-login-enable", "Save and enable", "保存并开启")
            XCTAssertFalse(element("school-login-enable").isEnabled)
            app.navigationBars.buttons[wording("Settings", "设置")].firstMatch.tap()
            element("settings-privacy-page").tap()
            check("settings-terms-page", "Terms of Use and Service", "使用与服务条款")
            capture("privacy")
            app.buttons[wording("简体中文", "English")].firstMatch.tap()
            check("settings-terms-page", "使用与服务条款", "Terms of Use and Service")
            XCTAssertTrue(app.staticTexts[wording("My Tasks", "我的任务")].firstMatch.exists)
            app.terminate()
        }
    }
}
