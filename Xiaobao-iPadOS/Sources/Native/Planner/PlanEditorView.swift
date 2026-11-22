import SwiftUI

/// Owned by the page, not by its sheet. Leaving to use the timetable does
/// not commit or discard other unsaved edits.
struct PlanEditorDraft {
    enum RepeatMode { case none, weekday, rotationDay }
    var title: String
    var timed: Bool
    var starts: Date
    var hasEnd: Bool
    var ends: Date
    var color: PlanColor?
    var icon: PlanIcon?
    var reusable: Bool
    var repeatMode: RepeatMode
    var weekday: Int
    var rotationDay: Int?
    var reminder: PlanReminder?
    var courseKind: SupplementalCourseKind?

    init(plan: PersonalPlan?, bubble: PlanBubble? = nil, on date: Date, now: Date, teachingDay: Int?) {
        title = plan?.title ?? ""
        timed = plan?.time != nil
        let start = plan?.time?.startMinute ?? SchoolClock.minute(in: now)
        starts = SchoolClock.at(minute: start, on: date)
        hasEnd = plan?.time?.endMinute != nil
        ends = SchoolClock.at(minute: plan?.time?.endMinute ?? min(start + 30, 1440), on: date)
        color = plan?.color
        icon = plan?.icon
        reusable = bubble?.reusable ?? false
        weekday = SchoolClock.calendar.component(.weekday, from: date)
        rotationDay = teachingDay.flatMap { PlanRecurrence.rotationDays.contains($0) ? $0 : nil }
        switch bubble?.latest?.rule?.recurrence {
        case .weekday(let value): repeatMode = .weekday; weekday = value
        case .rotationDay(let value): repeatMode = .rotationDay; rotationDay = value
        case nil: repeatMode = .none
        }
        reminder = plan?.reminder
        courseKind = plan?.courseKind
    }

    var time: PlanTime? {
        guard timed else { return nil }
        let end = SchoolClock.minute(in: ends)
        return PlanTime(startMinute: SchoolClock.minute(in: starts),
                        endMinute: hasEnd ? (end == 0 ? 1440 : end) : nil)
    }

    var recurrence: PlanRecurrence? {
        switch repeatMode {
        case .none: nil
        case .weekday: .weekday(weekday)
        case .rotationDay: rotationDay.map(PlanRecurrence.rotationDay)
        }
    }

    var allowsSave: Bool {
        if courseKind != nil && time?.endMinute == nil { return false }
        if repeatMode == .none { return !timed || time != nil }
        return time != nil && recurrence?.isValid == true
    }

    mutating func use(_ range: PlanTime, on date: Date) {
        starts = range.start(on: date)
        timed = true
        hasEnd = range.endMinute != nil
        if let end = range.end(on: date) { ends = end }
    }

    mutating func suggestEnd(on date: Date) {
        ends = SchoolClock.at(minute: min(SchoolClock.minute(in: starts) + 30, 1440), on: date)
    }
}

struct PlanEditorView: View {
    struct Completion {
        let completed: Bool
        let toggle: () async throws -> Void
    }
    struct Removal {
        let plan: PersonalPlan
        let recurring: Bool
        let commit: (PlanStore.RemovalScope) async throws -> Void
    }

    let date: Date
    let planID: UUID
    let target: PlanEditTarget
    let effectiveDate: Date
    let hadRepeatRule: Bool
    let calendar: PublishedSchoolCalendar?
    @Binding var draft: PlanEditorDraft
    let conflicts: (PlanTime) -> [PlannerSchoolEntry]
    let chooseRange: () -> Void
    let cancel: () -> Void
    var completion: Completion? = nil
    var removal: Removal? = nil
    let save: (PersonalPlan) async throws -> Void
    @ScaledMetric(relativeTo: .body) private var swatchCell = 44.0
    @State private var saving = false
    @State private var failureMessage: String?
    @State private var confirmingRemoval = false

