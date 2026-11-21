import SwiftUI
import Observation
@preconcurrency import WebKit

@MainActor @Observable
final class PortalSession: NSObject, WKNavigationDelegate, WKUIDelegate {
    static let url = SchoolPortalPage.origin
    var webView: WKWebView
    var loading = false
    var errorMessage: String?
    var revision = UUID()
    @ObservationIgnored weak var school: SchoolPortalStore?
    @ObservationIgnored var foreground = true
    @ObservationIgnored private(set) var readGeneration = UUID()
    @ObservationIgnored private let gradeEntry = SchoolPortalEntry()
    @ObservationIgnored private let passwordEntry = SchoolPortalPasswordEntry()
    @ObservationIgnored var onForgetLogin: (@MainActor () -> Void)?
    @ObservationIgnored var manualSheet = false
    @ObservationIgnored private var ordinaryNavigation: WKNavigation?
    @ObservationIgnored private var navigationDeadline: Task<Void, Never>?

    private func expectNavigation(_ navigation: WKNavigation?) {
        navigationDeadline?.cancel()
        ordinaryNavigation = navigation
        loading = navigation != nil
        guard let navigation else {
            errorMessage = SchoolPortalIssue.network.message
            school?.invalidate(.network)
            return
        }
        navigationDeadline = Task { [weak self, weak navigation] in
            do { try await Task.sleep(for: .seconds(10)) } catch { return }
            guard let self, let navigation, self.ordinaryNavigation === navigation else { return }
            self.ordinaryNavigation = nil
            self.loading = false
            self.errorMessage = "校宝网页未及时响应，可以重试。"
            self.webView.stopLoading()
            if self.school?.selected == true { self.school?.invalidate(.network) }
        }
    }

    func reopenForGrades() async throws {
        guard foreground, !loading else { throw SchoolPortalIssue.notReady }
        guard webView.configuration.websiteDataStore.isPersistent else { throw SchoolPortalIssue.login }
        try await gradeEntry.reopen(webView, home: Self.url.appendingPathComponent("Home"))
    }

    func cancelGradeEntry() { gradeEntry.cancel(CancellationError()); passwordEntry.cancel() }

    func signInWithDeviceBinding(allowed: @MainActor () -> Bool, claim: @MainActor () throws -> SchoolPortalLoginSecret) async throws {
        guard foreground, !manualSheet, !loading else { throw SchoolPortalIssue.notReady }
        try await passwordEntry.run(webView, allowed:allowed, claim:claim)
    }

    func cancelSchoolReads() {
        let previous = readGeneration
        readGeneration = UUID()
        guard SchoolPortalReader.isHome(webView.url) else { return }
        webView.callAsyncJavaScript("globalThis.tScheduleReads?.get(previous)?.forEach(c => c.abort());",
                                    arguments: ["previous":previous.uuidString], in: nil, in: .defaultClient,
                                    completionHandler: nil)
    }

