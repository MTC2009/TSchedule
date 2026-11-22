import Foundation

/// The app and extension each negotiate their own bundled language using iPadOS preferences.
/// This is a presentation locale only: school days, cache keys and API timestamps never use it.
enum AppLanguage {
    static var isEnglish: Bool {
        Bundle.main.preferredLocalizations.first?.hasPrefix("en") == true
    }

    static var locale: Locale {
        let language = isEnglish ? "en" : "zh-Hans"
        let region = Locale.current.region?.identifier ?? (isEnglish ? "US" : "CN")
        return Locale(identifier: language + "_" + region)
    }
}
