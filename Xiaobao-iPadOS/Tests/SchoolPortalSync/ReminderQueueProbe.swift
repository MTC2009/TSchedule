// Compiled only into the disposable loopback simulator app (never the product target).
import UserNotifications
private let fixtureProcess = UUID().uuidString

extension AppModel {
    func sampleFixtureQueue() async {
        guard SchoolPortalPage.origin.host == "127.0.0.1" else { return }
        let center = UNUserNotificationCenter.current()
        while !Task.isCancelled {
            if let owner = activePlanOwner, let book = localSchoolTimetable,
               !UserDefaults.standard.bool(forKey: "fixture.plans.seeded") {
                let now = Date(), cal = SchoolClock.calendar
                // The fixture's dated exception is seven minutes ahead when first imported.
                if let publication = PublishedSchoolCalendar.bundledHS,
                   let fire = book.lessonReminders(now: now, lead: 5, calendar: publication)
                    .first(where: { $0.fireDate.timeIntervalSince(now) <= 150 })?.fireDate {
                    for day in [fire, cal.date(byAdding: .day, value: 1, to: fire)!] {
                        let plan = PersonalPlan(day: SchoolClock.key(day), title: "Paper samples",
                            time: PlanTime(startMinute: SchoolClock.minute(in: day)), reminder: .atStart)!
                        _ = try? await planStore.create(plan, for: owner)
                    }
                    UserDefaults.standard.set(true, forKey: "fixture.plans.seeded")
                    await refreshPlanReminders()
                }
            }
            let pending = await center.pendingNotificationRequests(), shown = await center.deliveredNotifications()
            let personal = pending.filter { $0.identifier.hasPrefix(PlanReminderPlanner.identifierPrefix) }
            let lessons = pending.filter { $0.identifier.hasPrefix(SchoolLessonReminder.prefix) }
            let displayed = shown.map(\.request.identifier)
            let ds = displayed.filter { $0.hasPrefix(SchoolLessonReminder.prefix) }.count
            let dp = displayed.filter { $0.hasPrefix(PlanReminderPlanner.identifierPrefix) }.count
            var req = URLRequest(url: SchoolPortalPage.origin.appendingPathComponent("control/annual/qa-state"))
            req.httpMethod = "POST"
            let auth = await center.notificationSettings().authorizationStatus
            req.httpBody = try? JSONSerialization.data(withJSONObject: [
                "process": fixtureProcess, "issue": school.identityIssue?.rawValue ?? "",
                "revoked": reminderAccess == .revoked,
                "seeded": UserDefaults.standard.bool(forKey: "fixture.plans.seeded"),
                "optIn": timetable.lessonRemindersEnabled, "permission": auth.rawValue,
                "hasOwner": activePlanOwner != nil, "hasBook": localSchoolTimetable != nil,
                "planStatus": notifications.planStatus ?? "", "schoolStatus": notifications.schoolStatus ?? "",
                "personal": personal.count, "school": lessons.count, "deliveredBoth": ds > 0 && dp > 0,
                "deliveredSchool": ds, "deliveredTotal": ds+dp,
                "private": lessons.allSatisfy { $0.content.title == "课前提醒" && $0.content.subtitle.isEmpty &&
                    $0.content.userInfo.isEmpty && $0.content.body == "距离上课还有 5 分钟。" }
            ])
            _ = try? await URLSession.shared.data(for: req)
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
        }
    }
}
