import Foundation
@preconcurrency import WebKit

/// A single foreground transaction on the school's original page. It temporarily
/// owns navigation in the *same* WKWebView: no copied cookies, form interception,
/// custom auth endpoint, server-side credential or background job.
@MainActor final class SchoolPortalPasswordEntry: NSObject, WKNavigationDelegate, WKUIDelegate {
    private var ticket: UUID?
    private weak var view: WKWebView?
    private var stopped: Error?
    private var documents = 0
    private var reply: (UUID, CheckedContinuation<String, Error>)?
    private let script: String?
    init(bundle: Bundle = .main) {
        script = bundle.url(forResource: "PortalLogin", withExtension: "js")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
            .map { "return await (" + $0 + ")(operation, loginName, password);" }
    }

    func cancel() { stop(CancellationError()) }
    private func stop(_ error: Error) {
        guard ticket != nil, stopped == nil else { return }
        stopped = error; view?.stopLoading()
        let current = reply; reply = nil; current?.1.resume(throwing: error)
    }

    func run(_ web: WKWebView, allowed: @MainActor () -> Bool,
             claim: @MainActor () throws -> SchoolPortalLoginSecret) async throws {
        guard ticket == nil, let script, allowed(), !web.isLoading else { throw SchoolPortalIssue.notReady }
        guard web.configuration.websiteDataStore.isPersistent else { throw SchoolPortalIssue.login }
        guard let url = web.url, SchoolPortalPage.isOfficial(url) else { throw SchoolPortalIssue.interaction }
        let initial = SchoolPortalPage.issue(at:url, foreground:true, loading:false)
        guard initial == nil || initial == .login else { throw SchoolPortalIssue.interaction }
        let id = UUID(), navigation = web.navigationDelegate, ui = web.uiDelegate
        ticket = id; stopped = nil; documents = 0; view = web
        web.navigationDelegate = self; web.uiDelegate = self
        var attempted = false
        let timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(16)) } catch { return }
            if self?.ticket == id { self?.stop(SchoolPortalIssue.interaction) }
        }
        defer {
            timeout.cancel()
            if attempted, web.url.map(SchoolPortalPage.isOfficial) == true {
                // Clear only controls written by this transaction; never read their values.
                web.callAsyncJavaScript(script, arguments:["operation":"clear","loginName":"","password":""],
                                        in:nil, in:.defaultClient, completionHandler:nil)
            }
            if web.navigationDelegate === self { web.navigationDelegate = navigation }
            if web.uiDelegate === self { web.uiDelegate = ui }
            ticket = nil; view = nil; stopped = nil
        }
        func check() throws {
            try Task.checkCancellation()
            if let stopped { throw stopped }
            guard ticket == id, allowed() else { throw CancellationError() }
        }
        try await withTaskCancellationHandler {
            try check()
            // The Home document sometimes remains loaded even after the identity
            // read returned 401. Visit the normal entry only in that case; never
            // reload an existing login/challenge screen to seek another outcome.
            if initial == nil {
                guard web.load(URLRequest(url:SchoolPortalPage.origin, cachePolicy:.reloadIgnoringLocalCacheData,
                                          timeoutInterval:12)) != nil else { throw SchoolPortalIssue.network }
                while documents == 0 || web.isLoading { try check(); try await Task.sleep(for:.milliseconds(100)) }
            }
            while true {
                try check()
                if !web.isLoading {
                    let here = SchoolPortalPage.issue(at:web.url, foreground:true, loading:false)
                    if here == nil { return } // The store must independently verify the bound student.
                    guard here == .login else { throw SchoolPortalIssue.interaction }
                    let shape = try await evaluate(web, script, "probe")
                    try check()
                    if shape == "blocked" { throw SchoolPortalIssue.interaction }
                    if shape == "ready", !attempted {
                        let secret = try claim()
                        try check()
                        attempted = true
                        do {
                            let result = try await evaluate(web, script, "submit", secret)
                            guard result == "submitted" else { throw SchoolPortalIssue.interaction }
                        } catch let issue as SchoolPortalIssue where issue == .notReady {
                            // Navigation can destroy the JS context during the click. Only
                            // observe its outcome; never use the password a second time.
                        }
                    }
                }
                try await Task.sleep(for:.milliseconds(attempted ? 220 : 120))
            }
        } onCancel: { [weak self] in
            Task { @MainActor in if self?.ticket == id { self?.cancel() } }
        }
    }

    private func evaluate(_ web: WKWebView, _ script: String, _ operation: String,
                          _ secret: SchoolPortalLoginSecret? = nil) async throws -> String {
        let call = UUID()
        return try await withCheckedThrowingContinuation { continuation in
            reply = (call, continuation)
            web.callAsyncJavaScript(script, arguments:["operation":operation,"loginName":secret?.name ?? "",
                                                         "password":secret?.password ?? ""], in:nil, in:.defaultClient) { [weak self] result in
                guard let self, let current = self.reply, current.0 == call else { return }
                self.reply = nil
                if case .success(let raw) = result, let state = raw as? String { current.1.resume(returning:state) }
                else { current.1.resume(throwing:SchoolPortalIssue.notReady) }
            }
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard stopped == nil, action.targetFrame?.isMainFrame == true, let url = action.request.url,
              SchoolPortalPage.isOfficial(url), ["GET","HEAD"].contains(action.request.httpMethod ?? "GET") else {
            decisionHandler(.cancel); stop(SchoolPortalIssue.interaction); return
        }
        let issue = SchoolPortalPage.issue(at:url, foreground:true, loading:false)
        if issue == nil || issue == .login { decisionHandler(.allow) }
        else { decisionHandler(.cancel); stop(SchoolPortalIssue.interaction) }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { documents += 1 }
    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        // Also fence server redirects, which need not create a new navigation-action callback.
        guard response.isForMainFrame, let url = response.response.url, SchoolPortalPage.isOfficial(url),
              let http = response.response as? HTTPURLResponse else {
            decisionHandler(.cancel); stop(SchoolPortalIssue.interaction); return
        }
        let issue = SchoolPortalPage.issue(at:url, foreground:true, loading:false)
        guard (issue == nil || issue == .login), (200..<400).contains(http.statusCode) else {
            decisionHandler(.cancel); stop(http.statusCode >= 500 ? SchoolPortalIssue.network : SchoolPortalIssue.interaction); return
        }
        decisionHandler(.allow)
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { stop(SchoolPortalIssue.network) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { stop(SchoolPortalIssue.network) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { stop(SchoolPortalIssue.network) }
    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
                 completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            completionHandler(.performDefaultHandling,nil)
        } else { completionHandler(.cancelAuthenticationChallenge,nil); stop(SchoolPortalIssue.interaction) }
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        stop(SchoolPortalIssue.interaction); return nil
    }
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping () -> Void) {
        stop(SchoolPortalIssue.interaction); completionHandler()
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (Bool) -> Void) {
        stop(SchoolPortalIssue.interaction); completionHandler(false)
    }
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        stop(SchoolPortalIssue.interaction); completionHandler(nil)
    }
}
