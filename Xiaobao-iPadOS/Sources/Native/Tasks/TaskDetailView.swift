import SwiftUI

private let taskDetailShape = RoundedRectangle(cornerRadius: 16)

struct TaskDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    let task: TaskRecord

    private var completed: Bool { model.completedDemoTaskIDs.contains(task.id) }

    var body: some View {
        GeometryReader { geometry in
            // Measure the detail pane, not the unwrapped width of either text column.
            let wide = geometry.size.width >= 680 && !typeSize.isAccessibilitySize
            StudentDetailSurface {
                GlassEffectContainer(spacing: 8) {
                    VStack(alignment: .leading, spacing: 18) {
                        header
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
        .navigationTitle("任务详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("在校宝查看", systemImage: "safari") { model.openPortal(section: "我的任务") }
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
        TaskMaterialSection(title: String(localized: "任务内容"), material: task.instructions, emptyText: String(localized: "未提供任务说明。"))
    }

    private var answer: some View {
        VStack(alignment: .leading, spacing: 10) {
            TaskMaterialSection(title: String(localized: "我的回答"), material: task.answer, emptyText: String(localized: "未提供回答内容。"))
                .accessibilityIdentifier("task-detail-answer")
            if let date = task.submittedAt {
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
        TaskMaterialSection(title: String(localized: "老师点评"), material: task.feedback, emptyText: String(localized: "未提供点评。"))
            .accessibilityIdentifier("task-detail-feedback")
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

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
            if let text = material?.text { Text(text).lineSpacing(4).textSelection(.enabled) }
            if let attachments = material?.attachments, !attachments.isEmpty {
                Text("附件名称").font(.caption).foregroundStyle(.secondary)
                ForEach(Array(attachments.enumerated()), id: \.offset) { _, file in
                    Label(file.name, systemImage: "paperclip").font(.callout).textSelection(.enabled)
                }
            } else if material?.text == nil {
                Text(emptyText).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
