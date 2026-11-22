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
    var status = String(localized: "尚未开启")
    var pendingCount = 0
    var route: NotificationRoute?
    var working = false
    private(set) var planStatus: String?
    private(set) var schoolStatus: String?
    @ObservationIgnored var permitsSchoolDelivery: @MainActor @Sendable () -> Bool = { false }
    @ObservationIgnored var permitsPersonalDelivery: @MainActor @Sendable () -> Bool = { false }
    @ObservationIgnored var permitsAssignmentDelivery: @MainActor @Sendable () -> Bool = { false }
    private(set) var assignmentStatus: String?
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
        // Do not leave a switch disabled forever if the system fails to present or
        // answer the dialog. A late grant never enables this device setting by itself.
        enum Answer: Sendable { case allowed, denied, unavailable }
        let answer: Answer? = await readNotificationState(timeout: .seconds(60)) { reply in
            center.requestAuthorization(options: [.alert, .sound, .badge]) { allowed, error in
                reply(error != nil ? .unavailable : allowed ? .allowed : .denied)
            }
        }
        switch answer {
        case .allowed: return true
        case .denied: status = String(localized: "通知未获授权，可以在系统设置中开启。")
        case .unavailable, nil: status = String(localized: "系统暂未返回通知授权结果，请稍后重试。")
        }
        return false
    }

    #if DEBUG && TSCHEDULE_INTERNAL_FIXTURES
    @ObservationIgnored var permitsFixtureDelivery: @MainActor () -> Bool = { false }

    func schedule(provider: DemoSchoolProvider, lead: Int, morning: Int?) async {
        let token = UUID(); revision = token; working = true
        defer { if revision == token { working = false } }
        let authorization = await notificationAuthorization()
        guard revision == token else { return }
        guard let authorization else { status = String(localized: "暂时无法读取系统通知设置。"); return }
        guard authorization == .authorized || authorization == .provisional else {
            status = String(localized: "通知未获授权，可以在系统设置中开启。"); return
        }
        let old = await pendingRequests()
        guard revision == token else { return }
        guard let old else { status = String(localized: "暂时无法读取系统通知队列。"); return }
        let plan = ReminderPlanner.make(now: Date(), provider: provider, leadMinutes: lead, morningMinute: morning)
        let allIDs = old.map(\.identifier)
        let school = allIDs.filter { $0.hasPrefix(ReminderPlanner.identifierPrefix) }
        let personal = allIDs.filter { $0.hasPrefix(PlanReminderPlanner.identifierPrefix) }
        // Preserve the existing school allocation. Personal reminders fill only
        // the remainder when the caller reconciles them after the school write.
        let overflow = max(0, allIDs.count - school.count + plan.count - Self.pendingBudget)
        let replaced = school + Array(personal.prefix(overflow))
        if !replaced.isEmpty { center.removePendingNotificationRequests(withIdentifiers: replaced) }
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
            pendingCount = count; status = String(localized: "已安排未来 7 天的 \(count) 条课表提醒")
        } catch { if revision == token { pendingCount = count; status = String(localized: "部分提醒未能安排：\(error.localizedDescription)") } }
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
            let retired = requests.map(\.identifier).filter { $0.hasPrefix(ReminderPlanner.identifierPrefix) }
            if !retired.isEmpty { center.removePendingNotificationRequests(withIdentifiers: retired) }
            pendingCount = 0
        }
        if let retired = shown?.filter({ $0.hasPrefix(ReminderPlanner.identifierPrefix) }), !retired.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: retired)
        }
        status = requests == nil || shown == nil ? String(localized: "暂时无法确认课表提醒已移除。") : String(localized: "课表提醒已关闭")
    }

    func requestPlanPermission() async {
        // Do not await the permission dialog while holding the plan write queue.
        // It may stay open while the app changes scenes or the owner changes.
        _ = await requestPermission()
    }

    /// nil personal input means that its protected records cannot be read: leave its
    /// queue untouched. An empty input means the owner has no eligible reminders.
    func syncDeviceReminders(plans: [PlannedPlanReminder]?, lessons: [SchoolLessonReminder], subtitle: String?, assignments: [AssignmentDeadline]? = nil) async {
        let work = enqueue { [weak self] token in
            guard let self, await self.finishRemoval(), self.planRevision == token else { return }
            await self.apply(plans: plans, lessons: lessons, subtitle: subtitle ?? "", assignments: assignments, token: token)
        }
        await work.value
    }

    private func apply(plans: [PlannedPlanReminder]?, lessons: [SchoolLessonReminder], subtitle: String, assignments: [AssignmentDeadline]?, token: UUID) async {
        async let auth = notificationAuthorization()
        async let list = pendingRequests()
        let (authorization, pending) = await (auth, list)
        guard planRevision == token else { return }
        let unavailable = String(localized: "暂时无法更新系统提醒，下次打开 App 会重试。")
        guard let authorization, let pending else {
            if plans != nil { planStatus = unavailable }; if assignments != nil { assignmentStatus = unavailable }; schoolStatus = unavailable; return
        }
        let allowed = authorization == .authorized || authorization == .provisional
        let personal = pending.filter { $0.identifier.hasPrefix(PlanReminderPlanner.identifierPrefix) }
        let school = pending.filter { $0.identifier.hasPrefix(SchoolLessonReminder.prefix) }
        let tasks = pending.filter { $0.identifier.hasPrefix(AssignmentDeadline.prefix) }
        let future = (assignments ?? []).filter { $0.fire > Date() }
        // Nil means unknown, not empty. Lend unused capacity round-robin rather than
        // evicting personal or class alerts to make room for a busy semester.
        let free = max(0, Self.pendingBudget - pending.count + (plans == nil ? 0 : personal.count)
                       + school.count + (assignments == nil ? 0 : tasks.count))
        let demand = [plans?.count ?? 0, lessons.count, future.count]
        var slots = [0, 0, 0], left = allowed ? free : 0
        while left > 0 && slots != demand {
            for i in demand.indices where left > 0 && slots[i] < demand[i] { slots[i] += 1; left -= 1 }
        }
        let candidates = Array((plans ?? []).prefix(slots[0]))
        let classes = Array(lessons.prefix(slots[1]))
        let deadlines = Array(future.prefix(slots[2]))
        var stale: [String] = [], keptPlans = Set<String>()
        if plans != nil {
            let leads = Dictionary(candidates.map { (planSignature($0), $0.lead) }, uniquingKeysWith: { first, _ in first })
            for old in personal {
                if let sig = old.planSignature, let lead = leads[sig], old.matchesPlan(lead: lead, subtitle: subtitle),
                   keptPlans.insert(sig).inserted { continue }
                stale.append(old.identifier)
            }
        }
        let desired = Dictionary(classes.map { ($0.id, $0.lead) }, uniquingKeysWith: { first, _ in first })
        // Older releases registered literal Chinese content. Keep stable IDs but let add(_:)
        // replace stale wording in place, without changing the fire date or duplicating a class.
        let keptClasses = Set(school.compactMap { old -> String? in
            guard let lead = desired[old.identifier], old.matchesLesson(lead: lead) else { return nil }
            return old.identifier
        })
        stale += school.map(\.identifier).filter { desired[$0] == nil }
        let wantedTasks = Dictionary(uniqueKeysWithValues: deadlines.map { ($0.id, $0) })
        var keptTasks = Set<String>()
        if let assignments {
            for old in tasks {
                guard let item = wantedTasks[old.identifier] else { stale.append(old.identifier); continue }
                if old.matchesAssignment(item) { keptTasks.insert(old.identifier) }
            }
            // Don't take down a valid delivered banner simply because its fire date passed.
            // Do remove withdrawn, retimed or privacy-changed banners already on the Lock Screen.
            if let delivered = await deliveredAssignments() {
                guard planRevision == token else { return }
                let valid = Dictionary(uniqueKeysWithValues: assignments.map { ($0.id, $0) })
                let ids = delivered.filter { old in !allowed || valid[old.identifier].map { old.matchesAssignment($0) } != true }.map(\.identifier)
                if !ids.isEmpty { center.removeDeliveredNotifications(withIdentifiers: ids) }
            }
        }
        guard planRevision == token else { return }
        if !stale.isEmpty { center.removePendingNotificationRequests(withIdentifiers: stale) }
        var planFailed = false, schoolCount = keptClasses.count
        for item in candidates where !keptPlans.contains(planSignature(item)) {
            guard planRevision == token else { return }
            let request = planRequest(item, subtitle: subtitle, signature: planSignature(item), token: token)
            do { try await center.add(request) } catch { planFailed = true }
            guard planRevision == token else { center.removePendingNotificationRequests(withIdentifiers: [request.identifier]); return }
        }
        for item in classes where !keptClasses.contains(item.id) {
            guard planRevision == token else { return }
            do { try await center.add(Self.schoolRequest(item)); schoolCount += 1 } catch { /* reported by count below */ }
            guard planRevision == token else { center.removePendingNotificationRequests(withIdentifiers: [item.id]); return }
        }
        guard planRevision == token else { return }
        var taskFailed = false
        for item in deadlines where !keptTasks.contains(item.id) {
            guard planRevision == token else { return }
            do { try await center.add(Self.assignmentRequest(item)) } catch { taskFailed = true }
            guard planRevision == token else { center.removePendingNotificationRequests(withIdentifiers: [item.id]); return }
        }
        let denied = String(localized: "请在 iPad 系统设置中允许 TSchedule 发送通知。")
        if assignments != nil {
            if !allowed { assignmentStatus = denied }
            else if taskFailed { assignmentStatus = unavailable }
            else { assignmentStatus = deadlines.count < future.count ? String(localized: "通知名额有限，已优先安排最近截止的作业。") : nil }
        }
        if let plans {
            if !plans.isEmpty && !allowed { planStatus = denied }
            else if planFailed { planStatus = String(localized: "部分计划提醒未能登记。") }
            else { planStatus = candidates.count < plans.count ? String(localized: "通知队列已满，仅安排最近的计划提醒。") : nil }
        }
        if !allowed { schoolStatus = denied }
        else if schoolCount < classes.count { schoolStatus = String(localized: "已安排 \(schoolCount) 条课前提醒，部分未能登记。") }
        else if schoolCount < lessons.count { schoolStatus = String(localized: "通知名额有限，已安排最近的 \(schoolCount) 条课前提醒。") }
        else { schoolStatus = schoolCount == 0 ? String(localized: "未来 7 天没有可安排的课前提醒。") : String(localized: "已安排未来 7 天的 \(schoolCount) 条课前提醒。") }
    }

    private static var lessonTitle: String {
        NSString.localizedUserNotificationString(forKey: "课前提醒", arguments: nil)
    }

    private static func lessonBody(lead: Int) -> String {
        lead == 0 ? NSString.localizedUserNotificationString(forKey: "现在是上课时间。", arguments: nil)
                  : NSString.localizedUserNotificationString(forKey: "距离上课还有 %@ 分钟。", arguments: [NSNumber(value: lead)])
    }

    private static func planBody(lead: PlanReminder) -> String {
        lead == .atStart ? NSString.localizedUserNotificationString(forKey: "个人计划 · 现在开始", arguments: nil)
                         : NSString.localizedUserNotificationString(forKey: "个人计划 · %@ 分钟后开始", arguments: [NSNumber(value: lead.rawValue)])
    }

    /// No account, title, room, custom subtitle or navigation record enters the OS payload.
    static func schoolRequest(_ item: SchoolLessonReminder) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = lessonTitle
        content.body = lessonBody(lead: item.lead)
        content.sound = .default
        let clock = SchoolClock.calendar
        var date = clock.dateComponents([.year, .month, .day, .hour, .minute], from: item.fireDate)
        date.calendar = clock; date.timeZone = clock.timeZone
        return UNNotificationRequest(identifier: item.id, content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: date, repeats: false))
    }

    // Compare the same text on both sides of the daemon boundary. A deferred
    // notification key may be returned in the system language even when the app
    // is English. On the next foreground sync an app-language change replaces it.
    private static var assignmentTitle: String { String(localized: "作业即将截止") }
    private static var assignmentBody: String { String(localized: "这项作业将在一小时后截止。") }
    private static func assignmentRequest(_ item: AssignmentDeadline) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = item.title ?? assignmentTitle; content.body = assignmentBody; content.sound = .default
        let clock = SchoolClock.calendar
        var time = clock.dateComponents([.year, .month, .day, .hour, .minute, .second], from: item.fire)
        time.calendar = clock; time.timeZone = clock.timeZone
        return .init(identifier: item.id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: time, repeats: false))
    }

    private static let assignmentRemoval = "tschedule.notifications.clearAssignments"
    @discardableResult func requireAssignmentRemoval() -> Task<Void, Never> {
        UserDefaults.standard.set(UUID().uuidString, forKey: Self.assignmentRemoval)
        return enqueue(mustRun: true) { [weak self] _ in _ = await self?.finishRemoval() }
    }

    private static let accountRemoval = "tschedule.notifications.clearAccount"
    private static let schoolRemoval = "tschedule.notifications.clearLessons"

    /// Record revocation before yielding (even if the app is killed mid-cleanup).
    /// A privacy clear is ordered before all writes that follow it, never superseded.
    @discardableResult func requireRemoval(includingPlans: Bool) -> Task<Void, Never> {
        UserDefaults.standard.set(UUID().uuidString, forKey: includingPlans ? Self.accountRemoval : Self.schoolRemoval)
        return enqueue(mustRun: true) { [weak self] _ in _ = await self?.finishRemoval() }
    }

    private func enqueue(mustRun: Bool = false, _ op: @escaping @MainActor (UUID) async -> Void) -> Task<Void, Never> {
        let token = UUID(), previous = planOperation
        planRevision = token
        let step = Task { [weak self] in
            await previous?.value
            guard mustRun || self?.planRevision == token else { return }
            await op(token)
            if self?.planRevision == token { self?.planOperation = nil }
        }
        planOperation = step
        return step
    }

    func retryRemovalIfNeeded() async {
        if UserDefaults.standard.object(forKey: Self.accountRemoval) != nil ||
            UserDefaults.standard.object(forKey: Self.schoolRemoval) != nil || UserDefaults.standard.object(forKey: Self.assignmentRemoval) != nil {
            await enqueue(mustRun: true) { [weak self] _ in _ = await self?.finishRemoval() }.value
        }
    }

    private func finishRemoval() async -> Bool {
        let defaults = UserDefaults.standard
        let account = defaults.string(forKey: Self.accountRemoval), school = defaults.string(forKey: Self.schoolRemoval)
        let tasks = defaults.string(forKey: Self.assignmentRemoval)
        guard account != nil || school != nil || tasks != nil else { return true }
        func matches(_ id: String) -> Bool {
            ((account != nil || school != nil) && id.hasPrefix(SchoolLessonReminder.prefix)) ||
                (account != nil && id.hasPrefix(PlanReminderPlanner.identifierPrefix)) ||
                ((account != nil || tasks != nil) && id.hasPrefix(AssignmentDeadline.prefix))
        }
        async let pending = pendingRequests()
        async let delivered = deliveredRequestIDs()
        let (requests, shown) = await (pending, delivered)
        if let ids = requests?.map(\.identifier).filter(matches), !ids.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
        if let ids = shown?.filter(matches), !ids.isEmpty { center.removeDeliveredNotifications(withIdentifiers: ids) }
        guard requests != nil, shown != nil else {
            let message = String(localized: "暂时无法确认旧提醒已移除。")
            if account != nil || school != nil { schoolStatus = message }
            if account != nil { planStatus = message }
            if account != nil || tasks != nil { assignmentStatus = message }
            return false
        }
        if account != nil || school != nil { schoolStatus = nil }
        if account != nil || tasks != nil { assignmentStatus = nil }
        if account != nil { planStatus = nil }
        for (key, stamp) in [(Self.accountRemoval, account), (Self.schoolRemoval, school), (Self.assignmentRemoval, tasks)] {
            if let stamp, defaults.string(forKey: key) == stamp { defaults.removeObject(forKey: key) }
        }
        return true
    }

    private struct PendingRequest: Sendable {
        let identifier: String
        let planSignature: String?
        let subtitle: String
        let body: String
        let lessonTitle: String?
        var assignmentTitle: String? = nil
        var assignmentFire: Int? = nil

        @MainActor func matchesAssignment(_ item: AssignmentDeadline) -> Bool {
            self.assignmentFire == Int(item.fire.timeIntervalSince1970) && self.assignmentTitle == (item.title ?? ReminderService.assignmentTitle)
                && body == ReminderService.assignmentBody
        }

        @MainActor func matchesPlan(lead: PlanReminder, subtitle: String) -> Bool {
            self.subtitle == subtitle && body == ReminderService.planBody(lead: lead)
        }

        @MainActor func matchesLesson(lead: Int) -> Bool {
            lessonTitle == ReminderService.lessonTitle && body == ReminderService.lessonBody(lead: lead)
        }

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
                reply(requests.map(Self.inspect))
            }
        }
    }

    private nonisolated static func inspect(_ r: UNNotificationRequest) -> PendingRequest {
        let task = r.identifier.hasPrefix(AssignmentDeadline.prefix)
        let date = (r.trigger as? UNCalendarNotificationTrigger)?.dateComponents.date
        return .init(identifier: r.identifier, planSignature: r.content.userInfo["planSignature"] as? String,
                     subtitle: r.content.subtitle, body: r.content.body,
                     lessonTitle: r.identifier.hasPrefix(SchoolLessonReminder.prefix) ? r.content.title : nil,
                     assignmentTitle: task ? r.content.title : nil, assignmentFire: task ? date.map { Int($0.timeIntervalSince1970) } : nil)
    }

    private func deliveredAssignments() async -> [PendingRequest]? {
        await readNotificationState { reply in
            center.getDeliveredNotifications { reply($0.map { $0.request }.filter { $0.identifier.hasPrefix(AssignmentDeadline.prefix) }.map(Self.inspect)) }
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
        timeout: Duration = .seconds(4),
        _ start: (@escaping @Sendable (Value) -> Void) -> Void
    ) async -> Value? {
        await withCheckedContinuation { continuation in
            let read = NotificationRead(continuation)
            start { value in Task { @MainActor in read.finish(value) } }
            Task {
                try? await Task.sleep(for: timeout)
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
        content.body = Self.planBody(lead: item.lead)
        content.sound = .default
        content.userInfo = ["planSignature": signature]
        return UNNotificationRequest(identifier: item.id + "." + token.uuidString, content: content,
                                     trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: repeats))
    }

    func sendTest(subtitle: String?) async -> String {
        guard await requestPermission() else { return status }
        let content = UNMutableNotificationContent()
        content.title = NSString.localizedUserNotificationString(forKey: "通知检查", arguments: nil)
        content.subtitle = subtitle ?? ""
        content.body = NSString.localizedUserNotificationString(forKey: "这是一条本机测试通知。", arguments: nil)
        content.sound = .default
        do {
            try await center.add(UNNotificationRequest(identifier: "xiaobao.test", content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)))
            return String(localized: "请在 5 秒后查看通知。")
        } catch { return String(localized: "未能安排测试通知，请重试。") }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let id = notification.request.identifier
        if id.hasPrefix(SchoolLessonReminder.prefix) || id.hasPrefix(PlanReminderPlanner.identifierPrefix) || id.hasPrefix(AssignmentDeadline.prefix) {
            let clearing = await MainActor.run {
                let defaults = UserDefaults.standard
                return defaults.object(forKey: Self.accountRemoval) != nil ||
                    (id.hasPrefix(SchoolLessonReminder.prefix) && defaults.object(forKey: Self.schoolRemoval) != nil) ||
                    (id.hasPrefix(AssignmentDeadline.prefix) && defaults.object(forKey: Self.assignmentRemoval) != nil)
            }
            if clearing { return [] }
        }
        if id.hasPrefix(AssignmentDeadline.prefix), !(await permitsAssignmentDelivery()) { return [] }
        if id.hasPrefix(SchoolLessonReminder.prefix), !(await permitsSchoolDelivery()) { return [] }
        if id.hasPrefix(PlanReminderPlanner.identifierPrefix), !(await permitsPersonalDelivery()) { return [] }
        if id.hasPrefix(ReminderPlanner.identifierPrefix) {
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
