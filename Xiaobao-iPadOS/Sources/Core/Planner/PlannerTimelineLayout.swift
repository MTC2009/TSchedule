import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// An uncompressed school day. Breaks and time outside teaching have the
/// same scale as classes, unlike the fixed gutters in the Today strip.
struct PlannerTimeScale {
    let hourHeight: Double
    var height: Double { hourHeight * 24 }

    init(hourHeight: Double) {
        self.hourHeight = hourHeight.isFinite ? max(1, hourHeight) : 1
    }

    func position(at minute: Double) -> Double { minute / 60 * hourHeight }

    func minute(at position: Double, includingDayEnd: Bool = false) -> Double? {
        if includingDayEnd && position == height { return 1440 }
        guard position.isFinite, (0..<height).contains(position) else { return nil }
        return position / hourHeight * 60
    }

    func minute(_ date: Date, in day: Date) -> Double { date.timeIntervalSince(day) / 60 }
}

/// Places display-only annotations over an already laid-out day. It never
/// adjusts plan times, school frames or the width of the date column.
struct PlannerAnnotationLayout {
    struct Annotation: Identifiable {
        let marks: [PlannerTimelineLayout.Mark]
        let frame: CGRect
        let showsTitle: Bool
        var id: PlannerDay.TimedRow.ID { marks[0].id }
    }

    let annotations: [Annotation]

    init(personal: PlannerTimelineLayout.Layer, track: CGRect, labelHeight: CGFloat, avoiding labels: [CGRect]) {
        let marks = personal.items.map { PlannerTimelineLayout.Mark(row: $0.row, top: $0.top, bottom: $0.bottom) }
            + personal.markGroups.flatMap(\.marks)
        let chronological = marks.enumerated().sorted { a, b in
            a.element.top == b.element.top ? a.offset < b.offset : a.element.top < b.element.top
        }.map(\.element)
        let bounds = track.insetBy(dx: 3, dy: 0)
        var groups: [[PlannerTimelineLayout.Mark]] = []
        for mark in chronological {
            if let first = groups.last?.first, mark.top - first.top < max(labelHeight + 3, PlannerTimelineLayout.markerTarget) {
                groups[groups.count - 1].append(mark)
            } else {
                groups.append([mark])
            }
        }

        var placed: [Annotation] = []
        var occupied = labels.map { $0.insetBy(dx: -3, dy: -2) }
        for group in groups {
            guard let first = group.first else { continue }
            // A small cluster can still keep its names if both fit, without
            // moving a label far from its own range just to avoid grouping.
            var named: [Annotation] = []
            if group.count <= 2 {
                for mark in group {
                    let start = CGFloat(mark.top) + 3
                    let end = min(CGFloat(mark.bottom) - labelHeight - 3, start + (group.count == 1 ? 64 : 30))
                    let nearby = (start - 6)...max(start + 8, end)
                    let blocked = occupied + named.map { $0.frame.insetBy(dx: -3, dy: -2) }
                    let preferred = start...max(start, end)
                    let minWidth = max(56, labelHeight * 2.6)
                    let rect = Self.fit(bounds, labelHeight, minWidth...max(216, minWidth), preferred, start, blocked)
                        ?? Self.fit(bounds, labelHeight, minWidth...max(216, minWidth), nearby, start, blocked)
                    guard let rect else { break }
                    named.append(.init(marks: [mark], frame: rect, showsTitle: true))
                }
            }
            if named.count == group.count {
                placed += named
                occupied += named.map { $0.frame.insetBy(dx: -3, dy: -2) }
                continue
            }

            let y = CGFloat(first.top) + 3
            let single = max(22, labelHeight)
            let widths: ClosedRange<CGFloat> = group.count == 1 ? single...single
                : 44...max(44, min(216, 14 + CGFloat(group.count) * 26))
            // Keep a readable icon or capsule as close as possible to the
            // timestamp; expanding this search never expands the time band.
            let anchor = (y - 44)...(y + 52)
            let fullWidth = min(bounds.width, widths.upperBound)
            let full = group.count > 1 && fullWidth >= widths.lowerBound
                ? Self.fit(bounds, labelHeight, fullWidth...fullWidth, anchor, y, occupied) : nil
            if let rect = full ?? Self.fit(bounds, labelHeight, widths, anchor, y, occupied)
                ?? Self.fit(bounds, labelHeight, widths, bounds.minY...max(bounds.minY, bounds.maxY), y, occupied) {
                placed.append(.init(marks: group, frame: rect, showsTitle: false))
                occupied.append(rect.insetBy(dx: -3, dy: -2))
            }
        }
        annotations = placed
    }

