import SwiftUI

enum PlannerCorners {
    static let card = RoundedRectangle(cornerRadius: 12, style: .continuous)
    static let tray = RoundedRectangle(cornerRadius: 16, style: .continuous)
    static let inset = RoundedRectangle(cornerRadius: 8, style: .continuous)
}

struct PlannerPlanActions {
    let space: Namespace.ID
    // Board gestures and quick actions are separate from opening a saved form.
    let canEdit: Bool
    let canOpenEditor: Bool
    let pendingID: UUID?
    let selected, dragging: PlanPlacementItem?
    let select: (PlanPlacementItem) -> Void
    let edit: (PlanPlacementItem) -> Void
    let toggleCompletion: (PersonalPlan) -> Void
}

struct PlannerRepeatGlyph: View {
    var font: Font = .callout.weight(.medium)

    var body: some View {
        Image(systemName: "repeat").font(font)
            .overlay { Image(systemName: "equal").font(.system(size: 6, weight: .bold)) }
            .accessibilityHidden(true)
    }
}

struct PlannerPlanGlyph: View {
    let plan: PersonalPlan
    let recurring: Bool
    var font: Font = .caption.weight(.semibold)

    var body: some View {
        Group {
            if let icon = plan.icon { Image(systemName: icon.symbol).font(font) }
            else if recurring { PlannerRepeatGlyph(font: font) }
            else { Image(systemName: "bookmark").font(font) }
        }
        .accessibilityHidden(true)
    }
}

struct PlannerPlanCard: View {
    enum Density { case standard, compact, combined, marker }
    enum ShelfKind { case pending, reusable, recurring }

    let plan: PersonalPlan
    let timeLabel: String?
    let actions: PlannerPlanActions
    var density: Density = .standard
    var conflictsWithSchool = false
    var recurring = false
    var shelfKind: ShelfKind?

    private var item: PlanPlacementItem {
        let source: PlanPlacementItem.Source = switch shelfKind {
        case .recurring: .recurringBubble
        case .reusable: .reusableBubble
        case .pending: .plan
        case nil: recurring ? .occurrence : .plan
        }
        return PlanPlacementItem(plan: plan, source: source)
    }

    private var isSelected: Bool { actions.selected == item }
    private var isTemplate: Bool { shelfKind == .reusable || shelfKind == .recurring }
    private var isPending: Bool { actions.pendingID == plan.id }
    private var completionLabel: String { plan.isCompleted ? String(localized: "取消完成") : String(localized: "完成") }

