import Foundation

struct TimetablePlanScope: Hashable {
    let owner: PlanOwner
    let session: UUID?

    @MainActor init?(_ model: AppModel) {
        guard let owner = model.activePlanOwner else { return nil }
        if model.school.selected {
            guard model.schoolContentVisible, !model.portalPresented, !model.portal.manualSheet,
                  !model.timetable.isReviewingAccount else { return nil }
        }
        self.owner = owner
        session = model.school.selected ? model.school.epoch : model.campus.account?.scope
    }
}

/// Read-only inputs from the same school cache used by the native timetable.
/// The bundled publication is scoped to this student's Main Campus HS calendar.
@MainActor
struct PlannerSchoolSource {
    typealias DayInput = (school: PlannerSchoolDay, calendarDay: SchoolCalendarDay?, usesDaytimeRotation: Bool, studyTimePending: Bool)
    let model: AppModel
    let dates: [Date]

    var publication: PublishedSchoolCalendar? {
        if model.school.selected { return model.localSchoolTimetable == nil ? nil : .bundledHS }
        guard model.usesLocalTimetable || model.campus.account != nil else { return nil }
        return .bundledHS
    }

    var calendarPage: CampusPage? {
        guard let first = dates.first, let last = dates.last else { return nil }
        return .calendar(SchoolClock.key(first), SchoolClock.key(last))
    }

    func column(on date: Date, records: PlanStore.Day?, showsPlans: Bool, editing: Bool) -> PlannerTimelineColumn {
        let input = schoolDay(on: date)
        let display = TimetablePresentation(on: date, school: input.school, plans: records?.plans ?? [], settings: model.personalization,
                                            editingPersonalCourses: editing)
        let day = PlannerDay(on: date, school: display.school, plans: display.plans.filter { showsPlans || $0.courseKind != nil })
        let focus = PlannerDay(on: date, school: display.school, plans: display.plans.filter { $0.courseKind != nil }).focus(at: model.now)
        return .init(day: day, placementDay: PlannerDay(on: date, school: display.placementSchool, plans: []),
                     school: display.school, calendarDay: input.calendarDay, usesDaytimeRotation: input.usesDaytimeRotation,
                     studyTimePending: input.studyTimePending && model.personalization.shows(.tssa),
                     recurringIDs: records?.recurringIDs ?? [], focus: focus)
    }

    func schoolDay(on date: Date) -> DayInput {
        let input = baseSchoolDay(on: date)
        // A service account must own the matching publication. The month picker's
        // legacy display fallback is not evidence of a school or of boarding nights.
        let routineCalendar = model.school.selected || model.usesLocalTimetable ? publication : model.campus.cachedSchoolCalendar
        guard let routineCalendar, let row = input.calendarDay else { return input }
        let published = routineCalendar.day(on: date)
        guard row.date == published.date, row.status == published.status, row.teachingDay == published.teachingDay else { return input }
        return (input.school.withCampusRoutine(on: date, calendar: routineCalendar,
                    showsBoardingRoutine: model.personalization.showsBoardingRoutine), row, input.usesDaytimeRotation, input.studyTimePending)
    }

    private func baseSchoolDay(on date: Date) -> DayInput {
        if model.school.selected {
            let day = model.schoolTimetableDay(date)
            return (.connected(on: date, schedule: day?.schedule, calendar: day?.events) { $0 }, day?.calendarDay, day?.usesDaytimeRotation == true, day?.studyTimePending == true)
        }
        if model.usesLocalTimetable {
            let school = PlannerSchoolDay.local(on: date, provider: model.provider, work: StudentServices.work(on: date))
            return (school, model.provider.schoolCalendar.publishedDay(on: date), false, false)
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
            courses[$0] ?? String(localized: "课程名称待载入")
        }
        return (school, schedule?.calendarDay ?? publication?.day(on: date), false, false)
    }

    func load(selected date: Date, force: Bool = false) async {
        if model.school.selected { return } // The two timetable views only render the saved academic year.
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
