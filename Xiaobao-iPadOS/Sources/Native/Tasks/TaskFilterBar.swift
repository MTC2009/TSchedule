import SwiftUI

struct TaskFilterBar<TermControl: View>: View {
    let tasks: [TaskRecord]
    let now: Date
    @Binding var filters: TaskFilters
    let resetEnabled: Bool
    let reset: () -> Void
    @ViewBuilder let termControl: () -> TermControl
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var editingDates = false

    var body: some View {
        GlassCard(padding: 14, shape: .rect(cornerRadius: 18)) {
            VStack(alignment: .leading, spacing: 10) {
                LazyVGrid(columns: [GridItem(typeSize.isAccessibilitySize ? .flexible() : .adaptive(minimum: 150),
                                            spacing: 8, alignment: .leading)], spacing: 8) {
                    facet("课程", all: "全部课程", options: TaskFilters.courses(in: tasks), selection: $filters.course, id: "course")
                    facet("任务类型", all: "全部类型", options: TaskFilters.workTypes(in: tasks), selection: $filters.workType, id: "type")
                    submissionMenu
                    gradingMenu
                    deadlineButton
                    facet("任务模式", all: "全部模式", options: TaskFilters.modes(in: tasks), selection: $filters.mode, id: "mode")
                    termControl()
                }
                HStack(spacing: 8) {
                    HStack(spacing: 9) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                        TextField("搜索任务标题", text: $filters.query)
                            .textInputAutocapitalization(.never)
                            .accessibilityIdentifier("task-filter-search")
                    }
                    .padding(.horizontal, 11).frame(minHeight: 44)
                    .background(.fill.tertiary, in: .rect(cornerRadius: 10))
                    Button("重置", action: reset)
                        .buttonStyle(.glass).disabled(!resetEnabled)
                        .accessibilityIdentifier("task-filter-reset")
                }
            }
        }
    }

    private func facet(_ title: String, all: String, options: [TaskFacetOption], selection: Binding<TaskFacetValue?>, id: String) -> some View {
        let current = options.first { $0.value == selection.wrappedValue }?.title ?? all
        return Menu {
            Picker(title, selection: selection) {
                Text(all).tag(nil as TaskFacetValue?)
                ForEach(options) { option in Text(option.title).tag(Optional(option.value)) }
            }.pickerStyle(.inline)
        } label: {
            TaskFilterLabel(title: title, value: current)
        }
        .buttonStyle(.plain).hoverEffect(.highlight)
        .accessibilityIdentifier("task-filter-\(id)")
    }

    private var submissionMenu: some View {
        Menu {
            Picker("提交状态", selection: $filters.submission) {
                Text("全部提交状态").tag(nil as TaskSubmissionState?)
                ForEach(TaskSubmissionState.allCases) { state in Text(state.title).tag(Optional(state)) }
            }.pickerStyle(.inline)
        } label: {
            TaskFilterLabel(title: "提交状态", value: filters.submission?.title ?? "全部")
        }
        .buttonStyle(.plain).hoverEffect(.highlight)
        .accessibilityIdentifier("task-filter-submission")
    }

    private var gradingMenu: some View {
        Menu {
            Picker("批改状态", selection: $filters.grading) {
                Text("全部批改状态").tag(nil as TaskGradingState?)
                ForEach(TaskGradingState.allCases) { state in Text(state.title).tag(Optional(state)) }
            }.pickerStyle(.inline)
        } label: {
            TaskFilterLabel(title: "批改状态", value: filters.grading?.title ?? "全部")
        }
        .buttonStyle(.plain).hoverEffect(.highlight)
        .accessibilityIdentifier("task-filter-grading")
    }

    private var deadlineButton: some View {
        Button { editingDates = true } label: {
            let value = filters.deadlines.map {
                schoolDateLabel($0.start, format: "M/d") + " – " + schoolDateLabel($0.end, format: "M/d")
            } ?? "不限日期"
            TaskFilterLabel(title: "截止日期", value: value, symbol: "calendar")
        }
        .buttonStyle(.plain).hoverEffect(.highlight)
        .accessibilityIdentifier("task-filter-dates")
        .sheet(isPresented: $editingDates) {
            let dates = tasks.compactMap(\.dueAt)
            TaskDeadlineEditor(
                start: filters.deadlines?.start ?? dates.min() ?? now,
                end: filters.deadlines?.end ?? dates.max() ?? now,
                hasSelection: filters.deadlines != nil
            ) { filters.deadlines = $0 }
        }
    }
}

struct TaskFilterLabel: View {
    let title, value: String
    var symbol = "chevron.up.chevron.down"

    var body: some View {
        HStack(spacing: 7) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.caption2).foregroundStyle(.secondary)
                Text(value).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
            }
            Spacer(minLength: 0)
            Image(systemName: symbol).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 6).frame(minHeight: 44)
        .background(.fill.tertiary, in: .rect(cornerRadius: 10))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}

private struct TaskDeadlineEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var start: Date
    @State var end: Date
    let hasSelection: Bool
    let apply: (TaskDeadlineRange?) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("起始日期", selection: $start, displayedComponents: .date)
                    DatePicker("结束日期", selection: $end, displayedComponents: .date)
                } footer: {
                    if TaskDeadlineRange(start: start, end: end) == nil {
                        Text("起始日期不能晚于结束日期。")
                    }
                }
                if hasSelection {
                    Button("不限日期") { apply(nil); dismiss() }
                }
            }
            .navigationTitle("筛选截止日期")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("应用") {
                        if let range = TaskDeadlineRange(start: start, end: end) { apply(range); dismiss() }
                    }
                    .disabled(TaskDeadlineRange(start: start, end: end) == nil)
                }
            }
        }
        .environment(\.calendar, SchoolClock.calendar)
        .environment(\.timeZone, SchoolClock.calendar.timeZone)
    }
}
