import SwiftUI

/// Renders the visual labels, not the time bands. Only an overflowing group
/// uses glass; individual labels remain ink on the original track.
struct PlannerPlanAnnotations: View {
    let values: [PlannerAnnotationLayout.Annotation]
    let day: PlannerDay
    let actions: PlannerPlanActions
    let weeklyIDs: Set<UUID>
    let permitsOpening: Bool
    @Binding var shownGroup: PlannerDay.TimedRow.ID?

    var body: some View {
        ForEach(values) { value in
            let plans = value.marks.compactMap { mark -> PersonalPlan? in
                if case .personal(let plan, _, _) = mark.row { return plan }
                return nil
            }
            if let first = plans.first {
                connector(for: value, color: plans.count == 1 ? first.color : nil)
                if plans.count == 1 {
                    PlannerPlanCard(plan: first, timeLabel: first.time.map(PlannerScheduleCanvas.timeLabel),
                                    actions: actions, density: density(value),
                                    conflictsWithSchool: first.time.map { !day.conflicts(with: $0).isEmpty } ?? false,
                                    weekly: weeklyIDs.contains(first.id))
                        .frame(width: value.frame.width, height: value.frame.height)
                        .allowsHitTesting(permitsOpening && actions.canOpenEditor)
                        .position(x: value.frame.midX, y: value.frame.midY)
                } else {
                    PlannerPlanGroupCapsule(plans: plans, weeklyIDs: weeklyIDs, size: value.frame.size,
                                            actions: actions, permitsOpening: permitsOpening,
                                            presented: presentation(of: value.id))
                        .position(x: value.frame.midX, y: value.frame.midY)
                        .onDisappear { if shownGroup == value.id { shownGroup = nil } }
                }
            }
        }
    }

    private func density(_ value: PlannerAnnotationLayout.Annotation) -> PlannerPlanCard.Density {
        guard value.showsTitle else { return .marker }
        return value.frame.width >= 196 ? .standard : value.frame.width >= 104 ? .compact : .combined
    }

    private func presentation(of id: PlannerDay.TimedRow.ID) -> Binding<Bool> {
        Binding(get: { shownGroup == id }, set: { next in
            if next { shownGroup = id } else if shownGroup == id { shownGroup = nil }
        })
    }

    @ViewBuilder private func connector(for value: PlannerAnnotationLayout.Annotation, color: PlanColor?) -> some View {
        let first = value.marks[0].top
        let last = value.marks.map(\.bottom).max() ?? first
        let frame = value.frame
        if frame.maxY < first || frame.minY > last {
            let near = frame.maxY < first ? frame.maxY : frame.minY
            let time = frame.maxY < first ? first : last
            Path { path in
                let x = frame.maxX - 2
                path.move(to: CGPoint(x: x, y: near))
                path.addLine(to: CGPoint(x: x, y: time))
            }
            .stroke(color?.tint ?? .secondary, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
            .allowsHitTesting(false).accessibilityHidden(true)
        }
    }
}

private struct PlannerPlanGroupCapsule: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let plans: [PersonalPlan]
    let weeklyIDs: Set<UUID>
    let size: CGSize
    let actions: PlannerPlanActions
    let permitsOpening: Bool
    @Binding var presented: Bool

    var body: some View {
        Button { presented = true } label: {
            capsule
                .frame(width: size.width, height: max(size.height, PlannerTimelineLayout.markerTarget))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).hoverEffect(.highlight)
        .disabled(!permitsOpening)
        .accessibilityLabel("\(plans.count) 项计划")
        .accessibilityHint("查看全部计划")
        .accessibilityIdentifier("planner-plan-group-\(plans[0].id.uuidString)")
        .popover(isPresented: $presented) { details.presentationCompactAdaptation(.popover) }
    }

    @ViewBuilder private var capsule: some View {
        if reduceTransparency {
            tokens.background(Color(uiColor: .secondarySystemBackground), in: Capsule())
        } else {
            tokens.glassEffect(model.preferences.glass == .clear ? .clear.interactive() : .regular.interactive(), in: Capsule())
        }
    }

    private var tokens: some View {
        let cell = max(21, size.height)
        let pad: CGFloat = size.width < 58 ? 4 : 6
        let gap: CGFloat = 3
        let capacity = max(1, Int((size.width - pad * 2 + gap) / (cell + gap)))
        let displayed = plans.count <= capacity ? plans.count : min(plans.count, max(1, capacity - 1))
        return HStack(spacing: gap) {
            ForEach(Array(plans.prefix(displayed).enumerated()), id: \.element.id) { index, plan in
                HStack(spacing: 2) {
                    Text((index + 1).formatted()).font(.caption2.weight(.semibold)).monospacedDigit()
                    PlannerPlanGlyph(plan: plan, weekly: weeklyIDs.contains(plan.id), font: .caption2.weight(.medium))
                }
                .lineLimit(1).minimumScaleFactor(0.78)
                .frame(width: cell)
            }
            if displayed < plans.count {
                Image(systemName: "ellipsis").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.primary)
        .frame(width: size.width, height: size.height)
        .accessibilityHidden(true)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(plans.count) 项计划").font(.headline).accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("planner-plan-group-title")
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(plans.enumerated()), id: \.element.id) { index, plan in
                        if index != 0 { Divider() }
                        HStack(spacing: 6) {
                            Button {
                                presented = false
                                actions.edit(item(plan))
                            } label: { detailLabel(plan, number: index + 1) }
                            .buttonStyle(.plain).hoverEffect(.highlight)
                            .disabled(!actions.canOpenEditor)
                            .accessibilityHint("编辑计划")
                            .accessibilityIdentifier("planner-plan-group-item-\(plan.id.uuidString)")
                            if actions.canEdit { rowActions(plan) }
                        }
                    }
                }
            }
            .defaultScrollAnchor(.top)
            .frame(idealHeight: min(340, CGFloat(plans.count) * 62), maxHeight: 350)
        }
        .padding(16)
        .frame(idealWidth: 320, maxWidth: 400)
    }

    private func detailLabel(_ plan: PersonalPlan, number: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(number.formatted()).font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(.secondary)
            PlannerPlanGlyph(plan: plan, weekly: weeklyIDs.contains(plan.id))
            VStack(alignment: .leading, spacing: 2) {
                Text(plan.title).font(.body.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                Text(detailTime(plan)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer(minLength: 0)
            if plan.isCompleted { Image(systemName: "checkmark.circle.fill").accessibilityLabel("已完成") }
        }
        .frame(minHeight: 44).padding(.vertical, 5).contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func detailTime(_ plan: PersonalPlan) -> String {
        let time = plan.time.map(PlannerScheduleCanvas.timeLabel) ?? "待安排"
        return weeklyIDs.contains(plan.id) ? time + " · 每周重复" : time
    }

    private func item(_ plan: PersonalPlan) -> PlanPlacementItem {
        .init(plan: plan, source: weeklyIDs.contains(plan.id) ? .weeklyOccurrence : .plan)
    }

    private func rowActions(_ plan: PersonalPlan) -> some View {
        Menu {
            Button("选择落点", systemImage: "arrow.up.and.down") {
                presented = false
                actions.select(item(plan))
            }
            Button(plan.isCompleted ? "取消完成" : "完成", systemImage: "checkmark.circle") {
                presented = false
                actions.toggleCompletion(plan)
            }
        } label: {
            Image(systemName: "ellipsis").frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .accessibilityLabel("\(plan.title)的操作")
    }
}
