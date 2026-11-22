import SwiftUI

/// Short school entries keep their exact range and a separate accessible name target.
struct PlannerTimelineMarks<SchoolLabel: View>: View {
    let groups: [PlannerTimelineLayout.MarkGroup]
    let permitsOpening: Bool
    let canOpenSchool: (PlannerSchoolEntry) -> Bool
    let openSchool: (PlannerSchoolEntry) -> Void
    let timeLabel: (PlannerSchoolEntry) -> String
    let trackWidth: CGFloat
    let left: CGFloat
    @ViewBuilder let schoolLabel: (PlannerSchoolEntry) -> SchoolLabel

    private let target = PlannerTimelineLayout.markerTarget

    var body: some View {
        ForEach(groups) { group in
            ForEach(group.marks) { mark in
                let duration = mark.bottom - mark.top
                PlannerRangeBand(color: nil, isPoint: duration == 0)
                    .frame(width: min(trackWidth, target - 8), height: duration + 3)
                    .position(x: left + min(trackWidth, target - 8) / 2, y: mark.top + duration / 2)
            }
            if let entry = group.singleSchoolEntry, let mark = group.marks.first {
                schoolLabel(entry)
                    .frame(width: trackWidth, height: target, alignment: .leading)
                    .position(x: left + trackWidth / 2, y: (mark.top + mark.bottom) / 2)
            } else {
                let entries = group.marks.compactMap { mark -> PlannerSchoolEntry? in
                    if case .school(let entry) = mark.row { entry } else { nil }
                }
                Group {
                    if permitsOpening {
                        Menu {
                            ForEach(entries) { entry in
                                if canOpenSchool(entry) {
                                    Button(detail(for: entry)) { openSchool(entry) }
                                } else {
                                    Text(detail(for: entry))
                                }
                            }
                        } label: { groupLabel(entries) }
                        .buttonStyle(.plain).accessibilityHint("查看起止时间")
                    } else {
                        groupLabel(entries).allowsHitTesting(false)
                    }
                }
                .frame(width: trackWidth, height: target, alignment: .leading)
                .position(x: left + trackWidth / 2, y: group.top + target / 2)
            }
        }
    }

    private func groupLabel(_ entries: [PlannerSchoolEntry]) -> some View {
        Text(entries.map(\.title).joined(separator: " · ")).font(.caption.weight(.semibold))
            .lineLimit(2).padding(.horizontal, 5)
            .frame(minWidth: target, minHeight: target, alignment: .leading)
            .contentShape(Rectangle())
    }

    private func detail(for entry: PlannerSchoolEntry) -> String {
        entry.title + " · " + timeLabel(entry)
    }
}
