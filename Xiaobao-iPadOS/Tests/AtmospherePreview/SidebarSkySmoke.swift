import MetalKit
import SwiftUI

// Test-only SwiftUI route. It belongs to the keyed navigation stack just like
// a real destination; an imperative UIKit push is not owned by SwiftUI.
struct SidebarFixtureRoute: ViewModifier {
    static let open = Notification.Name("fixture.openSidebarCover")
    static let close = Notification.Name("fixture.closeSidebarCover")
    static let title = "Fixture detail"
    @State private var presented = false

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: Self.open)) { _ in presented = true }
            .navigationDestination(isPresented: $presented) {
                Text(Self.title).navigationTitle(Self.title)
                    .onReceive(NotificationCenter.default.publisher(for: Self.close)) { _ in presented = false }
            }
    }
}

// This entry point is substituted only in the isolated simulator fixture.
// It mounts the production RootView, not a duplicate of the navigation layout.
@main @MainActor
struct SidebarSkySmoke: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView().environment(model).task { await run() }
        }
    }

    private func views<T: UIView>(_ root: UIView, _ type: T.Type) -> [T] {
        guard !root.isHidden, root.alpha > 0.01 else { return [] }
        return (root as? T).map { [$0] } ?? root.subviews.flatMap { views($0, type) }
    }

    private func waitFor<T>(_ find: () -> T?) async -> T? {
        for _ in 0..<120 {
            if let value = find() { return value }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return nil
    }

    private func finish(_ success: Bool, _ message: String) -> Never {
        print("SIDEBAR-SKY \(success ? "PASS" : "FAIL"): \(message)")
        fflush(stdout); exit(success ? 0 : 1)
    }

    private func run() async {
        guard Bundle.main.bundleIdentifier == "cn.xiaobao.fixture.sidebar-sky",
              !model.school.selected, model.campus.account == nil else { finish(false, "not a fixture session") }
        model.previewWeather(.cloudy)
        model.preferences.liveBackground = false
        model.preferences.sceneMinute = 720
        guard let window = await waitFor({ UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }.first }) else { finish(false, "no window") }
        func nav(_ title: String) -> UINavigationController? {
            views(window, UINavigationBar.self).compactMap { $0.delegate as? UINavigationController }
                .first { $0.topViewController?.navigationItem.title == title }
        }
        func oneSky() -> MTKView? {
            let found = views(window, MTKView.self)
            return found.count == 1 && found[0].device != nil && found[0].drawableSize.width > 1 ? found[0] : nil
        }
        guard let original = await waitFor(oneSky) else { finish(false, "no drawable sky") }
        // Hold references so an allocator cannot reuse an old surface's address.
        var sampled = [original]
        for tab: AppTab in [.tasks, .grades, .planner, .attendance, .today, .settings] {
            model.tab = tab
            guard await waitFor({ nav(tab.title) }) != nil else { finish(false, "section did not change: " + tab.rawValue) }
            try? await Task.sleep(for: .milliseconds(180))
            guard let surface = await waitFor(oneSky) else { finish(false, "expected a single main sky") }
            sampled.append(surface)
            if tab == .grades, CommandLine.arguments.contains("--inspect-sky"), UIApplication.shared.applicationState == .active {
                print("SIDEBAR-SKY fixture frame ready"); fflush(stdout)
                try? await Task.sleep(for: .seconds(4))
            }
        }
        let count = Set(sampled.map(ObjectIdentifier.init)).count
        guard count == 1 else { finish(false, "\(count) different skies across six sidebar switches") }

        func push(over surface: MTKView) async -> Bool {
            NotificationCenter.default.post(name: SidebarFixtureRoute.open, object:nil)
            return await waitFor({ nav(SidebarFixtureRoute.title) != nil && surface.isPaused ? true : nil }) != nil
        }
        guard await push(over: original) else { finish(false, "destination not shown or covered sky not paused") }
        NotificationCenter.default.post(name: SidebarFixtureRoute.close, object:nil)
        guard await waitFor({ nav(AppTab.settings.title) != nil && oneSky() === original && !original.isPaused ? true : nil }) != nil
        else { finish(false, "sky did not resume after the pop (disable system Reduce Motion / Low Power for this test)") }
        guard await push(over: original) else { finish(false, "second push not registered") }
        model.tab = .tasks
        guard await waitFor({ nav(AppTab.tasks.title) != nil && nav(SidebarFixtureRoute.title) == nil &&
                            oneSky() === original ? true : nil }) != nil else { finish(false, "sidebar switch from detail failed") }
        // Settings doesn't open or fetch from the portal. A new identity,
        // unlike a tab change, may replace the whole system split stack.
        model.tab = .settings
        model.school.select(true)
        guard let sessionSky = await waitFor({ nav(AppTab.settings.title) != nil ? oneSky() : nil }),
              await push(over: sessionSky) else { finish(false, "session detail not shown") }
        model.school.invalidate()
        guard await waitFor({ nav(AppTab.settings.title) != nil && nav(SidebarFixtureRoute.title) == nil &&
                           oneSky() != nil ? true : nil }) != nil else {
            finish(false, "scope reset: root visible=\(nav(AppTab.settings.title) != nil), " +
                   "old detail visible=\(nav(SidebarFixtureRoute.title) != nil), original sky=\(oneSky() === original)")
        }
        // Sheets are owned by the surrounding root, not by the protected
        // foreground stack. Exercise this without opening a live login page.
        model.environmentPresented = true
        guard let sheet = await waitFor({ window.rootViewController?.presentedViewController }) else {
            finish(false, "root sheet did not present")
        }
        try? await Task.sleep(for: .milliseconds(400))
        model.school.invalidate()
        try? await Task.sleep(for: .milliseconds(450))
        guard window.rootViewController?.presentedViewController === sheet,
              sheet.viewIfLoaded?.window != nil else { finish(false, "session reset interrupted an independent sheet") }
        model.environmentPresented = false
        model.school.select(false)
        finish(true, "one sky across six switches and a switch out of detail; pause/resume, session reset and root sheet passed")
    }
}
