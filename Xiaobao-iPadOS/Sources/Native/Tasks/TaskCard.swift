import SwiftUI

struct TaskCard: View {
    let task: TaskRecord
    let stage: TaskCardStage?
    let showsLocalCompletion: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    private let padding: CGFloat = 18
    private let shape = RoundedRectangle(cornerRadius: 30)
    private var ribbonClearance: CGSize {
        guard stage != nil else { return .zero }
        return CGSize(width: TaskCornerRibbon.footprint.width - padding + 4,
                      height: TaskCornerRibbon.footprint.height - padding + 4)
    }

    var body: some View {
        GlassCard(padding: 0, shape: shape) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(task.title).font(.headline).lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.forward").font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary).accessibilityHidden(true)
                }
                let scope = [task.courseName, task.workType.map(TaskRecord.workTypeTitle)].compactMap { $0 }
                if !scope.isEmpty { Text(scope.joined(separator: " · ")).font(.subheadline) }
                scoreAndMetadata
            }
            .frame(minHeight: 161, alignment: .topLeading)
            .padding(padding)
            // Keep the sash in the glass content, not in the backdrop sampled at its rounded edge.
            .overlay {
                if let stage {
                    TaskCornerRibbon(stage: stage)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .clipShape(shape)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        }
        .contentShape(Rectangle())
    }

    private var scoreAndMetadata: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let mark = task.mark {
                Text(mark.displayText).font(.system(.title, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .accessibilityLabel("任务成绩 \(mark.displayText)")
            }
            if let dueAt = task.dueAt {
                Label("截止 \(schoolDateLabel(dueAt, format: "M月d日 HH:mm"))", systemImage: "clock")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let teacher = task.teacher {
                Label(teacher, systemImage: "person").font(.caption).foregroundStyle(.secondary)
            }
            if showsLocalCompletion {
                TaskSubmissionLabel(state: .localCompletion).accessibilityHidden(true)
            }
        }
        // Keep wrapped metadata and even a card without metadata clear of the corner.
        .frame(minHeight: ribbonClearance.height, alignment: .topLeading)
        .padding(.trailing, ribbonClearance.width)
    }
}

private struct TaskCornerRibbon: View {
    static let footprint = CGSize(width: 64, height: 54)
    let stage: TaskCardStage
    private let bottomRun: CGFloat = 32

    var body: some View {
        let footprint = Self.footprint
        // Scale the two offsets together so the long edges stay parallel.
        let trailingRun = bottomRun * footprint.height / footprint.width
        Band(bottomRun: bottomRun, trailingRun: trailingRun)
            .fill(tint)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.black)
                    .position(x: footprint.width / 2 + bottomRun / 4,
                              y: footprint.height / 2 + trailingRun / 4)
            }
            .frame(width: footprint.width, height: footprint.height)
    }

    private var tint: Color {
        switch stage {
        case .unsubmitted, .overdue:
            let systemColor: Color = stage == .unsubmitted ? .gray : .yellow
            return systemColor.mix(with: .black, by: 0.07, in: .perceptual)
        case .awaitingGrading:
            return Color(.sRGB, red: 0.17, green: 0.57, blue: 0.95)
        case .graded:
            return Color(.sRGB, red: 0.29, green: 0.75, blue: 0.21)
        }
    }

    private var symbol: String {
        switch stage {
        case .unsubmitted: "minus"
        case .overdue: "exclamationmark"
        case .awaitingGrading: "clock"
        case .graded: "checkmark"
        }
    }

    private struct Band: Shape {
        let bottomRun: CGFloat
        let trailingRun: CGFloat

        func path(in rect: CGRect) -> Path {
            Path { path in
                path.addLines([
                    CGPoint(x: rect.minX, y: rect.maxY),
                    CGPoint(x: rect.minX + bottomRun, y: rect.maxY),
                    CGPoint(x: rect.maxX, y: rect.minY + trailingRun),
                    CGPoint(x: rect.maxX, y: rect.minY)
                ])
                path.closeSubpath()
            }
        }
    }
}

struct TaskGradingBadge: View {
    let state: TaskGradingState

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).foregroundStyle(tint).accessibilityHidden(true)
            Text(state.title).foregroundStyle(.primary)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(tint.opacity(0.14), in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private var tint: Color {
        switch state {
        case .graded: .green
        case .pending, .inProgress, .gradedUnpublished: .blue
        case .missing, .excused, .unavailable: .secondary
        }
    }

    private var symbol: String {
        switch state {
        case .graded: "checkmark.circle.fill"
        case .pending, .inProgress, .gradedUnpublished: "clock.fill"
        case .missing: "minus.circle"
        case .excused: "circle"
        case .unavailable: "questionmark.circle"
        }
    }
}

struct TaskSubmissionLabel: View {
    let state: TaskSubmissionState

    var body: some View {
        HStack(spacing: 4) {
            if state == .overdue {
                Image(systemName: "clock.badge.exclamationmark").foregroundStyle(.orange).accessibilityHidden(true)
            }
            Text(state.title)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
