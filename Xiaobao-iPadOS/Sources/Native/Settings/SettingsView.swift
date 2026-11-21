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
