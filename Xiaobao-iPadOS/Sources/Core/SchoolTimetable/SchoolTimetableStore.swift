import Foundation
import Observation

/// A single, revocable, device-local document. The registration is deliberately separate
/// from the protected file: logout still makes it unreachable if iPadOS has locked the file.
@MainActor @Observable final class SchoolTimetableStore {
    typealias Read = @MainActor (Date) async throws -> SchoolPortalWeek
    private struct Archive: Codable { let version: Int, registration: UUID, timetable: SchoolTimetable }
    private let file: URL
    private let defaults: UserDefaults
    private enum Key {
        static let registration = "tschedule.timetable.v1.registration"
        static let review = "tschedule.timetable.v1.review"
        static let attempted = "tschedule.timetable.v1.importOwner"
        static let lessonOptIn = "tschedule.timetable.v1.lessonOptIn"
        static let lessonLead = "tschedule.timetable.v1.lessonLead"
    }
    private var saved: SchoolTimetable?
    private var review: Bool
    private var optedInRegistration: String?
    private(set) var lessonLead: Int
    private var ticket = UUID()
    private var runningOwner: String?
    private(set) var busy = false
    private(set) var message: String?
    var visible: SchoolTimetable? { review ? nil : saved }
    var isReviewingAccount: Bool { review }
    var reminderRegistration: String? { visible == nil ? nil : defaults.string(forKey: Key.registration) }
    var lessonRemindersEnabled: Bool {
        guard let registration = reminderRegistration else { return false }
        return registration == optedInRegistration
    }

    /// An OS permission prompt may outlive the account/timetable it was opened for.
    @discardableResult func setLessonReminders(_ enabled: Bool, registration: String) -> Bool {
        guard registration == reminderRegistration else { return false }
        optedInRegistration = enabled ? registration : nil
        defaults.set(optedInRegistration, forKey: Key.lessonOptIn)
        return true
    }

    func setLessonLead(_ value: Int) {
        guard lessonRemindersEnabled, SchoolLessonReminder.leads.contains(value) else { return }
        lessonLead = value
        defaults.set(value, forKey: Key.lessonLead)
    }

    init(file: URL, defaults: UserDefaults = .standard) {
        self.file = file; self.defaults = defaults
        review = defaults.bool(forKey: Key.review)
        optedInRegistration = defaults.string(forKey: Key.lessonOptIn)
        let lead = defaults.object(forKey: Key.lessonLead) as? Int
        lessonLead = lead.flatMap { SchoolLessonReminder.leads.contains($0) ? $0 : nil } ?? 5
        restore()
    }

    func restore() {
        guard saved == nil else { return }
        guard let id = defaults.string(forKey: Key.registration) else {
            // Finish a deferred revocation once protected data becomes available.
            if FileManager.default.fileExists(atPath: file.path) { try? FileManager.default.removeItem(at: file) }
            return
        }
        let data: Data
        do { data = try Data(contentsOf: file) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            // A restored device may have preferences but not this deliberately unbacked-up
            // file. Treat a genuinely absent document as first use, not a locked file.
            defaults.removeObject(forKey: Key.registration); defaults.removeObject(forKey: Key.attempted)
            return
        } catch { return }
        guard data.count <= 4_000_000, let archive = try? PropertyListDecoder().decode(Archive.self, from: data),
              archive.version == 1, archive.registration.uuidString == id else { return }
        saved = archive.timetable
    }

    func reportUnverified(_ issue: SchoolPortalIssue?) {
        let needsLogin = issue.map { !$0.permitsIdentityRecheck } ?? false
        message = (needsLogin ? "请先在完整校宝确认本人登录，再更新课表。" : "暂时无法确认校宝登录，请联网后重试。")
            + (visible == nil ? "" : " 已保留上次的课表。")
    }

    func reviewAccount() {
        cancel(); review = true; message = nil
        defaults.set(true, forKey: Key.review)
    }

