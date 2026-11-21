import Foundation

public struct PlannedReminder: Identifiable, Equatable, Sendable {
    public let id: String
    public let fireDate: Date
    public let title: String
    public let body: String
    public let lessonID: String?
    public let schoolDate: Date
}

public enum ReminderPlanner {
    public static let identifierPrefix = "xiaobao.demo."

    public static func make(now: Date, provider: some SchoolScheduleProviding, leadMinutes: Int,
                            morningMinute: Int? = nil, days: Int = 7) -> [PlannedReminder] {
        let calendar = SchoolClock.calendar
        let lead = max(0, min(60, leadMinutes))
        var result: [PlannedReminder] = []
        for offset in 0..<max(0, min(14, days)) {
            let date = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
            let lessons = provider.lessons(on: date)
            guard let first = lessons.first else { continue }
            for lesson in lessons {
                let fire = lesson.start.addingTimeInterval(-Double(lead * 60))
                guard fire > now else { continue }
                result.append(PlannedReminder(id: identifierPrefix + "lesson." + lesson.id,
                    fireDate: fire, title: "Day \(lesson.day) · \(lesson.course.shortName)",
                    body: "本机课表 · \(lead == 0 ? "现在上课" : "\(lead) 分钟后上课") · \(lesson.course.room) · \(lesson.timeLabel)",
                    lessonID: lesson.id, schoolDate: date))
            }
            if let minute = morningMinute, (0..<1440).contains(minute) {
                let fire = SchoolClock.at(minute: minute, on: date)
                if fire > now {
                    result.append(PlannedReminder(id: identifierPrefix + "morning." + SchoolClock.key(date),
                        fireDate: fire, title: "今天是 Day \(first.day)",
                        body: "本机课表 · 第一节 \(first.course.name)，\(SchoolClock.time(first.startMinute)) · \(first.course.room)",
                        lessonID: first.id, schoolDate: date))
                }
            }
        }
        // Keep headroom below the system limit of pending local notifications.
        return Array(result.sorted { $0.fireDate < $1.fireDate }.prefix(60))
    }
}
