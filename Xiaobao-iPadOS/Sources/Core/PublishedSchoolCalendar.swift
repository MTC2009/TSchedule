import Foundation

struct SchoolCalendarDay: Codable, Equatable, Sendable {
    enum Status: String, Codable, Sendable {
        case teaching, noClass = "no_class", weekend, unpublished
    }

    let date: String
    /// The campus's printed Day, even when this division has no classes.
    let day: Int?
    let status: Status
    let notices: [String]

    var teachingDay: Int? { status == .teaching ? day : nil }

    func isValid(cycleLength: Int) -> Bool {
        if let day, !(1...max(1, cycleLength)).contains(day) { return false }
        switch status {
        case .teaching: return day != nil
        case .noClass: return true
        case .weekend, .unpublished: return day == nil
        }
    }

    static func unpublished(on key: String) -> Self {
        .init(date: key, day: nil, status: .unpublished, notices: [])
    }
}

/// An explicit, bounded calendar is authoritative over rotation arithmetic.
/// An absent publication still allows a legacy source's rotation to be used.
struct PublishedSchoolCalendar: Codable, Sendable {
    let campus, academicYear, division, from, through, sourceSHA256: String
    let days: [SchoolCalendarDay]
    private let byDate: [String: SchoolCalendarDay]

    private enum CodingKeys: String, CodingKey {
        case campus, division, from, through, days
        case academicYear = "academic_year", sourceSHA256 = "source_sha256"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        campus = try values.decode(String.self, forKey: .campus)
        academicYear = try values.decode(String.self, forKey: .academicYear)
        division = try values.decode(String.self, forKey: .division)
        from = try values.decode(String.self, forKey: .from)
        through = try values.decode(String.self, forKey: .through)
        sourceSHA256 = try values.decode(String.self, forKey: .sourceSHA256)
        days = try values.decode([SchoolCalendarDay].self, forKey: .days)
        let calendar = SchoolClock.calendar
        guard let first = SchoolClock.dayDate(from), let last = SchoolClock.dayDate(through),
              let span = calendar.dateComponents([.day], from: first, to: last).day,
              (0..<366).contains(span), days.count == span + 1,
              days.enumerated().allSatisfy({ offset, row in
                  let date = calendar.date(byAdding: .day, value: offset, to: first)
                  return date.map(SchoolClock.key) == row.date && row.isValid(cycleLength: 255)
              }) else {
            throw DecodingError.dataCorruptedError(forKey: .days, in: values,
                                                   debugDescription: "Invalid published calendar dates or Day.")
        }
        byDate = Dictionary(uniqueKeysWithValues: days.map { ($0.date, $0) })
    }

    func day(on date: Date) -> SchoolCalendarDay {
        let key = SchoolClock.key(date)
        return byDate[key] ?? .unpublished(on: key)
    }

    func isCompatible(cycleLength: Int) -> Bool { days.allSatisfy { $0.isValid(cycleLength: cycleLength) } }

    static let bundledHS: Self? = {
        guard let url = Bundle.main.url(forResource: "academic-calendar-hs-2026-2027", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let calendar = try? JSONDecoder().decode(Self.self, from: data),
              calendar.campus == "main", calendar.division == "HS",
              calendar.isCompatible(cycleLength: 6) else { return nil }
        return calendar
    }()
}
