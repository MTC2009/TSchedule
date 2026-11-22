import SwiftUI
import UIKit
@preconcurrency import WebKit

/// One explicit file save. Keep bytes in a protected, non-backed-up staging directory until
/// Files copies them; drop redirect/auth surprises rather than opening a login or a web page.
@MainActor final class SchoolTaskDownload: NSObject, WKDownloadDelegate {
    struct Export: Identifiable {
        let id = UUID()
        let url: URL
        func discard() { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    }
    private static let staging = FileManager.default.temporaryDirectory.appendingPathComponent(
        "TScheduleTaskExports-v1", isDirectory: true)
    // Tidy only our own unfinished transfer directories after a process restart.
    static func clearAbandoned() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil)) ?? []
        for url in urls where UUID(uuidString: url.lastPathComponent) != nil {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private var transfer: WKDownload?, isolatedWeb: WKWebView?
    private var pending: CheckedContinuation<Export, Error>?
    private var timeout: Task<Void, Never>?, observation: NSKeyValueObservation?
    private let link: SchoolTaskFileLink, current: @MainActor () -> Bool
    private let export: Export

    init(link: SchoolTaskFileLink, current: @escaping @MainActor () -> Bool) throws {
        self.link = link
        self.current = current
        let banned = CharacterSet.controlCharacters.union(
            CharacterSet(charactersIn: "/\\:\u{202A}\u{202B}\u{202C}\u{202D}\u{202E}\u{2066}\u{2067}\u{2068}\u{2069}"))
        let name = link.name.components(separatedBy: banned).joined(separator: "_").trimmingCharacters(
            in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.hasPrefix("."), name.utf8.count <= 240 else { throw SchoolPortalIssue.unavailable }
        var dir = Self.staging.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
        var flags = URLResourceValues()
        flags.isExcludedFromBackup = true
        try dir.setResourceValues(flags)
        export = Export(url: dir.appendingPathComponent(name))
    }
    func fetch(using session: WKWebView) async throws -> Export {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending = continuation
                guard current(), !Task.isCancelled else {
                    finish(.failure(CancellationError()))
                    return
                }
                let web: WKWebView
                if SchoolPortalPage.isOfficial(link.url) {
                    web = session
                } else {
                    let config = WKWebViewConfiguration()
                    config.websiteDataStore = .nonPersistent()
                    web = WKWebView(frame: .zero, configuration: config)
                    isolatedWeb = web
                }
                let req = URLRequest(url: link.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
                timeout = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(90)) } catch { return }
                    self?.cancel(SchoolPortalIssue.network)
                }
                web.startDownload(using: req) { [weak self] download in
                    guard let self, self.pending != nil, self.current() else {
                        download.cancel { _ in }
                        self?.cancel(CancellationError())
                        return
                    }
                    self.transfer = download
                    download.delegate = self
                    self.observation = download.progress.observe(\.completedUnitCount, options: [.new]) {
                        [weak self] progress, _ in
                        if progress.completedUnitCount > SchoolTaskFilePolicy.limit {
                            Task { @MainActor in self?.cancel(SchoolPortalIssue.unavailable) }
                        }
                    }
                }
            }
        } onCancel: {
            Task { @MainActor in self.cancel(CancellationError()) }
        }
    }
    private func finish(_ result: Result<Export, Error>) {
        guard let pending else { return }
        self.pending = nil
        timeout?.cancel()
        timeout = nil
        observation = nil
        transfer = nil
        isolatedWeb = nil
        if case .failure = result { export.discard() }
        pending.resume(with: result)
    }
    private func cancel(_ error: Error) {
        transfer?.cancel { _ in }
        finish(.failure(error))
    }
    func download(
        _ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String,
        completionHandler: @escaping @MainActor (URL?) -> Void
    ) {
        guard current(), let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
            http.url == link.url, http.expectedContentLength <= SchoolTaskFilePolicy.limit,
            !["text/html", "application/xhtml+xml", "application/json"].contains(http.mimeType?.lowercased() ?? "")
        else {
            completionHandler(nil)
            finish(.failure(SchoolPortalIssue.unavailable))
            return
        }
        completionHandler(export.url)
    }
    func download(
        _ download: WKDownload, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        decisionHandler: @escaping @MainActor (WKDownload.RedirectPolicy) -> Void
    ) {
        decisionHandler(.cancel)
        finish(.failure(SchoolPortalIssue.unavailable))
    }
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        finish(.failure(SchoolPortalIssue.network))
    }
    func downloadDidFinish(_ download: WKDownload) {
        guard current(), let size = try? export.url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
            size <= SchoolTaskFilePolicy.limit
        else {
            finish(.failure(SchoolPortalIssue.unavailable))
            return
        }
        finish(.success(export))
    }
}

struct SchoolTaskExportPicker: UIViewControllerRepresentable {
    let file: SchoolTaskDownload.Export
    let done: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(done) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [file.url], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ picker: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let done: () -> Void
        init(_ done: @escaping () -> Void) { self.done = done }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { done() }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { done() }
    }
}
