import Foundation

/// Session-only, owner-scoped reversible changes. An entire series move (or
/// a bubble plus its first placement) is one entry, not one entry per date.
struct PlanEditHistory {
    enum Direction { case undo, redo }

    private struct Entry {
        let before, after: PlanStore.Schedule
    }

    private static let limit = 32
    private var past: [Entry] = []
    private var future: [Entry] = []

    var canUndo: Bool { !past.isEmpty }
    var canRedo: Bool { !future.isEmpty }

    mutating func record(before: PlanStore.Schedule, after: PlanStore.Schedule) {
        guard before != after else { return }
        past.append(Entry(before: before, after: after))
        if past.count > Self.limit { past.removeFirst() }
        future.removeAll()
    }

    /// Consume only after checking the expected state. The store commits a copy
    /// of this history after the corresponding disk write has succeeded.
    mutating func step(_ direction: Direction, from current: PlanStore.Schedule) -> PlanStore.Schedule? {
        switch direction {
        case .undo:
            guard let entry = past.last, entry.after == current else { return nil }
            past.removeLast()
            future.append(entry)
            return entry.before
        case .redo:
            guard let entry = future.last, entry.before == current else { return nil }
            future.removeLast()
            past.append(entry)
            return entry.after
        }
    }
}
