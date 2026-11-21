import SwiftUI

struct CampusConnectionSettings: View {
    @Environment(AppModel.self) private var model
    @State private var origin = "http://127.0.0.1:3001"
    @State private var profile = "demo-a"
    @State private var remember = true
    @State private var busy = false
    @State private var message: String?
    @State private var confirmLogout = false
    private var clearingSchoolSession: Bool { model.school.selected && model.school.owner == nil }

    private var schoolStatus: String {
        let store = model.school
        if store.isRecoveringGrades { return "正在恢复登录" }
        if model.portal.loading || store.pending.contains(.identity) { return "正在确认" }
        if store.owner != nil { return "已登录" }
        switch store.identityIssue {
        case .login: return "未登录"
        case .expired: return "登录已过期"
        case .changed, .interaction: return "需本人确认"
        case .notReady, nil: return "正在等待页面"
        case .network: return "暂时无法连接"
        default: return "暂时无法读取资料"
        }
    }

    /// One entry within Settings for all three sources; keep the shared sidebar shortcut unchanged.
    private var schoolPortalButton: some View {
        let title: String
        if !model.school.selected || model.school.identityIssue == .login { title = "登录校宝" }
        else if model.school.identityIssue == .expired { title = "重新登录校宝" }
        else if [.changed, .interaction].contains(model.school.identityIssue) { title = "前往校宝确认账号" }
        else { title = "打开校宝网页" }
        return Button(title, systemImage: "safari") { model.openPortal() }
            .accessibilityIdentifier("settings-school-portal")
    }

    var body: some View {
        Section {
            if model.school.selected {
                LabeledContent("校宝账号", value: schoolStatus)
                    .accessibilityIdentifier("settings-school-status")
                SchoolPortalLoginSettings()
                schoolPortalButton
                if model.school.owner == nil {
                    Button("查看演示资料") { model.selectSchool(false) }
                }
                Button(clearingSchoolSession ? "清除本机校宝登录资料" : "退出校宝登录", role: .destructive) { confirmLogout = true }
            } else if let account = model.campus.account {
                LabeledContent("演示资料账户", value: account.profile == "demo-a" ? "学生 A" : account.profile == "demo-b" ? "学生 B" : "已连接")
                LabeledContent("演示服务会话", value: account.refresh == nil ? "仅本次" : "在此 iPad 保持登录")
                Picker("资料更新", selection: Binding(get: { model.campus.updatePolicy }, set: { policy in
                    Task {
                        do { try await model.campus.setUpdatePolicy(policy); model.scheduleDataCheck(); message = nil }
                        catch { message = error.localizedDescription }
                    }
                })) {
                    ForEach(CampusUpdatePolicy.allCases.filter { $0 != .background || account.refresh != nil }, id: \.self) { Text($0.title).tag($0) }
                }
                Button("检查全部资料（含成绩）", systemImage: "arrow.triangle.2.circlepath") {
                    Task { _ = await model.campus.checkAll() }
                }.disabled(model.campus.syncing)
                if let time = model.campus.lastFullCheck {
                    LabeledContent("上次完整检查", value: time.formatted(date: .abbreviated, time: .shortened))
                }
                if model.campus.updatePolicy == .background, let status = model.backgroundCheckStatus {
                    Text(status).font(.footnote).foregroundStyle(.secondary)
                }
                schoolPortalButton
                Button("退出账号", role: .destructive) { confirmLogout = true }
            } else {
                LabeledContent("数据来源", value: "本机演示")
                schoolPortalButton
                DisclosureGroup("连接演示资料服务") {
                    TextField("服务地址", text: $origin).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Picker("资料账户", selection: $profile) {
                        Text("学生 A").tag("demo-a"); Text("学生 B").tag("demo-b")
                    }
                    Toggle("在此 iPad 保持登录", isOn: $remember)
                    Button("连接并读取资料") {
                        busy = true; message = nil
                        Task {
                            defer { busy = false }
                            do {
                                try await model.campus.connect(origin: origin, profile: profile, remember: remember)
                                if model.preferences.rememberSession != remember {
                                    model.preferences.rememberSession = remember
                                    await model.portal.reset(persistent: remember)
                                }
                                model.selectedLesson = nil; model.tab = .today
                            } catch { message = error.localizedDescription }
                        }
                    }
                }
            }
            if busy { ProgressView() }
            if !model.school.selected, let text = message ?? model.campus.notice ?? model.campus.syncIssue { Text(text).font(.footnote).foregroundStyle(.secondary) }
        } header: { Text("校园资料") } footer: {
            Text(model.school.selected ? "课表、任务、考勤和已公布的成绩仅在本机当前会话中使用。"
                 : "当前为演示资料。登录校宝后可查看自己的课表、任务、考勤和已公布成绩。")
        }
        .disabled(busy)
        .onAppear { remember = model.preferences.rememberSession }
        .confirmationDialog(clearingSchoolSession ? "清除这台 iPad 的校宝登录资料？" : "退出当前账号？", isPresented: $confirmLogout) {
            Button(clearingSchoolSession ? "清除登录资料" : "退出账号", role: .destructive) {
                busy = true; message = nil
                Task {
                    defer { busy = false }
                    do {
                        if model.school.selected {
                            await model.portal.reset(persistent: model.preferences.rememberSession)
                            return
                        }
                        try await model.campus.logout()
                        model.scheduleDataCheck()
                        await model.portal.reset(persistent: model.preferences.rememberSession)
                    } catch { message = error.localizedDescription }
                }
            }
        }
    }
}

