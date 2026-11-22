import SwiftUI

/// Pass a resolved calendar date; an unloaded request is not a rest day.
struct TodayRotationHeader: View {
    let date: Date
    let day: Int?
    var unpublished = false
    var unknownDayTitle: String? = nil

    private var dayTitle: String { day.map { "Day \($0)" } ?? unknownDayTitle ?? (unpublished ? String(localized: "Day 未公布") : String(localized: "休息日")) }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            heading(separator: "\u{2003}").fixedSize(horizontal: true, vertical: false)
            heading(separator: "\n").fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func heading(separator: String) -> some View {
        let dateTitle = schoolDateLabel(date)
        let rotation = Text(verbatim: dayTitle).font(.system(.largeTitle, design: .rounded, weight: .bold))
        let calendarDate = Text(verbatim: dateTitle).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
        // One text element keeps the visual hierarchy without a second, separately spoken day.
        return Text("\(rotation)\(separator)\(calendarDate)")
            .accessibilityLabel(day == nil ? String(localized: "\(dayTitle)，\(dateTitle)") : String(localized: "轮转日 \(dayTitle)，\(dateTitle)"))
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("today-rotation-heading")
    }
}

struct StudentPageHeader: View {
    @Environment(AppModel.self) private var model
    let title: String
    let subtitle: String
    let portalSection: String
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 20) { heading; Spacer(); portalButton }
            VStack(alignment: .leading, spacing: 14) { heading; portalButton }
        }
    }
    private var heading: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.title2.weight(.semibold))
            Text(subtitle).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private var portalButton: some View {
        Button("在校宝查看", systemImage: "safari") { model.openPortal(section: portalSection) }.buttonStyle(.glass)
    }
}

struct StudentEmptyState: View {
    let title: String
    let detail: String
    var symbol = "tray"
    var body: some View {
        ContentUnavailableView { Label(title, systemImage: symbol) } description: { Text(detail) }
            .frame(maxWidth: .infinity).padding(.vertical, 18)
    }
}

struct StudentDetailSurface<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        ZStack {
            AtmosphereView().ignoresSafeArea()
            ScrollView { VStack(alignment: .leading, spacing: 22) { content }.padding(24).frame(maxWidth: 980).frame(maxWidth: .infinity) }
        }.navigationBarTitleDisplayMode(.inline)
    }
}

struct MetricValue: View {
    let title: String
    let value: String
    var color: Color = .primary
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.semibold)).monospacedDigit().foregroundStyle(color)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension AttendanceStatus {
    var color: Color { switch self { case .present: .blue; case .late: .orange; case .early: .pink; case .absent: .purple } }
}

func compactNumber(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...1))) }
func attendancePercent(_ value: Double?) -> String {
    guard let value else { return "—" }
    return (value * 100).formatted(.number.precision(.fractionLength(0...2))) + "%"
}
