import ActivityKit
import Foundation
import Observation

@Observable @MainActor final class LessonActivityController {
    enum Source: Equatable {
        case school(String)
        case connectedDemo(UUID)
        case localDemo

        var isDemo: Bool {
            if case .school = self { return false }
            return true
        }
    }

    private struct Session {
        let activity: Activity<LessonActivityAttributes>
        let plan: LessonActivityPlan
        let source: Source
    }

    private var session: Session?
    private(set) var ending = false
    private(set) var issue: String?
    private(set) var wantsNextFocus = false
    @ObservationIgnored private var stateWatcher: Task<Void, Never>?
    @ObservationIgnored private var endTimer: Task<Void, Never>?
    var isRunning: Bool { session != nil }

    func start(_ plan: LessonActivityPlan, source: Source, appearance: LessonActivityAppearance) {
        guard !ending, session == nil, plan.startsAt <= Date(), Date() < plan.endsAt else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            issue = "请在系统设置中允许 TSchedule 的实时活动。"
            return
        }
        // Don't transfer an activity from a previous app process to an unverified user.
        guard Activity<LessonActivityAttributes>.activities.isEmpty else {
            clearOrphans()
            return
        }
        do {
            let content = LessonActivityAttributes.ContentState(
                startsAt: plan.startsAt, endsAt: plan.endsAt,
                nextLesson: Self.lockScreenTitle(plan.next?.title), isDemo: source.isDemo,
                appearance: appearance == .init() ? nil : appearance)
            let activity = try Activity.request(attributes: LessonActivityAttributes(),
                content: ActivityContent(state: content, staleDate: plan.endsAt), pushType: nil)
            session = .init(activity: activity, plan: plan, source: source)
            issue = nil
            observe(activity, endingAt: plan.endsAt)
        } catch {
            issue = "暂时无法开始实时活动，请重试。"
        }
    }

    private static func lockScreenTitle(_ title: String?) -> String? {
        guard let title else { return nil }
        let line = title.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        // ActivityKit has a finite payload budget; the full title is kept in Today.
        var safe = ""
        var count = 0
        for character in line {
            let bytes = String(character).utf8.count
            guard count + bytes <= 512 else { return safe.isEmpty ? nil : safe + "…" }
            safe.append(character)
            count += bytes
        }
        return safe.isEmpty ? nil : safe
    }

    func stop() {
        wantsNextFocus = false
        issue = nil
        guard let active = session else { return }
        detach()
        end([active.activity])
    }

    func clearOrphans() {
        guard !ending, session == nil else { return }
        end(Activity<LessonActivityAttributes>.activities)
    }

    func revoke(unless source: Source?) {
        if let session, session.source != source { stop() }
    }

    func validate(_ plan: LessonActivityPlan?, source: Source) {
        if let session, session.source == source, session.plan != plan { stop() }
    }

    func requestNextFocus() { wantsNextFocus = session?.plan.next != nil }

    func focusMinute(in timeline: LessonTimeline, source: Source?, at instant: Date) -> Int? {
        guard wantsNextFocus, let session, session.source == source else { return nil }
        return session.plan.focusMinute(in: timeline, at: instant)
    }

    func consumeFocus() { wantsNextFocus = false }

    private func observe(_ activity: Activity<LessonActivityAttributes>, endingAt end: Date) {
        stateWatcher = Task { [weak self] in
            for await state in activity.activityStateUpdates {
                guard !Task.isCancelled, let self, self.session?.activity.id == activity.id else { return }
                switch state {
                case .stale:
                    self.stop()
                    return
                case .dismissed, .ended:
                    self.detach()
                    return
                default: continue
                }
            }
        }
        endTimer = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow))) } catch { return }
            guard self?.session?.activity.id == activity.id else { return }
            self?.stop()
        }
    }

    private func detach() {
        session = nil; wantsNextFocus = false
        stateWatcher?.cancel(); stateWatcher = nil
        endTimer?.cancel(); endTimer = nil
    }

    private func end(_ activities: [Activity<LessonActivityAttributes>]) {
        guard !activities.isEmpty else { return }
        ending = true
        Task { [weak self] in
            for activity in activities {
                await activity.end(ActivityContent(state: .closed, staleDate: nil), dismissalPolicy: .immediate)
            }
            self?.ending = false
        }
    }
}

extension AppModel {
    var lessonActivitySource: LessonActivityController.Source? {
        if school.selected { return school.owner.map(LessonActivityController.Source.school) }
        if let scope = campus.account?.scope { return .connectedDemo(scope) }
        return usesLocalTimetable ? .localDemo : nil
    }

    func reconcileLessonActivitySource() {
        // Locking the screen invalidates the app's read cache, not the user's
        // explicit request to show this short-lived snapshot on the Lock Screen.
        if school.selected && school.owner == nil && school.identityIssue == .notReady { return }
        lessonActivity.revoke(unless: lessonActivitySource)
    }

    func openLessonActivity(_ url: URL) {
        guard url.absoluteString == LessonActivityAttributes.courseLink?.absoluteString else { return }
        returnToNow()
        selectedLesson = nil
        tab = .today
        lessonActivity.requestNextFocus()
    }
}
