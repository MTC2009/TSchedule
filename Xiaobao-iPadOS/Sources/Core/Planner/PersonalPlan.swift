import Foundation

/// An optional point or half-open time range in school-local minutes.
struct PlanTime: Codable, Equatable, Sendable {
    let startMinute: Int
    let endMinute: Int?

    init?(startMinute: Int, endMinute: Int? = nil) {
        self.startMinute = startMinute
        self.endMinute = endMinute
        guard isValid else { return nil }
    }

    var isValid: Bool {
        (0..<1440).contains(startMinute) &&
            (endMinute.map { startMinute < $0 && $0 <= 1440 } ?? true)
    }

    func start(on date: Date) -> Date { SchoolClock.at(minute: startMinute, on: date) }
    func end(on date: Date) -> Date? { endMinute.map { SchoolClock.at(minute: $0, on: date) } }
}

/// Stable identifiers for optional appearance. The native view maps these to
/// the system palette and symbols; no platform color is persisted.
enum PlanColor: String, Codable, CaseIterable, Sendable {
    case blue, teal, green, orange, pink
}

enum PlanIcon: String, Codable, CaseIterable, Sendable {
    case book, pencil, computer, people, exercise, music, flag, errands
}

enum PlanReminder: Int, Codable, CaseIterable, Sendable {
    case atStart = 0
    case fiveMinutes = 5
    case tenMinutes = 10
    case thirtyMinutes = 30
    case oneHour = 60
}

struct PersonalPlan: Codable, Equatable, Identifiable, Sendable {
    static let titleLimit = 160

    let id: UUID
    let day: String
    let title: String
    let time: PlanTime?
    var isCompleted: Bool
    let color: PlanColor?
    let icon: PlanIcon?
    let reminder: PlanReminder?

    init?(id: UUID = UUID(), day: String, title: String, time: PlanTime?, isCompleted: Bool = false,
          color: PlanColor? = nil, icon: PlanIcon? = nil, reminder: PlanReminder? = nil) {
        self.id = id
        self.day = day
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.time = time
        self.isCompleted = isCompleted
        self.color = color
        self.icon = icon
        self.reminder = reminder
        guard isValid else { return nil }
    }

    func placing(at time: PlanTime?, on day: String? = nil) -> PersonalPlan? {
        PersonalPlan(id: id, day: day ?? self.day, title: title, time: time, isCompleted: isCompleted,
                     color: color, icon: icon, reminder: reminder)
    }

    // Codable can bypass the failable initializers. Validate loaded records before
    // publishing them or allowing a write to replace the previous file.
    var isValid: Bool {
        SchoolClock.dayDate(day) != nil && !title.isEmpty && title.count <= Self.titleLimit &&
            title == title.trimmingCharacters(in: .whitespacesAndNewlines) && (time?.isValid ?? true)
    }
}
