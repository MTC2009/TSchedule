import Foundation

extension AppModel {
    /// The visible page gets the first read. Prime only overview lists, one at a time;
    /// never prefetch GPA, historical terms, attachments or a course's details.
    func warmSchoolPages() async {
        let epoch = school.epoch
        guard let owner = school.owner else { return }
        @MainActor func current() -> Bool {
            !Task.isCancelled && portal.foreground && !portalPresented && !portal.manualSheet &&
            school.selected && school.owner == owner && school.epoch == epoch
        }
        let visible = tab
        if visible == .grades {
            // Let the deliberate visit issue its GPA read before any secondary requests.
            let deadline = ContinuousClock.now.advanced(by: .milliseconds(700))
            while current(), ContinuousClock.now < deadline, !school.pending.contains(school.gradeRead),
                  school.grades == nil, school.issues[school.gradeRead] == nil, tab == .grades {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            }
        }
        for page in [visible] + [.today, .tasks, .attendance, .otherItems].filter({ $0 != visible }) {
            guard current() else { return }
            switch page {
            case .today, .planner: if school.issues[SchoolPortalStore.weekKey(now)] == nil { await school.loadWeek(now) }
            case .tasks: if school.issues[school.taskRead] == nil { await school.loadTasks() }
            case .attendance:
                if school.attendanceQuery == nil { await school.loadAttendance(.init()) }
            case .otherItems:
                let first = otherItemsSection.collection
                for group in [first] + SchoolPortalCollection.allCases.filter({ $0 != first }) {
                    guard current() else { return }
                    if school.issues[.collection(group)] == nil { await school.loadCollection(group) }
                }
            case .grades, .settings: break
            }
        }
    }
}
