import Foundation

/// Planner reference entries, never course enrollments, notification inputs, or personal plans.
enum PlannerCampusPeriod: String, Hashable {
    case block9, block10, dinner, firstStudy, secondStudy, sport, eveningWash, sleep, morningWash, breakfast

    // Boarding periods are anchored to the evening of a stay. Offsets past 24h
    // intentionally belong to the next Shanghai date, not the device's current timezone.
    var minutes: Range<Int> {
        switch self {
        case .block9: 955..<1005
        case .block10: 1005..<1055
        case .dinner: 1055..<1100
        case .firstStudy: 1100..<1150
        case .secondStudy: 1155..<1205
        case .sport: 1205..<1260
        case .eveningWash: 1260..<1350
        case .sleep: 1350..<(1440 + 420)
        case .morningWash: (1440 + 420)..<(1440 + 460)
        case .breakfast: (1440 + 460)..<(1440 + 480)
        }
    }

    var title: String {
        switch self {
        case .block9: "Block 9"
        case .block10: "Block 10"
        case .dinner: String(localized: "晚餐")
        case .firstStudy, .secondStudy: String(localized: "晚自习")
        case .sport: String(localized: "体育活动")
        case .eveningWash, .morningWash: String(localized: "洗漱")
        case .sleep: String(localized: "就寝")
        case .breakfast: String(localized: "早餐")
        }
    }

    var location: String? {
        switch self {
        case .breakfast, .dinner: CampusBells.Activity.lunch.location
        case .firstStudy, .secondStudy: String(localized: "晚自习教室")
        case .sport: String(localized: "室内／室外运动场")
        case .morningWash, .eveningWash, .sleep: String(localized: "宿舍")
        case .block9, .block10: nil
        }
    }

    static let boarding: [Self] = [.firstStudy, .secondStudy, .sport, .eveningWash, .sleep, .morningWash, .breakfast]
}

extension PlannerSchoolDay {
    /// Apply only to the Planner's read-only day/week columns, after selecting the
    /// authorized school source. Missing roster data is not proof of an unselected elective.
    func withCampusRoutine(on date: Date, calendar: PublishedSchoolCalendar?, showsBoardingRoutine: Bool) -> Self {
        guard let calendar, CampusBells.applies(to: calendar) else { return self }
        let clock = SchoolClock.calendar, day = clock.startOfDay(for: date)
        let today = calendar.day(on: day)
        guard today.status != .unpublished, let tomorrow = clock.date(byAdding: .day, value: 1, to: day),
              let yesterday = clock.date(byAdding: .day, value: -1, to: day) else { return self }

        var extra: [PlannerSchoolEntry] = []
        func append(_ period: PlannerCampusPeriod, anchoredTo anchor: Date) {
            let start = SchoolClock.at(minute: period.minutes.lowerBound, on: anchor)
            let end = SchoolClock.at(minute: period.minutes.upperBound, on: anchor)
            guard start < tomorrow, day < end else { return }
            let elective = period == .block9 || period == .block10
            if elective, entries.contains(where: { entry in
                !entry.allDay && (entry.kind == .lesson || entry.kind == .exam) &&
                entry.start < end && (entry.end ?? entry.start) > start
            }) { return }
            // Keep the real evening registration rather than adding the identical study period twice.
            if !elective, entries.contains(where: { $0.kind == .lesson && $0.start == start && $0.end == end }) { return }
            if [.firstStudy,.secondStudy,.sport].contains(period),
               entries.contains(where:{ $0.kind == .lesson && $0.start < end && ($0.end ?? $0.start) > start }) { return }
            extra.append(.init(id: .routine(period, anchor: anchor), kind: elective ? .optionalBlock : .campusRoutine,
                               title: period.title, location: period.location, start: max(start, day), end: min(end, tomorrow), allDay: false))
        }

        if showsBoardingRoutine && SchoolResidenceNight.kind(on:yesterday,calendar:calendar) != nil {
            for period in PlannerCampusPeriod.boarding { append(period, anchoredTo: yesterday) }
        }
        let tonight = showsBoardingRoutine ? SchoolResidenceNight.kind(on:day,calendar:calendar) : nil
        // A one-date off-grid trip or partial calendar is not the ordinary bell day.
        let regularDay = hasStandardBells && today.teachingDay != nil && rotationDay == today.teachingDay
        if regularDay {
            append(.block9, anchoredTo: day)
            append(.block10, anchoredTo: day)
        }
        if regularDay || tonight == .returning {
            append(.dinner, anchoredTo: day)
        }
        if tonight != nil {
            for period in PlannerCampusPeriod.boarding { append(period, anchoredTo: day) }
        }
        return .init(rotationDay: rotationDay, hasTimetable: hasTimetable, hasCalendar: hasCalendar,
                     entries: entries + extra, hasStandardBells: hasStandardBells)
    }
}
