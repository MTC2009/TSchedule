import SwiftUI

private let taskDetailShape = RoundedRectangle(cornerRadius: 16)

struct TaskDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    let task: TaskRecord
    var schoolTerm: String? = nil
    private struct Scope: Hashable {
        let term: String?, task: String, epoch: UUID, key: SchoolAssignmentStore.MaterialKey?
        let online, mayUseCopy: Bool
    }
    private var liveRow: SchoolPortalTasks.Row? {
        guard let schoolTerm, model.school.tasks?.termLabel?.id == schoolTerm else { return nil }
        return model.school.tasks?.rows.first { $0.id == task.id }
    }
    private var isListed: Bool {
        guard isSchoolTask else { return true }
        if model.school.tasks != nil { return model.school.owner != nil && liveRow != nil }
        return model.canDisplaySavedAssignments && schoolTerm.map { model.assignments.containsTask(term:$0,task:task.id) } == true
    }
    private var scope: Scope {
        // A known online withdrawal, closed row or failed cache replacement must
        // take precedence over any older disk snapshot, even in an already-pushed detail.
        let permitsCopy = model.canDisplaySavedAssignments && (model.school.tasks == nil ||
            (liveRow?.detailReadable == true && !model.assignments.writeFailed))
        let key = schoolTerm.flatMap { permitsCopy ? model.assignments.materialKey(term:$0,task:task.id) : nil }
        return .init(term:schoolTerm,task:task.id,epoch:model.school.epoch,key:key,
            online:schoolTerm != nil && model.school.owner != nil && model.timetableForeground && !model.portalPresented &&
                liveRow?.detailReadable == true,
            mayUseCopy:model.canDisplaySavedAssignments)
    }
    @State private var shownScope: Scope?
    @State private var material: SchoolTaskMaterial?
    @State private var copyDate: Date?
    @State private var readingMaterial = false
    @State private var readIssue: SchoolPortalIssue?
    @State private var fileBusy = false
    @State private var fileIssue: SchoolPortalIssue?
    @State private var fileTask: Task<Void,Never>?
    @State private var export: SchoolTaskDownload.Export?
    @State private var staged: SchoolTaskDownload.Export?
    private var visibleMaterial: SchoolTaskMaterial? { scope == shownScope ? material : nil }


    private var isSchoolTask: Bool { model.school.selected }
    private var completed: Bool { model.completedDemoTaskIDs.contains(task.id) }

    var body: some View {
        GeometryReader { geometry in
            // Measure the detail pane, not the unwrapped width of either text column.
            let wide = geometry.size.width >= 680 && !typeSize.isAccessibilitySize
            if !isListed {
                StudentEmptyState(title:String(localized:"任务资料不可用"), detail:String(localized:"当前账户没有可读取的任务。"),symbol:"checklist")
            } else {
                StudentDetailSurface {
                GlassEffectContainer(spacing: 8) {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        if isSchoolTask { syncStatus }
                        reading(wide: wide)
                        evaluation(wide: wide)
                    }
                }
                if task.permitsLocalCompletion {
                    VStack(alignment: .leading, spacing: 8) {
                        Button(completed ? String(localized: "撤销本地完成") : String(localized: "标记本地完成"), systemImage: "checkmark.circle") {
                            model.toggleDemoTask(task.id)
                        }.buttonStyle(.glass)
                        Text("只在此设备记录，不会提交任务。").font(.caption).foregroundStyle(.secondary)
                    }
                }
                }
            }
        }
        .task(id:scope) { if isSchoolTask { await loadMaterial() } }
        .onChange(of:scope) { _,_ in cancelFile() }
        .onDisappear { cancelFile() }
        .sheet(item:$export, onDismiss:{ staged?.discard(); staged = nil }) { item in
            SchoolTaskExportPicker(file:item) { export = nil }
        }
        .navigationTitle("任务详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("在校宝查看", systemImage: "safari") { model.openPortal(section: "我的任务") }
            }
        }
    }

    @ViewBuilder private var syncStatus: some View {
        VStack(alignment:.leading,spacing:6) {
            if shownScope == scope, let copyDate {
                Text("本机详情更新于 \(time(copyDate))").font(.footnote).foregroundStyle(.secondary)
            }
            if readingMaterial && shownScope == scope { ProgressView("正在读取任务详情") }
            if let issue = shownScope == scope ? readIssue : nil {
                Text(issue.message).font(.footnote).foregroundStyle(.secondary)
                if scope.online && !readingMaterial {
                    Button("重试") { Task { await loadMaterial() } }
                }
            }
            if fileBusy { ProgressView("正在下载附件") }
            if let fileIssue {
                Text(fileIssue == .unavailable ? String(localized:"此附件暂不能在 App 内下载，可在校宝查看。") : fileIssue.message)
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func loadMaterial() async {
        let stamp = scope
        if shownScope == stamp, readingMaterial { return }
        shownScope = stamp; readIssue = nil; copyDate = nil; fileIssue = nil
        let saved = stamp.key.flatMap { model.assignments.material(for:$0) }
        material = saved?.value; copyDate = saved?.checked; readingMaterial = false
        guard stamp.online, let term = stamp.term else {
            if saved == nil { readIssue = model.school.identityIssue ?? .unavailable }; return
        }
        readingMaterial = true
        defer { if scope == stamp { readingMaterial = false } }
        do {
            let live: SchoolTaskMaterial
            if let key = stamp.key { live = try await model.readMaterial(key) }
            else { live = try await model.school.readTaskMaterial(term:term,task:task.id) }
            guard !Task.isCancelled, scope == stamp else { return }
            material = live; copyDate = nil
        } catch {
            guard !Task.isCancelled, scope == stamp else { return }
            let issue = error as? SchoolPortalIssue ?? .network
            if issue != .network && issue != .notReady && issue != .format { material = nil; copyDate = nil }
            readIssue = issue
        }
    }

    private func cancelFile() {
        fileTask?.cancel(); fileTask = nil; fileBusy = false; fileIssue = nil
        export = nil; staged?.discard(); staged = nil
    }
    private func saveFile(_ file: SchoolTaskMaterial.File, section: SchoolTaskMaterial.Section) {
        let stamp = scope
        guard !fileBusy, stamp.online, let term = stamp.term,
              visibleMaterial?[section].files.contains(file) == true else { return }
        fileBusy = true; fileIssue = nil
        fileTask = Task { @MainActor in
            defer { if stamp == scope { fileBusy = false } }
            do {
                let link = try await model.school.taskFileLink(term:term,task:task.id,section:section,file:file)
                try Task.checkCancellation(); guard stamp == scope else { return }
                let download = try SchoolTaskDownload(link:link) { stamp == scope && model.portal.foreground }
                let result = try await download.fetch(using:model.portal.webView)
                guard !Task.isCancelled, stamp == scope else { result.discard(); return }
                staged = result; export = result
            } catch {
                if !Task.isCancelled, stamp == scope {
                    let issue = error as? SchoolPortalIssue ?? .network
                    // The file or its publication can change between opening a detail and tapping Save.
                    if issue == .denied || issue == .unavailable {
                        if let key = stamp.key { model.assignments.removeMaterial(key) }
                        material = nil; copyDate = nil
                        await loadMaterial()
                    }
                    if stamp == scope { fileIssue = issue }
                }
            }
        }
    }

    private var header: some View {
        GlassCard(padding: 20, shape: taskDetailShape) {
            VStack(alignment: .leading, spacing: 12) {
                Text(task.title).font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
                let metadata = [task.courseName, task.workTypeLabel, task.mode.map(TaskRecord.modeTitle)]
                    .compactMap { $0 }.joined(separator: " · ")
                if !metadata.isEmpty { Text(metadata).font(.subheadline).foregroundStyle(.secondary) }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { states }
                    VStack(alignment: .leading, spacing: 8) { states }
                }
                if task.teacher != nil || task.publishedAt != nil || task.opensAt != nil || task.dueAt != nil {
                    Divider()
                    LazyVGrid(columns: [GridItem(typeSize.isAccessibilitySize ? .flexible() : .adaptive(minimum: 166),
                                                 spacing: 14, alignment: .leading)], alignment: .leading, spacing: 12) {
                        if let teacher = task.teacher { metadataField(String(localized: "任课教师"), value: teacher) }
                        if let published = task.publishedAt { metadataField(String(localized: "发布时间"), value: time(published)) }
                        if let opens = task.opensAt { metadataField(String(localized: "开始时间"), value: time(opens)) }
                        if let due = task.dueAt { metadataField(String(localized: "截止时间"), value: time(due)) }
                    }
                }
            }
        }
    }

    @ViewBuilder private var states: some View {
        TaskSubmissionLabel(state: task.submission(at: model.now, locallyCompleted: completed))
        TaskGradingBadge(state: task.grading)
    }

    private func reading(wide: Bool) -> some View {
        GlassCard(padding: 20, shape: taskDetailShape) {
            if wide {
                HStack(alignment: .top, spacing: 22) {
                    instructions
                    Divider().frame(height: 78).accessibilityHidden(true)
                    answer.frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(alignment: .leading, spacing: 16) { instructions; Divider(); answer }
            }
        }
    }

    private var instructions: some View {
        section(.instructions, title:String(localized: "任务内容"), demo:task.instructions, empty:String(localized: "未提供任务说明。"))
    }

    private var answer: some View {
        VStack(alignment: .leading, spacing: 10) {
            section(.answer, title:String(localized: "我的回答"), demo:task.answer, empty:String(localized: "未提供回答内容。"))
                .accessibilityIdentifier("task-detail-answer")
            if let date = (!isSchoolTask ? task.submittedAt : visibleMaterial?.submitted.flatMap(campusInstant)) {
                Text("提交于 \(time(date))").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func evaluation(wide: Bool) -> some View {
        let published = task.mark
        let mark = published ?? task.estimatedMark
        return GlassCard(padding: 20, shape: taskDetailShape) {
            if wide, let mark {
                HStack(alignment: .top, spacing: 22) {
                    score(mark, isEstimate: published == nil).frame(minWidth: 116, alignment: .leading)
                    Divider().frame(height: 62).accessibilityHidden(true)
                    feedback
                }
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    if let mark { score(mark, isEstimate: published == nil); Divider() }
                    feedback
                }
            }
        }
    }

    private func score(_ mark: GradeMark, isEstimate: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(mark.displayText).font(.system(.largeTitle, design: .rounded, weight: .semibold)).monospacedDigit()
            Text(isEstimate ? String(localized: "预估分") : String(localized: "任务成绩")).font(.caption).foregroundStyle(.secondary)
            if isEstimate { Text("校方提供 · 非正式成绩").font(.caption2).foregroundStyle(.secondary) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(isEstimate ? "task-detail-score-estimate" : "task-detail-score")
    }

    private var feedback: some View {
        section(.feedback, title:String(localized: "老师点评"), demo:task.feedback, empty:String(localized: "未提供点评。"))
            .accessibilityIdentifier("task-detail-feedback")
    }

    private func section(_ section: SchoolTaskMaterial.Section, title: String, demo: TaskRecord.Material?, empty: String) -> some View {
        let part = visibleMaterial?[section]
        let message: String
        if isSchoolTask && (part == nil || part?.state == .unknown) {
            message = String(localized:"尚未读到这项内容。")
        } else if part?.state == .hidden {
            message = section == .feedback ? String(localized:"暂无已发布的点评。") : String(localized:"暂无可见的提交。")
        } else { message = empty }
        return TaskMaterialSection(title:title, material:isSchoolTask ? nil : demo, emptyText:message, part:part,
            canDownload:scope.online && !fileBusy, download:{ saveFile($0,section:section) })
    }

    private func metadataField(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline)
        }
        .accessibilityElement(children: .combine)
    }

    private func time(_ date: Date) -> String {
        schoolDateLabel(date, format: "yyyy年M月d日 HH:mm")
    }
}

private struct TaskMaterialSection: View {
    let title: String
    let material: TaskRecord.Material?
    let emptyText: String
    var part: SchoolTaskMaterial.Part?
    var canDownload = false
    let download: (SchoolTaskMaterial.File) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
            if let text = part?.text ?? material?.text { Text(text).lineSpacing(4).textSelection(.enabled) }
            if let files = part?.files, !files.isEmpty {
                ForEach(files) { file in
                    if file.downloadable {
                        Button { download(file) } label: {
                            Label(file.name, systemImage:"arrow.down.doc").frame(minHeight:44,alignment:.leading)
                        }.disabled(!canDownload).accessibilityHint("将附件保存到文件")
                    } else { Label(file.name,systemImage:"paperclip").font(.callout) }
                }
            } else if let attachments = material?.attachments, !attachments.isEmpty {
                Text("附件名称").font(.caption).foregroundStyle(.secondary)
                ForEach(Array(attachments.enumerated()), id: \.offset) { _, file in
                    Label(file.name, systemImage: "paperclip").font(.callout).textSelection(.enabled)
                }
            } else if (part?.text ?? material?.text) == nil {
                Text(emptyText).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
