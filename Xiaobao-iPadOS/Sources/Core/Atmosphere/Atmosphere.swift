import Foundation

public enum Festival: String, CaseIterable, Codable, Identifiable, Sendable {
    case none, spring, midautumn, christmas, newyear
    public var id: String { rawValue }
    public var title: String { switch self { case .none: "日常"; case .spring: "春节"; case .midautumn: "中秋"; case .christmas: "圣诞"; case .newyear: "元旦" } }

    public static func automatic(on date: Date) -> Festival {
        let parts = SchoolClock.calendar.dateComponents([.month, .day], from: date)
        if parts.month == 1 && parts.day == 1 { return .newyear }
        if parts.month == 12 && parts.day == 25 { return .christmas }
        var lunar = Calendar(identifier: .chinese)
        lunar.timeZone = SchoolClock.calendar.timeZone
        let chinese = lunar.dateComponents([.month, .day], from: date)
        guard chinese.isLeapMonth != true else { return .none }
        if chinese.month == 1 && chinese.day == 1 { return .spring }
        if chinese.month == 8 && chinese.day == 15 { return .midautumn }
        return .none
    }
}

public enum DayPhase: String, Sendable {
    case dawn, day, sunset, night
    public var title: String { switch self { case .dawn: "晨光"; case .day: "白昼"; case .sunset: "黄昏"; case .night: "夜间" } }
    public static func at(minute: Int) -> DayPhase {
        switch minute { case 300..<480: .dawn; case 480..<1020: .day; case 1020..<1170: .sunset; default: .night }
    }
}
