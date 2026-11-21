import SwiftUI

/// Route real mode *before* testing for the optional Rust account. In particular
/// missing sections, a closed login sheet and a failed connection are not sample mode.
struct SchoolPortalPages: View {
    @Environment(AppModel.self) private var model
    // Route the mounted stack, not the sidebar's changing selection. An outgoing stack
    // must not start the incoming tab's read and then cancel it while disappearing.
    let tab: AppTab
    var body: some View {
        let school = model.school
        if school.owner == nil {
            if school.isRecoveringGrades {
                ProgressView("正在恢复校宝登录")
            } else if school.pending.contains(.identity) || model.portal.loading || school.identityIssue == nil {
                ProgressView("正在确认校宝登录").accessibilityIdentifier("school-identity-pending")
            } else if tab == .grades && (school.identityIssue == .expired ||
                       (school.identityIssue == .login && model.schoolLogin.binding?.paused == false)) {
                ContentUnavailableView {
                    Label("需要重新登录校宝", systemImage: "person.crop.circle")
                } description: { Text("可以在这里重新检查，不必先打开网页。") }
                actions: { Button("刷新 GPA") { model.requestSchoolGrades() }.buttonStyle(.glass) }
            } else if let issue = school.identityIssue, issue.permitsIdentityRecheck {
                SchoolPortalRetry(issue: issue) { await model.retrySchoolIdentity() }
            } else {
                ContentUnavailableView {
                    Label("校宝登录", systemImage: "person.crop.circle")
                } description: { Text(school.identityIssue?.message ?? "登录校宝后，在这里查看自己的校园资料。") }
                actions: { Button("打开校宝登录") { model.openPortal() }.buttonStyle(.glass) }
            }
        } else {
            switch tab {
            case .today: SchoolPortalToday()
            case .planner: PlannerView()
            case .grades: SchoolPortalGradebook()
            case .tasks: TasksView()
            case .otherItems: OtherItemsView()
            case .attendance: SchoolPortalAttendancePage()
            case .settings: SettingsView()
            }
        }
    }
}

struct SchoolPortalWebSection: View {
    @Environment(AppModel.self) private var model
    let section: String?
    var body: some View {
        ContentUnavailableView {
            Label("在校宝中查看", systemImage: "safari")
        } description: { Text("这个栏目暂未导入本机。") }
        actions: { Button("打开校宝") { model.openPortal(section: section) }.buttonStyle(.glass) }
    }
}

private struct SchoolPortalToday: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let store = model.school, now = model.now
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                TodayRotationHeader(date: now, day: model.todayRotationDay, unknownDayTitle: "今日课表")
                if let week = store.week(on: now), let schedule = week.schedule(on: now) {
                    if schedule.lessons.isEmpty {
                        StudentEmptyState(title: "今天没有排课", detail: "校宝本周课表中，这天没有课程。")
                    } else {
                        TodayTimetableView(timeline: schedule.timeline { week.names[$0] ?? "课程" })
                    }
                } else if let issue = store.issues[SchoolPortalStore.weekKey(now)] {
                    SchoolPortalRetry(issue: issue) { await store.loadWeek(now, force: true) }
                } else { ProgressView("正在读取本周课表") }
            }.padding(24).frame(maxWidth: 1000).frame(maxWidth: .infinity)
        }
        .task(id: SchoolPortalStore.weekKey(now)) { await store.loadWeek(now) }
        .refreshable { await store.loadWeek(now, force: true) }
    }
}

struct SchoolPortalRetry: View {
    let issue: SchoolPortalIssue
    let retry: () async -> Void
    @State private var busy = false
    var body: some View {
        ContentUnavailableView {
            Label("未能读取校宝资料", systemImage: "exclamationmark.circle")
        } description: { Text(issue.message) } actions: {
            Button("重试") { busy = true; Task { await retry(); busy = false } }.buttonStyle(.glass).disabled(busy)
        }
    }
}
