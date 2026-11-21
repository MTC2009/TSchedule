import SwiftUI

struct PlannerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var phase
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var chosenDate: Date?
    @State private var editing = false
    @State private var plansHidden = false
    @State private var monthPresented = false
    @State private var editSession = UUID()
    @State private var read: PlanRead?
    @State private var checkedSchool: SchoolRead?
    @State private var refreshingSchool = false
    @State private var writeFailure: String?
    @State private var pendingPlanID: UUID?
    @State private var editor: Editor?

    private struct Scope: Hashable {
        let owner: PlanOwner
        let session: UUID?
    }

    private struct SchoolRead: Hashable {
        let scope: Scope?
        let dates: [Date]
    }

    private struct PlanRead {
        let scope: Scope
        let value: PlanStore.EditorState?
    }

    private struct Editor {
        let id = UUID()
        let scope: Scope
        let date: Date
        let target: PlanEditTarget
        let planID: UUID
        let effectiveDay: String
        let hadRepeatRule: Bool
        let completionPlan: PersonalPlan?
        var draft: PlanEditorDraft
        var selectingRange = false
    }

    private var date: Date { SchoolClock.calendar.startOfDay(for: chosenDate ?? model.now) }
    private var isToday: Bool { SchoolClock.calendar.isDate(date, inSameDayAs: model.now) }
    // Defer an external date jump until the planner's unsaved draft is closed.
    private var incomingDate: Date? { editor == nil ? model.plannerDateRequest : nil }
    private var scope: Scope? {
        model.activePlanOwner.map { Scope(owner: $0, session: model.school.selected ? model.school.epoch : model.campus.account?.scope) }
    }
    private var state: PlanStore.EditorState? { read?.scope == scope ? read?.value : nil }
    private var canWrite: Bool { state != nil && pendingPlanID == nil && scope != nil }

    private var rangeRequest: PlannerRangeRequest? {
        guard let editor, editor.scope == scope, editor.selectingRange else { return nil }
        return .init(id: editor.id, date: editor.date, title: editor.draft.title, color: editor.draft.color,
                     anchor: editor.draft.time?.startMinute)
    }

    private var editorPresented: Binding<Bool> {
        Binding(get: { editor.map { $0.scope == scope && !$0.selectingRange } ?? false },
                set: { if !$0, editor?.selectingRange == false { editor = nil } })
    }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let wide = size.width >= 745 && size.width > size.height && !typeSize.isAccessibilitySize
            let week = TimetableWeek(containing: date)
            let dates = wide ? week.dates.filter { PlannerCalendarMonth.selectableDates.contains($0) } : [date]
            content(dates: dates, week: wide ? week : nil)
                .padding(.horizontal, wide ? 20 : 24)
                .padding(.top, 12).padding(.bottom, 8)
                .frame(maxWidth: wide ? 1280 : 1000)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: scope) { await readPlans() }
        .onChange(of: incomingDate, initial: true) { _, request in
            guard request != nil, let date = model.takePlannerDateRequest() else { return }
            select(date)
        }
        .onChange(of: scope) { _, _ in
            editing = false
            plansHidden = false
            editor = nil
            monthPresented = false
            writeFailure = nil
        }
        .sheet(isPresented: editorPresented) { if let editor { editorSheet(editor) } }
    }

    private func content(dates: [Date], week: TimetableWeek?) -> some View {
        let source = PlannerSchoolSource(model: model, dates: dates)
        let current = scope
        // Entering Edit temporarily shows the records without changing the browse preference.
        let showsPlans = editing || !plansHidden
        let calendar = model.planRotationCalendar
        let columns = dates.map {
            source.column(on: $0, records: showsPlans ? state?.schedule.day(SchoolClock.key($0), calendar: calendar) : nil)
        }
        let selected = columns.first { $0.id == date }
        let fetch = SchoolRead(scope: current, dates: dates)
        let acceptsTouches = !monthPresented && !model.environmentPresented && !model.portalPresented &&
            model.selectedLesson == nil && (editor == nil || rangeRequest != nil)
        return VStack(spacing: 8) {
            header(selected, week: week, source: source)
                .disabled(rangeRequest != nil)
            if model.school.selected {
                if selected?.school.hasTimetable != true {
                    Text(model.timetable.busy ? "正在保存本学年课表" : "当天课表尚未确认，可在设置中更新。")
                        .font(.callout).foregroundStyle(.secondary)
                }
            } else if current?.session != nil { schoolStatus(source, selected: selected, fetch: fetch) }
            if current == nil {
                Label(model.localSchoolTimetable == nil ? "暂时无法读取此账号的计划。" : "正在查看本机课表；个人计划需确认账号后查看。", systemImage: "person.crop.circle.badge.exclamationmark")
                    .font(.callout).foregroundStyle(.secondary)
            } else if read?.scope == current, state == nil {
                status("无法读取已保存的计划。") { Task { await readPlans() } }
            }
            if let writeFailure {
                GlassCard(padding: 8, shape: PlannerCorners.card) {
                    Label(writeFailure, systemImage: "exclamationmark.circle").font(.callout)
                }
            }
            PlannerTimelineView(columns: columns, selectedDate: date,
                                initialMinute: initialMinute(selected, columns: columns, week: week),
                                canWrite: canWrite, editing: editing, showsPlans: showsPlans,
                                acceptsTouches: acceptsTouches,
                                pendingPlanID: pendingPlanID,
                                bubbles: state?.schedule.bubbles.filter(\.visibleOnShelf) ?? [],
                                reminderStatus: model.notifications.planStatus, rangeRequest: rangeRequest,
                                selectDay: { if rangeRequest == nil { select($0) } },
                                finishRange: finishRange, add: { openEditor(nil, on: date) },
                                edit: editPlan, place: place, toggleCompletion: complete)
                .id(current)
        }
        .task(id: phase == .active ? fetch : nil) {
            if phase == .active, !model.school.selected { await loadSchool(source, fetch: fetch) }
        }
    }

    private func header(_ selected: PlannerTimelineColumn?, week: TimetableWeek?, source: PlannerSchoolSource) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                heading(selected, week: week)
                Spacer(minLength: 8)
                navigation(week: week, source: source)
                editControls
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    heading(selected, week: week)
                    Spacer(minLength: 4)
                    editControls
                }
                navigation(week: week, source: source)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func heading(_ selected: PlannerTimelineColumn?, week: TimetableWeek?) -> some View {
        let title: String
        if let week {
            title = schoolDateLabel(week.start, format: "M月d日") + "–" + schoolDateLabel(week.end, format: "M月d日")
        } else if selected?.calendarDay?.status == .unpublished && selected?.day.timed.isEmpty != false {
            title = "尚未公布"
        } else if let rotation = selected?.calendarDay?.day ?? selected?.school.rotationDay {
            title = "Day \(rotation)"
        } else if selected?.calendarDay?.status == .noClass || selected?.calendarDay?.status == .weekend {
            title = "休息日"
        } else {
            title = schoolDateLabel(date, format: "M月d日")
        }
        return HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(title).font(.system(week == nil ? .largeTitle : .title2, design: .rounded, weight: .bold))
            if week == nil {
                Text(isToday ? "今天" : schoolDateLabel(date, format: "EEEE"))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
    }

    private func navigation(week: TimetableWeek?, source: PlannerSchoolSource) -> some View {
        HStack(spacing: 1) {
            dateButton(week == nil ? "前一天" : "上一周", icon: "chevron.left", offset: week == nil ? -1 : -7)
            Button { monthPresented = true } label: {
                Text(schoolDateLabel(date, format: week == nil ? "yyyy年M月d日" : "M月d日"))
                    .font(.callout.weight(.medium)).monospacedDigit()
                    .padding(.horizontal, 5).frame(minHeight: 36)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("选择日期").accessibilityValue(schoolDateLabel(date))
            .accessibilityIdentifier("planner-date")
            .popover(isPresented: $monthPresented, arrowEdge: .top) {
                PlannerMonthPicker(selectedDate: date, publication: source.publication) { newDate in
                    select(newDate)
                    monthPresented = false
                }
                .presentationCompactAdaptation(.popover)
            }
            dateButton(week == nil ? "后一天" : "下一周", icon: "chevron.right", offset: week == nil ? 1 : 7)
            if !isToday {
                Button("今天") { select(model.now) }
                    .font(.callout).frame(minHeight: 44)
                    .accessibilityLabel("回到今天")
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var editControls: some View {
        GlassEffectContainer(spacing: 4) {
            HStack(spacing: 3) {
                if editing {
                    historyButton(.undo, title: "撤销", icon: "arrow.uturn.backward", available: state?.canUndo == true)
                    historyButton(.redo, title: "重做", icon: "arrow.uturn.forward", available: state?.canRedo == true)
                } else {
                    // Keep the header on the same line at intermediate widths.
                    // The underlying scroll view should not move on mode changes.
                    historyButton(.undo, title: "撤销", icon: "arrow.uturn.backward", available: false)
                        .hidden().accessibilityHidden(true).allowsHitTesting(false)
                    Button { plansHidden.toggle() } label: {
                        Label(plansHidden ? "显示个人计划" : "隐藏个人计划", systemImage: plansHidden ? "eye.slash" : "eye")
                            .labelStyle(.iconOnly).frame(minWidth: 32, minHeight: 36)
                    }
                    .buttonStyle(.glass)
                    .accessibilityIdentifier("planner-plan-visibility")
                    .accessibilityValue(plansHidden ? "已隐藏" : "已显示")
                }
                Button { editing.toggle(); writeFailure = nil } label: {
                    Label(editing ? "完成" : "编辑", systemImage: editing ? "checkmark" : "pencil")
                        .font(.callout.weight(.medium)).frame(minWidth: 52, minHeight: 36)
                }
                .buttonStyle(.glass)
                .disabled(!canWrite)
                .accessibilityIdentifier("planner-edit-mode")
                .accessibilityLabel(editing ? "完成编辑" : "编辑计划")
                .accessibilityAddTraits(editing ? .isSelected : [])
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func historyButton(_ direction: PlanEditHistory.Direction, title: String, icon: String,
                               available: Bool) -> some View {
        Button { changeHistory(direction) } label: {
            Label(title, systemImage: icon).labelStyle(.iconOnly)
                .frame(minWidth: 32, minHeight: 36)
        }
        .buttonStyle(.glass)
        .disabled(!canWrite || !available)
        .accessibilityIdentifier(direction == .undo ? "planner-undo" : "planner-redo")
    }

    private func dateButton(_ label: String, icon: String, offset: Int) -> some View {
        let next = SchoolClock.calendar.date(byAdding: .day, value: offset, to: date)
        return Button {
            if let next { select(next) }
        } label: {
            Label(label, systemImage: icon).labelStyle(.iconOnly)
                .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(next.map { !PlannerCalendarMonth.selectableDates.contains($0) } ?? true)
    }

    private func select(_ newDate: Date) {
        let day = SchoolClock.calendar.startOfDay(for: newDate)
        guard PlannerCalendarMonth.selectableDates.contains(day) else { return }
        chosenDate = SchoolClock.calendar.isDate(day, inSameDayAs: model.now) ? nil : day
    }

    private func initialMinute(_ selected: PlannerTimelineColumn?, columns: [PlannerTimelineColumn], week: TimetableWeek?) -> Int? {
        if week != nil {
            let first = columns.flatMap { column in
                column.day.timed.compactMap { row -> Int? in
                    guard case .school(let entry) = row else { return nil }
                    return SchoolClock.minute(in: entry.start)
                }
            }.min() ?? 480
            return min(480, first)
        }
        guard let selected else { return nil }
        let school = PlannerDay(on: selected.id, school: selected.school, plans: [])
        if !isToday { return school.timed.first.map { SchoolClock.minute(in: $0.start) } ?? 480 }
        let next = selected.focus.flatMap { focus in school.timed.first { $0.id == focus.id } }
        if let current = school.timed.last(where: { row in
            row.canBeFocus && row.start <= model.now && (row.end.map { model.now < $0 } ?? false)
        }), next.map({ $0.start.timeIntervalSince(current.start) <= 5400 }) ?? true {
            return SchoolClock.minute(in: current.start)
        }
        return SchoolClock.minute(in: next?.start ?? model.now)
    }

    @ViewBuilder private func schoolStatus(_ source: PlannerSchoolSource, selected: PlannerTimelineColumn?, fetch: SchoolRead) -> some View {
        let failed = source.calendarPage.map { model.campus.errors[$0] != nil } ?? false
        if failed || (checkedSchool == fetch && selected?.school.hasCalendar == false) {
            status("学校资料暂未更新，已有安排仍可查看。") {
                Task { await loadSchool(source, fetch: fetch, force: true) }
            }
        }
    }

    private func status(_ message: String, retry: @escaping () -> Void) -> some View {
        GlassCard(padding: 10, shape: PlannerCorners.card) {
            HStack {
                Label(message, systemImage: "exclamationmark.circle").font(.callout)
                Spacer(minLength: 8)
                Button("重试", action: retry).frame(minHeight: 44).disabled(refreshingSchool)
            }
        }
    }

    private func readPlans() async {
        guard let current = scope else { read = nil; return }
        let result = try? await model.planStore.readEditor(for: current.owner, session: editSession)
        if current == scope, !Task.isCancelled { read = PlanRead(scope: current, value: result) }
    }

    private func loadSchool(_ source: PlannerSchoolSource, fetch: SchoolRead, force: Bool = false) async {
        guard scope == fetch.scope, fetch.scope?.session != nil, !force || !refreshingSchool else { return }
        if force { refreshingSchool = true }
        defer { if force { refreshingSchool = false } }
        await source.load(selected: date, force: force)
        if scope == fetch.scope, !Task.isCancelled { checkedSchool = fetch }
    }

    private func editPlan(_ item: PlanPlacementItem) {
        let target = item.source == .recurringBubble || item.source == .reusableBubble ? date :
            (SchoolClock.dayDate(item.plan.day) ?? date)
        openEditor(item, on: target)
    }

    private func openEditor(_ item: PlanPlacementItem?, on day: Date, range: PlanTime? = nil) {
        // Opening an existing record is an explicit action; creating a new
        // record still requires the board to be in Edit.
        guard editor == nil, canWrite, editing || item != nil, let current = scope else { return }
        let bubble = item.flatMap { item in state?.schedule.bubbles.first { $0.id == item.plan.id } }
        let target: PlanEditTarget = if let bubble { .bubble(bubble.id) }
            else if let item { .plan(item.plan.id) } else { .create }
        let today = SchoolClock.key(model.now)
        let effective = max(today, SchoolClock.key(day), bubble?.revisions.first?.effectiveDay ?? today)
        var draft = PlanEditorDraft(plan: bubble?.prototype ?? item?.plan, bubble: bubble, on: day, now: model.now,
                                    teachingDay: model.planRotationCalendar?.day(on: day).teachingDay)
        if let range { draft.use(range, on: day) }
        let completion = item.flatMap { $0.source == .plan || $0.source == .occurrence ? $0.plan : nil }
        editor = Editor(scope: current, date: day, target: target, planID: item?.plan.id ?? UUID(),
                        effectiveDay: effective, hadRepeatRule: bubble?.latest?.rule != nil,
                        completionPlan: completion, draft: draft)
    }

    private func editorSheet(_ request: Editor) -> some View {
        let school = PlannerSchoolSource(model: model, dates: [request.date]).schoolDay(on: request.date).school
        let conflictDay = PlannerDay(on: request.date, school: school, plans: [])
        let draft = Binding(get: { editor?.id == request.id ? editor?.draft ?? request.draft : request.draft },
                            set: { if editor?.id == request.id { editor?.draft = $0 } })
        let completion = request.completionPlan.flatMap { source in
            state?.schedule.day(source.day, calendar: model.planRotationCalendar).plans.first { $0.id == source.id }
        }
        return PlanEditorView(date: request.date, planID: request.planID, target: request.target,
                              effectiveDate: SchoolClock.dayDate(request.effectiveDay) ?? request.date,
                              hadRepeatRule: request.hadRepeatRule, calendar: model.planRotationCalendar, draft: draft,
                              conflicts: conflictDay.conflicts(with:),
                              chooseRange: { chooseRange(for: request) },
                              cancel: { if editor?.id == request.id { editor = nil } },
                              completion: completion.map { plan in
            .init(completed: plan.isCompleted, toggle: {
                try await persist(.complete(!plan.isCompleted, plan: plan), pending: plan.id, scope: request.scope)
            })
        }) { plan in
            guard let current = editor, current.id == request.id else { throw CancellationError() }
            let edit = PlanEdit(target: request.target, plan: plan, reusable: current.draft.reusable,
                                recurrence: current.draft.recurrence,
                                effectiveDay: request.effectiveDay)
            try await persist(.save(edit), pending: plan.id, scope: request.scope,
                              requestPermission: plan.reminder != nil && plan.time != nil)
            if editor?.id == request.id {
                select(request.date)
                editor = nil
            }
        }
    }

    private func chooseRange(for request: Editor) {
        guard editor?.id == request.id, request.scope == scope, canWrite else { return }
        // Keep the draft and hand its date to the same board edit mode used
        // for a new range. Only the requested day's time can change here.
        select(request.date)
        editing = true
        editor?.selectingRange = true
    }

    private func finishRange(_ day: Date, _ range: PlanTime?) {
        if var current = editor, current.scope == scope, current.selectingRange {
            guard current.date == day else { return }
            if let range { current.draft.use(range, on: day) }
            current.selectingRange = false
            editor = current
        } else if editing, let range {
            openEditor(nil, on: day, range: range)
        }
    }

    private func place(_ item: PlanPlacementItem, on day: Date, at time: PlanTime?) {
        guard editing, PlannerCalendarMonth.selectableDates.contains(day) else { return }
        if item.isRecurring, case .rotationDay = state?.schedule.bubbles.first(where: { $0.id == item.plan.id })?.latest?.rule?.recurrence,
           model.planRotationCalendar?.day(on: day).teachingDay == nil {
            writeFailure = "这一天没有已确认的轮转 Day，原计划没有改动。"
            return
        }
        apply(.place(item, on: SchoolClock.key(day), at: time, now: model.now), pending: item.plan.id,
              requestPermission: time != nil && item.plan.reminder != nil)
    }

    private func complete(_ plan: PersonalPlan) {
        guard editing else { return }
        apply(.complete(!plan.isCompleted, plan: plan), pending: plan.id)
    }

    private func apply(_ command: PlanStore.Mutation, pending id: UUID, requestPermission: Bool = false) {
        guard canWrite, let current = scope else { return }
        Task {
            do { try await persist(command, pending: id, scope: current, requestPermission: requestPermission) }
            catch is CancellationError {}
            catch { if scope == current { writeFailure = "未能保存，原计划没有改动。" } }
        }
    }

    private func persist(_ command: PlanStore.Mutation, pending id: UUID, scope current: Scope,
                         requestPermission: Bool = false) async throws {
        try await write(pending: id, scope: current, requestPermission: requestPermission) { session in
            try await model.planStore.apply(command, for: current.owner, session: session, calendar: model.planRotationCalendar)
        }
    }

    private func changeHistory(_ direction: PlanEditHistory.Direction) {
        guard editing, canWrite, let current = scope else { return }
        Task {
            do {
                try await write(pending: UUID(), scope: current) { session in
                    try await model.planStore.step(direction, for: current.owner, session: session)
                }
            } catch is CancellationError {} catch {
                if scope == current { writeFailure = direction == .undo ? "未能撤销，原计划没有改动。" : "未能重做，原计划没有改动。" }
            }
        }
    }

    private func write(pending id: UUID, scope current: Scope, requestPermission: Bool = false,
                       _ commit: (UUID) async throws -> PlanStore.EditorState) async throws {
        guard canWrite, scope == current else { throw CancellationError() }
        pendingPlanID = id
        writeFailure = nil
        defer { pendingPlanID = nil }
        let value = try await commit(editSession)
        if scope == current {
            read = PlanRead(scope: current, value: value)
            Task { await model.refreshPlanReminders(requestPermission: requestPermission) }
        }
    }
}
