import SwiftUI

extension PlanColor {
    var name: String {
        switch self {
        case .blue: String(localized: "蓝色")
        case .teal: String(localized: "青色")
        case .green: String(localized: "绿色")
        case .orange: String(localized: "橙色")
        case .pink: String(localized: "粉色")
        }
    }

    var tint: Color {
        switch self {
        case .blue: .blue
        case .teal: .teal
        case .green: .green
        case .orange: .orange
        case .pink: .pink
        }
    }
}

extension PlanIcon {
    var name: String {
        switch self {
        case .book: String(localized: "阅读")
        case .pencil: String(localized: "写作")
        case .computer: String(localized: "电脑")
        case .people: String(localized: "小组")
        case .exercise: String(localized: "运动")
        case .music: String(localized: "音乐")
        case .flag: String(localized: "目标")
        case .errands: String(localized: "杂事")
        }
    }

    var symbol: String {
        switch self {
        case .book: "book"
        case .pencil: "pencil"
        case .computer: "laptopcomputer"
        case .people: "person.2"
        case .exercise: "figure.run"
        case .music: "music.note"
        case .flag: "flag"
        case .errands: "basket"
        }
    }
}

/// A painted interval, not a control. The caller supplies exact bounds, so
/// the decorative rules never influence layout, hit testing or the clock.
struct PlannerRangeBand: View {
    enum Paint { case marker, overlayFill, endpoints, preview }
    static let savedOpacity = 0.14
    static let savedOverlapOpacityLimit = 0.28
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let color: PlanColor?
    var paint: Paint = .marker
    var isPoint = false

    private var ink: Color { color?.tint ?? (paint == .preview ? .accentColor : .secondary) }

    private var fillOpacity: Double {
        switch paint {
        case .marker: Self.savedOpacity
        case .overlayFill: Self.savedOpacity / Self.savedOverlapOpacityLimit
        case .preview: 0.22
        case .endpoints: 0
        }
    }

    var body: some View {
        ZStack {
            if !isPoint && !reduceTransparency && paint != .endpoints {
                PlannerCorners.card.fill(ink.opacity(fillOpacity))
                    .padding(.vertical, 1.5)
            }
            if paint != .overlayFill { strokes }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private var strokes: some View {
        Canvas { context, size in
                let width = size.width
                let length = min(12, width / 3)
                let rows = isPoint || size.height < 4 ? [size.height / 2] : [1.5, size.height - 1.5]
                for y in rows {
                    var line = Path()
                    line.move(to: CGPoint(x: 0, y: y))
                    line.addLine(to: CGPoint(x: width, y: y))
                    context.stroke(line, with: .color(ink.opacity(paint == .preview ? 0.95 : 0.68)), lineWidth: 1)

                    var caps = Path()
                    caps.move(to: CGPoint(x: 0, y: y))
                    caps.addLine(to: CGPoint(x: length, y: y))
                    caps.move(to: CGPoint(x: width - length, y: y))
                    caps.addLine(to: CGPoint(x: width, y: y))
                    context.stroke(caps, with: .color(ink), lineWidth: 3)
                }
        }
    }
}