    var body: some View {
        Group {
            if shelfKind != nil {
                shelfContent
                    .background((plan.color?.tint ?? .secondary).opacity(PlannerRangeBand.savedOpacity), in: .capsule)
            } else {
                timedContent
            }
        }
        .overlay {
            if shelfKind != nil, isSelected || actions.dragging == item {
                Capsule().stroke(.tint, lineWidth: 2).padding(1)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder private var timedContent: some View {
        if !actions.canEdit {
            editorButton("planner-plan-label-\(plan.id.uuidString)") {
                annotationLabel.frame(maxHeight: .infinity).contentShape(Rectangle())
            }
        } else if density == .marker || density == .combined {
            // At small widths the label is one target: tap edits, hold moves.
            handle(action: { actions.edit(item) }, combined: true)
        } else {
            HStack(spacing: 0) {
                handle(action: { actions.select(item) })
                titleButton
                if density == .standard { completeButton }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
    }

    private var shelfContent: some View {
        HStack(spacing: 0) {
            if actions.canEdit { handle(action: { actions.select(item) }) }
            editorButton("planner-shelf-plan-\(plan.id.uuidString)") {
                HStack(spacing: 0) {
                    if !actions.canEdit && item.isRecurring { PlannerRepeatGlyph().padding(.leading, 10) }
                    shelfLabel.padding(.leading, actions.canEdit ? 0 : 10)
                }
                .contentShape(Rectangle())
            }
        }
    }

    private var shelfLabel: some View {
        HStack(spacing: 5) {
            if let icon = plan.icon { Image(systemName: icon.symbol).accessibilityHidden(true) }
            Text(plan.title).lineLimit(1)
            if shelfKind == .reusable {
                Image(systemName: "bookmark").foregroundStyle(.secondary).accessibilityHidden(true)
            }
        }
        .font(.subheadline.weight(.medium))
        .padding(.trailing, 12)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private var titleButton: some View {
        editorButton("planner-edit-plan-\(plan.id.uuidString)") {
            annotationTitle
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
    }

    private func editorButton<Label: View>(_ identifier: String, @ViewBuilder label: () -> Label) -> some View {
        Button { actions.edit(item) } label: { label() }
            .buttonStyle(.plain).hoverEffect(.highlight)
            .disabled(!actions.canOpenEditor)
            .accessibilityLabel(plan.title).accessibilityValue(status)
            .accessibilityHint("编辑计划")
            .accessibilityIdentifier(identifier)
            .accessibilityActions {
                if actions.canEdit && !isTemplate {
                    Button(completionLabel) { actions.toggleCompletion(plan) }
                }
            }
    }

    private var completeButton: some View {
        Button { actions.toggleCompletion(plan) } label: {
            Image(systemName: plan.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.caption).frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("\(completionLabel) \(plan.title)")
        .accessibilityIdentifier("planner-complete-\(plan.id.uuidString)")
    }

    private func handle(action: @escaping () -> Void, combined: Bool = false) -> some View {
        Button(action: action) {
            if combined && density == .combined {
                annotationLabel.frame(minHeight: 44).contentShape(Rectangle())
            } else {
                Group {
                    if isPending { ProgressView().controlSize(.mini) }
                    else if shelfKind == nil { PlannerPlanGlyph(plan: plan, recurring: item.isRecurring) }
                    else if item.isRecurring { PlannerRepeatGlyph() }
                    else { Image(systemName: "line.3.horizontal").font(.callout.weight(.medium)) }
                }
                .frame(width: 44, height: 44).contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain).foregroundStyle(.tint).hoverEffect(.highlight)
        .accessibilityLabel(combined ? plan.title : String(localized: "移动 \(plan.title)"))
        .accessibilityValue(status)
        .accessibilityHint(item.isRecurring ? String(localized: "长按拖动调整重复安排") : String(localized: "长按后拖动，也可点选时间"))
        .accessibilityIdentifier((shelfKind == nil ? "planner-move-" : "planner-shelf-") + plan.id.uuidString)
        .accessibilityAction(named: Text("选择落点")) { actions.select(item) }
        .accessibilityAction(named: Text(completionLabel)) {
            if !isTemplate { actions.toggleCompletion(plan) }
        }
        .background {
            GeometryReader { geometry in
                Color.clear.preference(key: PlannerHandleFrames.self,
                    value: [.init(item: item, frame: geometry.frame(in: .named(actions.space)))])
            }
            .allowsHitTesting(false).accessibilityHidden(true)
        }
    }

    private var annotationLabel: some View {
        HStack(spacing: 4) {
            PlannerPlanGlyph(plan: plan, recurring: item.isRecurring)
            if density != .marker {
                annotationTitle
                if plan.isCompleted { Image(systemName: "checkmark").font(.caption2).accessibilityHidden(true) }
            }
        }
        .foregroundStyle(isSelected || actions.dragging == item ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
        .frame(maxWidth: .infinity, alignment: density == .marker ? .center : .leading)
    }

    private var annotationTitle: some View {
        Text(plan.title).font(.caption.weight(.semibold)).lineLimit(1).truncationMode(.tail)
            .foregroundStyle(.primary)
    }

    private var status: String {
        let kind = item.isRecurring ? String(localized: "重复安排") : (isTemplate ? String(localized: "常用气泡") : nil)
        return [timeLabel, kind, isTemplate ? nil : (plan.isCompleted ? String(localized: "已完成") : String(localized: "未完成")),
                conflictsWithSchool ? String(localized: "与学校安排重叠") : nil,
                plan.color?.name, plan.icon?.name, plan.reminder == nil ? nil : String(localized: "已设置提醒")]
            .compactMap { $0 }.joined(separator: String(localized: "，"))
    }
}
