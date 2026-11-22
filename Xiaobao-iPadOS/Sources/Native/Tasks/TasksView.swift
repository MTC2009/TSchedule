import SwiftUI

struct TasksView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var phase
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var filters = TaskFilters()
    // Nil denotes the active source's current term, not a date calculated on the device.
    @State private var term: String?
    @State private var directory: TaskTermDirectory?
    @State private var isTermPickerOpen = false
    @State private var isDirectoryLoading = false
    @State private var directoryMessage: String?
    @State private var downloaded: Downloaded?
    @State private var requestID: UUID?
    @State private var problem: String?
    @State private var offlineTerm: String?

    private var savedTermID: String? {
        if model.school.owner == nil {
            if let offlineTerm, model.assignments.terms[offlineTerm] != nil { return offlineTerm }
            return model.assignments.current
        }
        return model.school.selectedTermID ?? model.school.terms?.current ?? model.assignments.current
    }
    private var saved: SchoolPortalTasks? {
        model.canDisplaySavedAssignments ? model.assignments.snapshot(for: savedTermID) : nil
    }
    private var taskIssue: String? {
        guard model.school.selected else { return problem }
        if model.school.owner == nil { return model.school.identityIssue?.message }
        return model.school.issues[model.school.taskRead]?.message
    }

    private struct Downloaded {
        let term: String?
        let rows: [CampusWork]
    }

    private struct LoadKey: Hashable {
        let scope: UUID?
        let term: String?
        let active: Bool
        let includesSchoolScores: Bool
    }

    private var client: CampusConnection { model.campus }
    private var scope: UUID? { model.school.selected ? model.school.epoch : client.account?.scope }
    private var activeDirectory: TaskTermDirectory? {
        if model.school.selected { return nil }
        guard scope != nil else { return DemoTasks.directory }
        return directory ?? client.cachedTaskList?.taskTermDirectory
    }

    private var termLabel: String {
        if model.school.selected { return model.school.tasks?.displayTerm ?? String(localized: "本学期") }
        let current = activeDirectory?.current ?? client.cachedTaskList?.items.compactMap(\.term).first
        return (term ?? current).map(TaskTermDirectory.title) ?? String(localized: "本学期")
    }

    private var records: [TaskRecord]? {
        if model.school.selected { return (model.school.tasks ?? saved)?.records }
        if scope == nil { return DemoTasks.records.filter { $0.term == (term ?? DemoTasks.currentTerm) } }
        guard client.canReadTasks else { return nil }
        let rows: [CampusWork]
        if term == nil, let saved = client.cachedTaskList, saved.items.count == saved.total {
            rows = saved.items
        } else if let downloaded, downloaded.term == term {
            rows = downloaded.rows
        } else { return nil }
        let courses: [CampusCourse]
        if case .courses(let loaded) = client.pages[.courses]?.content { courses = loaded }
        else { courses = [] }
        let roster = Dictionary(courses.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return rows.map { TaskRecord(campus: $0, roster: roster) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !model.school.selected && scope != nil && !client.canReadTasks {
                    StudentEmptyState(title: String(localized: "任务资料不可用"), detail: String(localized: "当前账户没有可读取的任务。"), symbol: "checklist")
                } else {
                    let available = records
                    TaskFilterBar(tasks: available ?? [], now: model.now, filters: $filters,
                                  resetEnabled: term != nil || model.school.selectedTermID != nil || offlineTerm != nil || filters != TaskFilters(), reset: reset) {
                        if model.school.selected && model.school.owner == nil && model.canDisplaySavedAssignments {
                            Menu {
                                ForEach(model.assignments.terms.values.map(\.label).sorted { $0.id < $1.id }) { label in
                                    Button(label.displayName) { offlineTerm = label.id == model.assignments.current ? nil : label.id; filters = .init() }
                                }
                            } label: {
                                TaskFilterLabel(title: String(localized: "学期"), value: saved?.displayTerm ?? String(localized: "本学期"))
                            }.accessibilityIdentifier("school-term-menu")
                        } else if model.school.selected { SchoolTermMenu { filters = .init(); problem = nil } } else { termPicker }
                    }
                    if model.canDisplaySavedAssignments, let id = savedTermID, let info = model.assignments.terms[id] {
                        Text("上次完整更新：\(schoolDateLabel(info.checked, format: "M月d日 HH:mm"))")
                            .font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("assignment-last-check")
                        if model.school.pending.contains(model.school.taskRead) {
                            Text("正在核对校宝，先显示上次完整清单。").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    if model.school.selected && model.assignments.writeFailed {
                        Text("这次清单未能保存在本机。").font(.footnote)
                    }
                    results(available)
                }
            }
            .padding(24).frame(maxWidth: 1100).frame(maxWidth: .infinity)
        }
        .refreshable { await retryTasks() }
        .onChange(of: model.assignments.registration) { offlineTerm = nil }
        .task(id: LoadKey(scope: scope, term: model.school.selected ? model.school.selectedTermID : term, active: phase == .active,
                          includesSchoolScores: model.school.allowsTaskScores)) {
            if phase == .active { await load(force: model.school.selected) }
        }
    }

    @ViewBuilder private func results(_ available: [TaskRecord]?) -> some View {
        if let available {
            let visible = filters.results(in: available, at: model.now, completed: model.completedDemoTaskIDs,
                                          preservingUndatedSourceOrder: model.school.selected)
            HStack {
                Text("任务列表").font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
                Spacer()
                Text("\(visible.count) 项").font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal, 3)
            if let message = taskIssue {
                VStack(alignment: .leading) {
                    Label(message, systemImage: "wifi.slash").font(.footnote)
                    if model.school.selected {
                        Text("本次更新未确认，正在显示上次完整清单。").font(.footnote)
                        Button("重试") { Task { await retryTasks() } }
                    }
                }.accessibilityIdentifier("assignment-update-issue")
            }
            if visible.isEmpty {
                emptyResults(filtered: !available.isEmpty)
            } else {
                GlassEffectContainer(spacing: 8) {
                    LazyVGrid(columns: [GridItem(typeSize.isAccessibilitySize ? .flexible() : .adaptive(minimum: 250),
                                                 spacing: 16, alignment: .topLeading)], spacing: 16) {
                        ForEach(visible) { item in
                            let locallyCompleted = item.permitsLocalCompletion
                                && model.completedDemoTaskIDs.contains(item.id)
                            let sourceSubmission = item.submission(at: model.now, locallyCompleted: false)
                            let status = [sourceSubmission.title, item.grading.title]
                                + (locallyCompleted ? [TaskSubmissionState.localCompletion.title] : [])
                            NavigationLink {
                                TaskDetailView(task: item, schoolTerm: model.school.selected ? (model.school.tasks ?? saved)?.termLabel?.id : nil)
                            } label: {
                                TaskCard(task: item, stage: item.cardStage(at: model.now),
                                         showsLocalCompletion: locallyCompleted)
                            }
                            .buttonStyle(.plain).hoverEffect(.highlight)
                            .accessibilityElement(children: .combine)
                            .accessibilityValue(status.joined(separator: String(localized: "，")))
                            .accessibilityIdentifier("task-card-\(item.id)")
                        }
                    }
                }
            }
        } else if let problem = taskIssue {
            ContentUnavailableView {
                Label(term == nil ? String(localized: "暂时无法读取任务") : String(localized: "往期任务未载入"), systemImage: "wifi.exclamationmark")
            } description: {
                Text(problem)
            } actions: {
                Button("重试") { Task { await retryTasks() } }.buttonStyle(.glass)
            }
        } else {
            ProgressView("正在载入任务").frame(maxWidth: .infinity).padding(.vertical, 24)
        }
    }

    private func emptyResults(filtered: Bool) -> some View {
        let title: String, detail: String
        if filtered {
            title = String(localized: "没有匹配的任务"); detail = String(localized: "试试调整筛选项或搜索词。")
        } else if model.school.selected && model.school.tasks == nil {
            title = String(localized: "上次清单没有任务"); detail = String(localized: "这是上次确认的结果，不代表现在没有作业。")
        } else {
            title = String(localized: "这个学期没有任务")
            detail = model.school.selected ? String(localized: "校宝没有返回本学期的任务。") : String(localized: "可以切换学期查看。")
        }
        return StudentEmptyState(title: title, detail: detail, symbol: "checklist")
    }

    private var termPicker: some View {
        Button { isTermPickerOpen = true } label: {
            TaskFilterLabel(title: String(localized: "学期"), value: termLabel)
        }
        .buttonStyle(.plain).hoverEffect(.highlight)
        .accessibilityIdentifier("task-filter-term")
        .popover(isPresented: $isTermPickerOpen) {
            VStack(alignment: .leading, spacing: 10) {
                Text("选择学期").font(.headline).accessibilityAddTraits(.isHeader)
                let current = activeDirectory?.current
                termOption(current.map(TaskTermDirectory.title) ?? String(localized: "本学期"), id: nil)
                ForEach((activeDirectory?.available ?? []).filter { $0 != current }, id: \.self) { past in
                    termOption(TaskTermDirectory.title(past), id: past)
                }
                if isDirectoryLoading { ProgressView("正在读取学期").font(.caption) }
                if let directoryMessage { Text(directoryMessage).font(.caption).foregroundStyle(.secondary) }
            }
            .padding(16).frame(minWidth: 220, alignment: .leading)
            .task { await loadDirectory() }
        }
    }

    private func termOption(_ label: String, id: String?) -> some View {
        Button {
            if term != id {
                term = id
                filters = TaskFilters()
                problem = nil
            }
            isTermPickerOpen = false
        } label: {
            HStack {
                Text(label)
                Spacer(minLength: 10)
                if term == id { Image(systemName: "checkmark").accessibilityHidden(true) }
            }.frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(term == id ? .isSelected : [])
    }

    private func reset() {
        filters = TaskFilters()
        offlineTerm = nil
        if model.school.selected, let current = model.school.terms?.current { model.selectAcademicTerm(current) }
        if term != nil { term = nil; problem = nil }
    }

    private func loadDirectory() async {
        guard let scope, directory == nil, !isDirectoryLoading else { return }
        if let cached = client.cachedTaskList, cached.available_terms != nil, let known = cached.taskTermDirectory {
            directory = known
            return
        }
        isDirectoryLoading = true; directoryMessage = nil
        defer { isDirectoryLoading = false }
        do {
            let page = try await client.readTaskPage(TaskReadRequest(limit: 1), scope: scope)
            directory = page.taskTermDirectory
            if directory == nil { directoryMessage = String(localized: "资料服务未提供往期学期。") }
        } catch is CancellationError {
            return
        } catch {
            directoryMessage = String(localized: "暂时无法读取往期学期。")
        }
    }

    private func retryTasks() async {
        if model.school.selected && model.school.owner == nil { await model.retrySchoolIdentity() }
        await load(force: true)
    }

    private func load(force: Bool) async {
        if model.school.selected {
            await model.school.loadTasks(force: force)
            problem = model.school.issues[model.school.taskRead]?.message
            return
        }
        guard let scope, client.canReadTasks else { return }
        let selection = term
        let generation = client.taskReadGeneration
        if selection != nil, !force, downloaded?.term == selection { return }
        let request = UUID()
        requestID = request
        func isCurrent() -> Bool {
            requestID == request && client.account?.scope == scope && client.taskReadGeneration == generation &&
                term == selection && !Task.isCancelled
        }
        problem = nil
        if selection == nil {
            async let courses: Void = client.load(.courses)
            await client.load(.work("task"), force: force)
            await courses
            guard isCurrent() else { return }
            let saved = client.cachedTaskList
            if saved == nil || saved?.items.count == saved?.total {
                if saved == nil { problem = String(localized: "没有可读取的已保存任务，请联网重试。") }
                else if client.errors[.work("task")] != nil { problem = String(localized: "暂时无法更新，正显示已保存的任务。") }
                return
            }
            if !force, let downloaded, downloaded.term == nil { return }
        }
        do {
            let batch = try await TaskCatalog.load(term: selection) { query in
                try await client.readTaskPage(query, scope: scope)
            }
            guard isCurrent() else { return }
            downloaded = Downloaded(term: selection, rows: batch.rows)
            if let known = batch.directory { directory = known }
        } catch {
            guard isCurrent() else { return }
            if case CampusError.http(403) = error { downloaded = nil }
            problem = downloaded?.term == selection && downloaded != nil
                ? String(localized: "暂时无法更新，正显示本次已读取的任务。")
                : String(localized: "当前没有完整的任务列表，请联网重试。")
        }
    }
}
