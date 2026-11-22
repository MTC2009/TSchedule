import SwiftUI

/// Student-controlled enrollment, separate from granting a grade read. Never
/// take input from the school's web fields or permit an arbitrary account name.
struct SchoolPortalLoginSettings: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var phase
    @State private var expanded = false
    @State private var password = ""
    @State private var message: String?
    @State private var work: Task<Void,Never>?
    @State private var ticket = UUID()

    private var enrollableOwner: String? {
        guard model.portal.webView.configuration.websiteDataStore.isPersistent,
              model.schoolLogin.binding?.paused != false else { return nil }
        return model.school.owner
    }

    private var status: String {
        guard model.schoolLogin.registered else { return String(localized: "未开启") }
        guard let binding = model.schoolLogin.binding else { return String(localized: "钥匙串暂不可用") }
        return binding.paused ? String(localized: "已暂停") : String(localized: "已开启")
    }

    var body: some View {
        Group {
            // A registered student must still be able to remove the binding if an account check or Keychain read fails.
            if model.schoolLogin.registered || enrollableOwner != nil {
                DisclosureGroup(isExpanded: $expanded) {
                    if model.schoolLogin.binding?.paused == true {
                        Text("上次登录未完成。确认校宝账号后可重新设置。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if let owner = enrollableOwner {
                        Text("请仅在设有锁屏密码的个人 iPad 上开启。密码存入本机钥匙串，不同步到 iCloud。打开 App 或主动查看 GPA 时，优先沿用校宝会话；确实需要登录时才使用保存的账号和密码一次。")
                            .font(.footnote).foregroundStyle(.secondary)
                        SecureField("当前校宝账号的密码", text: $password)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityIdentifier("school-login-password")
                        Button(work == nil ? String(localized: "保存并开启") : String(localized: "正在保存…")) { enable(owner) }
                            .disabled(password.isEmpty || work != nil)
                            .accessibilityIdentifier("school-login-enable")
                    }
                    if let binding = model.schoolLogin.binding {
                        Toggle("打开 App 时恢复登录", isOn: Binding(get: { binding.restoresOnLaunch == true }, set: { enabled in
                            do { try model.schoolLogin.setRestoresOnLaunch(enabled) }
                            catch { message = SchoolPortalEnrollmentError.storage.localizedDescription }
                        }))
                    }
                    if model.schoolLogin.registered {
                        Button("移除已保存的登录", role: .destructive) {
                            clear()
                            do { try model.schoolLogin.disable(); message = nil; expanded = false }
                            catch { message = SchoolPortalEnrollmentError.storage.localizedDescription }
                        }.accessibilityIdentifier("school-login-remove")
                    }
                } label: {
                    LabeledContent("本机代登录", value: status)
                }
            } else {
                LabeledContent("本机代登录", value: model.portal.webView.configuration.websiteDataStore.isPersistent
                               ? String(localized: "登录后可设置") : String(localized: "临时会话不可用"))
            }
            if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
        }
        .onChange(of: expanded) { _,value in if !value { clear() } }
        .onChange(of: phase) { _,value in if value != .active { expanded = false; clear() } }
        .onDisappear { clear() }
    }
    private func clear() {
        ticket = UUID(); work?.cancel(); work = nil; password = ""
    }
    private func enable(_ owner: String) {
        guard phase == .active, model.tab == .settings, !model.portalPresented, work == nil else { return }
        let id = UUID(), epoch = model.school.epoch, entered = password
        ticket = id; password = ""; message = nil
        work = Task { @MainActor in
            defer { if ticket == id { work = nil } }
            do {
                let name = try await model.school.enrollmentName(for:owner)
                guard ticket == id, !Task.isCancelled, model.school.epoch == epoch,
                      model.school.owner == owner, model.tab == .settings, model.portal.foreground,
                      !model.portalPresented else { return }
                try model.schoolLogin.enable(owner:owner, name:name, password:entered, restoresOnLaunch:true)
                expanded = false
            } catch {
                if !Task.isCancelled && ticket == id {
                    message = (error as? SchoolPortalEnrollmentError ?? .identity).localizedDescription
                }
            }
        }
    }
}
