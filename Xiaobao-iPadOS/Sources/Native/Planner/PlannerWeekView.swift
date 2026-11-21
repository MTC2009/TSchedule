import SwiftUI

struct PlannerTimelineColumn: Identifiable {
    var id: Date { day.date }
    let day: PlannerDay
    let school: PlannerSchoolDay
    let calendarDay: SchoolCalendarDay?
    let weeklyIDs: Set<UUID>
    let focus: PlannerDay.Focus?

    var notices: [String] {
        var seen = Set<String>()
        let status = calendarDay?.status
        let fallback: [String] = switch status {
        case .noClass: ["不上课"]
        case .weekend: ["周末"]
        case .unpublished: ["尚未公布"]
        default: school.hasTimetable ? [] : ["未载入"]
        }
        let published = calendarDay?.notices ?? []
        return ((published.isEmpty ? fallback : published) + day.allDay.map(\.title)).filter { seen.insert($0).inserted }
    }
}

/// One set of column edges is shared by the week header, school and personal
/// layers, and pointer routing. A plan never changes the width of a day.
struct PlannerBoardGeometry {
    let ruler, columnWidth: CGFloat
    let count: Int

    init(width: CGFloat, count: Int, rulerWidth: CGFloat) {
        self.count = max(1, count)
        ruler = min(rulerWidth, max(44, width / 4))
        columnWidth = max(1, width - ruler) / CGFloat(self.count)
    }

    func column(at x: CGFloat) -> Int? {
        guard x.isFinite, x >= ruler, x <= ruler + columnWidth * CGFloat(count) else { return nil }
        return min(count - 1, Int((x - ruler) / columnWidth))
    }
}

struct PlannerWeekView: View {
    let columns: [PlannerTimelineColumn]
    let selectedDate: Date
    let rulerWidth: CGFloat
    let select: (Date) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Text("时间").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                .frame(width: rulerWidth)
            ForEach(columns) { column in
                let selected = column.id == selectedDate
                Button { select(column.id) } label: {
                    VStack(spacing: 4) {
                        Text(schoolDateLabel(column.id, format: "EEE M/d"))
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        if let day = column.calendarDay?.day ?? column.school.rotationDay {
                            Text("Day \(day)").font(.subheadline.weight(.semibold)).monospacedDigit()
                        } else {
                            Text("—").font(.subheadline)
                        }
                        if !column.notices.isEmpty {
                            Text(column.notices.joined(separator: " · "))
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 62, alignment: .top)
                    .padding(.horizontal, 3)
                    .contentShape(Rectangle())
                    .overlay(alignment: .bottom) {
                        if selected { Capsule().fill(.tint).frame(height: 2).padding(.horizontal, 8) }
                    }
                }
                .buttonStyle(.plain).hoverEffect(.highlight)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("planner-week-day-\(SchoolClock.key(column.id))")
            }
        }
    }
}

struct PlannerTimeRuler: View {
    enum Mode { case browse, range, placement }
    let scale: PlannerTimeScale
    let width: CGFloat
    let mode: Mode
    let tap: (Double) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0...48, id: \.self) { tick in
                let minute = tick * 30
                let y = scale.position(at: Double(minute))
                let label = SchoolClock.time(minute)
                let selectable = mode == .range || (mode == .placement && tick < 48)
                if tick.isMultiple(of: 2) {
                    Text(label).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        .frame(width: max(1, width - 4), alignment: .leading)
                        .position(x: (width - 4) / 2, y: y)
                        .accessibilityIdentifier("planner-minute-\(minute)")
                        .accessibilityHidden(selectable)
                        .allowsHitTesting(false)
                }
                // Editing adds targets, not another visual ruler. Half-hours
                // remain selectable at the grid lines without extra labels.
                if selectable {
                    Button { tap(Double(minute)) } label: {
                        Color.clear.frame(width: width, height: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(mode == .range ? "选时刻 \(label)" : "安排到 \(label)")
                    .accessibilityIdentifier(mode == .range ? "planner-boundary-\(minute)" : "planner-target-\(minute)")
                    .position(x: width / 2, y: y)
                }
            }
        }
        .frame(width: width)
    }
}
