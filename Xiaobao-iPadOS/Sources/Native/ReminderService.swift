import Foundation
import Observation
import UserNotifications

struct NotificationRoute: Equatable {
    let eventID = UUID()
    let lessonID: String
    let date: Date
}

@MainActor @Observable
final class ReminderService: NSObject, UNUserNotificationCenterDelegate {
    var status = "尚未开启"
    var pendingCount = 0
    var route: NotificationRoute?
    var working = false
    private(set) var planStatus: String?
    private static let pendingBudget = 60
    @ObservationIgnored private let center = UNUserNotificationCenter.current()
    @ObservationIgnored private var revision = UUID()
    @ObservationIgnored private var planRevision = UUID()
    @ObservationIgnored private var planOperation: Task<Void, Never>?

    override init() {
        super.init()
        center.delegate = self
    }

    func requestPermission() async -> Bool {
        do {
            let allowed = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            if !allowed { status = "通知未获授权，可以在系统设置中开启。" }
            return allowed
        } catch { status = error.localizedDescription; return false }
    }

    #if DEBUG && TSCHEDULE_INTERNAL_FIXTURES
    @ObservationIgnored var permitsFixtureDelivery: @MainActor () -> Bool = { false }

    func schedule(provider: DemoSchoolProvider, lead: Int, morning: Int?) async {
        let token = UUID(); revision = token; working = true
        defer { if revision == token { working = false } }
        let authorization = await notificationAuthorization()
        guard revision == token else { return }
        guard let authorization else { status = "暂时无法读取系统通知设置。"; return }
        guard authorization == .authorized || authorization == .provisional else {
            status = "通知未获授权，可以在系统设置中开启。"; return
        }
        let old = await pendingRequests()
        guard revision == token else { return }
        guard let old else { status = "暂时无法读取系统通知队列。"; return }
        let plan = ReminderPlanner.make(now: Date(), provider: provider, leadMinutes: lead, morningMinute: morning)
        let allIDs = old.map(\.identifier)
        let school = allIDs.filter { $0.hasPrefix(ReminderPlanner.identifierPrefix) }
        let personal = allIDs.filter { $0.hasPrefix(PlanReminderPlanner.identifierPrefix) }
        // Preserve the existing school allocation. Personal reminders fill only
        // the remainder when the caller reconciles them after the school write.
        let overflow = max(0, allIDs.count - school.count + plan.count - Self.pendingBudget)
        center.removePendingNotificationRequests(withIdentifiers: school + Array(personal.prefix(overflow)))
        var count = 0
        do {
            for item in plan {
                guard revision == token else { return }
                let content = UNMutableNotificationContent()
                content.title = item.title; content.body = item.body; content.sound = .default
                content.userInfo = ["lessonID": item.lessonID ?? "", "schoolDate": item.schoolDate.timeIntervalSince1970]
                var components = SchoolClock.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: item.fireDate)
                components.timeZone = SchoolClock.calendar.timeZone
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                let requestID = item.id + "." + token.uuidString
                try await center.add(UNNotificationRequest(identifier: requestID, content: content, trigger: trigger))
                // A concurrent cancellation may happen while add() is suspended.
                guard revision == token else { center.removePendingNotificationRequests(withIdentifiers: [requestID]); return }
                count += 1
            }
            pendingCount = count; status = "已安排未来 7 天的 \(count) 条课表提醒"
        } catch { if revision == token { pendingCount = count; status = "部分提醒未能安排：\(error.localizedDescription)" } }
    }

    #endif

    func cancelScheduled() async {
        let token = UUID(); revision = token
        working = false
        // Removal needs no permission prompt. Inspect only the legacy timetable namespace.
        async let pending = pendingRequests()
        async let delivered = deliveredRequestIDs()
        let (requests, shown) = await (pending, delivered)
        guard revision == token else { return }
        if let requests {
            center.removePendingNotificationRequests(withIdentifiers: requests.map(\.identifier)
                .filter { $0.hasPrefix(ReminderPlanner.identifierPrefix) })
            pendingCount = 0
        }
        if let shown {
            center.removeDeliveredNotifications(withIdentifiers: shown.filter { $0.hasPrefix(ReminderPlanner.identifierPrefix) })
        }
        status = requests == nil || shown == nil ? "暂时无法确认课表提醒已移除。" : "课表提醒已关闭"
    }

    func requestPlanPermission() async {
        // Do not await the permission dialog while holding the plan write queue.
        // It may stay open while the app changes scenes or the owner changes.
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func syncPlanReminders(_ plan: [PlannedPlanReminder], subtitle: String?) async {
        await runPlanOperation { [weak self] token in
            await self?.applyPlanReminders(plan, subtitle: subtitle ?? "", token: token)
        }
    }

    private func applyPlanReminders(_ plan: [PlannedPlanReminder], subtitle: String, token: UUID) async {
        let authorization = await notificationAuthorization()
        guard planRevision == token else { return }
        let unavailable = "暂时无法更新系统提醒，下次打开 App 会重试。"
        guard let authorization else { planStatus = unavailable; return }
        if authorization == .notDetermined {
            planStatus = plan.isEmpty ? nil : "计划已保存；请在系统设置允许通知。"
            return
        }
        let pending = await pendingRequests()
        guard planRevision == token else { return }
        guard let pending else { planStatus = unavailable; return }
        let existing = pending.filter { $0.identifier.hasPrefix(PlanReminderPlanner.identifierPrefix) }
        let allowed = authorization == .authorized || authorization == .provisional
        guard allowed, !plan.isEmpty else {
            center.removePendingNotificationRequests(withIdentifiers: existing.map(\.identifier))
            planStatus = plan.isEmpty ? nil : "计划已保存；请在系统设置允许通知。"
            return
        }
        let limit = max(0, Self.pendingBudget - (pending.count - existing.count))
        let candidates = Array(plan.prefix(limit))
        let signatures = Set(candidates.map(planSignature))
        // Check the OS content itself so a subtitle edit or reset replaces the
        // pending personal request without changing legacy plan signatures.
        let (retained, stale) = existing.reduce(into: (Set<String>(), [String]())) { result, request in
            if let key = request.planSignature, signatures.contains(key), request.subtitle == subtitle {
                result.0.insert(key)
            } else {
                result.1.append(request.identifier)
            }
        }
        center.removePendingNotificationRequests(withIdentifiers: stale)
        var failures = false
        for item in candidates {
            guard planRevision == token else { return }
            let signature = planSignature(item)
            guard !retained.contains(signature) else { continue }
            let request = planRequest(item, subtitle: subtitle, signature: signature, token: token)
            do {
                try await center.add(request)
                guard planRevision == token else {
                    center.removePendingNotificationRequests(withIdentifiers: [request.identifier])
                    return
                }
            } catch { failures = true }
        }
        guard planRevision == token else { return }
        planStatus = failures ? "部分计划提醒未能登记。" :
            (candidates.count < plan.count ? "通知队列已满，仅安排最近的计划提醒。" : nil)
    }

    func clearPlanReminders() async {
        await runPlanOperation(mustRun: true) { [weak self] _ in
            await self?.removePlanReminders()
        }
    }

    /// The next reconciliation cannot retain an add that the previous one
    /// is still cancelling. A scope clear runs before its replacement.
    private func runPlanOperation(mustRun: Bool = false,
                                  _ operation: @escaping @MainActor (UUID) async -> Void) async {
        let token = UUID()
        planRevision = token
        let previous = planOperation
        let step = Task { [weak self] in
            await previous?.value
            guard mustRun || self?.planRevision == token else { return }
            await operation(token)
        }
        planOperation = step
        await step.value
        if planRevision == token { planOperation = nil }
    }

    private func removePlanReminders() async {
        if await notificationAuthorization() == .notDetermined { planStatus = nil; return }
        async let oldRequests = pendingRequests()
        async let deliveredIDs = deliveredRequestIDs()
        let (old, shown) = await (oldRequests, deliveredIDs)
        if let old {
            center.removePendingNotificationRequests(withIdentifiers: old.map(\.identifier)
                .filter { $0.hasPrefix(PlanReminderPlanner.identifierPrefix) })
        }
        if let shown {
            center.removeDeliveredNotifications(withIdentifiers: shown.filter { $0.hasPrefix(PlanReminderPlanner.identifierPrefix) })
        }
        planStatus = old == nil || shown == nil ? "暂时无法确认旧计划提醒已移除。" : nil
    }

    private struct PendingRequest: Sendable {
        let identifier: String
        let planSignature: String?
        let subtitle: String
    }

    private func notificationAuthorization() async -> UNAuthorizationStatus? {
        let rawValue: Int? = await readNotificationState { reply in
            center.getNotificationSettings { reply($0.authorizationStatus.rawValue) }
        }
        return rawValue.flatMap(UNAuthorizationStatus.init(rawValue:))
    }

    private func pendingRequests() async -> [PendingRequest]? {
        await readNotificationState { reply in
            center.getPendingNotificationRequests { requests in
                reply(requests.map { PendingRequest(identifier: $0.identifier,
                    planSignature: $0.content.userInfo["planSignature"] as? String, subtitle: $0.content.subtitle) })
            }
        }
    }

    private func deliveredRequestIDs() async -> [String]? {
        await readNotificationState { reply in
            center.getDeliveredNotifications { reply($0.map(\.request.identifier)) }
        }
    }

    // A missing response from the notification daemon must not hold the serial
    // write queue indefinitely. An unknown queue is never treated as empty.
    private func readNotificationState<Value: Sendable>(
        _ start: (@escaping @Sendable (Value) -> Void) -> Void
    ) async -> Value? {
        await withCheckedContinuation { continuation in
            let read = NotificationRead(continuation)
            start { value in Task { @MainActor in read.finish(value) } }
            Task {
                try? await Task.sleep(for: .seconds(4))
                read.finish(nil)
            }
        }
    }

    @MainActor private final class NotificationRead<Value: Sendable> {
        private var continuation: CheckedContinuation<Value?, Never>?

        init(_ continuation: CheckedContinuation<Value?, Never>) { self.continuation = continuation }

        func finish(_ value: Value?) {
            let current = continuation
            continuation = nil
            current?.resume(returning: value)
        }
    }

    private func planSignature(_ item: PlannedPlanReminder) -> String {
        let time: String
        switch item.timing {
        case .once: time = "date.\(Int(item.nextFire.timeIntervalSince1970))"
        case .weekly(let day, let minute): time = "week.\(day).\(minute)"
        }
        // The title is already present in the device notification; no owner
        // or account identifier is stored in the notification payload.
        return "\(item.id)|\(time)|\(item.lead.rawValue)|\(item.planTitle)"
    }

    private func planRequest(_ item: PlannedPlanReminder, subtitle: String, signature: String, token: UUID) -> UNNotificationRequest {
        let calendar = SchoolClock.calendar
        let repeats: Bool
        var components: DateComponents
        switch item.timing {
        case .once:
            repeats = false
            components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: item.nextFire)
        case .weekly(let weekday, let minute):
            repeats = true
            components = DateComponents(hour: minute / 60, minute: minute % 60, weekday: weekday)
        }
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        let content = UNMutableNotificationContent()
        content.title = item.planTitle
        content.subtitle = subtitle
        content.body = item.lead == .atStart ? "个人计划 · 现在开始" : "个人计划 · \(item.lead.rawValue) 分钟后开始"
        content.sound = .default
        content.userInfo = ["planSignature": signature]
        return UNNotificationRequest(identifier: item.id + "." + token.uuidString, content: content,
                                     trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: repeats))
    }

    func sendTest(subtitle: String?) async -> String {
        guard await requestPermission() else { return status }
        let content = UNMutableNotificationContent()
        content.title = "通知检查"
        content.subtitle = subtitle ?? ""
        content.body = "这是一条本机测试通知。"
        content.sound = .default
        do {
            try await center.add(UNNotificationRequest(identifier: "xiaobao.test", content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)))
            return "请在 5 秒后查看通知。"
        } catch { return "未能安排测试通知，请重试。" }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        if notification.request.identifier.hasPrefix(ReminderPlanner.identifierPrefix) {
            #if DEBUG && TSCHEDULE_INTERNAL_FIXTURES
            guard await permitsFixtureDelivery() else { return [] }
            #else
            return []
            #endif
        }
        return [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse) async {
        guard let lessonID = response.notification.request.content.userInfo["lessonID"] as? String,
              !lessonID.isEmpty,
              let stamp = response.notification.request.content.userInfo["schoolDate"] as? Double else { return }
        await MainActor.run { self.route = NotificationRoute(lessonID: lessonID, date: Date(timeIntervalSince1970: stamp)) }
    }
}
