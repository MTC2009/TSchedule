import Foundation

/// A single backdrop per Shanghai civil day. Raw IDs are also saved manual choices.
public enum Festival: String, CaseIterable, Codable, Identifiable, Sendable {
    case none, newyear, lunarEve, spring, lantern, dragonBoat
    case qixi, midautumn, doubleNinth, halloween, thanksgiving, christmasEve
    case christmas, yearEve, springBegins, springRain, awakening, springEquinox
    case qingming, grainRain, summerBegins, grainBuds, grainInEar, summerSolstice
    case lesserHeat, greaterHeat, autumnBegins, endOfHeat, whiteDew, autumnEquinox
    case coldDew, frostDescent, winterBegins, lightSnow, heavySnow, winterSolstice
    case lesserCold, greaterCold
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .none: String(localized: "festival.none", defaultValue: "日常")
        case .newyear: String(localized: "元旦")
        case .lunarEve: String(localized: "除夕")
        case .spring: String(localized: "春节")
        case .lantern: String(localized: "元宵")
        case .dragonBoat: String(localized: "端午")
        case .qixi: String(localized: "七夕")
        case .midautumn: String(localized: "中秋")
        case .doubleNinth: String(localized: "重阳")
        case .halloween: String(localized: "万圣夜")
        case .thanksgiving: String(localized: "感恩节")
        case .christmasEve: String(localized: "平安夜")
        case .christmas: String(localized: "圣诞")
        case .yearEve: String(localized: "跨年夜")
        case .springBegins: String(localized: "立春")
        case .springRain: String(localized: "雨水")
        case .awakening: String(localized: "惊蛰")
        case .springEquinox: String(localized: "春分")
        case .qingming: String(localized: "清明")
        case .grainRain: String(localized: "谷雨")
        case .summerBegins: String(localized: "立夏")
        case .grainBuds: String(localized: "小满")
        case .grainInEar: String(localized: "芒种")
        case .summerSolstice: String(localized: "夏至")
        case .lesserHeat: String(localized: "小暑")
        case .greaterHeat: String(localized: "大暑")
        case .autumnBegins: String(localized: "立秋")
        case .endOfHeat: String(localized: "处暑")
        case .whiteDew: String(localized: "白露")
        case .autumnEquinox: String(localized: "秋分")
        case .coldDew: String(localized: "寒露")
        case .frostDescent: String(localized: "霜降")
        case .winterBegins: String(localized: "立冬")
        case .lightSnow: String(localized: "solarTerm.minorSnow", defaultValue: "小雪")
        case .heavySnow: String(localized: "solarTerm.majorSnow", defaultValue: "大雪")
        case .winterSolstice: String(localized: "冬至")
        case .lesserCold: String(localized: "小寒")
        case .greaterCold: String(localized: "大寒")
        }
    }

    public static let solarTerms: [Festival] = [
        .springBegins, .springRain, .awakening, .springEquinox, .qingming, .grainRain,
        .summerBegins, .grainBuds, .grainInEar, .summerSolstice, .lesserHeat, .greaterHeat,
        .autumnBegins, .endOfHeat, .whiteDew, .autumnEquinox, .coldDew, .frostDescent,
        .winterBegins, .lightSnow, .heavySnow, .winterSolstice, .lesserCold, .greaterCold,
    ]
    public static let holidays = allCases.filter { $0 != .none && !solarTerms.contains($0) }

    /// Pause scene rendering without rewriting anyone's last manual selection or the calendar.
    #if TSCHEDULE_SEASONAL_ART
    static let decorationsEnabled = true
    #else
    static let decorationsEnabled = false
    #endif
    static func displayed(on date: Date, automatic: Bool, manual: Festival) -> Festival {
        guard decorationsEnabled else { return .none }
        return automatic ? Self.automatic(on: date) : manual
    }

    public static func automatic(on date: Date) -> Festival {
        let cal = SchoolClock.calendar
        let c = cal.dateComponents([.year, .month, .day, .weekday], from: date)
        guard let year = c.year, let month = c.month, let day = c.day else { return .none }
        // Explicit festivals take precedence over a coincident solar term, never draw both.
        var lunar = Calendar(identifier: .chinese)
        lunar.timeZone = cal.timeZone
        let l = lunar.dateComponents([.month, .day, .isLeapMonth], from: date)
        if l.isLeapMonth != true {
            switch (l.month, l.day) {
            case (1, 1): return .spring
            case (1, 15): return .lantern
            case (5, 5): return .dragonBoat
            case (7, 7): return .qixi
            case (8, 15): return .midautumn
            case (9, 9): return .doubleNinth
            default: break
            }
        }
        // The last lunar month may have 29 or 30 days; its successor decides.
        if l.month == 12, (l.day ?? 0) >= 29, let next = cal.date(byAdding: .day, value: 1, to: date) {
            let n = lunar.dateComponents([.month, .day, .isLeapMonth], from: next)
            if n.month == 1 && n.day == 1 && n.isLeapMonth != true { return .lunarEve }
        }
        switch (month, day) {
        case (1, 1): return .newyear
        case (10, 31): return .halloween
        case (11, 22...28) where c.weekday == 5: return .thanksgiving
        case (12, 24): return .christmasEve
        case (12, 25): return .christmas
        case (12, 31): return .yearEve
        default: return SolarTermCalendar.scene(year: year, month: month, day: day) ?? .none
        }
    }
}

public enum DayPhase: String, Sendable {
    case dawn, day, sunset, night
    public var title: String { switch self { case .dawn: String(localized: "晨光"); case .day: String(localized: "白昼"); case .sunset: String(localized: "黄昏"); case .night: String(localized: "夜间") } }
    public static func at(minute: Int) -> DayPhase {
        switch minute { case 300..<480: .dawn; case 480..<1020: .day; case 1020..<1170: .sunset; default: .night }
    }
}
