import Foundation
@preconcurrency import WebKit

/// Await exactly one ordinary top-level navigation. The school alone decides whether
/// its own WebKit session can resume. Never inspect a login form, challenge or cookie.
@MainActor final class SchoolPortalEntry {
    private let owned = NSHashTable<WKNavigation>.weakObjects()
    private var active: WKNavigation?
    private weak var web: WKWebView?
    private var waiter: CheckedContinuation<Void, Error>?
    private var timeout: Task<Void, Never>?
    private var request: UUID?
    var pending: Bool { waiter != nil }

    func owns(_ navigation: WKNavigation?) -> Bool {
        navigation.map { owned.contains($0) } ?? false
    }

    /// The app supplies its fixed official Home URL; the standalone test supplies loopback.
    func reopen(_ web: WKWebView, home: URL) async throws {
        guard !pending, !web.isLoading else { throw SchoolPortalIssue.notReady }
        try Task.checkCancellation()
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                guard let navigation = web.load(URLRequest(url: home, cachePolicy: .reloadIgnoringLocalCacheData,
                                                           timeoutInterval: 12)) else {
                    continuation.resume(throwing: SchoolPortalIssue.network); return
                }
                self.web = web; request = id; waiter = continuation
                active = navigation; owned.add(navigation)
                // A stalled redirect must not strand the grade page or its continuation.
                timeout = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(15)) } catch { return }
                    if self?.request == id { self?.cancel(SchoolPortalIssue.network) }
                }
            }
        } onCancel: { [weak self] in
            Task { @MainActor in if self?.request == id { self?.cancel(CancellationError()) } }
        }
    }

    func finish(_ navigation: WKNavigation?, issue: SchoolPortalIssue?) {
        guard let navigation, navigation === active else { return }
        complete(issue)
    }

    func cancel(_ error: Error, stopLoading: Bool = true) {
        guard pending else { return }
        let view = web
        complete(error)
        if stopLoading { view?.stopLoading() }
    }

    private func complete(_ error: Error?) {
        let continuation = waiter
        waiter = nil; active = nil; request = nil; web = nil; timeout?.cancel(); timeout = nil
        if let error { continuation?.resume(throwing: error) } else { continuation?.resume() }
    }
}
