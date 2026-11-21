import Foundation

/// Projects the published HS school days onto a Monday-first month grid. No
/// event text, weekend tint, or blank publication is taken as a closure rule.
struct PlannerCalendarMonth {
    static let selectableDates = SchoolClock.date(2000, 1, 1)...SchoolClock.date(2100, 12, 31)

    struct Notice: Identifiable, Equatable {
        var id: String { title }
        let title: String
        let first, last: Date
        let isClosed: Bool
    }

    let first: Date
    let cells: [Date?]
    private let publication: PublishedSchoolCalendar?

    init(containing date: Date, publication: PublishedSchoolCalendar?) {
        let calendar = SchoolClock.calendar
        let first = calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
        self.first = first
        let weekday = calendar.component(.weekday, from: first)
        let leading = (weekday + 5) % 7
        let count = calendar.range(of: .day, in: .month, for: first)?.count ?? 0
        let trailing = (7 - (leading + count) % 7) % 7
        cells = Array(repeating: nil, count: leading) + (0..<count).map { calendar.date(byAdding: .day, value: $0, to: first) }
            + Array(repeating: nil, count: trailing)
        self.publication = publication?.campus == "main" && publication?.division == "HS" ? publication : nil
    }

    func schoolDay(_ date: Date) -> SchoolCalendarDay? { publication?.day(on: date) }

    func notices(on date: Date) -> [Notice] {
        guard let publication, let daily = schoolDay(date) else { return [] }
        let day = SchoolClock.calendar.startOfDay(for: date)
        let closed = daily.status == .noClass
        let titles = daily.notices.isEmpty && closed ? ["不上课"] : daily.notices
        return titles.map { title in
            let first = edge(of: title, on: day, step: -1, publication: publication, closed: closed)
            let last = edge(of: title, on: day, step: 1, publication: publication, closed: closed)
            return Notice(title: title, first: first, last: last, isClosed: closed)
        }
    }

    private func edge(of title: String, on date: Date, step: Int,
                      publication: PublishedSchoolCalendar, closed: Bool) -> Date {
        var result = date
        while let next = SchoolClock.calendar.date(byAdding: .day, value: step, to: result) {
            let day = publication.day(on: next)
            guard day.status != .unpublished, (day.status == .noClass) == closed, day.notices.contains(title) else { break }
            result = next
        }
        return result
    }
}