    private var plan: PersonalPlan? {
        guard draft.allowsSave else { return nil }
        return PersonalPlan(id: planID, day: SchoolClock.key(date), title: draft.title, time: draft.time,
                            color: draft.color, icon: draft.icon, reminder: draft.reminder, courseKind: draft.courseKind)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(schoolDateLabel(date)) {
                    TextField("计划名称", text: $draft.title)
                        .accessibilityIdentifier("plan-title")
                    if draft.title.trimmingCharacters(in: .whitespacesAndNewlines).count > PersonalPlan.titleLimit {
                        Text("计划名称最多 \(PersonalPlan.titleLimit) 个字。").foregroundStyle(.secondary)
                    }
                    Picker("安排类型", selection: $draft.courseKind) {
                        Text("个人计划").tag(nil as SupplementalCourseKind?)
                        ForEach(SupplementalCourseKind.allCases, id: \.self) { kind in
                            Text(verbatim: kind.category.title).tag(Optional(kind))
                        }
                    }
                    .accessibilityIdentifier("plan-course-kind")
                    .onChange(of: draft.courseKind) { _, kind in
                        guard kind != nil else { return }
                        draft.timed = true
                        if !draft.hasEnd { draft.suggestEnd(on: date); draft.hasEnd = true }
                    }
                    if draft.courseKind != nil {
                        Text("补充课程会按所选时段显示在「今日」和「计划」，不会写入校宝。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Button("在课表上选时段", systemImage: "hand.draw", action: chooseRange)
                        .accessibilityIdentifier("plan-choose-range")
                    if draft.timed {
                        DatePicker("开始", selection: $draft.starts, displayedComponents: .hourAndMinute)
                            .accessibilityIdentifier("plan-start-time")
                        Toggle("设置结束时间", isOn: $draft.hasEnd)
                            .disabled(draft.courseKind != nil)
                            .onChange(of: draft.hasEnd) { _, enabled in
                                if enabled, draft.time == nil { draft.suggestEnd(on: date) }
                            }
                        if draft.hasEnd {
                            DatePicker("结束", selection: $draft.ends, displayedComponents: .hourAndMinute)
                                .accessibilityIdentifier("plan-end-time")
                            if draft.time == nil {
                                Text("结束时间须晚于开始时间。").foregroundStyle(.secondary)
                            } else if draft.time?.endMinute == 1440 {
                                Text("结束时间为当天 24:00。").foregroundStyle(.secondary)
                            }
                        }
                        if let time = draft.time, !conflicts(time).isEmpty {
                            Label("与已知学校安排重叠，仍可保存。", systemImage: "exclamationmark.circle")
                        }
                        if target == .create && draft.courseKind == nil {
                            Button("不设置时间") { draft.timed = false }
                        }
                    } else {
                        Button("按分钟设置时间") { draft.timed = true }
                    }
                } footer: {
                    if let time = draft.time {
                        Text(PlannerScheduleCanvas.timeLabel(time)).monospacedDigit()
                            .accessibilityIdentifier("plan-editor-time")
                    } else {
                        Text("未定时间的计划留在当天的「待安排」。")
                    }
                }
                if let removal {
                    Section {
                        Button("移除计划", role: .destructive) { confirmingRemoval = true }
                            .accessibilityIdentifier("plan-editor-remove")
                            .confirmationDialog(removal.plan.title, isPresented: $confirmingRemoval, titleVisibility: .visible) {
                                if removal.recurring {
                                    Button("仅这次", role: .destructive) { remove(.onlyThis, using: removal) }
                                    Button("这次及以后", role: .destructive) { remove(.thisAndLater, using: removal) }
                                } else {
                                    Button("确认移除", role: .destructive) { remove(.onlyThis, using: removal) }
                                }
                                Button("取消", role: .cancel) { }
                            } message: {
                                if removal.recurring {
                                    Text("所选日期：\(removal.plan.day)。移除的安排将不再提醒，之前的记录不变。")
                                } else {
                                    Text("仅移除这条个人计划和它的提醒。")
                                }
                            }
                    }
                }
                if case .plan = target {} else { repeatOptions }
                if let completion {
                    Section {
                        Button(completion.completed ? String(localized: "取消本次完成") : String(localized: "标记本次完成"),
                               systemImage: completion.completed ? "checkmark.circle.fill" : "circle") {
                            perform(completion.toggle)
                        }
                        .accessibilityIdentifier("plan-editor-completion")
                    }
                }
                reminderOptions
                appearance
                if let failureMessage {
                    Section {
                        Label(failureMessage, systemImage: "exclamationmark.circle")
                    }
                }
            }
            .disabled(saving)
            .onChange(of: draft.starts) { _, _ in
                if !draft.hasEnd { draft.suggestEnd(on: date) }
            }
            .navigationTitle(target == .create ? String(localized: "新建计划") : String(localized: "编辑计划"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: cancel).disabled(saving).accessibilityIdentifier("plan-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        guard let plan, !saving else { return }
                        perform { try await save(plan) }
                    } label: {
                        if saving { ProgressView().accessibilityLabel("正在保存") }
                        else { Text("保存") }
                    }
                    .disabled(plan == nil || saving)
                    .accessibilityIdentifier("plan-save")
                }
            }
        }
        .environment(\.calendar, SchoolClock.calendar)
        .interactiveDismissDisabled(saving)
    }

    private func remove(_ scope: PlanStore.RemovalScope, using removal: Removal) {
        perform(failure: String(localized: "移除未成功，请重新打开这条计划再试。")) { try await removal.commit(scope) }
    }

    private func perform(failure: String = String(localized: "没有保存，原有计划未改动。请重试。"),
                         _ operation: @escaping () async throws -> Void) {
        guard !saving else { return }
        saving = true
        failureMessage = nil
        Task {
            defer { saving = false }
            do { try await operation() }
            catch { failureMessage = failure }
        }
    }

    private var repeatOptions: some View {
        Section {
            Toggle("留作常用气泡", isOn: $draft.reusable)
                .accessibilityIdentifier("plan-reusable")
            Picker("重复", selection: $draft.repeatMode) {
                Text("不重复").tag(PlanEditorDraft.RepeatMode.none)
                Text("按星期").tag(PlanEditorDraft.RepeatMode.weekday)
                Text("按轮转 Day").tag(PlanEditorDraft.RepeatMode.rotationDay)
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("plan-repeat-mode")
            if draft.repeatMode == .weekday {
                Picker("重复星期", selection: $draft.weekday) {
                    ForEach([String(localized: "星期日"), String(localized: "星期一"), String(localized: "星期二"), String(localized: "星期三"), String(localized: "星期四"), String(localized: "星期五"), String(localized: "星期六")].enumerated().map { ($0.offset + 1, $0.element) }, id: \.0) { day in
                        Text(day.1).tag(day.0)
                    }
                }
                .accessibilityIdentifier("plan-weekday")
            } else if draft.repeatMode == .rotationDay {
                Picker("轮转日", selection: $draft.rotationDay) {
                    Text("请选择").tag(nil as Int?)
                    ForEach(PlanRecurrence.rotationDays, id: \.self) { day in
                        Text(verbatim: "Day \(day)").tag(Optional(day))
                    }
                }
                .accessibilityIdentifier("plan-rotation-day")
            }
        } footer: {
            if draft.repeatMode != .none && draft.time == nil {
                Text("请先设置重复计划的开始时间。")
            } else if draft.repeatMode == .rotationDay && draft.rotationDay == nil {
                Text("请选择要重复的轮转日。")
            } else if draft.repeatMode != .none || hadRepeatRule {
                let first = SchoolClock.key(effectiveDate)
                if draft.repeatMode == .rotationDay, let day = draft.rotationDay,
                   calendar?.days.contains(where: { $0.date >= first && $0.teachingDay == day }) != true {
                    Text("校历暂未确认后续的这个 Day。可以先保存，暂不安排日期或提醒。")
                } else {
                    Text("只影响\(schoolDateLabel(effectiveDate, format: "M月d日"))起的重复安排，不改之前的记录。")
                }
            } else {
                Text("常用气泡可以反复拖到课表，每次只添加当天的一条计划。")
            }
        }
    }

    private var reminderOptions: some View {
        Section {
            Picker(selection: $draft.reminder) {
                Text("不提醒").tag(nil as PlanReminder?)
                ForEach(PlanReminder.allCases, id: \.self) { choice in
                    Text(reminderLabel(choice)).tag(Optional(choice))
                }
            } label: {
                Label("提醒", systemImage: "bell")
            }
            .accessibilityIdentifier("plan-reminder")
        } footer: {
            if draft.reminder != nil && draft.time == nil {
                Text("安排好开始时间后才会提醒。")
            }
        }
    }

    private func reminderLabel(_ reminder: PlanReminder) -> String {
        switch reminder {
        case .atStart: String(localized: "开始时")
        case .oneHour: String(localized: "提前 1 小时")
        default: String(localized: "提前 \(reminder.rawValue) 分钟")
        }
    }

    private var appearance: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("颜色")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: swatchCell), spacing: 4)], spacing: 4) {
                    swatch(nil)
                    ForEach(PlanColor.allCases, id: \.self) { swatch($0) }
                }
            }
            Picker(selection: $draft.icon) {
                Text("无图标").tag(nil as PlanIcon?)
                ForEach(PlanIcon.allCases, id: \.self) { icon in
                    Label(icon.name, systemImage: icon.symbol).tag(Optional(icon))
                }
            } label: {
                Label("图标", systemImage: draft.icon?.symbol ?? "square.dashed")
            }
            .accessibilityIdentifier("plan-icon-picker")
        } footer: {
            Text("仅保存在这台 iPad。")
        }
    }

    private func swatch(_ color: PlanColor?) -> some View {
        let selected = draft.color == color
        return Button { draft.color = color } label: {
            Circle().fill((color?.tint ?? .secondary).opacity(0.22))
                .overlay {
                    Circle().strokeBorder(color?.tint ?? .secondary, lineWidth: selected ? 2 : 1)
                    if selected { Image(systemName: "checkmark").font(.caption.weight(.semibold)).foregroundStyle(.primary) }
                }
                .frame(width: 28, height: 28)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(color?.name ?? String(localized: "默认颜色"))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("plan-color-\(color?.rawValue ?? "default")")
    }
}
