// Added only to the disposable simulator build. Inspect the production content builders without
// requesting notification permission, scheduling an alert, or reading any student records.
extension ReminderService {
    func inspectFixtureLanguage() async {
        guard SchoolPortalPage.origin.host == "127.0.0.1" else { return }
        let english = AppLanguage.isEnglish
        let date = Date().addingTimeInterval(600)
        let lesson = Self.schoolRequest(.init(fireDate: date, lead: 5)).content
        let item = PlannedPlanReminder(id: "fixture", planTitle: "邮票 / Notes", lead: .tenMinutes,
                                       nextFire: date, timing: .once)
        let personal = planRequest(item, subtitle: "提醒", signature: "fixture", token: UUID()).content
        let widget = Bundle.main.builtInPlugInsURL.flatMap {
            Bundle(url: $0.appendingPathComponent("LessonActivityWidget.appex"))
        }
        let next = widget?.localizedString(forKey: "下一节课", value: nil, table: nil)
        let usage = Bundle.main.localizedString(forKey: "NSLocalNetworkUsageDescription", value: nil, table: "InfoPlist")
        let spring = SchoolClock.date(2028, 3, 17, minute: 600)
        let formatted = schoolDateLabel(spring, format: "M月d日 EEEE")
        // An already pending request from a previous build/language cannot be kept by ID alone.
        let stale = PendingRequest(identifier: "local", planSignature: nil, subtitle: "提醒",
            body: english ? "个人计划 · 10 分钟后开始" : "Personal plan · Starts in 10 min",
            lessonTitle: english ? "课前提醒" : "Class reminder")
        let current = PendingRequest(identifier: "local", planSignature: nil, subtitle: "提醒",
            body: personal.body, lessonTitle: nil)
        let checks: [String: Bool] = [
            "upgrade": !stale.matchesLesson(lead: 5) && !stale.matchesPlan(lead: .tenMinutes, subtitle: "提醒") &&
                current.matchesPlan(lead: .tenMinutes, subtitle: "提醒"),
            "lesson": lesson.title == (english ? "Class reminder" : "课前提醒") &&
                lesson.body == (english ? "Class starts in 5 min." : "距离上课还有 5 分钟。") &&
                lesson.subtitle.isEmpty && lesson.userInfo.isEmpty,
            "plan": personal.title == "邮票 / Notes" && personal.subtitle == "提醒" &&
                personal.body == (english ? "Personal plan · Starts in 10 min" : "个人计划 · 10 分钟后开始"),
            "widget": next == (english ? "Next class" : "下一节课"),
            "usage": usage.hasPrefix(english ? "Connect to the Xiaobao" : "连接你选择的校宝"),
            "date": formatted.contains(english ? "March" : "3月") && formatted.contains(english ? "Friday" : "星期五")
        ]
        var request = URLRequest(url: SchoolPortalPage.origin.appendingPathComponent("control/language-bundles"))
        request.httpMethod = "POST"
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["language":english ? "en" : "zh-Hans", "checks":checks])
        _ = try? await URLSession.shared.data(for: request)
    }
}
