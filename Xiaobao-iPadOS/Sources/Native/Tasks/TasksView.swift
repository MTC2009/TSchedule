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
        if model.school.selected { return model.school.tasks?.term ?? "本学期" }
        let current = activeDirectory?.current ?? client.cachedTaskList?.items.compactMap(\.term).first
        return (term ?? current).map(TaskTermDirectory.title) ?? "本学期"
    }

    private var records: [TaskRecord]? {
        if model.school.selected { return model.school.tasks?.records }
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
                    StudentEmptyState(title: "任务资料不可用", detail: "当前账户没有可读取的任务。", symbol: "checklist")
                } else {
                    let available = records
                    TaskFilterBar(tasks: available ?? [], now: model.now, filters: $filters,
                                  resetEnabled: term != nil || filters != TaskFilters(), reset: reset) {
                        if model.school.selected { Text(termLabel).font(.caption) } else { termPicker }
                    }
                    results(available)
                }
            }
            .padding(24).frame(maxWidth: 1100).frame(maxWidth: .infinity)
        }
        .refreshable { await load(force: true) }
        .task(id: LoadKey(scope: scope, term: term, active: phase == .active,
                          includesSchoolScores: model.school.allowsTaskScores)) {
            if phase == .active { await load(force: false) }
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
            if let problem {
                Label(problem, systemImage: "wifi.slash").font(.caption).foregroundStyle(.secondary)
            }
            if visible.isEmpty {
                StudentEmptyState(title: available.isEmpty ? "这个学期没有任务" : "没有匹配的任务",
                                  detail: available.isEmpty ? (model.school.selected ? "校宝没有返回本学期的任务。" : "可以切换学期查看。") : "试试调整筛选项或搜索词。", symbol: "checklist")
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
                                TaskDetailView(task: item)
                            } label: {
                                TaskCard(task: item, stage: item.cardStage(at: model.now),
                                         showsLocalCompletion: locallyCompleted)
                            }
                            .buttonStyle(.plain).hoverEffect(.highlight)
                            .accessibilityElement(children: .combine)
                            .accessibilityValue(status.joined(separator: "，"))
                            .accessibilityIdentifier("task-card-\(item.id)")
                        }
                    }
                }
            }
        } else if let problem {
            ContentUnavailableView {
                Label(term == nil ? "暂时无法读取任务" : "往期任务未载入", systemImage: "wifi.exclamationmark")
            } description: {
                Text(problem)
            } actions: {
                Button("重试") { Task { await load(force: true) } }.buttonStyle(.glass)
            }
        } else {
            ProgressView("正在载入任务").frame(maxWidth: .infinity).padding(.vertical, 24)
        }
    }

    private var termPicker: some View {
        Button { isTermPickerOpen = true } label: {
            TaskFilterLabel(title: "学期", value: termLabel)
        }
        .buttonStyle(.plain).hoverEffect(.highlight)
        .accessibilityIdentifier("task-filter-term")
        .popover(isPresented: $isTermPickerOpen) {
            VStack(alignment: .leading, spacing: 10) {
                Text("选择学期").font(.headline).accessibilityAddTraits(.isHeader)
                let current = activeDirectory?.current
                termOption(current.map(TaskTermDirectory.title) ?? "本学期", id: nil)
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
            if directory == nil { directoryMessage = "资料服务未提供往期学期。" }
        } catch is CancellationError {
            return
        } catch {
            directoryMessage = "暂时无法读取往期学期。"
        }
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
                if saved == nil { problem = "没有可读取的已保存任务，请联网重试。" }
                else if client.errors[.work("task")] != nil { problem = "暂时无法更新，正显示已保存的任务。" }
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
                ? "暂时无法更新，正显示本次已读取的任务。"
                : "当前没有完整的任务列表，请联网重试。"
        }
    }
}
