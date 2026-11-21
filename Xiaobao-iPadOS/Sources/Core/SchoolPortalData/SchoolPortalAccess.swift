import Foundation

enum SchoolPortalIssue: String, Error {
    case notReady, login, expired, interaction, changed, denied, format, network, term, unavailable

    /// Such a failure cannot authenticate anyone or prove the last student signed out.
    var permitsIdentityRecheck: Bool { self != .login && self != .expired && self != .changed && self != .interaction }

    var message: String {
        switch self {
        case .notReady: "正在等待校宝页面就绪。"
        case .login: "请在校宝中完成登录后再查看。"
        case .interaction: "校宝需要本人确认登录，本次不会再代为提交。"
        case .expired: "此前的校宝登录已失效。"
        case .changed: "当前校宝账号已改变，请确认账号后再查看。"
        case .denied: "校宝未向当前账号开放这项资料。"
        case .format: "校宝返回的格式无法识别，未将它当作空记录。"
        case .network: "暂时无法连接校宝，请检查网络后重试。"
        case .term: "暂时无法从校宝确认当前学期。"
        case .unavailable: "当前页面未提供这项资料。"
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

    static func issue(at url: URL?, foreground: Bool, loading: Bool) -> SchoolPortalIssue? {
        guard foreground, !loading, let url, url.absoluteString != "about:blank" else { return .notReady }
        guard isOfficial(url) else { return .unavailable }
        switch url.path.lowercased() {
        case "/home", "/home/", "/home/index", "/home/index/": return nil
        case "", "/", "/account/login", "/account/login/": return .login
        default: return .unavailable
        }
    }
}
