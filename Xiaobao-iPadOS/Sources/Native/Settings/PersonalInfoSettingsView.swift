import SwiftUI

struct PersonalInfoSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var nickname = ""

    var body: some View {
        SettingsForm {
            CampusConnectionSettings()
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
