import SwiftUI

struct PersonalInfoSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var nickname = ""

    var body: some View {
        @Bindable var model = model
        SettingsForm {
            CampusConnectionSettings()
            Section {
                Toggle("住宿生", isOn: $model.personalization.showsBoardingRoutine)
                    .accessibilityIdentifier("settings-boarding-routine")
            } header: {
                Text("课表")
            } footer: {
                Text("在「今日」和「计划」中补齐住校夜的作息。走读生自己参加的课程和晚自习也会显示。")
            }
            Section {
                TextField("显示昵称", text: $nickname, prompt: Text("未设置"))
                    .accessibilityIdentifier("settings-nickname")
                    .submitLabel(.done)
                    .onSubmit(save)
                Button("保存昵称", action: save)
                    .disabled(nickname == (model.personalization.nickname ?? ""))
            } header: {
                Text("本机昵称")
            } footer: {
                Text("只显示在这台设备的设置里，不修改校宝账号。留空保存可清除。")
            }
        }
        .navigationTitle("个人信息")
        .onAppear { nickname = model.personalization.nickname ?? "" }
    }

    private func save() {
        model.personalization.setNickname(nickname)
        nickname = model.personalization.nickname ?? ""
    }
}
