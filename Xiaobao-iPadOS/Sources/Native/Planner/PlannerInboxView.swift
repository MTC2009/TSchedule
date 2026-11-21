import SwiftUI

struct PlannerInboxView: View {
    let plans: [PersonalPlan]
    let bubbles: [PlanBubble]
    let selected: PlanPlacementItem?
    let returning: Bool
    let actions: PlannerPlanActions
    let add: () -> Void
    let cancelSelection: () -> Void
    let returnSelected: (PlanPlacementItem) -> Void
    let canAdd: Bool
    let reminderStatus: String?

    var body: some View {
        GlassCard(padding: 12, shape: PlannerCorners.tray) {
            VStack(alignment: .leading, spacing: 8) {
                if let selected {
                    HStack {
                        selectionLabel(selected.plan)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        returnButton(selected)
                        Button("取消", action: cancelSelection)
                            .font(.subheadline).frame(minHeight: 44)
                            .accessibilityLabel("取消安排 \(selected.plan.title)")
                    }
                }

                HStack(spacing: 8) {
                    shelf.frame(maxWidth: .infinity, alignment: .leading)
                    Button(action: add) {
                        Label("新建计划", systemImage: "plus").labelStyle(.iconOnly)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.glass)
                    .disabled(!canAdd)
                    .accessibilityIdentifier("planner-add")
                }
                if let reminderStatus {
                    Label(reminderStatus, systemImage: "bell.slash")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .overlay {
            if returning {
                PlannerCorners.tray.strokeBorder(.tint, lineWidth: 2).allowsHitTesting(false)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("planner-inbox")
    }

    @ViewBuilder private var shelf: some View {
        if plans.isEmpty && bubbles.isEmpty {
            Text("计划气泡").font(.callout).foregroundStyle(.secondary).frame(minHeight: 44)
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(plans.reversed()) { plan in
                        PlannerPlanCard(plan: plan, timeLabel: nil, actions: actions, shelfKind: .pending)
                    }
                    ForEach(bubbles.reversed()) { bubble in
                        PlannerPlanCard(plan: bubble.prototype, timeLabel: nil, actions: actions,
                                        shelfKind: bubble.latest?.week == nil ? .reusable : .weekly)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .accessibilityIdentifier("planner-bubbles")
        }
    }

    private func selectionLabel(_ plan: PersonalPlan) -> some View {
        Text("已选「\(plan.title)」· 点时间轴安排").font(.callout).foregroundStyle(.secondary)
    }

    @ViewBuilder private func returnButton(_ item: PlanPlacementItem) -> some View {
        if item.plan.time != nil && item.source == .plan {
            Button("移回待安排") { returnSelected(item) }.font(.callout).frame(minHeight: 44)
                .disabled(!actions.canEdit)
        }
    }

}
