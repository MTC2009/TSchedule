import Foundation

enum PlanOwner: Codable, Hashable, Sendable {
    case local
    // Session IDs rotate on re-login. A service's profile is stable only within its origin.
    case campus(origin: URL, profile: String)
}

/// Private, on-device user records. Never put them in the refreshable school cache.
actor PlanStore {
    enum StoreError: Error { case invalidArchive, invalidPlan, alreadyExists, missingPlan, historyUnavailable }
    enum RemovalScope: Sendable { case onlyThis, thisAndLater }

    enum Mutation: Sendable {
        case save(PlanEdit)
        case place(PlanPlacementItem, on: String, at: PlanTime?, now: Date)
        case complete(Bool, plan: PersonalPlan)
        case remove(PersonalPlan, RemovalScope)
    }

    struct EditorState: Sendable {
        let schedule: Schedule
        let canUndo, canRedo: Bool
    }

    struct Day: Sendable {
        let plans: [PersonalPlan]
        let bubbles: [PlanBubble]
        let recurringIDs: Set<UUID>
    }

    struct Schedule: Codable, Equatable, Sendable {
        var plans: [PersonalPlan] = []
        var bubbles: [PlanBubble] = []

        var isValid: Bool {
            let ids = plans.map(\.id) + bubbles.map(\.id)
            return plans.allSatisfy(\.isValid) && bubbles.allSatisfy(\.isValid) && Set(ids).count == ids.count
        }

        func day(_ key: String, calendar: PublishedSchoolCalendar? = nil) -> Day {
            let occurrences = bubbles.compactMap { $0.occurrence(on: key, calendar: calendar) }
            return Day(plans: plans.filter { $0.day == key } + occurrences,
                       bubbles: bubbles, recurringIDs: Set(occurrences.map(\.id)))
        }
    }

    private struct Archive: Codable {
        var owners: [PlanOwner: Schedule]
    }

    private let file: URL
    private var archive: Archive?
    private struct EditScope: Equatable { let owner: PlanOwner; let session: UUID }
    private var editScope: EditScope?
    private var history = PlanEditHistory()

    init(file: URL) { self.file = file }

    func read(day: String, for owner: PlanOwner, calendar: PublishedSchoolCalendar? = nil) throws -> [PersonalPlan] {
        try readDay(day, for: owner, calendar: calendar).plans
    }

    func readDay(_ day: String, for owner: PlanOwner, calendar: PublishedSchoolCalendar? = nil) throws -> Day {
        try readSchedule(for: owner).day(day, calendar: calendar)
    }

    func readSchedule(for owner: PlanOwner) throws -> Schedule {
        try readArchive().owners[owner] ?? Schedule()
    }

    func readEditor(for owner: PlanOwner, session: UUID) throws -> EditorState {
        let schedule = try readSchedule(for: owner)
        let isCurrent = editScope == EditScope(owner: owner, session: session)
        return EditorState(schedule: schedule, canUndo: isCurrent && history.canUndo, canRedo: isCurrent && history.canRedo)
    }

    func apply(_ command: Mutation, for owner: PlanOwner, session: UUID,
               calendar: PublishedSchoolCalendar? = nil) throws -> EditorState {
        _ = try change(for: owner, session: session) { schedule in
            switch command {
            case .save(let edit): try Self.save(edit, in: &schedule)
            case let .place(item, day, time, now): try Self.place(item, on: day, at: time, now: now, calendar: calendar, in: &schedule)
            case let .complete(value, plan): try Self.complete(value, plan: plan, calendar: calendar, in: &schedule)
            case let .remove(plan, scope): try Self.remove(plan, scope: scope, calendar: calendar, in: &schedule)
            }
        }
        return try readEditor(for: owner, session: session)
    }

    func step(_ direction: PlanEditHistory.Direction, for owner: PlanOwner, session: UUID) throws -> EditorState {
        guard editScope == EditScope(owner: owner, session: session) else { throw StoreError.historyUnavailable }
        var current = try readArchive()
        var next = history
        guard let restored = next.step(direction, from: current.owners[owner] ?? Schedule()) else {
            throw StoreError.historyUnavailable
        }
        current.owners[owner] = restored
        try write(current)
        history = next
        return EditorState(schedule: restored, canUndo: next.canUndo, canRedo: next.canRedo)
    }

    func create(_ plan: PersonalPlan, for owner: PlanOwner) throws -> [PersonalPlan] {
        try save(PlanEdit(target: .create, plan: plan, reusable: false, recurrence: nil,
                          effectiveDay: plan.day), for: owner).plans
    }

    func update(_ plan: PersonalPlan, for owner: PlanOwner) throws -> [PersonalPlan] {
        try save(PlanEdit(target: .plan(plan.id), plan: plan, reusable: false, recurrence: nil,
                          effectiveDay: plan.day), for: owner).plans
    }

    /// Record edits, template edits, and template + first placement are atomic.
    func save(_ edit: PlanEdit, for owner: PlanOwner, calendar: PublishedSchoolCalendar? = nil) throws -> Day {
        try change(for: owner) { try Self.save(edit, in: &$0) }.day(edit.plan.day, calendar: calendar)
    }

    private static func save(_ edit: PlanEdit, in schedule: inout Schedule) throws {
        let plan = edit.plan
        guard plan.isValid, SchoolClock.dayDate(edit.effectiveDay) != nil,
              edit.recurrence.map({ $0.isValid && plan.time != nil }) ?? true else { throw StoreError.invalidPlan }
        switch edit.target {
        case .create:
            guard !schedule.plans.contains(where: { $0.id == plan.id }),
                  !schedule.bubbles.contains(where: { $0.id == plan.id }) else { throw StoreError.alreadyExists }
            if edit.reusable || edit.recurrence != nil {
                var prototype = plan
                prototype.isCompleted = false
                var bubble = PlanBubble(prototype: prototype, reusable: edit.reusable)
                bubble.revise(recurrence: edit.recurrence, effectiveDay: edit.effectiveDay)
                schedule.bubbles.append(bubble)
                if edit.recurrence == nil, let time = plan.time, let initial = bubble.copy(on: plan.day, at: time) {
                    schedule.plans.append(initial)
                }
            } else {
                schedule.plans.append(plan)
            }
        case .plan(let id):
            guard id == plan.id, !edit.reusable, edit.recurrence == nil,
                  let index = schedule.plans.firstIndex(where: { $0.id == id && $0.day == plan.day }) else {
                throw StoreError.missingPlan
            }
            var updated = plan
            // Editing the content must not undo a more recent completion change.
            updated.isCompleted = schedule.plans[index].isCompleted
            schedule.plans[index] = updated
        case .bubble(let id):
            guard id == plan.id, let index = schedule.bubbles.firstIndex(where: { $0.id == id }) else {
                throw StoreError.missingPlan
            }
            var bubble = schedule.bubbles[index]
            var prototype = plan
            prototype.isCompleted = false
            bubble.prototype = prototype
            bubble.reusable = edit.reusable
            let effective = max(edit.effectiveDay, bubble.revisions.first?.effectiveDay ?? edit.effectiveDay)
            bubble.revise(recurrence: edit.recurrence, effectiveDay: effective)
            schedule.bubbles[index] = bubble
        }
    }

    func placeBubble(_ id: UUID, on day: String, at time: PlanTime, for owner: PlanOwner,
                     calendar: PublishedSchoolCalendar? = nil) throws -> Day {
        try change(for: owner) { schedule in
            guard let bubble = schedule.bubbles.first(where: { $0.id == id && $0.reusable && $0.latest?.rule == nil }),
                  let instance = bubble.copy(on: day, at: time) else { throw StoreError.missingPlan }
            schedule.plans.append(instance)
        }.day(day, calendar: calendar)
    }

    private static func place(_ item: PlanPlacementItem, on day: String, at time: PlanTime?, now: Date,
                              calendar: PublishedSchoolCalendar?, in schedule: inout Schedule) throws {
        guard let date = SchoolClock.dayDate(day), time?.isValid != false else { throw StoreError.invalidPlan }
        let source = item.plan
        switch item.source {
        case .plan:
            guard let index = schedule.plans.firstIndex(of: source),
                  let placed = source.placing(at: time, on: day) else { throw StoreError.missingPlan }
            schedule.plans[index] = placed
        case .reusableBubble:
            guard let time, let bubble = schedule.bubbles.first(where: {
                $0.prototype == source && $0.reusable && $0.latest?.rule == nil
            }), let placed = bubble.copy(on: day, at: time) else { throw StoreError.missingPlan }
            schedule.plans.append(placed)
        case .recurringBubble, .occurrence:
            guard let time, let index = schedule.bubbles.firstIndex(where: { bubble in
                bubble.id == source.id && bubble.latest?.rule != nil &&
                (item.source == .recurringBubble ? bubble.prototype == source : bubble.occurrence(on: source.day, calendar: calendar) == source)
            }) else { throw StoreError.missingPlan }
            guard schedule.bubbles[index].reschedule(to: date, at: time, now: now, calendar: calendar) else { throw StoreError.invalidPlan }
        }
    }

    func setCompleted(_ completed: Bool, plan: PersonalPlan, for owner: PlanOwner,
                      calendar: PublishedSchoolCalendar? = nil) throws -> [PersonalPlan] {
        try complete(completed, plan: plan, for: owner, calendar: calendar).plans
    }

    func complete(_ completed: Bool, plan: PersonalPlan, for owner: PlanOwner,
                  calendar: PublishedSchoolCalendar? = nil) throws -> Day {
        try change(for: owner) { try Self.complete(completed, plan: plan, calendar: calendar, in: &$0) }.day(plan.day, calendar: calendar)
    }

    private static func complete(_ completed: Bool, plan: PersonalPlan, calendar: PublishedSchoolCalendar?,
                                 in schedule: inout Schedule) throws {
        if let index = schedule.plans.firstIndex(where: { $0.id == plan.id && $0.day == plan.day }) {
            schedule.plans[index].isCompleted = completed
        } else if let index = schedule.bubbles.firstIndex(where: { $0.id == plan.id && $0.occurrence(on: plan.day, calendar: calendar) != nil }) {
            schedule.bubbles[index].setCompleted(completed, on: plan.day)
        } else {
            throw StoreError.missingPlan
        }
    }

    private static func remove(_ plan: PersonalPlan, scope: RemovalScope, calendar: PublishedSchoolCalendar?,
                               in schedule: inout Schedule) throws {
        // Require the exact saved occurrence. A stale editor or another plan with the same
        // title is never a fallback; the owner and edit session are fenced by apply/change.
        if let index = schedule.plans.firstIndex(of: plan) {
            guard scope == .onlyThis else { throw StoreError.invalidPlan }
            schedule.plans.remove(at: index)
            return
        }
        guard let index = schedule.bubbles.firstIndex(where: {
            $0.id == plan.id && $0.occurrence(on: plan.day, calendar: calendar) == plan
        }) else { throw StoreError.missingPlan }
        switch scope {
        case .onlyThis: schedule.bubbles[index].excludeOccurrence(on: plan.day)
        case .thisAndLater: schedule.bubbles[index].revise(recurrence: nil, effectiveDay: plan.day)
        }
    }

    private func readArchive() throws -> Archive {
        if let archive { return archive }
        let bytes: Data
        do { bytes = try Data(contentsOf: file) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return Archive(owners: [:]) }
        let decoder = PropertyListDecoder()
        let decoded: Archive
        if let current = try? decoder.decode(Archive.self, from: bytes) {
            decoded = current
        } else {
            // The previous file was the owner-to-plans map itself. Reading it
            // leaves the bytes untouched until a successful explicit write.
            let previous = try decoder.decode([PlanOwner: [PersonalPlan]].self, from: bytes)
            decoded = Archive(owners: previous.mapValues { Schedule(plans: $0) })
        }
        guard decoded.owners.values.allSatisfy(\.isValid) else { throw StoreError.invalidArchive }
        archive = decoded
        return decoded
    }

    private func change(for owner: PlanOwner, session: UUID? = nil,
                        _ mutate: (inout Schedule) throws -> Void) throws -> Schedule {
        var updated = try readArchive()
        let before = updated.owners[owner] ?? Schedule()
        var schedule = before
        try mutate(&schedule)
        guard schedule.isValid else { throw StoreError.invalidPlan }
        guard schedule != before else { return schedule }
        updated.owners[owner] = schedule
        try write(updated)
        if let session {
            let scope = EditScope(owner: owner, session: session)
            if editScope != scope { history = PlanEditHistory(); editScope = scope }
            history.record(before: before, after: schedule)
        } else if editScope?.owner == owner {
            history = PlanEditHistory()
            editScope = nil
        }
        return schedule
    }

    private func write(_ updated: Archive) throws {
        let bytes = try PropertyListEncoder().encode(updated)
        let directory = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #if os(iOS)
        var protectedDirectory = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try protectedDirectory.setResourceValues(values)
        try bytes.write(to: file, options: [.atomic, .completeFileProtection])
        #else
        try bytes.write(to: file, options: .atomic)
        #endif
        // Only publish after the disk write succeeds. A failed edit leaves the old archive intact.
        archive = updated
    }
}
