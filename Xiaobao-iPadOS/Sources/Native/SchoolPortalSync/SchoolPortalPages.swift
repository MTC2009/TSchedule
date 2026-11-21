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
        if tab == .today, model.localSchoolTimetable != nil {
            SchoolPortalToday()
        } else if tab == .planner, model.localSchoolTimetable != nil {
            PlannerView()
        } else if school.owner == nil {
            if school.isRecoveringSession {
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

private struct SchoolPortalToday: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let now = model.now, day = model.schoolTimetableDay(now)
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                TodayRotationHeader(date: now, day: day?.calendarDay.teachingDay,
                                    unpublished: day?.calendarDay.status == .unpublished, unknownDayTitle: day == nil || day?.hasDatedException == true ? "今日课表" : nil)
                    .accessibilityIdentifier("verified-school-today")
                if day?.hasDatedException == true {
                    Text("校历标为非教学日；下列是校宝当天单独列出的课次，不计入轮转。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if let day, day.schedule != nil {
                    let next = PublishedSchoolCalendar.bundledHS.flatMap {
                        model.localSchoolTimetable?.nextSchoolDay(after: now, calendar: $0)
                    }
                    TodayTimetableView(timeline: day.timeline, nextSchoolDay: next,
                                       noClassNotice: day.calendarDay.notices.first)
                } else if model.timetable.busy && model.localSchoolTimetable == nil {
                    ProgressView("正在保存本学年课表")
                } else {
                    StudentEmptyState(title: "当天课表尚未确认",
                                      detail: model.timetable.message ?? "可在设置中更新课表。未确认的课程不会按空课表显示。")
                }
            }.padding(24).frame(maxWidth: 1000).frame(maxWidth: .infinity)
        }
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
