import SwiftUI
import UIKit

struct PlannerRangeRequest {
    let id: UUID
    let date: Date
    let title: String
    let color: PlanColor?
    let anchor: Int?
}

/// One interactive surface for either a day or a week. Date and minute
/// resolution for both the preview and commit use the same measured board.
struct PlannerTimelineView: View {
    let columns: [PlannerTimelineColumn]
    let selectedDate: Date
    let initialMinute: Int?
    let canWrite: Bool
    let editing: Bool
    let showsPlans: Bool
    let acceptsTouches: Bool
    let pendingPlanID: UUID?
    let bubbles: [PlanBubble]
    let reminderStatus: String?
    let rangeRequest: PlannerRangeRequest?
    let selectDay: (Date) -> Void
    let finishRange: (Date, PlanTime?) -> Void
    let add: () -> Void
    let edit: (PlanPlacementItem) -> Void
    let place: (PlanPlacementItem, Date, PlanTime?) -> Void
    let toggleCompletion: (PersonalPlan) -> Void

    @Namespace private var space
    @ScaledMetric(relativeTo: .body) private var hourHeight = 96.0
    @ScaledMetric(relativeTo: .body) private var minimumHeight = 48.0
    @ScaledMetric(relativeTo: .caption) private var rulerWidth = 62.0
    @State private var scroll = ScrollPosition()
    @State private var metrics = ScrollMetrics(offset: 0, limit: 0)
    @State private var viewport = CGRect.null
    @State private var canvas = CGRect.null
    @State private var inbox = CGRect.null
    @State private var handles: [PlannerHandleFrame] = []
    @State private var positioned = false
    @State private var selected: PlanPlacementItem?
    @State private var firstBoundary: Boundary?
    @State private var hold: Hold?
    @State private var feedback: String?
    @State private var blockedTapUntil: ContinuousClock.Instant?
    @State private var shownGroup: PlannerDay.TimedRow.ID?

    private enum Held {
        case item(PlanPlacementItem), range(Boundary)
    }

    private struct Hold {
        let id = UUID()
        let target: Held
        let origin: CGPoint
        let initialMinuteOffset: Double
        var point: CGPoint
    }

    private struct Boundary {
        let date: Date
        let minute: Double
    }

    private struct ScrollMetrics: Equatable {
        let offset, limit: CGFloat
    }

    private enum Target {
        case time(Date, PlannerPlacement), inbox, outsideDay
    }

    private var scale: PlannerTimeScale { PlannerTimeScale(hourHeight: max(88, hourHeight)) }
    private var isWeek: Bool { columns.count > 1 }
    private var showsInbox: Bool { editing && rangeRequest == nil }
    private var canHold: Bool { editing && acceptsTouches && canWrite && shownGroup == nil }
    private var canOpenPlanEditor: Bool { acceptsTouches && canWrite && rangeRequest == nil && selected == nil }
    private var canTap: Bool {
        hold == nil && (blockedTapUntil.map { ContinuousClock.now >= $0 } ?? true)
    }
    private var boardHeight: CGFloat { scale.height + PlannerTimelineLayout.markerTarget }
    private var currentColumn: PlannerTimelineColumn? { column(on: selectedDate) ?? columns.first }

    private var moving: PlanPlacementItem? {
        if case .item(let item) = hold?.target { return item }
        return nil
    }

    private var actions: PlannerPlanActions {
        PlannerPlanActions(space: space, canEdit: canWrite && editing && rangeRequest == nil,
                           canOpenEditor: canOpenPlanEditor,
                           pendingID: pendingPlanID, selected: selected, dragging: moving,
                           select: selectItem, edit: openEditor, toggleCompletion: {
            if canTap { toggleCompletion($0) }
        })
    }

