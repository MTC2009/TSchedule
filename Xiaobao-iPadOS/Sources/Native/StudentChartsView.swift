import Charts
import SwiftUI

struct AssessmentHistoryChart: View {
    enum Presentation { case preview, detail }
    let points: [AssessmentPoint]
    var presentation: Presentation = .detail
    var range: AssessmentHistoryRange? = nil
    @State private var selection: Date?

    var body: some View {
        Group {
            if let first = points.first, let last = points.last {
                let domain = (range?.start ?? first.day).addingTimeInterval(-43200)...(range?.end ?? last.day).addingTimeInterval(43200)
                if presentation == .preview {
                    plot(selectedDay: nil)
                        .chartXScale(domain: domain)
                        .chartXAxis(.hidden).chartYAxis(.hidden)
                        .frame(height: 86)
                        .allowsHitTesting(false).accessibilityHidden(true)
                } else {
                    detailPlot(domain: domain)
                }
            } else {
                Text(presentation == .preview ? "暂无可绘制的考核" : "所选日期内没有已评分的数值记录。")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(minHeight: presentation == .preview ? 86 : 120)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func plot(selectedDay: Date?) -> some View {
        Chart {
            ForEach(points) { point in
                LineMark(x: .value("考核日期", point.day), y: .value("得分率", point.percentage),
                         series: .value("连续记录", point.segment))
                    .interpolationMethod(.linear).foregroundStyle(Color.accentColor).accessibilityHidden(true)
                PointMark(x: .value("考核日期", point.day), y: .value("得分率", point.percentage))
                    .symbolSize(presentation == .preview ? 22 : (point.day == selectedDay ? 80 : 40))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityLabel("\(schoolDateLabel(point.day))，\(point.title)")
                    .accessibilityValue("\(compactNumber(point.percentage))%")
            }
        }
        .chartYScale(domain: presentation == .preview ? previewScale : 0...100)
    }

    private var previewScale: ClosedRange<Double> {
        // Center the sparkline on the observations, with a minimum span so a tiny change isn't exaggerated.
        let scores = points.map(\.percentage)
        guard let low = scores.min(), let high = scores.max() else { return 0...100 }
        let span = min(100, max(20, high - low + 10))
        let start = min(100 - span, max(0, (low + high - span) * 0.5))
        return start...(start + span)
    }

    private func detailPlot(domain: ClosedRange<Date>) -> some View {
        let days = points.reduce(into: [Date]()) { dates, point in
            if dates.last != point.day { dates.append(point.day) }
        }
        let ticks = days.count <= 4 ? days : [days[0], days[days.count / 2], days[days.count - 1]]
        let selectedDay = selection.flatMap { time in days.min { abs($0.timeIntervalSince(time)) < abs($1.timeIntervalSince(time)) } }
        return VStack(alignment: .leading, spacing: 12) {
            plot(selectedDay: selectedDay)
                .chartXScale(domain: domain)
                .chartXAxis {
                    AxisMarks(values: ticks) { value in
                        AxisTick()
                        AxisValueLabel {
                            if let date = value.as(Date.self) { Text(schoolDateLabel(date, format: "M月d日")) }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                        AxisGridLine()
                        AxisValueLabel { if let n = value.as(Int.self) { Text("\(n)%") } }
                    }
                }
                .chartXSelection(value: $selection)
                .frame(height: 300)
                .accessibilityLabel("历次考核得分率")
            if let selectedDay {
                ForEach(points.filter { $0.day == selectedDay }) { point in
                    Text("\(schoolDateLabel(point.day, format: "M月d日")) · \(point.title)  \(compactNumber(point.percentage))%").font(.callout)
                }
            } else {
                Text(points.count == 1 ? "此日期范围内有 1 次已评分考核。" : "点选日期查看对应考核。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onChange(of: range) { _, _ in selection = nil }
    }
}

struct AttendanceCourseTable<Destination: View>: View {
    let rows: [AttendanceCourseRow]
    private let destination: ((AttendanceCourseRow) -> Destination)?
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .callout) private var countWidth: CGFloat = 46
    @ScaledMetric(relativeTo: .callout) private var rateWidth: CGFloat = 76
    private let columnSpacing: CGFloat = 12
    private let disclosureWidth: CGFloat = 16

    init(rows: [AttendanceCourseRow], @ViewBuilder destination: @escaping (AttendanceCourseRow) -> Destination) {
        self.rows = rows
        self.destination = destination
    }

    init(rows: [AttendanceCourseRow]) where Destination == EmptyView {
        self.rows = rows
        destination = nil
    }

    var body: some View {
        if rows.isEmpty {
            Text("所选范围暂无逐科考勤。").font(.callout).foregroundStyle(.secondary)
        } else {
            ViewThatFits(in: .horizontal) {
                if !typeSize.isAccessibilitySize {
                    table(columnar: true).frame(minWidth: tableMinimumWidth)
                }
                table(columnar: false)
            }
        }
    }

    private var tableMinimumWidth: CGFloat {
        let disclosure = destination == nil ? 0 : disclosureWidth + columnSpacing
        return 108 + 4 * countWidth + rateWidth + 5 * columnSpacing + disclosure
    }

    private func table(columnar: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if columnar {
                tableLine(nil).padding(.bottom, 6).accessibilityHidden(true)
            }
            ForEach(rows) { row in
                let label = rowContent(row, columnar: columnar)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(row.name)
                    .accessibilityValue(spokenValues(row))
                if let destination {
                    NavigationLink { destination(row) } label: { label }
                        .buttonStyle(.plain).hoverEffect(.highlight)
                } else {
                    label
                }
                if row.id != rows.last?.id { Divider() }
            }
        }
    }

    private func rowContent(_ row: AttendanceCourseRow, columnar: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if columnar {
                tableLine(row)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: columnSpacing) {
                    Text(row.name).font(.callout.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading)
                    Text(attendancePercent(row.presentRate)).font(.callout.weight(.medium)).monospacedDigit()
                    if destination != nil { disclosure }
                }
                Text(row.counts.map(namedCounts) ?? "暂无可用的考勤数据").font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let counts = row.counts, counts.total > 0 {
                AttendanceCompositionBar(composition: AttendanceComposition(counts: counts))
            }
        }
        .padding(.vertical, 14)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private func tableLine(_ row: AttendanceCourseRow?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: columnSpacing) {
            Text(row?.name ?? "课程").font(.callout.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(AttendanceStatus.allCases) { status in
                Text(row.map { $0.counts?[status].formatted() ?? "—" } ?? status.title)
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                    .frame(width: countWidth, alignment: .trailing)
            }
            Text(row.map { attendancePercent($0.presentRate) } ?? "出勤率")
                .font(.callout.weight(.medium)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7).frame(width: rateWidth, alignment: .trailing)
            if destination != nil { disclosure.opacity(row == nil ? 0 : 1) }
        }
        .font(.callout)
        .foregroundStyle(row == nil ? Color.secondary : Color.primary)
    }

    private var disclosure: some View {
        Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            .frame(width: disclosureWidth, alignment: .trailing)
    }

    private func namedCounts(_ counts: AttendanceCounts) -> String {
        AttendanceStatus.allCases.map { "\($0.title) \(counts[$0].formatted())" }.joined(separator: " · ")
    }

    private func spokenValues(_ row: AttendanceCourseRow) -> String {
        guard let counts = row.counts else { return "暂无可用的考勤数据" }
        guard counts.total > 0 else { return "暂无考勤记录" }
        return "\(namedCounts(counts))，出勤率 \(attendancePercent(row.presentRate))"
    }
}

private struct AttendanceCompositionBar: View {
    let composition: AttendanceComposition
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                ForEach(composition.segments) { segment in
                    let fraction = segment.fractionRange.upperBound - segment.fractionRange.lowerBound
                    Rectangle().fill(segment.status.color.opacity(reduceTransparency || contrast == .increased ? 1 : 0.52))
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipShape(Capsule())
        }
        .frame(height: 16)
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}
