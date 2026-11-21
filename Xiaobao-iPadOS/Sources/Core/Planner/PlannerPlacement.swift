import Foundation

/// The preview and final gesture share a lookup. A dropped card can inherit a
/// school slot; an explicitly drawn range never inherits or moves either boundary.
struct PlannerPlacement {
    private static let step = 5
    let time: PlanTime
    let conflicts: [PlannerSchoolEntry]

    init?(at minute: Double, moving existing: PlanTime?, in day: PlannerDay) {
        guard (0..<1440).contains(minute), let boundary = Self.rangeBoundary(at: minute) else { return nil }
        let instant = day.date.addingTimeInterval(minute * 60)

        if existing == nil, let slot = day.timed.lazy.compactMap(Self.freeSlot).first(where: { slot in
            guard let end = slot.end else { return false }
            return slot.start <= instant && instant < end
        }), let end = slot.end, let range = PlanTime(
            startMinute: Self.minute(slot.start, on: day.date), endMinute: Self.minute(end, on: day.date)
        ) {
            time = range
        } else {
            // The last grid point is 23:55; midnight belongs to the following date.
            let start = min(1440 - Self.step, boundary)
            let duration = existing.flatMap { old in old.endMinute.map { $0 - old.startMinute } }
            guard let range = PlanTime(startMinute: start, endMinute: duration.map { start + $0 }) else { return nil }
            time = range
        }
        conflicts = day.conflicts(with: time)
    }

    init?(from first: Double, to second: Double, in day: PlannerDay) {
        guard let a = Self.rangeBoundary(at: first), let b = Self.rangeBoundary(at: second),
              let range = PlanTime(startMinute: min(a, b), endMinute: max(a, b)) else { return nil }
        time = range
        conflicts = day.conflicts(with: time)
    }

    /// Both endpoints may touch the end of the day, but a zero-length range
    /// is invalid. The caller can display the first snapped endpoint alone.
    static func rangeBoundary(at minute: Double) -> Int? {
        guard minute.isFinite, (0...1440).contains(minute) else { return nil }
        return Int((minute / Double(step)).rounded()) * step
    }

    private static func freeSlot(_ row: PlannerDay.TimedRow) -> PlannerSchoolEntry? {
        guard case .school(let entry) = row, entry.kind == .freeblock else { return nil }
        return entry
    }

    private static func minute(_ date: Date, on day: Date) -> Int {
        Int(date.timeIntervalSince(day) / 60)
    }
}