    var body: some View {
        VStack(spacing: 8) {
            if isWeek {
                GeometryReader { geometry in
                    PlannerWeekView(columns: columns, selectedDate: selectedDate,
                                    rulerWidth: boardGeometry(width: geometry.size.width).ruler, select: selectDay)
                }
                .frame(height: 66)
            } else if let currentColumn, !currentColumn.notices.isEmpty {
                dayNotices(currentColumn.notices)
            }

            timeline
            if let feedback {
                Label(feedback, systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
            controls
        }
        .contentShape(Rectangle())
        .coordinateSpace(name: space)
        .background {
            PlannerHoldGesture(enabled: canHold, accepts: acceptsHold, changed: handleHold)
                .accessibilityHidden(true)
        }
        .onPreferenceChange(PlannerHandleFrames.self) { handles = $0 }
        .overlay(alignment: .topLeading) { if let moving, let hold { dragPreview(moving, hold: hold) } }
        .onChange(of: initialMinute, initial: true) { _, _ in positionInitially() }
        .onChange(of: columns.map(\.id)) { _, _ in
            positioned = false
            resetInteraction()
            positionInitially()
        }
        .onChange(of: editing) { _, _ in resetInteraction() }
        .onChange(of: showsPlans) { _, _ in resetInteraction() }
        .onChange(of: rangeRequest?.id) { _, _ in
            resetInteraction()
            if let anchor = rangeRequest?.anchor { revealIfNeeded(anchor) }
        }
        .task(id: hold?.id) { if let hold { await scrollWhileHeldAtEdge(id: hold.id) } }
    }

    private var timeline: some View {
        ScrollView {
            GeometryReader { geometry in
                board(layout: boardGeometry(width: geometry.size.width))
            }
            .frame(height: boardHeight)
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(space)) }) {
                canvas = $0
                positionInitially()
            }
        }
        .scrollPosition($scroll)
        .scrollDisabled(hold != nil)
        .onScrollGeometryChange(for: ScrollMetrics.self, of: { info in
            ScrollMetrics(offset: info.contentOffset.y + info.contentInsets.top,
                          limit: max(0, info.contentSize.height - info.containerSize.height +
                                     info.contentInsets.top + info.contentInsets.bottom))
        }, action: { _, new in
            metrics = new
            positionInitially()
        })
        .onScrollPhaseChange { _, phase in if phase == .interacting { positioned = true } }
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(space)) }) {
            viewport = $0
            positionInitially()
        }
        .accessibilityIdentifier("planner-timeline")
    }

    private func board(layout: PlannerBoardGeometry) -> some View {
        let mode: PlannerTimeRuler.Mode = selected != nil ? .placement : (canHold ? .range : .browse)
        return HStack(alignment: .top, spacing: 0) {
            PlannerTimeRuler(scale: scale, width: layout.ruler, mode: mode) { minute in
                if let date = rangeRequest?.date ?? currentColumn?.id { tapTime(minute, on: date) }
            }
            ForEach(columns) { column in
                PlannerScheduleCanvas(day: column.day, scale: scale, minimumHeight: minimumHeight, focus: column.focus,
                                      preview: preview(on: column.id), actions: actions,
                                      tapMinute: { tapTime($0, on: column.id) },
                                      acceptsTimeTap: canWrite && (selected != nil || rangeRequest?.date == column.id),
                                      opensSchool: !editing,
                                      compact: isWeek, recurringIDs: column.recurringIDs, shownGroup: $shownGroup)
                    .frame(width: layout.columnWidth)
            }
        }
        .frame(height: boardHeight)
        .contentShape(Rectangle())
    }

    private func boardGeometry(width: CGFloat) -> PlannerBoardGeometry {
        PlannerBoardGeometry(width: width, count: columns.count, rulerWidth: rulerWidth)
    }

    @ViewBuilder private var controls: some View {
        if let request = rangeRequest {
            GlassCard(padding: 12, shape: PlannerCorners.tray) {
                HStack {
                    let date = schoolDateLabel(request.date, format: "EEE M/d")
                    Label(isWeek ? String(localized: "\(date) · 长按后拖动选时段") : String(localized: "长按后拖动选时段"), systemImage: "hand.draw")
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("取消") { finishRange(request.date, nil) }
                        .frame(minHeight: 44).accessibilityIdentifier("planner-range-cancel")
                }
            }
        } else if showsInbox {
            PlannerInboxView(plans: currentColumn?.day.unscheduled ?? [], bubbles: bubbles, selected: selected,
                             returning: hoverIsInbox, actions: actions, add: add,
                             cancelSelection: { selected = nil }, returnSelected: {
                commit($0, on: selectedDate, at: nil)
            }, canAdd: canWrite, reminderStatus: reminderStatus)
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(space)) }) { inbox = $0 }
        }
    }

    private func dayNotices(_ items: [String]) -> some View {
        GlassCard(padding: 10, shape: PlannerCorners.card) {
            Label(items.joined(separator: " · "), systemImage: "calendar")
                .font(.caption).frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("planner-day-notices")
    }

    private func column(on date: Date) -> PlannerTimelineColumn? {
        columns.first { $0.id == date }
    }

    private func column(at point: CGPoint) -> PlannerTimelineColumn? {
        guard viewport.contains(point), canvas.contains(point), let index = boardGeometry(width: canvas.width).column(at: point.x - canvas.minX),
              columns.indices.contains(index) else { return nil }
        return columns[index]
    }

    private func selectItem(_ item: PlanPlacementItem) {
        guard actions.canEdit, canTap else { return }
        firstBoundary = nil
        feedback = nil
        selected = selected == item ? nil : item
    }

    private func openEditor(_ item: PlanPlacementItem) {
        guard canOpenPlanEditor, canTap else { return }
        resetInteraction()
        edit(item)
    }

    private func resetInteraction() {
        hold = nil
        selected = nil
        firstBoundary = nil
        feedback = nil
        shownGroup = nil
    }

    private func tapTime(_ minute: Double, on date: Date) {
        guard canHold, canTap, let column = column(on: date) else { return }
        if let selected {
            guard let target = PlannerPlacement(at: minute, moving: selected.plan.time, in: column.placementDay) else {
                feedback = String(localized: "该安排会跨到下一天，请选早一点。")
                return
            }
            commit(selected, on: date, at: target.time)
        } else if rangeRequest?.date == nil || rangeRequest?.date == date {
            if let firstBoundary, firstBoundary.date == date {
                guard let picked = PlannerPlacement(from: firstBoundary.minute, to: minute, in: column.placementDay) else {
                    feedback = String(localized: "请选择不同的起止时刻。")
                    return
                }
                resetInteraction()
                finishRange(date, picked.time)
            } else {
                firstBoundary = .init(date: date, minute: minute)
                feedback = nil
            }
        }
    }

    private func handle(at point: CGPoint) -> PlannerHandleFrame? {
        guard rangeRequest == nil else { return nil }
        return handles.last { handle in
            let onShelf = handle.item.source == .reusableBubble || handle.item.source == .recurringBubble || handle.item.plan.time == nil
            return (onShelf ? showsInbox && inbox.contains(point) : viewport.contains(point)) && handle.frame.contains(point)
        }
    }

    private func acceptsHold(at point: CGPoint) -> Bool {
        if handle(at: point) != nil { return true }
        guard let column = column(at: point), rangeRequest?.date == nil || rangeRequest?.date == column.id else { return false }
        return scale.minute(at: point.y - canvas.minY, includingDayEnd: true) != nil
    }

    private func handleHold(_ state: UIGestureRecognizer.State, _ point: CGPoint) {
        switch state {
        case .began:
            guard canHold else { return }
            feedback = nil
            firstBoundary = nil
            selected = nil
            positioned = true
            if let frame = handle(at: point) {
                let initialOffset: Double
                if frame.item.source == .plan || frame.item.source == .occurrence,
                   let time = frame.item.plan.time, viewport.contains(point),
                   let minute = scale.minute(at: point.y - canvas.minY) {
                    // Keep the grab point relative to the start, not the center of
                    // the badge, so lifting by itself cannot jump a timed card.
                    initialOffset = minute - Double(time.startMinute)
                } else {
                    initialOffset = 0
                }
                hold = Hold(target: .item(frame.item), origin: point, initialMinuteOffset: initialOffset, point: point)
            } else if let column = column(at: point), rangeRequest?.date == nil || rangeRequest?.date == column.id,
                      let minute = scale.minute(at: point.y - canvas.minY, includingDayEnd: true) {
                hold = Hold(target: .range(.init(date: column.id, minute: minute)), origin: point,
                            initialMinuteOffset: 0, point: point)
            }
        case .changed:
            if var current = hold { current.point = point; hold = current }
        case .ended:
            guard var current = hold else { return }
            current.point = point
            hold = nil
            blockedTapUntil = ContinuousClock.now.advanced(by: .milliseconds(220))
            guard canHold, hypot(point.x - current.origin.x, point.y - current.origin.y) >= 6 else { return }
            switch current.target {
            case .range(let start):
                if let picked = range(start, endingAt: point) { finishRange(start.date, picked.time) }
            case .item(let item):
                switch target(for: item, hold: current) {
                case .time(let date, let placement): commit(item, on: date, at: placement.time)
                case .inbox: commit(item, on: SchoolClock.dayDate(item.plan.day) ?? selectedDate, at: nil)
                case .outsideDay: feedback = String(localized: "该安排会跨到下一天，请选早一点。")
                case nil: break
                }
            }
        case .cancelled, .failed:
            if hold != nil { blockedTapUntil = ContinuousClock.now.advanced(by: .milliseconds(220)) }
            hold = nil
        default: break
        }
    }

    private func commit(_ item: PlanPlacementItem, on date: Date, at time: PlanTime?) {
        guard canWrite, editing else { return }
        resetInteraction()
        guard item.source == .reusableBubble || item.timeOrDateDiffers(date: date, time: time) else { return }
        place(item, date, time)
    }

    private func range(_ start: Boundary, endingAt point: CGPoint) -> PlannerPlacement? {
        guard let column = column(on: start.date), !canvas.isNull,
              viewport.insetBy(dx: -4, dy: -4).contains(point),
              let end = scale.minute(at: max(0, min(scale.height, point.y - canvas.minY)), includingDayEnd: true) else { return nil }
        return PlannerPlacement(from: start.minute, to: end, in: column.placementDay)
    }

    private func target(for item: PlanPlacementItem, hold: Hold) -> Target? {
        if showsInbox && inbox.contains(hold.point) { return item.source == .plan && item.plan.time != nil && item.plan.courseKind == nil ? .inbox : nil }
        guard let column = column(at: hold.point),
              let raw = scale.minute(at: hold.point.y - canvas.minY) else { return nil }
        let minute = max(0, raw - hold.initialMinuteOffset)
        guard let placement = PlannerPlacement(at: minute, moving: item.plan.time, in: column.placementDay) else { return .outsideDay }
        return .time(column.id, placement)
    }

    private var hoverIsInbox: Bool {
        guard let moving, let hold, case .inbox = target(for: moving, hold: hold) else { return false }
        return true
    }

    private func preview(on date: Date) -> PlannerBandPreview? {
        if let hold {
            switch hold.target {
            case .item(let item):
                if case .time(let destination, let placement) = target(for: item, hold: hold), destination == date {
                    return .init(start: placement.time.startMinute, end: placement.time.endMinute, color: item.plan.color)
                }
            case .range(let start) where start.date == date:
                if let time = range(start, endingAt: hold.point)?.time {
                    return .init(start: time.startMinute, end: time.endMinute, color: rangeRequest?.color)
                }
                return PlannerPlacement.rangeBoundary(at: start.minute).map { .init(start: $0, end: nil, color: rangeRequest?.color) }
            case .range: break
            }
        }
        guard let firstBoundary, firstBoundary.date == date,
              let minute = PlannerPlacement.rangeBoundary(at: firstBoundary.minute) else { return nil }
        return .init(start: minute, end: nil, color: rangeRequest?.color)
    }

    private func dragPreview(_ item: PlanPlacementItem, hold: Hold) -> some View {
        GeometryReader { geometry in
            let width = min(224, max(1, geometry.size.width - 16))
            GlassCard(padding: 9, shape: PlannerCorners.card) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.plan.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    switch target(for: item, hold: hold) {
                    case .time(let date, let placement):
                        Text((isWeek ? schoolDateLabel(date, format: "EEE") + " · " : "") +
                             PlannerScheduleCanvas.timeLabel(placement.time)).font(.caption).monospacedDigit()
                        if item.isRecurring { Label("调整今后的重复安排", systemImage: "repeat").font(.caption) }
                    case .inbox: Text("移回待安排").font(.caption)
                    case .outsideDay: Text("超出当天").font(.caption)
                    case nil: Text("拖到时间轴").font(.caption)
                    }
                }
            }
            .frame(width: width)
            .position(x: min(max(hold.point.x, width / 2), geometry.size.width - width / 2),
                      y: max(34, hold.point.y - 48))
        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }

    private func positionInitially() {
        guard !positioned, let initialMinute, !viewport.isNull, !canvas.isNull, metrics.limit > 0 else { return }
        positioned = true
        scrollToMinute(initialMinute)
    }

    private func revealIfNeeded(_ minute: Int) {
        guard !viewport.isNull, !canvas.isNull, metrics.limit > 0 else { return }
        let y = canvas.minY + scale.position(at: Double(minute))
        if y < viewport.minY || y >= viewport.maxY { scrollToMinute(minute) }
    }

    private func scrollToMinute(_ minute: Int) {
        let origin = canvas.minY - viewport.minY + metrics.offset
        let anchor = origin + scale.position(at: Double(minute)) - 8
        scroll.scrollTo(y: min(max(0, anchor), metrics.limit))
    }

    private func scrollWhileHeldAtEdge(id: UUID) async {
        let clock = ContinuousClock()
        var stationary: (point: CGPoint, since: ContinuousClock.Instant)?
        while !Task.isCancelled, let hold, hold.id == id {
            let point = hold.point
            let edge = min(44, viewport.height / 4)
            let top = point.y - viewport.minY, bottom = viewport.maxY - point.y
            if edge > 0, viewport.contains(point), min(top, bottom) < edge {
                let now = clock.now
                if let stationary, hypot(stationary.point.x - point.x, stationary.point.y - point.y) <= 6 {
                    if stationary.since.duration(to: now) >= .milliseconds(360) {
                        let delta = top < bottom ? -12 * (1 - top / edge) : 12 * (1 - bottom / edge)
                        let next = min(max(metrics.offset + delta, 0), metrics.limit)
                        if abs(next - metrics.offset) >= 0.5 { scroll.scrollTo(y: next) }
                    }
                } else { stationary = (point, now) }
            } else { stationary = nil }
            do { try await Task.sleep(for: .milliseconds(30)) } catch { return }
        }
    }
}

private extension PlanPlacementItem {
    func timeOrDateDiffers(date: Date, time: PlanTime?) -> Bool {
        plan.time != time || plan.day != SchoolClock.key(date)
    }
}
