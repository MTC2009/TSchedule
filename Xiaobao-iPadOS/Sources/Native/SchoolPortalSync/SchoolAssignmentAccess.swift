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
        stopTaskMaterials()
        notifications.requireAssignmentRemoval()
        school.discardTaskLists()
        assignments.forget()
    }

    func stopTaskMaterials() {
        materialQueue?.cancel(); materialQueue = nil
        for flight in materialReads.values { flight.read.cancel() }
        materialReads.removeAll()
    }

    /// A saved registration cannot authorize a network request. A deliberate visit joins
    /// an in-flight read for that row, or starts one immediately ahead of the idle queue.
    func readMaterial(_ key: SchoolAssignmentStore.MaterialKey) async throws -> SchoolTaskMaterial {
        let epoch = school.epoch
        func current() -> Bool {
            canDisplaySavedAssignments && school.owner == assignments.owner && school.owner != nil &&
            school.epoch == epoch && school.tasks?.termLabel?.id == key.term &&
            assignments.materialKey(term:key.term,task:key.task) == key
        }
        guard current() else { throw SchoolPortalIssue.notReady }
        if let active = materialReads[key], active.epoch == epoch { return try await active.read.value }
        let id = UUID()
        let read = Task { @MainActor in
            do {
                let value = try await school.readTaskMaterial(term:key.term,task:key.task)
                try Task.checkCancellation()
                guard current() else { throw CancellationError() }
                // A full device must not hide a successfully read online detail.
                try? assignments.saveMaterial(value,for:key)
                return value
            } catch {
                if current(), let issue = error as? SchoolPortalIssue, issue == .denied || issue == .unavailable {
                    assignments.removeMaterial(key)
                }
                throw error
            }
        }
        materialReads[key] = (id,epoch,read)
        defer { if materialReads[key]?.id == id { materialReads[key] = nil } }
        return try await read.value
    }

    func warmTaskMaterials(in term: String) {
        materialQueue?.cancel()
        let epoch = school.epoch, keys = assignments.materialKeys(term:term)
        guard !keys.isEmpty else { return }
        materialQueue = Task(priority:.utility) { @MainActor [weak self] in
            // No timer polling: one bounded walk after a complete list for the selected term.
            for key in keys {
                guard let self, !Task.isCancelled, self.school.epoch == epoch, self.canDisplaySavedAssignments,
                      self.school.tasks?.termLabel?.id == term else { return }
                if self.assignments.materialIsRecent(key) { continue }
                do {
                    try await Task.sleep(for:.seconds(2))
                    _ = try await self.readMaterial(key)
                } catch let issue as SchoolPortalIssue where issue == .denied || issue == .unavailable || issue == .format {
                    continue // An inaccessible item doesn't make the other student's own items empty.
                } catch { return } // Never retry an expired session, outage or cancellation in a loop.
            }
        }
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
