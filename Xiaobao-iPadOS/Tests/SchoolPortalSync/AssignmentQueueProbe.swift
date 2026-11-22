// Appended only to the temporary simulator build; read the actual notification daemon.
import UserNotifications
private let assignmentFixtureProcess = UUID().uuidString

// A cold notification daemon can stall its first callback. Keep reporting the actual
// app state independently; an unknown queue must never count as an empty queue.
@MainActor private final class AssignmentQueueRead {
    struct Entry: Sendable {
        let id: String, title: String, emptyInfo: Bool, fire: Int
        var json: [String: Any] { ["id": id, "title": title, "emptyInfo": emptyInfo, "fire": fire] }
    }
    private var started = Date.distantPast, token: UUID?
    private(set) var entries: [Entry]?

    func update() {
        if token != nil, Date().timeIntervalSince(started) < 4 { return }
        let ticket = UUID()
        if token != nil { entries = nil }
        started = Date(); token = ticket
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let sample = requests.filter { $0.identifier.hasPrefix(AssignmentDeadline.prefix) }.map {
                Entry(id: $0.identifier, title: $0.content.title, emptyInfo: $0.content.userInfo.isEmpty,
                      fire: Int(($0.trigger as? UNCalendarNotificationTrigger)?.dateComponents.date?.timeIntervalSince1970 ?? 0))
            }
            Task { @MainActor in
                guard self.token == ticket else { return }
                self.token = nil; self.entries = sample
            }
        }
    }
}

extension AppModel {
    func inspectAssignmentQueue() async {
        guard SchoolPortalPage.origin.host == "127.0.0.1" else { return }
        let reader = AssignmentQueueRead()
        while !Task.isCancelled {
            var request = URLRequest(url: SchoolPortalPage.origin.appendingPathComponent("control/assignments/sample"))
            request.httpMethod = "POST"
            request.httpBody = try? JSONSerialization.data(withJSONObject: [
                "pending": reader.entries?.map(\.json) ?? [], "pendingKnown": reader.entries != nil, "online": school.owner != nil,
                "process": assignmentFixtureProcess, "issue": school.identityIssue?.rawValue ?? "",
                "taskError": school.issues[school.taskRead]?.rawValue ?? "", "review": assignments.reviewing,
                "optIn": assignments.enabled, "notificationStatus": notifications.status])
            _ = try? await URLSession.shared.data(for: request)
            reader.update()
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
        }
    }
}
