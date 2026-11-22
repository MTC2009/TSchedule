import Foundation

extension AppModel {
    func refreshReminders() async {
        #if DEBUG && TSCHEDULE_INTERNAL_FIXTURES
        if usesLocalTimetable && preferences.remindersEnabled {
            await notifications.schedule(provider: provider, lead: preferences.reminderLead,
                                         morning: preferences.morningEnabled ? preferences.morningMinute : nil)
        } else {
            await notifications.cancelScheduled()
        }
        #else
        // Upgrades may still have requests queued by a previous version.
        await notifications.cancelScheduled()
        #endif
        await refreshPlanReminders()
    }

    var activePlanOwner: PlanOwner? {
        if school.selected { return school.owner.map { .campus(origin: PortalSession.url, profile: $0) } }
        if let account = campus.account { return .campus(origin: account.origin, profile: account.profile) }
        return usesLocalTimetable ? .local : nil
    }

    /// Projection, editing and notifications must agree on the calendar for the
    /// active owner. This lookup never starts a school read or authorizes a plan.
    var planRotationCalendar: PublishedSchoolCalendar? {
        if school.selected {
            guard let book = localSchoolTimetable, school.owner == book.owner,
                  let calendar = PublishedSchoolCalendar.bundledHS,
                  calendar.academicYear == book.year, calendar.sourceSHA256 == book.calendarDigest else { return nil }
            return calendar
        }
        return usesLocalTimetable ? .bundledHS : campus.cachedSchoolCalendar
    }

    /// Unknown identity during ordinary suspension is not a sign-out. It cannot
    /// authorize reading a plan; it also cannot revoke a previously registered alert.
    enum ReminderAccess: Equatable { case waiting, revoked, verified(PlanOwner) }
    var reminderAccess: ReminderAccess {
        if school.selected {
            if portalPresented || portal.manualSheet || timetable.isReviewingAccount ||
                school.identityIssue?.permitsIdentityRecheck == false { return .revoked }
            guard portal.foreground, timetableForeground else { return .waiting }
            return activePlanOwner.map(ReminderAccess.verified) ?? .waiting
        }
        return activePlanOwner.map(ReminderAccess.verified) ?? .revoked
    }

    func revokeAccountReminders() {
        planReminderRead = UUID(); planReminderOwner = nil; planReminderOwnerKnown = true
        UserDefaults.standard.removeObject(forKey: Self.queuedSchoolOwnerKey)
        notifications.requireRemoval(includingPlans: true)
    }

    // A device-salted comparison value, not a login credential or authority to read plans.
    private static let queuedSchoolOwnerKey = "tschedule.notifications.verifiedSchoolScope"

    func confirmReminderOwner(_ owner: String) {
        if let queued = UserDefaults.standard.string(forKey: Self.queuedSchoolOwnerKey), queued != owner {
            revokeAccountReminders()
        }
    }

    var canEnableSchoolReminders: Bool {
        localSchoolTimetable != nil && timetable.reminderRegistration != nil && reminderAccess != .revoked
    }

    func setSchoolReminders(_ enabled: Bool) async -> String? {
        guard let id = timetable.reminderRegistration else { return String(localized: "请先在设置中更新本机课表。") }
        let epoch = school.epoch
        if enabled {
            guard canEnableSchoolReminders else { return String(localized: "请先确认校宝账号。") }
            guard await notifications.requestPermission() else { return notifications.status }
            // The system permission sheet can leave the scene inactive for one more turn.
            // Recheck the registration and account fence, not the sheet's dismissal animation.
            guard school.selected, !portalPresented, !portal.manualSheet, reminderAccess != .revoked,
                  school.epoch == epoch else { return String(localized: "账号状态已改变，请重新开启。") }
        }
        guard timetable.setLessonReminders(enabled, registration: id) else { return String(localized: "课表已改变，请重试。") }
        if !enabled { await notifications.requireRemoval(includingPlans: false).value }
        await refreshPlanReminders()
        return nil
    }

    func refreshPlanReminders(requestPermission: Bool = false) async {
        if requestPermission, case let .verified(owner) = reminderAccess,
           let snapshot = try? await planStore.readSchedule(for: owner), reminderAccess == .verified(owner),
           !PlanReminderPlanner.make(now: Date(), schedule: snapshot, calendar: planRotationCalendar).isEmpty {
            await notifications.requestPlanPermission()
        }
        let ticket = UUID(); planReminderRead = ticket
        let access = reminderAccess
        if access == .revoked {
            if !planReminderOwnerKnown || planReminderOwner != nil { revokeAccountReminders() }
            await notifications.retryRemovalIfNeeded()
            return
        }
        guard timetableForeground, portal.foreground else { return }
        var plans: [PlannedPlanReminder]?
        if case let .verified(owner) = access {
            if !planReminderOwnerKnown || planReminderOwner != owner {
                let sameOnRelaunch = !planReminderOwnerKnown && school.selected && school.owner != nil &&
                    UserDefaults.standard.string(forKey: Self.queuedSchoolOwnerKey) == school.owner
                planReminderOwnerKnown = true; planReminderOwner = owner
                UserDefaults.standard.set(school.selected ? school.owner : nil, forKey: Self.queuedSchoolOwnerKey)
                if !sameOnRelaunch { await notifications.requireRemoval(includingPlans: true).value }
            }
            guard planReminderRead == ticket, reminderAccess == access else { return }
            let snapshot = try? await planStore.readSchedule(for: owner)
            guard planReminderRead == ticket, reminderAccess == access else { return }
            plans = snapshot.map { PlanReminderPlanner.make(now: Date(), schedule: $0, calendar: planRotationCalendar) }
        } else if localSchoolTimetable == nil && !canDisplaySavedAssignments {
            await notifications.retryRemovalIfNeeded()
            return
        }
        let lessons: [SchoolLessonReminder]
        if timetable.lessonRemindersEnabled, let book = localSchoolTimetable, let calendar = PublishedSchoolCalendar.bundledHS {
            lessons = book.lessonReminders(now: Date(), lead: timetable.lessonLead, calendar: calendar)
        } else { lessons = [] }
        let due: [AssignmentDeadline]? = canDisplaySavedAssignments && !assignments.writeFailed
            ? assignments.deadlines(at: .distantPast, currentTerm: school.terms?.current) : nil
        await notifications.syncDeviceReminders(plans: plans, lessons: lessons, subtitle: personalization.reminderSubtitle, assignments: due)
    }

}