    private static func fit(_ board: CGRect, _ height: CGFloat, _ widths: ClosedRange<CGFloat>,
                            _ allowed: ClosedRange<CGFloat>, _ preferredY: CGFloat, _ occupied: [CGRect]) -> CGRect? {
        let low = max(board.minY, allowed.lowerBound)
        let high = min(board.maxY - height, allowed.upperBound)
        guard board.width >= widths.lowerBound, low <= high else { return nil }
        let relevant = occupied.filter { $0.maxY > low && $0.minY < high + height &&
            $0.maxX > board.minX && $0.minX < board.maxX }
        let idealY = min(high, max(low, preferredY))
        var candidates: Set<CGFloat> = [low, high, idealY]
        for rect in relevant {
            let before = rect.minY - height
            if (low...high).contains(before) { candidates.insert(before) }
            if (low...high).contains(rect.maxY) { candidates.insert(rect.maxY) }
        }
        let origins = candidates.sorted { a, b in
            let distanceA = abs(a - idealY), distanceB = abs(b - idealY)
            return distanceA == distanceB ? a < b : distanceA < distanceB
        }

        for y in origins {
            var spans: [Range<CGFloat>] = [board.minX..<board.maxX]
            for rect in relevant where rect.minY < y + height && y < rect.maxY {
                spans = spans.flatMap { span in
                    if rect.maxX <= span.lowerBound || rect.minX >= span.upperBound { return [span] }
                    var pieces: [Range<CGFloat>] = []
                    if span.lowerBound < rect.minX { pieces.append(span.lowerBound..<rect.minX) }
                    if rect.maxX < span.upperBound { pieces.append(rect.maxX..<span.upperBound) }
                    return pieces
                }
            }
            if let span = spans.filter({ $0.upperBound - $0.lowerBound >= widths.lowerBound }).max(by: { a, b in
                let aw = a.upperBound - a.lowerBound, bw = b.upperBound - b.lowerBound
                return aw == bw ? a.upperBound < b.upperBound : aw < bw
            }) {
                let width = min(widths.upperBound, span.upperBound - span.lowerBound)
                return CGRect(x: span.upperBound - width, y: y, width: width, height: height)
            }
        }
        return nil
    }
}

struct PlannerTimelineLayout {
    struct Item: Identifiable {
        let row: PlannerDay.TimedRow
        let top, bottom, height: Double
        let lane, laneCount: Int
        var id: PlannerDay.TimedRow.ID { row.id }
    }

    struct FreeBlock: Identifiable {
        let entry: PlannerSchoolEntry
        let top, bottom: Double
        var id: PlannerSchoolEntry.ID { entry.id }
        var height: Double { bottom - top }
    }

    struct Mark: Identifiable {
        let row: PlannerDay.TimedRow
        let top, bottom: Double
        var id: PlannerDay.TimedRow.ID { row.id }
    }

    struct MarkGroup: Identifiable {
        let marks: [Mark]
        var id: PlannerDay.TimedRow.ID { marks[0].id }
        var top: Double { marks[0].top }
        var singleSchoolEntry: PlannerSchoolEntry? {
            guard marks.count == 1, case .school(let entry) = marks[0].row else { return nil }
            return entry
        }
    }