    init(persistent: Bool) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = persistent ? .default() : .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: config)
        super.init(); configure()
    }

    private func configure() {
        webView.navigationDelegate = self; webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
    }

    func loadIfNeeded() {
        guard webView.url == nil, !webView.isLoading, !loading else { return }
        expectNavigation(webView.load(URLRequest(url: Self.url)))
    }

    /// User chose the visible sign-in screen after an interaction-required result.
    func openSignIn(after issue: SchoolPortalIssue) {
        // Reloading the entry would discard the school's inline error or a just-completed login.
        if errorMessage == nil, SchoolPortalPage.canContinueManually(at: webView.url, after: issue) { return }
        errorMessage = nil
        expectNavigation(webView.load(URLRequest(url: Self.url, cachePolicy: .reloadIgnoringLocalCacheData)))
    }

    // The portal and its deep links use the same WebKit store, including the school's own sign-in redirects.
    func open(_ section: String?) -> Bool {
        let routes = ["我的任务": "task/list", "我的考勤": "attendance", "我的日程": "schedule",
                      "我的资料库": "cloudDisk", "动态成绩": "realtime/list",
                      "我的考试": "exam/list", "我的测评": "assessment"]
        guard let section, let route = routes[section], !webView.isLoading, !loading else { return false }
        if let current = webView.url, !(current.host == Self.url.host && current.path.hasPrefix("/Home")) { return false }
        var target = URLComponents(url: Self.url, resolvingAgainstBaseURL: false)!
        target.path = "/Home"; target.fragment = "!/" + route
        guard let url = target.url else { return false }
        if url != webView.url {
            // Hash routes can complete in the same document without any WebKit navigation callbacks.
            // Never mark those as a new document load. A real navigation will notify the delegate.
            if SchoolPortalReader.isHome(webView.url) { webView.load(URLRequest(url: url)) }
            else { expectNavigation(webView.load(URLRequest(url: url))) }
        }
        return true
    }
    func reload() { errorMessage = nil; if webView.url == nil { loadIfNeeded() } else { expectNavigation(webView.reload()) } }

    func reset(persistent: Bool) async {
        onForgetLogin?()
        cancelGradeEntry(); navigationDeadline?.cancel(); ordinaryNavigation = nil
        cancelSchoolReads()
        if school?.selected == true { school?.invalidate(.login) }
        loading = true
        webView.stopLoading(); webView.navigationDelegate = nil; webView.uiDelegate = nil
        let current = webView.configuration.websiteDataStore
        let stores = current.isPersistent ? [current] : [current, WKWebsiteDataStore.default()]
        for store in stores {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) { continuation.resume() }
            }
        }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = persistent ? .default() : .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: config)
        configure(); revision = UUID(); errorMessage = nil; loading = false
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard webView === self.webView else { return }
        if gradeEntry.owns(navigation) { return }
        gradeEntry.cancel(CancellationError(), stopLoading: false)
        expectNavigation(navigation)
        errorMessage = nil
        if school?.selected == true { cancelSchoolReads(); school?.beginNavigation() }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === self.webView else { return }
        let issue = SchoolPortalPage.issue(at: webView.url, foreground: foreground, loading: false)
        if gradeEntry.owns(navigation) { gradeEntry.finish(navigation, issue: issue); return }
        guard navigation === ordinaryNavigation else { return }
        navigationDeadline?.cancel(); ordinaryNavigation = nil; loading = false
        if foreground, school?.selected == true {
            if let issue {
                school?.invalidate(issue)
            }
            else if let school, !manualSheet {
                let ticket = school.epoch
                Task {
                    guard self.foreground, school.epoch == ticket, !self.loading, !self.gradeEntry.pending else { return }
                    await school.verify()
                }
            }
        }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { report(error, webView, navigation) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { report(error, webView, navigation) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard webView === self.webView else { return }
        navigationDeadline?.cancel(); ordinaryNavigation = nil
        gradeEntry.cancel(SchoolPortalIssue.network)
        if school?.selected == true { school?.invalidate(.network) }
        loading = false; errorMessage = "网页已暂停，点刷新重新载入。"
    }

    private func report(_ error: Error, _ web: WKWebView, _ navigation: WKNavigation?) {
        guard web === webView else { return }
        if gradeEntry.owns(navigation) { gradeEntry.finish(navigation, issue: .network); return }
        guard let navigation, navigation === ordinaryNavigation else { return }
        navigationDeadline?.cancel(); ordinaryNavigation = nil; loading = false
        errorMessage = error.localizedDescription
        if school?.selected == true { school?.invalidate(.network) }
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        if gradeEntry.pending, action.targetFrame?.isMainFrame != false, !SchoolPortalPage.isOfficial(url) {
            decisionHandler(.cancel); gradeEntry.cancel(SchoolPortalIssue.interaction); return
        }
        if url.scheme == "https" || url.absoluteString == "about:blank" { decisionHandler(.allow); return }
        decisionHandler(.cancel)
        if !gradeEntry.pending, action.navigationType == .linkActivated && ["mailto", "tel"].contains(url.scheme ?? "") {
            UIApplication.shared.open(url)
        }
    }

    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
                 completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // Trust evaluation remains the platform's job. A credential prompt is not a
        // background sign-in method and must not appear on top of the student's grade page.
        if gradeEntry.pending, challenge.protectionSpace.authenticationMethod != NSURLAuthenticationMethodServerTrust {
            completionHandler(.cancelAuthenticationChallenge, nil); gradeEntry.cancel(SchoolPortalIssue.interaction)
        } else { completionHandler(.performDefaultHandling, nil) }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if gradeEntry.pending { gradeEntry.cancel(SchoolPortalIssue.interaction); return nil }
        if action.targetFrame == nil, action.request.url?.scheme == "https" { webView.load(action.request) }
        return nil
    }
}

private struct PortalWebView: UIViewRepresentable {
    let session: PortalSession
    func makeUIView(context: Context) -> WKWebView { session.loadIfNeeded(); return session.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct SchoolPortalView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let section = model.portalSection {
                    Label("请在校宝导航中选择「\(section)」", systemImage: "arrow.turn.up.right")
                        .font(.callout).frame(maxWidth: .infinity, alignment: .leading).padding(14).background(.thinMaterial)
                }
                portalContent
            }
            .navigationTitle("校宝 · 网页入口")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("后退", systemImage: "chevron.left") { model.portal.webView.goBack() }
                    Button("刷新", systemImage: "arrow.clockwise") { model.portal.reload() }
                }
            }
        }
    }

    private var portalContent: some View {
        ZStack(alignment: .top) {
            PortalWebView(session: model.portal).id(model.portal.revision)
            if model.portal.loading { ProgressView().padding(12).glassEffect() }
            if let message = model.portal.errorMessage {
                ContentUnavailableView {
                    Label("暂时无法载入校宝", systemImage: "wifi.exclamationmark")
                } description: { Text(message) } actions: { Button("重试") { model.portal.reload() }.buttonStyle(.glassProminent) }
                .background(.regularMaterial)
            }
        }
    }
}
