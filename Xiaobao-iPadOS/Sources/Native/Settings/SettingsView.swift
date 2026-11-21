import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        SettingsForm {
            Section("个性化") {
                NavigationLink {
                    AppearanceSettingsView()
                } label: {
                    Label("外观", systemImage: "circle.lefthalf.filled")
                }
                .accessibilityIdentifier("settings-appearance-page")
                NavigationLink {
                    LessonActivitySettingsView()
                } label: {
                    Label("实时活动", systemImage: "lock.rectangle")
                }
                .accessibilityIdentifier("settings-activity-page")
                NavigationLink {
                    ReminderSettingsView()
                } label: {
                    Label("提醒", systemImage: "bell")
                }
                .accessibilityIdentifier("settings-reminders-page")
            }
            Section("账号与数据") {
                if model.school.selected {
                    Button {
                        Task { await model.updateSchoolTimetable(manual: true) }
                    } label: {
                        Label(model.timetable.busy || model.timetableCheckingSession ? "正在更新课表" : "更新课表", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.timetable.busy || model.timetableCheckingSession)
                    .accessibilityIdentifier("settings-refresh-timetable")
                    if let book = model.localSchoolTimetable {
                        Text("\(book.year) · 已确认 \(book.rotations.count)/6 个轮转日 · "
                             + schoolDateLabel(book.savedAt, format: "M月d日 HH:mm") + " 更新")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if let message = model.timetable.message {
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                    } else if model.school.owner == nil {
                        Text("更新需要有效的校宝登录；查看本机课表不需要。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                NavigationLink {
                    PersonalInfoSettingsView()
                } label: {
                    LabeledContent {
                        if let nickname = model.personalization.nickname {
                            Text(verbatim: nickname).lineLimit(1)
                        }
                    } label: {
                        Label("个人信息", systemImage: "person.crop.circle")
                    }
                }
                .accessibilityIdentifier("settings-personal-info-page")
                NavigationLink {
                    PrivacyPolicyView()
                } label: {
                    Label("隐私", systemImage: "hand.raised")
                }
                .accessibilityIdentifier("settings-privacy-page")
            }
            GradeTrialSettings()
            Section {
                LabeledContent("版本", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
            }
        }
    }
}

/// Uses the same native form width and background on every Settings route.
struct SettingsForm<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        Form { content }
            .scrollContentBackground(.hidden)
            .frame(maxWidth: 840)
            .frame(maxWidth: .infinity)
            .containerBackground(.clear, for: .navigation)
            .navigationBarTitleDisplayMode(.inline)
    }
}
