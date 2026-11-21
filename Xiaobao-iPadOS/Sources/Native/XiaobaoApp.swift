import SwiftUI

@main @MainActor
struct XiaobaoApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .onChange(of: phase == .active && model.school.selected && model.tab == .grades && !model.portalPresented,
                          initial: true) { _, visible in model.setGradePageActive(visible) }
                .onChange(of: model.school.owner) { _, _ in model.schoolIdentityUpdated() }
                .onChange(of: model.school.identityIssue) { _, _ in model.schoolIdentityUpdated() }
                .onOpenURL { model.openLessonActivity($0) }
                .onChange(of: model.portal.loading || model.school.isRecoveringGrades || model.school.pending.contains(.grades)) {
                    _, busy in if !busy { model.startRequestedGradeRead() }
                }
                .environment(\.locale, Locale(identifier: "zh_CN"))
                .environment(\.timeZone, SchoolClock.calendar.timeZone)
                .preferredColorScheme(model.colorScheme)
                .tint(.blue)
        }
        .onChange(of: phase, initial: true) { _, phase in
            if phase == .active { model.lessonActivity.clearOrphans() }
            model.cityWeather.setForeground(phase == .active)
            model.portal.foreground = phase == .active
            if model.school.selected {
                if phase == .background {
                    model.setGradePageActive(false); model.portal.cancelSchoolReads(); model.school.suspend()
                }
                if phase == .active {
                    model.schoolLogin.refresh()
                    if let bound = model.schoolLogin.binding { model.school.rememberComparison(bound.owner) }
                    Task { await model.checkPortalSession(); model.startRequestedGradeRead() }
                }
                return
            }
            if phase == .background { model.campus.enteredBackground(); model.scheduleDataCheck() }
            if phase == .active { Task { await model.campus.opened() } }
        }
        .backgroundTask(.appRefresh(AppModel.refreshID)) { [model] in await model.runDataCheck() }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var compactColumn: NavigationSplitViewColumn = .detail
    @State private var coveredScope: NavigationScope?
    var body: some View {
        @Bindable var model = model
        let scope = navigationScope
        NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: $compactColumn) {
            List(selection: Binding<AppTab?>(get: { model.tab }, set: { if let tab = $0 { model.selectSidebar(tab) } })) {
                Section("校园") { sidebarItems([.today, .planner]) }
                Section("学习") { sidebarItems([.grades, .tasks, .otherItems]) }
                Section("记录") { sidebarItems([.attendance]) }
                Section {
                    sidebarItems([.settings])
                    Button { model.openPortal() } label: { Label("完整校宝", systemImage: "safari") }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("TSchedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Image("TScheduleMark").renderingMode(.original).resizable().scaledToFit()
                            .frame(width: 24, height: 24)
                            .clipShape(.rect(cornerRadius: 5)).accessibilityHidden(true)
                        Text(verbatim: "TSchedule").font(.headline).lineLimit(1).minimumScaleFactor(0.75)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: "TSchedule")).accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("sidebar-brand")
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 225, max: 280)
        } detail: {
            ZStack {
                // Only the navigation/records subtree is keyed to the tab and student.
                AtmosphereView(isCovered: coveredScope == scope).ignoresSafeArea()
                detailScreen(scope)
            }
        }
        // The split view can own a pushed destination even while its detail
        // root is offscreen. Reset that system stack at a real account boundary,
        // never just because the user selected another sidebar item.
        .id(scope.account)
        .navigationSplitViewStyle(.balanced)
        .onChange(of: model.tab) { _, _ in compactColumn = .detail }
        .onChange(of: SchoolClock.calendar.startOfDay(for: model.now)) { _, _ in model.returnToNow() }
        .onChange(of: model.campus.account?.scope) { _, _ in
            model.reconcileLessonActivitySource()
            model.selectedLesson = nil
            model.returnToNow()
            Task { await model.refreshReminders() }
        }
        .onChange(of: model.campus.notice != nil) { _, _ in
            model.reconcileLessonActivitySource()
            Task { await model.refreshPlanReminders() }
        }
        .onChange(of: model.activePlanOwner) { _, _ in
            model.selectedLesson = nil
            Task { await model.refreshReminders() }
        }
        .sheet(isPresented: $model.environmentPresented) {
            EnvironmentView().presentationDetents([.large]).presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $model.portalPresented, onDismiss: {
            Task { await model.finishManualPortal() }
        }) { SchoolPortalView() }
        .sheet(item: $model.selectedLesson) { lesson in
            LessonDetailView(lesson: lesson).presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        }
        .onChange(of: model.notifications.route) { _, route in
            if let route { model.openNotification(route) }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            if !model.school.selected { model.campus.restore() }
            await model.refreshReminders()
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                model.now = Date()
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                if model.school.selected, model.school.owner != nil, !model.portalPresented { await model.checkPortalSession() }
            }
        }
    }

    private func detailScreen(_ scope: NavigationScope) -> some View {
        AppScreen(title: scope.tab.title) {
            tabContent(scope.tab)
                .onAppear { if navigationScope == scope { coveredScope = nil } }
                .onDisappear {
                    // A push covers this root; an outgoing sidebar tab must not pause the new one.
                    if navigationScope == scope { coveredScope = scope }
                }
        }
        // Reset the entire stack, including view-based links, on the original privacy boundaries.
        .id(scope)
    }

    @ViewBuilder private func tabContent(_ tab: AppTab) -> some View {
        if model.school.selected && tab != .settings {
            SchoolPortalPages(tab: tab)
        } else if tab == .grades, model.campus.account != nil {
            CampusGradebookView()
        } else if tab == .tasks, model.campus.account != nil {
            TasksView()
        } else if tab != .settings, tab != .planner, tab != .otherItems, model.campus.account != nil {
            CampusPageView(tab: tab)
        } else if tab != .settings, model.campus.account == nil, let notice = model.campus.notice {
            ContentUnavailableView {
                Label("账号连接", systemImage: "person.crop.circle")
            } description: { Text(notice) } actions: {
                Button("查看账号设置") { model.tab = .settings }
            }
        } else {
            switch tab {
            case .today: TodayView()
            case .grades: GradesView()
            case .attendance: AttendanceView()
            case .tasks: TasksView()
            case .otherItems: OtherItemsView()
            case .planner: PlannerView().id(model.campus.account?.scope)
            case .settings: SettingsView()
            }
        }
    }

    private struct NavigationScope: Hashable {
        let tab: AppTab
        let account: AccountBoundary
    }
    private struct AccountBoundary: Hashable {
        let campus: CampusAccess?
        let schoolEpoch: UUID?
    }
    private struct CampusAccess: Hashable {
        let account: UUID
        let hasGrades, permitsTasks: Bool
        let taskGeneration: UUID
    }
    private var navigationScope: NavigationScope {
        if model.school.selected {
            return NavigationScope(tab: model.tab, account: .init(campus: nil, schoolEpoch: model.school.epoch))
        }
        let campus = model.campus
        let access = campus.account.map {
            CampusAccess(account: $0.scope, hasGrades: campus.savedGrades != nil,
                         permitsTasks: campus.canReadTasks, taskGeneration: campus.taskReadGeneration)
        }
        return NavigationScope(tab: model.tab, account: .init(campus: access, schoolEpoch: nil))
    }

    private func sidebarItems(_ tabs: [AppTab]) -> some View {
        ForEach(tabs) { tab in Label(tab.title, systemImage: tab.symbol).tag(tab) }
    }
}

struct AppScreen<Content: View>: View {
    @Environment(AppModel.self) private var model
    let title: String
    let content: Content
    init(title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .containerBackground(.clear, for: .navigation)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        let rotation = model.todayRotationDay.map { "Day \($0)" }
                        let date = schoolDateLabel(model.now, format: "M月d日")
                        Button {
                            model.openPlanner(on: model.now)
                        } label: {
                            Text(rotation ?? date).fontWeight(.semibold)
                        }
                        .accessibilityLabel("查看今天的计划")
                        .accessibilityValue(rotation.map { "\(date)，\($0)" } ?? date)
                        .accessibilityIdentifier("open-today-planner")
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button("环境", systemImage: model.backgroundSymbol) { model.environmentPresented = true }
                        Button("校宝", systemImage: "safari") { model.openPortal(section: model.activePortalSection) }
                    }
                }
        }
    }
}

#Preview("iPad 原生玻璃") {
    RootView().environment(AppModel())
}
