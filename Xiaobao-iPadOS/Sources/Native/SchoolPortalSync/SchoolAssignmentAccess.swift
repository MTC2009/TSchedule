import Foundation

extension AppModel {
    /// A network outage may reveal this device's last confirmed registration. A pending
    /// identity, open account sheet, explicit refusal or different student may not.
    var canDisplaySavedAssignments: Bool {
        guard school.selected, timetableForeground, portal.foreground, !portalPresented, !portal.manualSheet,
              !assignments.reviewing, let savedOwner = assignments.owner else { return false }
        if let owner = school.owner { return owner == savedOwner && school.issues[school.taskRead] != .denied }
        return school.identityIssue == .network
    }

    func clearSavedAssignments() {
        notifications.requireAssignmentRemoval()
        school.discardTaskLists()
        assignments.forget()
    }

    func configureAssignmentAlerts(enabled: Bool, titles: Bool) async -> String? {
        guard canDisplaySavedAssignments, let registration = assignments.registration else {
            return String(localized: "请先同步作业清单。")
        }
        if enabled && !assignments.enabled {
            guard await notifications.requestPermission() else { return notifications.status }
        }
        let hidePreviouslyNamedAlerts = assignments.showsTitles && !titles
        guard school.selected, !portal.manualSheet, !portalPresented, assignments.registration == registration,
              assignments.configure(enabled: enabled, titles: titles, registration: registration) else {
            return String(localized: "未能保存作业提醒设置。")
        }
        if !enabled || hidePreviouslyNamedAlerts { await notifications.requireAssignmentRemoval().value }
        await refreshPlanReminders()
        return nil
    }
}
