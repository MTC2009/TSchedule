import Foundation

extension AppModel {
    /// Offline authority applies to this one device document, never to plans, grades, or a
    /// school request. A website that might have switched students must be reverified first.
    var localSchoolTimetable: SchoolTimetable? {
        guard school.selected, schoolContentVisible, !portalPresented, !portal.manualSheet,
              school.identityIssue != .changed, let book = timetable.visible,
              school.owner == nil || school.owner == book.owner else { return nil }
        return book
    }

    func schoolTimetableDay(_ date: Date) -> SchoolTimetable.Day? {
        guard let book = localSchoolTimetable, let calendar = PublishedSchoolCalendar.bundledHS else { return nil }
        return book.day(on: date, calendar: calendar)
    }

    func updateSchoolTimetable(manual: Bool) async {
        guard school.selected, portal.foreground, !portal.manualSheet, !portalPresented,
              !timetableCheckingSession else { return }
        guard schoolNetworkAvailable else {
            if manual { timetable.reportOffline() }
            return
        }
        // Pressing Update can recheck existing cookies after an outage. It never claims a
        // password or opens the full website, and a change of student cancels this intent.
        let originalOwner = localSchoolTimetable?.owner
        let needsCheck = manual && school.owner == nil
        if needsCheck { timetableCheckingSession = true }
        defer { if needsCheck { timetableCheckingSession = false } }
        if needsCheck, school.identityIssue?.permitsIdentityRecheck != false {
            await retrySchoolIdentity()
            let deadline = ContinuousClock.now.advanced(by: .seconds(10))
            while school.owner == nil, portal.foreground, !portalPresented, !portal.manualSheet,
                  portal.loading || portal.webView.isLoading || school.pending.contains(.identity) || school.identityIssue == .notReady,
                  ContinuousClock.now < deadline {
                do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
            }
        }
        guard !Task.isCancelled, portal.foreground, !portalPresented, !portal.manualSheet else { return }
        guard let owner = school.owner else {
            if manual { timetable.reportUnverified(school.identityIssue) }
            return
        }
        // If rechecking instead confirmed a different student, only their own first-use
        // import is eligible. Never carry a prior owner's forced replacement across.
        let mayForce = manual && !(needsCheck && originalOwner != nil && originalOwner != owner)
        let ticket = school.epoch
        func current() -> Bool {
            school.selected && portal.foreground && !portal.manualSheet && !portalPresented &&
                school.epoch == ticket && school.owner == owner
        }
        timetable.verified(owner)
        let before = timetable.visible?.savedAt
        await timetable.update(for: owner, calendar: .bundledHS, now: now, manual: mayForce, current: current) { date in
            try await self.school.readTimetableWeek(date, for: owner)
        }
        // A replacement can change lesson times without changing the published calendar.
        if current(), manual || before != timetable.visible?.savedAt { await refreshPlanReminders() }
    }
}
