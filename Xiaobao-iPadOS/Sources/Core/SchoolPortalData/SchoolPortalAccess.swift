import Foundation

enum SchoolPortalIssue: String, Error {
    case notReady, login, expired, interaction, signInTimeout, signInRejected, changed, denied, format, network, term, unavailable

    /// Such a failure cannot authenticate anyone or prove the last student signed out.
    var permitsIdentityRecheck: Bool {
        switch self {
        case .login, .expired, .interaction, .changed, .signInTimeout, .signInRejected: false
        default: true
        }
    }

    var message: String {
        switch self {
        case .notReady: String(localized: "正在等待校宝页面就绪。")
        case .login: String(localized: "请在校宝中完成登录后再查看。")
        case .interaction: String(localized: "请打开校宝，在当前网页上完成登录。")
        case .signInTimeout: String(localized: "等待校宝登录结果超时。请打开校宝查看进度，不会自动重试。")
        case .signInRejected: String(localized: "校宝未接受这次登录。请打开校宝查看提示。")
        case .expired: String(localized: "此前的校宝登录已失效。")
        case .changed: String(localized: "当前校宝账号已改变，请确认账号后再查看。")
        case .denied: String(localized: "校宝未向当前账号开放这项资料。")
        case .format: String(localized: "校宝返回的格式无法识别，未将它当作空记录。")
        case .network: String(localized: "暂时无法连接校宝，请检查网络后重试。")
        case .term: String(localized: "暂时无法从校宝确认当前学期。")
        case .unavailable: String(localized: "当前页面未提供这项资料。")
        }
    }
}

/// A top-level URL can establish readiness or the need for interaction, never session expiry.
enum SchoolPortalPage {
    static let origin = URL(string: "https://tsinglanstudent.schoolis.cn")!

    static func isOfficial(_ url: URL) -> Bool {
        url.scheme == "https" && url.host?.lowercased() == origin.host && url.user == nil &&
            url.password == nil && (url.port == nil || url.port == 443)
    }

    /// A handoff displays the existing first-party page; it does not authorize a read or a submission.
    static func canContinueManually(at url: URL?, after reason: SchoolPortalIssue) -> Bool {
        guard let url, isOfficial(url) else { return false }
        switch reason {
        case .interaction, .signInTimeout, .signInRejected: return true
        case .login, .expired: return issue(at: url, foreground: true, loading: false) == .login
        default: return false
        }
    }

    static func issue(at url: URL?, foreground: Bool, loading: Bool, httpStatus: Int? = nil) -> SchoolPortalIssue? {
        guard foreground, !loading, let url, url.absoluteString != "about:blank" else { return .notReady }
        guard isOfficial(url) else { return .unavailable }
        // A maintenance response at "/" is not evidence of sign-out. Only the
        // main document at the matching URL may supply this status, never a subframe.
        if let httpStatus, httpStatus == 429 || (500..<600).contains(httpStatus) { return .network }
        switch url.path.lowercased() {
        case "/home", "/home/", "/home/index", "/home/index/": return nil
        case "", "/", "/account/login", "/account/login/": return .login
        default: return .unavailable
        }
    }
}