    static let cardGap = 4.0
    static let markerTarget = 44.0

    struct Layer {
        let items: [Item]
        let markGroups: [MarkGroup]
    }

    let school: Layer
    let personal: Layer
    let freeBlocks: [FreeBlock]
    let height: Double

    init(day: PlannerDay, scale: PlannerTimeScale, minimumHeight: Double) {
        var schoolRows: [PlannerDay.TimedRow] = []
        var personalRows: [PlannerDay.TimedRow] = []
        var slots: [FreeBlock] = []
        for row in day.timed {
            switch row {
            case .school(let entry):
                if entry.kind == .freeblock, let end = entry.end, entry.start < end {
                    slots.append(FreeBlock(entry: entry,
                                          top: scale.position(at: scale.minute(entry.start, in: day.date)),
                                          bottom: scale.position(at: scale.minute(end, in: day.date))))
                } else {
                    schoolRows.append(row)
                }
            case .personal:
                personalRows.append(row)
            }
        }

        // The lane allocator never sees mixed records. Adding, moving or
        // removing a plan therefore cannot change a school rectangle.
        school = Self.layer(for: schoolRows, date: day.date, scale: scale, minimumHeight: minimumHeight)
        personal = Self.layer(for: personalRows, date: day.date, scale: scale, minimumHeight: minimumHeight)
        freeBlocks = slots
        height = scale.height + Self.markerTarget
    }

    private static func layer(for rows: [PlannerDay.TimedRow], date: Date, scale: PlannerTimeScale,
                              minimumHeight: Double) -> Layer {
        var items: [Item] = []
        var markGroups: [MarkGroup] = []
        var marks: [Mark] = []
        var group: [(row: PlannerDay.TimedRow, top: Double, bottom: Double, height: Double, lane: Int)] = []
        var laneEnds: [Double] = []
        var groupEnd = -Double.infinity
        let minimumCardHeight = max(Self.markerTarget, minimumHeight)

        func finishGroup() {
            items += group.map { Item(row: $0.row, top: $0.top, bottom: $0.bottom, height: $0.height,
                                     lane: $0.lane, laneCount: laneEnds.count) }
            group.removeAll(keepingCapacity: true)
            laneEnds.removeAll(keepingCapacity: true)
            groupEnd = -Double.infinity
        }

        for row in rows {
            let top = scale.position(at: scale.minute(row.start, in: date))
            let bottom = row.end.map { scale.position(at: scale.minute($0, in: date)) } ?? top
            let duration = row.end.map { $0.timeIntervalSince(row.start) / 60 } ?? 0
            let height = scale.position(at: duration) - Self.cardGap
            // Meals keep the same card at their true duration, with compact ink
            // when needed. Other short intervals retain their separate marker lane.
            let meal = if case .school(let entry) = row { entry.isMeal } else { false }
            if height < minimumCardHeight && (!meal || height <= 0) {
                if let first = marks.first, top - first.top >= Self.markerTarget {
                    markGroups.append(MarkGroup(marks: marks))
                    marks.removeAll(keepingCapacity: true)
                }
                marks.append(Mark(row: row, top: top, bottom: max(top, bottom)))
                continue
            }
            // Lanes are based on half-open real intervals, not hit area or gap.
            if top >= groupEnd { finishGroup() }
            let lane: Int
            if let available = laneEnds.firstIndex(where: { $0 <= top }) {
                lane = available
                laneEnds[lane] = bottom
            } else {
                lane = laneEnds.count
                laneEnds.append(bottom)
            }
            groupEnd = max(groupEnd, bottom)
            group.append((row, top, bottom, height, lane))
        }
        finishGroup()
        if !marks.isEmpty { markGroups.append(MarkGroup(marks: marks)) }

        return Layer(items: items, markGroups: markGroups)
    }
}
