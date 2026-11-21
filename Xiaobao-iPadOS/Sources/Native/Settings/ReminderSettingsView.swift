import SwiftUI

struct ReminderSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var subtitle = ""
    @State private var checkingNotifications = false
    @State private var checkStatus: String?
    @State private var changingReminders = false

    var body: some View {
        SettingsForm {
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
                Text("副标题仅用于本机个人计划和测试通知。留空保存可清除；已送达的通知不变。")
            }
            if model.school.selected || model.campus.account != nil {
                Section("课表提醒") {
                    Label("课前和晨间提醒目前仅适用于本机演示课表。", systemImage: "bell.slash")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("settings-lesson-reminders-paused")
                }
            } else {
                localReminders
            }
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
}
