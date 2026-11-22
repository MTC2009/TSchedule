import SwiftUI

struct AttendanceRing: View {
    let counts: AttendanceCounts
    let rate: Double?
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title) private var diameter = 204.0
    @State private var selection: Selection?

    private struct Selection {
        let segment: AttendanceRingLayout.Segment
        let turn: Double
    }

    private let touchInset: CGFloat = 12

    var body: some View {
        content(AttendanceRingLayout(counts: counts))
            .onChange(of: counts) { _, _ in selection = nil }
    }

    private func accessibleDial(_ chart: AttendanceRingLayout) -> some View {
        // Focus and readout belong to the same fixed dial, never to the floating callout.
        Group {
            if chart.segments.isEmpty {
                dial(chart)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("暂无考勤记录")
            } else {
                dial(chart)
                    .focusable()
                    .onKeyPress(keys: [.leftArrow, .rightArrow, .escape], phases: .down) { event in
                        if event.key == .escape {
                            guard selection != nil else { return .ignored }
                            selection = nil
                        } else {
                            step(event.key == .rightArrow ? 1 : -1, in: chart)
                        }
                        return .handled
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("考勤占比")
                    .accessibilityValue(selection.map { Self.label(for: $0.segment) }
                                        ?? String(localized: "出勤率 \(attendancePercent(rate))"))
                    .accessibilityAdjustableAction { direction in
                        step(direction == .increment ? 1 : -1, in: chart)
                    }
                    .accessibilityAction(.escape) { selection = nil }
            }
        }
        .accessibilityIdentifier("attendance-ring")
    }

    private func step(_ delta: Int, in chart: AttendanceRingLayout) {
        let segments = chart.segments
        guard !segments.isEmpty else { return }
        let current = segments.firstIndex { $0.status == selection?.segment.status }
        let next = current.map { ($0 + delta + segments.count) % segments.count }
            ?? (delta > 0 ? 0 : segments.count - 1)
        let segment = segments[next]
        selection = Selection(segment: segment, turn: segment.midpoint)
    }

    private func content(_ chart: AttendanceRingLayout) -> some View {
        AttendanceCalloutPlacement(diameter: min(diameter, 278), touchInset: touchInset, turn: selection?.turn) {
            accessibleDial(chart)
            if !chart.segments.isEmpty {
                // Measure the longest actual value even when closed; a tap never shifts the ring or the legend.
                ZStack {
                    ForEach(chart.segments) { segment in
                        Text(Self.label(for: segment))
                            .opacity(selection?.segment.status == segment.status ? 1 : 0)
                    }
                }
                .font(.caption.weight(.semibold)).monospacedDigit()
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 11).padding(.vertical, 6)
                .foregroundStyle(Color.white).background(Color.black, in: .rect(cornerRadius: 12))
                .opacity(selection == nil ? 0 : 1)
                .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
    }

    private func dial(_ chart: AttendanceRingLayout) -> some View {
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let visibleDiameter = max(0, min(proxy.size.width, proxy.size.height) - touchInset * 2)
            let thickness = min(20, visibleDiameter / 5)
            let band = AttendanceRingBand(turns: 0..<1, thickness: thickness)
            let fallback = reduceTransparency || contrast == .increased
            let glass: Glass = model.preferences.glass == .clear ? .clear : .regular
            ZStack {
                ZStack {
                    band.fill(.fill.tertiary)
                    ForEach(chart.segments) { segment in
                        let selected = selection?.segment.status == segment.status
                        AttendanceRingBand(turns: segment.fractionRange, thickness: thickness)
                            .fill(segment.status.color.opacity(fallback ? 1 : (selected ? 0.94 : 0.72)))
                    }
                }
                .glassEffect(fallback || chart.segments.isEmpty ? .identity : glass.interactive(!reduceMotion), in: band)
                VStack(spacing: 4) {
                    Text(attendancePercent(rate))
                        .font(.system(.title, design: .rounded, weight: .semibold)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.55)
                    Text("出勤率").font(.caption).foregroundStyle(.secondary)
                }
                .frame(width: max(0, visibleDiameter - 2 * thickness - 12))
            }
            .frame(width: visibleDiameter, height: visibleDiameter)
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { value in
                let hit = chart.hit(at: value.location, center: center, radius: (visibleDiameter - thickness) / 2,
                                    hitWidth: thickness + 2 * touchInset)
                if let hit, hit.segment.status != selection?.segment.status {
                    selection = Selection(segment: hit.segment, turn: hit.turn)
                } else {
                    selection = nil
                }
            }, including: chart.segments.isEmpty ? .none : .all)
        }
    }

    private static func label(for segment: AttendanceRingLayout.Segment) -> String {
        String(localized: "\(segment.status.title) · \(attendancePercent(segment.share))")
    }
}

private struct AttendanceRingBand: Shape {
    let turns: Range<Double>
    let thickness: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = (min(rect.width, rect.height) - thickness) / 2
        guard radius > 0, thickness > 0, !turns.isEmpty else { return Path() }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let line: Path
        if turns == 0..<1 {
            line = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                          width: 2 * radius, height: 2 * radius))
        } else {
            line = Path { path in
                path.addArc(center: center, radius: radius,
                            startAngle: .degrees(turns.lowerBound * 360 - 90),
                            endAngle: .degrees(turns.upperBound * 360 - 90), clockwise: false)
            }
        }
        return line.strokedPath(StrokeStyle(lineWidth: thickness))
    }
}

private struct AttendanceCalloutPlacement: Layout {
    let diameter: CGFloat
    let touchInset: CGFloat
    let turn: Double?
    private let gap: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? diameter
        let (dial, label, sides) = measure(width: width, subviews: subviews)
        let gutter = sides || label == .zero ? 0 : max(0, label.height + gap - touchInset)
        return CGSize(width: width, height: dial + 2 * gutter)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (dial, label, sides) = measure(width: bounds.width, subviews: subviews)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        subviews[0].place(at: center, anchor: .center, proposal: ProposedViewSize(width: dial, height: dial))
        guard subviews.count > 1, let turn else { return }
        let direction = AttendanceRingLayout.direction(at: turn)
        let radius = max(0, dial / 2 - touchInset)
        let clearance = radius + gap
        let x: CGFloat, y: CGFloat
        if sides {
            let limit = (dial - label.height) / 2
            y = min(limit, max(-limit, direction.dy * radius))
            // Leave the nearest corner of the bubble outside the ring, not just its centre.
            let edge = max(0, abs(y) - label.height / 2)
            x = (direction.dx >= 0 ? 1 : -1) * (sqrt(max(0, clearance * clearance - edge * edge)) + label.width / 2)
        } else {
            let limit = max(0, bounds.width - label.width) / 2
            x = min(limit, max(-limit, direction.dx * radius))
            let edge = max(0, abs(x) - label.width / 2)
            y = (direction.dy >= 0 ? 1 : -1) * (sqrt(max(0, clearance * clearance - edge * edge)) + label.height / 2)
        }
        subviews[1].place(at: CGPoint(x: center.x + x, y: center.y + y), anchor: .center,
                          proposal: ProposedViewSize(label))
    }

    private func measure(width: CGFloat, subviews: Subviews) -> (CGFloat, CGSize, Bool) {
        let dial = min(diameter, width)
        let label = subviews.count > 1 ? subviews[1].sizeThatFits(ProposedViewSize(width: width, height: nil)) : .zero
        let sides = label.height <= dial && width >= dial + 2 * (label.width + gap)
        return (dial, label, sides)
    }
}