struct CampusPageView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var phase
    let tab: AppTab
    var otherItemsSection: OtherItemsSection = .exams
    @State private var offset = 0
    @State private var recentAttendance = false
    @State private var otherItemsFilters = OtherItemsFilters()

    private var page: CampusPage {
        switch tab {
        case .today: .schedule(SchoolClock.key(model.now))
        case .attendance: .attendance
        case .tasks: .work("task", offset: offset)
        case .otherItems: otherItemsSection.campusPage(offset: offset)
        case .grades, .planner, .settings: .courses // These tabs are routed directly by RootView.
        }
    }
    private var needsNames: Bool {
        [.today, .attendance].contains(tab) || (tab == .otherItems && otherItemsSection != .resources)
    }
    private func load(force: Bool = false) async {
        let selected = page
        let client = model.campus
        if needsNames {
            async let names: Void = client.load(.courses)
            await client.load(selected, force: force)
            await names
        } else { await client.load(selected, force: force) }
    }
    private func name(_ id: String) -> String {
        if case .courses(let values) = model.campus.pages[.courses]?.content,
           let course = values.first(where: { $0.id == id }) { return course.name }
        return "课程名称待载入"
    }
    var body: some View {
        pageView
            .refreshable { await load(force: true) }
            .task(id: "\(model.campus.account?.scope.uuidString ?? "")|\(page.route)|\(phase == .active)") {
                if phase == .active { await load() }
            }
    }

    private var pageView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if tab == .today, case .schedule(let schedule) = model.campus.pages[page]?.content {
                    TodayRotationHeader(date: model.now, day: model.todayRotationDay,
                                        unpublished: schedule.calendarDay?.status == .unpublished)
                }
                if let snapshot = model.campus.pages[page] {
                    HStack {
                        Text("上次检查 \(snapshot.cache.checked.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("刷新", systemImage: "arrow.clockwise") { Task { await load(force: true) } }.buttonStyle(.glass)
                    }
                    if model.campus.errors[page] != nil {
                        Label("暂时无法更新，正在显示已保存的内容", systemImage: "wifi.slash").font(.callout)
                    }
                    content(model.campus.cachedOtherItems(for: page) ?? snapshot.content)
                } else if let error = model.campus.errors[page] {
                    ContentUnavailableView {
                        Label("暂时无法载入", systemImage: "wifi.exclamationmark")
                    } description: { Text(error) } actions: {
                        Button("重试") { Task { await load(force: true) } }
                    }
                } else { ProgressView("正在载入").frame(maxWidth: .infinity) }
            }.padding(24).frame(maxWidth: tab == .otherItems ? 1100 : 1000).frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(tab == .otherItems ? .interactively : .automatic)
    }

    @ViewBuilder private func content(_ value: CampusContent) -> some View {
        switch value {
        case .schedule(let schedule):
            TodayTimetableView(timeline: schedule.timeline(courseName: name))
        case .grades: EmptyView() // CampusGradebookView owns the grade workflow.
        case .attendance(let report):
            if let saved = model.campus.attendanceRecords {
                Picker("考勤范围", selection: $recentAttendance) {
                    Text("全部记录").tag(false)
                    Text("最近七天").tag(true)
                }.pickerStyle(.segmented)
                if let range = recentAttendance ? saved.coverage.recentWeek(on: model.now) : saved.coverage {
                    Text("已缓存 \(range.from) 至 \(range.to)").font(.caption).foregroundStyle(.secondary)
                    if let filtered = range == saved.coverage ? report : saved.report(from: range.from, to: range.to) {
                        attendanceSummary(filtered)
                    }
                } else {
                    Text("最近七天还没有已缓存的考勤数据。").foregroundStyle(.secondary)
                }
            } else if let report { attendanceSummary(report) }
            else { Text("暂无可用的考勤数据") }
        case .work(let list):
            if tab == .otherItems {
                let kind: SchoolWorkKind = otherItemsSection == .evaluations ? .evaluation : .exam
                let names = otherItemsCourseNames
                OtherItemsGrid(section: otherItemsSection,
                               records: list.items.map { OtherItem(campus: $0, kind: kind, courseNames: names) },
                               filters: $otherItemsFilters, isPartialPage: list.total > list.items.count,
                               campusPage: page)
            } else {
                if list.items.isEmpty { Text("暂无记录") }
                ForEach(list.items) { item in
                    GlassCard { DisclosureGroup(item.title) {
                        Text("\(stateLabel(item.status)) · \(dateTime(item.due_at))").font(.subheadline)
                        Text(item.description)
                    } }
                }
            }
            pagination(list.offset, list.limit, list.total)
        case .resources(let list):
            OtherItemsGrid(section: .resources,
                           records: list.items.map { OtherItem(campus: $0) },
                           filters: $otherItemsFilters, isPartialPage: list.total > list.items.count,
                           campusPage: page)
            pagination(list.offset, list.limit, list.total)
        case .calendar: EmptyView() // PlannerView owns the calendar presentation.
        case .courses(let courses): ForEach(courses) { Text($0.name) }
        }
    }

    private var otherItemsCourseNames: [String: String] {
        guard case .courses(let roster) = model.campus.pages[.courses]?.content else { return [:] }
        return Dictionary(roster.map { ($0.id, $0.name) }, uniquingKeysWith: { existing, _ in existing })
    }
    @ViewBuilder private func attendanceSummary(_ report: CampusAttendance) -> some View {
        row("出勤率", rate(report.totals))
        GlassCard(padding: 18, shape: .rect(cornerRadius: 18)) {
            VStack(alignment: .leading, spacing: 14) {
                Text("考勤详情").font(.headline).accessibilityAddTraits(.isHeader)
                AttendanceCourseTable(rows: report.by_course.map {
                    AttendanceCourseRow(id: $0.course_id, name: name($0.course_id), summary: $0.summary)
                })
            }
        }
    }
    @ViewBuilder private func pagination(_ start: Int, _ limit: Int, _ total: Int) -> some View {
        if start > 0 || start + limit < total {
            HStack {
                Button("上一页") { offset = max(0, start - limit) }.disabled(start == 0)
                Spacer()
                Button("下一页") { offset = start + limit }.disabled(start + limit >= total)
            }
        }
    }
    private func row(_ title: String, _ value: String) -> some View {
        GlassCard { LabeledContent(title, value: value) }
    }
    private func dateTime(_ value: String) -> String { campusInstant(value).map { $0.formatted(date: .abbreviated, time: .shortened) } ?? value }
    private func rate(_ counts: CampusCounts) -> String { counts.present_rate.map { $0.formatted(.percent.precision(.fractionLength(1))) } ?? "暂无记录" }
    private func stateLabel(_ state: String) -> String {
        ["graded":"已评分", "pending":"待处理", "submitted":"已提交", "completed":"已完成", "missing":"未交", "excused":"免交"][state] ?? state
    }
}
