import SwiftUI

/// School markers retain the existing ruler position. Personal annotations are
/// laid out separately and never take space from school markers or cards.
struct PlannerTimelineMarks: View {
    let day: PlannerDay
    let groups: [PlannerTimelineLayout.MarkGroup]
    let permitsOpening: Bool
    let canOpenSchool: (PlannerSchoolEntry) -> Bool
    let openSchool: (PlannerSchoolEntry) -> Void

    private let target = PlannerTimelineLayout.markerTarget
    private var center: CGFloat { target / 2 }

    var body: some View {
        ForEach(groups) { group in
            ForEach(group.marks) { mark in
                let duration = mark.bottom - mark.top
                PlannerRangeBand(color: nil, isPoint: duration == 0)
                    .frame(width: target - 8, height: duration + 3)
                    .position(x: center, y: mark.top + duration / 2)
            }
            badge(group)
                .frame(width: target, height: target)
                .position(x: center, y: group.top + target / 2)
        }
    }

    @ViewBuilder private func badge(_ group: PlannerTimelineLayout.MarkGroup) -> some View {
        if group.marks.count == 1, let mark = group.marks.first, case .school(let entry) = mark.row {
            if permitsOpening && canOpenSchool(entry) {
                Button { openSchool(entry) } label: { schoolMark }
                    .buttonStyle(.plain)
                    .accessibilityLabel(label(for: entry))
            } else {
                schoolMark.accessibilityLabel(label(for: entry))
            }
        } else if permitsOpening {
            Menu {
                ForEach(group.marks) { mark in
                    if case .school(let entry) = mark.row {
                        if canOpenSchool(entry) {
                            Button(label(for: entry)) { openSchool(entry) }
                        } else {
                            Text(label(for: entry))
                        }
                    }
                }
            } label: {
                markCount(group.marks.count)
            }
            .accessibilityLabel("\(group.marks.count) 个邻近事项")
        } else {
            markCount(group.marks.count)
                .accessibilityLabel(group.marks.compactMap { mark in
                    if case .school(let entry) = mark.row { label(for: entry) } else { nil }
                }.joined(separator: "；"))
                .allowsHitTesting(false)
        }
    }

    private var schoolMark: some View {
        Image(systemName: "diamond")
            .font(.caption.weight(.semibold))
            .padding(5).background(.background, in: .circle)
            .frame(width: target, height: target)
            .contentShape(Rectangle())
    }

    private func markCount(_ count: Int) -> some View {
        Text(count.formatted()).font(.caption2.weight(.semibold)).monospacedDigit()
            .padding(5).background(.background, in: .circle)
            .frame(width: target, height: target)
            .contentShape(Rectangle())
    }

    private func label(for entry: PlannerSchoolEntry) -> String {
        let minute = Int(entry.start.timeIntervalSince(day.date) / 60)
        return "\(SchoolClock.time(minute)) · \(entry.title)"
    }

}