    func verified(_ owner: String) {
        if let previous = runningOwner ?? saved?.owner ?? defaults.string(forKey: Key.attempted), previous != owner { forget() }
        if review { review = false; defaults.removeObject(forKey: Key.review) }
    }

    func cancel() { ticket = UUID(); busy = false; runningOwner = nil }

    func forget() {
        cancel(); saved = nil; message = nil; review = false; optedInRegistration = nil; lessonLead = 5
        for key in [Key.registration, Key.review, Key.attempted, Key.lessonOptIn, Key.lessonLead] {
            defaults.removeObject(forKey: key)
        }
        if FileManager.default.fileExists(atPath: file.path) { try? FileManager.default.removeItem(at: file) }
    }

    func update(for owner: String, calendar: PublishedSchoolCalendar?, now: Date, manual: Bool,
                current: @MainActor () -> Bool, read: Read) async {
        guard current(), !Task.isCancelled, !review else { return }
        verified(owner)
        guard !busy else { return }
        guard manual || (saved == nil && defaults.string(forKey: Key.attempted) != owner) else { return }
        let id = UUID(); ticket = id; busy = true; runningOwner = owner; message = nil
        defer { if ticket == id { busy = false; runningOwner = nil } }
        func valid() -> Bool { ticket == id && !Task.isCancelled && !review && current() }
        guard let calendar, (calendar.from...calendar.through).contains(SchoolClock.key(now)) else {
            message = "还没有适用于当前学年的高中校历。" + (saved == nil ? "" : " 已保留上次的课表。")
            return // No school read occurred; a future matching publication can serve first use.
        }
        do {
            let dates = SchoolTimetable.sampleWeeks(near: now, calendar: calendar)
            var next = SchoolTimetable(owner: owner, calendar: calendar, now: now)
            var interruptedFirstImport = false
            for date in dates {
                guard valid() else { return }
                let week: SchoolPortalWeek
                do { week = try await read(date) }
                catch let issue as SchoolPortalIssue where (issue == .network || issue == .unavailable)
                    && saved == nil && !next.dated.isEmpty {
                    // A later week was unreachable. Keep already verified first-use evidence,
                    // explicitly marked partial. A replacement never patches a failed read.
                    interruptedFirstImport = true
                    break
                }
                guard valid() else { return }
                try next.absorb(week, calendar: calendar)
                if next.rotations.count == 6 { break }
            }
            guard valid() else { return }
            guard next.canReplace(saved) else {
                message = saved == nil ? "校宝还没有足够的课程资料。可稍后在设置中更新。" : "新资料不完整，已保留上次的课表。"
                defaults.set(owner, forKey: Key.attempted)
                return
            }
            // Preserve the registration on same-account atomic replacement: a power loss
            // after the rename cannot strand a successfully saved previous registration.
            let registration = saved?.owner == owner
                ? (defaults.string(forKey: Key.registration).flatMap(UUID.init(uuidString:)) ?? UUID()) : UUID()
            let bytes = try PropertyListEncoder().encode(Archive(version: 1, registration: registration, timetable: next))
            guard bytes.count <= 4_000_000 else { throw SchoolPortalIssue.format }
            var dir = file.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            #if os(iOS)
            var flags = URLResourceValues(); flags.isExcludedFromBackup = true
            try dir.setResourceValues(flags)
            try bytes.write(to: file, options: [.atomic, .completeFileProtection])
            #else
            try bytes.write(to: file, options: .atomic)
            #endif
            defaults.set(registration.uuidString, forKey: Key.registration)
            defaults.set(owner, forKey: Key.attempted)
            saved = next
            if interruptedFirstImport { message = "部分教学周未能读取，已保留可以确认的日期。请在设置中更新。" }
            else if next.rotations.count < 6 { message = "已保存能确认的课表；未确认的轮转日不会推算。" }
        } catch {
            guard valid() else { return }
            defaults.set(owner, forKey: Key.attempted)
            let reason = (error as? SchoolPortalIssue)?.message ?? "暂时无法保存课表。"
            message = reason + (saved == nil ? " 请在设置中重试。" : " 已保留上次的课表。")
        }
    }
}
