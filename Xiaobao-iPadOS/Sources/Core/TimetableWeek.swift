import Foundation

/// Match the portal's Sunday–Saturday columns without changing the app's calendar.
struct TimetableWeek {
    let dates: [Date]
    var start: Date { dates[0] }
    var end: Date { dates[6] }

    init(containing date: Date) {
        let clock = SchoolClock.calendar
        let day = clock.startOfDay(for: date)
        let start = clock.date(byAdding: .day, value: 1 - clock.component(.weekday, from: day), to: day)!
        dates = (0..<7).map { clock.date(byAdding: .day, value: $0, to: start)! }
    }
}

/// A resolved date for the week view. The printed Day and whether the
/// timetable is readable are separate from the date's teaching status.
struct WeekTimetableDay: Identifiable {
    var id: Date { date }
    let date: Date
    let rotationDay: Int?
    let calendarDay: SchoolCalendarDay?
    let timeline: LessonTimeline?
    var hasUnreadableTimes = false

    var printedDay: Int? { calendarDay?.day ?? rotationDay }

    var isConfirmedOff: Bool {
        guard !hasUnreadableTimes, timeline?.blocks.isEmpty != false else { return false }
        switch calendarDay?.status {
        case .noClass, .weekend: return true
        case nil: return timeline?.blocks.isEmpty == true && rotationDay == nil
        case .teaching, .unpublished: return false
        }
    }

    var notices: [String] {
        var notices = calendarDay?.notices ?? []
        if hasUnreadableTimes { notices.insert("时间待核对", at: 0) }
        switch calendarDay?.status {
        case .noClass:
            if timeline?.blocks.isEmpty == false { notices.insert("课表与校历待核对", at: 0) }
            else if notices.isEmpty { notices = ["不上课"] }
        case .weekend:
            if notices.isEmpty { notices = ["周末"] }
        case .unpublished:
            if timeline?.blocks.isEmpty != false { notices.insert("尚未公布", at: 0) }
        case nil:
            if timeline == nil, notices.isEmpty { notices = ["未载入"] }
            else if isConfirmedOff { notices = ["休息日"] }
        case .teaching: break
        }
        return notices
    }
}

/// Projects a resolved week for display, without inferring new teaching days
/// or changing any stored periods or dates.
struct WeekTimetableLayout {
    struct Placement: Identifiable {
        let block: LessonTimeline.Block
        let start, end: Double
        let lane, laneCount: Int
        var id: LessonTimeline.Block.ID { block.id }
    }

    struct ActivityBand: Identifiable {
        let columns: Range<Int>
        let placement: Placement
        var id: LessonTimeline.Block.ID { placement.id }
    }

    struct NoticeGroup: Identifiable {
        let columns: Range<Int>
        let notices: [String]
        var id: Int { columns.lowerBound }
    }

    private struct ActivityKey: Hashable {
        let kind: CampusBells.Activity
        let start, end: Double

        init?(_ placement: Placement) {
            // A campus activity has one resolved location per kind. Shortened
            // activities match only when both endpoints also match exactly.
            guard placement.laneCount == 1,
                  case .activity(let kind, _) = placement.block else { return nil }
            self.kind = kind
            start = placement.start
            end = placement.end
        }
    }

    let firstMinute, lastMinute: Int
    let guideMarks: [Int]
    let placementsByDay: [[Placement]]
    let activityBands: [ActivityBand]
    let noticeGroups: [NoticeGroup]
    private let widths: [Double]

    init(days: [WeekTimetableDay]) {
        let placements = days.map { $0.timeline.map(Self.placements) ?? [] }
        let all = placements.flatMap { $0 }
        let first = min(480, Int(floor((all.map(\.start).min() ?? 480) / 60)) * 60)
        let last = max(960, Int(ceil((all.map(\.end).max() ?? 960) / 60)) * 60)
        firstMinute = first
        lastMinute = last
        guideMarks = Self.guides(first: first, last: last, placements: all)

        let (bands, covered) = Self.mergeActivities(placements)
        activityBands = bands
        placementsByDay = placements.map { $0.filter { !covered.contains($0.id) } }
        noticeGroups = Self.groupNotices(days)

        let hasReadableOrUnknownDay = days.contains { !$0.isConfirmedOff }
        widths = days.map { day in
            guard hasReadableOrUnknownDay, day.isConfirmedOff else { return 1 }
            return day.printedDay == nil ? 0.62 : 0.74
        }
    }

