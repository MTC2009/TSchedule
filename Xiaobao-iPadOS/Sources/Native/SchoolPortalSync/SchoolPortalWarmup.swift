import Foundation

extension AppModel {
    /// Serve the visible tab first. On cached Today, revalidate the task snapshot before the
    /// grade freshness check; neither a slow GPA nor a slow attendance report delays the other.
    func warmSchoolPages() async {
        let epoch = school.epoch
        guard let owner = school.owner else { return }
        @MainActor func current() -> Bool {
            !Task.isCancelled && portal.foreground && !portalPresented && !portal.manualSheet &&
            school.selected && school.owner == owner && school.epoch == epoch
        }
        let visible = tab
        let refreshFromToday = visible == .today && localSchoolTimetable?.owner == owner && school.selectedTermID == nil
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
            case .today, .planner: break // Display the saved book; the calendar never schedules a school read.
            case .tasks:
                if school.issues[school.taskRead] == nil || refreshFromToday {
                    await school.loadTasks(force: refreshFromToday)
                }
            case .attendance:
                if refreshFromToday, current(), tab == .today {
                    async let grades: Void = school.refreshGradesFromToday()
                    if school.attendanceQuery == nil || school.attendanceQuery == .init() {
                        await school.loadAttendance(.init(), force: true)
                    }
                    await grades
                } else if school.attendanceQuery == nil {
                    await school.loadAttendance(.init())
                }
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
