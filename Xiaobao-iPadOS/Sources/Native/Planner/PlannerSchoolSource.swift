import Foundation

/// Read-only inputs from the same school cache used by the native timetable.
/// The bundled publication is scoped to this student's Main Campus HS calendar.
@MainActor
struct PlannerSchoolSource {
    let model: AppModel
    let dates: [Date]

    var publication: PublishedSchoolCalendar? {
        guard !model.school.selected, model.usesLocalTimetable || model.campus.account != nil else { return nil }
        return .bundledHS
    }

    var calendarPage: CampusPage? {
        guard let first = dates.first, let last = dates.last else { return nil }
        return .calendar(SchoolClock.key(first), SchoolClock.key(last))
    }

    func column(on date: Date, records: PlanStore.Day?) -> PlannerTimelineColumn {
        let input = schoolDay(on: date)
        let day = PlannerDay(on: date, school: input.school, plans: records?.plans ?? [])
        let focus = PlannerDay(on: date, school: input.school, plans: []).focus(at: model.now)
        return .init(day: day, school: input.school, calendarDay: input.calendarDay,
                     weeklyIDs: records?.weeklyIDs ?? [], focus: focus)
    }

    func schoolDay(on date: Date) -> (school: PlannerSchoolDay, calendarDay: SchoolCalendarDay?) {
        if model.school.selected {
            let week = model.school.week(on: date)
            return (.connected(on: date, schedule: week?.schedule(on: date), calendar: week?.calendar) {
                week?.names[$0] ?? "课程"
            }, nil)
        }
        if model.usesLocalTimetable {
            let school = PlannerSchoolDay.local(on: date, provider: model.provider, work: StudentServices.work(on: date))
            return (school, model.provider.schoolCalendar.publishedDay(on: date))
        }

        let schedule = model.campus.cachedSchedule(on: date)
        let pages = model.campus.pages
        let key = SchoolClock.key(date)
        let calendar: CampusCalendar? = if let calendarPage, case .calendar(let content) = pages[calendarPage]?.content { content }
            else if case .calendar(let content) = pages[.calendar(key, key)]?.content { content }
            else { nil }
        let courses: [String: String] = if case .courses(let values) = pages[.courses]?.content {
            Dictionary(values.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        } else { [:] }
        let school = PlannerSchoolDay.connected(on: date, schedule: schedule, calendar: calendar) {
            courses[$0] ?? "课程名称待载入"
        }
        return (school, schedule?.calendarDay ?? publication?.day(on: date))
    }

    func load(selected date: Date, force: Bool = false) async {
        if model.school.selected { await model.school.loadWeek(date, force: force); return }
        let client = model.campus
        guard let scope = client.account?.scope, let calendarPage else { return }
        async let courses: Void = client.load(.courses)
        async let focused: Void = client.load(.schedule(SchoolClock.key(date)), force: force)
        await client.load(calendarPage, force: force)
        _ = await (courses, focused)
        // Modern snapshots derive all seven days from one timetable. Fetch the
        // missing days only for legacy services that did not publish that snapshot.
        for day in dates where client.cachedSchedule(on: day) == nil && day != date {
            guard !Task.isCancelled, client.account?.scope == scope else { return }
            await client.load(.schedule(SchoolClock.key(day)))
        }
    }
}