    /// One set of edges aligns date headers, notices and both timed layers.
    /// Empty weeks keep equally wide dates so holiday notices can breathe.
    func columnEdges(in width: Double) -> [Double] {
        guard !widths.isEmpty else { return [0] }
        let total = widths.reduce(0, +)
        var edge = 0.0
        return [0] + widths.dropLast().map { weight in
            edge += width * weight / total
            return edge
        } + [width]
    }

    private static func groupNotices(_ days: [WeekTimetableDay]) -> [NoticeGroup] {
        var groups: [NoticeGroup] = []
        var start = 0
        while start < days.count {
            let notices = days[start].notices
            var end = start + 1
            if days[start].isConfirmedOff, !notices.isEmpty {
                while end < days.count, days[end].isConfirmedOff, days[end].notices == notices { end += 1 }
            }
            groups.append(.init(columns: start..<end, notices: notices))
            start = end
        }
        return groups
    }

    private static func mergeActivities(_ placements: [[Placement]]) -> ([ActivityBand], Set<LessonTimeline.Block.ID>) {
        var matches: [ActivityKey: [(column: Int, placement: Placement)]] = [:]
        for (column, entries) in placements.enumerated() {
            for entry in entries {
                guard let key = ActivityKey(entry) else { continue }
                matches[key, default: []].append((column, entry))
            }
        }
        var bands: [ActivityBand] = []
        var covered: Set<LessonTimeline.Block.ID> = []
        for entries in matches.values {
            var start = 0
            while start < entries.count {
                var end = start + 1
                while end < entries.count, entries[end].column == entries[end - 1].column + 1 { end += 1 }
                if end - start > 1 {
                    let first = entries[start]
                    bands.append(.init(columns: first.column..<(entries[end - 1].column + 1), placement: first.placement))
                    covered.formUnion(entries[start..<end].map { $0.placement.id })
                }
                start = end
            }
        }
        return (bands.sorted {
            ($0.placement.start, $0.columns.lowerBound) < ($1.placement.start, $1.columns.lowerBound)
        }, covered)
    }

    private static func guides(first: Int, last: Int, placements: [Placement]) -> [Int] {
        var anchors: Set<Int> = [first, last]
        for placement in placements {
            guard case .activity(let kind, _) = placement.block,
                  placement.start == Double(kind.minutes.lowerBound),
                  placement.end == Double(kind.minutes.upperBound) else { continue }
            anchors.insert(kind.minutes.lowerBound)
            if kind == .lunch { anchors.insert(kind.minutes.upperBound) }
        }
        // Prefer the confirmed campus landmarks. Fill longer gaps with whole
        // hours for orientation, without changing the linear time scale.
        let ordered = anchors.sorted()
        var guides = [first]
        for limit in ordered.dropFirst() {
            while limit - guides.last! > 120 {
                guides.append((guides.last! + 120) / 60 * 60)
            }
            guides.append(limit)
        }
        return guides
    }

    /// Independent overlap groups share lanes only while simultaneous, so
    /// later classes recover the full width of their date column.
    private static func placements(in timeline: LessonTimeline) -> [Placement] {
        var placements: [Placement] = []
        var group: [(block: LessonTimeline.Block, start: Double, end: Double, lane: Int)] = []
        var laneEnds: [Double] = []
        var groupEnd = -Double.infinity

        func finishGroup() {
            placements += group.map { .init(block: $0.block, start: $0.start, end: $0.end,
                                           lane: $0.lane, laneCount: laneEnds.count) }
            group.removeAll(keepingCapacity: true)
            laneEnds.removeAll(keepingCapacity: true)
        }

        for block in timeline.blocks {
            let start = timeline.minute(of: block.start), end = timeline.minute(of: block.end)
            if start >= groupEnd { finishGroup(); groupEnd = end }
            let lane = laneEnds.firstIndex { $0 <= start } ?? laneEnds.count
            if lane == laneEnds.count { laneEnds.append(end) } else { laneEnds[lane] = end }
            group.append((block, start, end, lane))
            groupEnd = max(groupEnd, end)
        }
        finishGroup()
        return placements
    }
}
