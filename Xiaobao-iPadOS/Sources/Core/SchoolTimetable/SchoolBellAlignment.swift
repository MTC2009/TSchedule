import Foundation

/// The portal uses a second set of clock labels for a few *specific* bells.
/// Match intervals, never a row's position: a missing B5 must not pull B6 forward.
struct SchoolBellAlignment {
    typealias Period = SchoolTimetable.Period
    typealias Record = (course: String?, period: Period)

    let periods: [Period]
    let vacancies: [TeachingSlot]

    private static let oldB1 = TeachingSlot(start: 505, end: 545)
    private static let oldB2 = TeachingSlot(start: 555, end: 595)
    private static let oldB5 = TeachingSlot(start: 755, end: 795)

    /// An export can collapse both halves to one range, including the meal between
    /// them. Corroborate all four instructional groups, not just a count of four rows.
    /// A single long appointment (or a pair overlapping an independent exact half)
    /// is never enough to split a class or move it across lunch.
    private static func expanded(_ records: [Record], blanks: [TeachingSlot]) -> ([Record], [TeachingSlot]) {
        let clocks = Set(records.map { TeachingSlot(start: $0.period.start, end: $0.period.end) } + blanks)
        var pairs: [TeachingSlot: [TeachingSlot]] = [:]
        for (i, halves) in CampusBells.teachingGroups.enumerated() {
            let ordinary = TeachingSlot(start: halves[0].start, end: halves[halves.count - 1].end)
            var spans = [ordinary]
            if i == 0 { spans.append(.init(start: oldB1.start, end: oldB2.end)) }
            if i == 2 { spans.append(.init(start: oldB5.start, end: ordinary.end)) }
            let grouped = spans.filter(clocks.contains)
            if grouped.count == 1, let span = grouped.first {
                guard !halves.contains(where: { $0 != span && clocks.contains($0) }) else { return (records, blanks) }
                pairs[span] = halves
            } else if grouped.isEmpty && (halves.allSatisfy(clocks.contains) ||
                        (i == 0 && clocks.contains(oldB1) && clocks.contains(oldB2))) {
                continue
            } else { return (records, blanks) }
        }
        guard !pairs.isEmpty else { return (records, blanks) }
        let lessons = records.flatMap { record -> [Record] in
            let p = record.period, span = TeachingSlot(start: p.start, end: p.end)
            return pairs[span]?.map { (record.course, Period(title: p.title, room: p.room, start: $0.start, end: $0.end, metadata: p.metadata)) } ?? [record]
        }
        return (lessons, blanks.flatMap { pairs[$0] ?? [$0] })
    }

    init(records input: [Record], blanks rawBlanks: [TeachingSlot] = []) {
        let (records, blanks) = Self.expanded(input, blanks: rawBlanks)
        let lessonClocks = records.map { TeachingSlot(start: $0.period.start, end: $0.period.end) }
        let clocks = Set(lessonClocks + blanks)
        let early = clocks.filter { $0.start < 610 && $0.end > 480 }.sorted { $0.start < $1.start }
        // Exact forty-minute halves with a shared displacement and a short or absent
        // recess identify the opening double. A parallel/overlapping period is not a pair.
        let candidate = early.count == 2 && (470...510).contains(early[0].start)
            && early.allSatisfy { $0.end - $0.start == 40 }
            && (0...10).contains(early[1].start - early[0].end)
        let opening = CampusBells.openingDouble, halves = CampusBells.openingHalves
        let regular = CampusBells.teachingSlots
        let first = candidate ? lessonClocks.indices.filter { lessonClocks[$0] == early[0] } : []
        let second = candidate ? lessonClocks.indices.filter { lessonClocks[$0] == early[1] } : []
        let simplePair = first.count == 1 && second.count == 1
        let sameEnrollment = simplePair && records[first[0]].course != nil && records[first[0]].course == records[second[0]].course
        let offset = (early.first?.start ?? opening.start) - opening.start
        // A different export may shift a whole day. Two other recognizable bells must
        // independently corroborate that offset. Exact, already-correct bells always win.
        let matches: [(TeachingSlot, TeachingSlot)] = candidate && offset != 0 ? regular.dropFirst().compactMap { bell in
            let source = TeachingSlot(start: bell.start + offset, end: bell.end + offset)
            return clocks.contains(source) && !regular.contains(source) && !clocks.contains(bell) ? (source, bell) : nil
        } : []
        let knownOpening = early == [Self.oldB1, Self.oldB2]
        let pair = candidate && (knownOpening || offset == 0 || matches.count >= 2
            || (abs(offset) <= 10 && (sameEnrollment || early.allSatisfy(blanks.contains))))
        var mapping = [Self.oldB1: halves.first, Self.oldB2: halves.second, Self.oldB5: CampusBells.beforeLunch]
        if pair {
            mapping[early[0]] = halves.first
            mapping[early[1]] = halves.second
            if matches.count >= 2 { for (source, bell) in matches { mapping[source] = bell } }
        }
        func target(_ source: TeachingSlot) -> TeachingSlot {
            // Do not superimpose a shifted lesson on a separately reported exact bell.
            guard let bell = mapping[source], bell == source || !clocks.contains(bell) else { return source }
            return bell
        }
        var output = zip(records, lessonClocks).map { record, source -> Period in
            let bell = target(source)
            return .init(title: record.period.title, room: record.period.room, start: bell.start, end: bell.end,
                         metadata: record.period.metadata)
        }
        if pair, simplePair, target(early[0]) == halves.first, target(early[1]) == halves.second {
            let i = first[0], j = second[0], a = records[i], b = records[j]
            // Legacy archives have no enrollment keys; the exact paired portal clocks
            // and equal labels/rooms provide narrower evidence than arbitrary adjacency.
            let sameArchivedClass = knownOpening && a.course == nil && b.course == nil
                && a.period.title == b.period.title && a.period.room == b.period.room
            if sameEnrollment || sameArchivedClass {
                output[i] = .init(title: a.period.title, room: a.period.room == b.period.room ? a.period.room : nil,
                                  start: opening.start, end: opening.end,
                                  metadata: .agreement([a.period.metadata, b.period.metadata], combineHalves: true))
                output.remove(at: j)
            }
        }
        periods = output.sorted { ($0.start, $0.end, $0.title, $0.room ?? "") < ($1.start, $1.end, $1.title, $1.room ?? "") }
        let empty = Set(blanks.map(target))
        vacancies = regular.filter { empty.contains($0) || ($0 == opening && empty.contains(halves.first) && empty.contains(halves.second)) }
    }
}
