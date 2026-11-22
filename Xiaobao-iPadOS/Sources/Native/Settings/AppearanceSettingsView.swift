import SwiftUI
import UIKit

struct AppearanceSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var currentIcon: String?
    @State private var updatingIcon = false
    @State private var iconError = false

    var body: some View {
        SettingsForm {
            Section("环境") {
                Button { model.environmentPresented = true } label: {
                    Label("天气与外观", systemImage: model.backgroundSymbol)
                }
                .accessibilityIdentifier("settings-appearance")
            }
            Section {
                if UIApplication.shared.supportsAlternateIcons {
                    ForEach(IconChoice.allCases, id: \.self) { choice in
                        Button { apply(choice) } label: {
                            let selected = currentIcon == choice.asset
                            HStack {
                                TScheduleMark(size: 28).environment(\.colorScheme, choice.previewScheme)
                                Text(choice.title).foregroundStyle(.primary)
                                Spacer()
                                if selected {
                                    Image(systemName: "checkmark").accessibilityHidden(true)
                                }
                            }
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                        .accessibilityIdentifier("settings-app-icon-\(choice.rawValue)")
                        .disabled(updatingIcon)
                    }
                    if updatingIcon { ProgressView("正在更换图标") }
                    if iconError { Text("未能更换图标，请重试。").foregroundStyle(.secondary) }
                } else {
                    Text("当前设备由系统管理 App 图标。").foregroundStyle(.secondary)
                }
            } header: {
                Text("App 图标")
            } footer: {
                Text("「跟随系统」保留默认浅深变体。图标应用于整个 App，通知头部由 iPadOS 显示，不支持单独更换。")
            }
        }
        .navigationTitle("外观")
        .onAppear { currentIcon = UIApplication.shared.alternateIconName }
    }

    private func apply(_ choice: IconChoice) {
        let app = UIApplication.shared
        guard !updatingIcon, app.supportsAlternateIcons, app.alternateIconName != choice.asset else { return }
        updatingIcon = true
        iconError = false
        Task {
            defer {
                currentIcon = app.alternateIconName
                updatingIcon = false
            }
            do { try await app.setAlternateIconName(choice.asset) }
            catch { iconError = true }
        }
    }

    private enum IconChoice: String, CaseIterable {
        case automatic, light, dark

        var asset: String? {
            switch self {
            case .automatic: nil
            case .light: "AppIconLight"
            case .dark: "AppIconDark"
            }
        }

        var title: String {
            switch self {
            case .automatic: String(localized: "跟随系统")
            case .light: String(localized: "浅色校园")
            case .dark: String(localized: "深色校园")
            }
        }

        var previewScheme: ColorScheme { self == .dark ? .dark : .light }
    }
}
