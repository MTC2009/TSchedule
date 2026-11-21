import SwiftUI

struct ReminderSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var subtitle = ""
    @State private var checkingNotifications = false
    @State private var checkStatus: String?
    @State private var changingReminders = false
    @State private var schoolMessage: String?

    var body: some View {
        SettingsForm {
            if model.school.selected { schoolReminders }
            Section {
                TextField("通知副标题", text: $subtitle, prompt: Text("不显示"))
                    .accessibilityIdentifier("settings-reminder-subtitle")
                    .submitLabel(.done)
                    .onSubmit(saveSubtitle)
                Button("保存副标题", action: saveSubtitle)
                    .disabled(subtitle == (model.personalization.reminderSubtitle ?? ""))
                Button("检查通知（5 秒后）", systemImage: "bell.badge") {
                    checkingNotifications = true
                    checkStatus = nil
                    Task {
                        defer { checkingNotifications = false }
                        checkStatus = await model.notifications.sendTest(subtitle: model.personalization.reminderSubtitle)
                    }
                }
                .disabled(checkingNotifications)
                if let checkStatus {
                    Text(checkStatus).font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("个人计划通知")
            } footer: {
                Text("给个人计划设置开始时间，并在计划的「提醒」中选择何时通知。副标题只用于个人计划和测试通知。")
            }
            #if DEBUG && TSCHEDULE_INTERNAL_FIXTURES
            if model.usesLocalTimetable { localReminders }
            #endif
        }
        .navigationTitle("提醒")
        .onAppear { subtitle = model.personalization.reminderSubtitle ?? "" }
    }

    private func saveSubtitle() {
        let previous = model.personalization.reminderSubtitle
        model.personalization.setReminderSubtitle(subtitle)
        subtitle = model.personalization.reminderSubtitle ?? ""
        if model.personalization.reminderSubtitle != previous {
            Task { await model.refreshPlanReminders() }
        }
    }

    private var schoolReminders: some View {
        let enabled = model.timetable.lessonRemindersEnabled
        return Section {
            Toggle("课前提醒", isOn: Binding(get: { model.timetable.lessonRemindersEnabled }, set: { next in
                changingReminders = true; schoolMessage = nil
                Task {
                    defer { changingReminders = false }
                    schoolMessage = await model.setSchoolReminders(next)
                }
            }))
            .disabled(changingReminders || (!enabled && !model.canEnableSchoolReminders))
            .accessibilityIdentifier("settings-school-lesson-reminders")
            if enabled {
                Picker("提醒时间", selection: Binding(get: { model.timetable.lessonLead }, set: { value in
                    model.timetable.setLessonLead(value)
                    schoolMessage = nil
                    Task { await model.refreshPlanReminders() }
                })) {
                    ForEach(SchoolLessonReminder.leads, id: \.self) { lead in
                        Text(lead == 0 ? "上课时" : "提前 \(lead) 分钟").tag(lead)
                    }
                }
                .disabled(changingReminders)
            }
            if let status = schoolMessage ?? (enabled ? model.notifications.schoolStatus : nil) {
                Text(status).font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings-school-lesson-status")
            }
        } header: { Text("校宝课表") } footer: {
            Text(model.canEnableSchoolReminders
                ? "只为本机课表已确认的课程安排未来 7 天的提醒，打开 App 时补排。通知不显示课程名或教室。"
                : "确认校宝账号并在设置中保存课表后可开启。")
        }
    }

    #if DEBUG && TSCHEDULE_INTERNAL_FIXTURES
    /// Built-in timetable only, independent of personal and school records.
    private var localReminders: some View {
        @Bindable var model = model
        return Section {
            Toggle("课前提醒", isOn: Binding(get: { model.preferences.remindersEnabled }, set: { enabled in
                changingReminders = true
                Task {
                    defer { changingReminders = false }
                    if enabled {
                        guard await model.notifications.requestPermission() else { return }
                        model.preferences.remindersEnabled = true
                    } else {
                        model.preferences.remindersEnabled = false
                    }
                    await model.refreshReminders()
                }
            })).disabled(changingReminders)
            Picker("提前多久", selection: $model.preferences.reminderLead) {
                Text("上课时").tag(0)
                ForEach([5, 10, 15], id: \.self) { Text("\($0) 分钟").tag($0) }
            }.onChange(of: model.preferences.reminderLead) { _, _ in Task { await model.refreshReminders() } }
            Toggle("晨间 Day 提醒", isOn: $model.preferences.morningEnabled)
                .onChange(of: model.preferences.morningEnabled) { _, _ in Task { await model.refreshReminders() } }
            DatePicker("提醒时间", selection: Binding(get: {
                SchoolClock.at(minute: model.preferences.morningMinute, on: model.now)
            }, set: { date in
                model.preferences.morningMinute = SchoolClock.minute(in: date)
                Task { await model.refreshReminders() }
            }), displayedComponents: .hourAndMinute).disabled(!model.preferences.morningEnabled)
            Text(model.notifications.status).font(.caption).foregroundStyle(.secondary)
        } header: { Text("课表提醒") } footer: {
            Text("按本机演示课表安排未来 7 天的提醒。")
        }
    }
    #endif
}
