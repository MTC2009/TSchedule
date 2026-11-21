import SwiftUI
import UIKit

struct AttendanceView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var category: AttendanceCategory = .classroom
    @State private var period: AttendancePeriod = .semester
    @State private var start = AttendanceReport.demo.range.start
    @State private var end = AttendanceReport.demo.range.end
    @State private var status: AttendanceStatus?
    private let summaryWidth: CGFloat = 408
    private let pageInset: CGFloat = 24
    private let maximumPageWidth: CGFloat = 1400
    private var range: SchoolDateRange { .init(start: start, end: end) }
    private var report: AttendanceReport? { model.attendance.filtered(category: category, range: range) }

    var body: some View {
        GeometryReader { geometry in
            let contentWidth = max(0, min(geometry.size.width, maximumPageWidth) - 2 * pageInset)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    filters
                    if let report {
                        if geometry.size.width > 1080 && !typeSize.isAccessibilitySize {
                            HStack(alignment: .top, spacing: 20) {
                                overview(report, width: summaryWidth, fillsRow: true).frame(width: summaryWidth)
                                courseList(report, fillsRow: true)
                            }
                            // Give both glass surfaces the taller card's natural height inside the scroll view.
                            .fixedSize(horizontal: false, vertical: true)
                        } else {
                            overview(report, width: contentWidth)
                            courseList(report)
                        }
                    } else {
                        GlassCard {
                            VStack(spacing: 16) {
                                StudentEmptyState(title: "这个范围尚未载入", detail: "当前只有本学期的上课考勤汇总。", symbol: "calendar.badge.exclamationmark")
                                Button("查看本学期上课考勤", systemImage: "arrow.uturn.backward") {
                                    category = .classroom; period = .semester
                                    start = model.attendance.range.start; end = model.attendance.range.end
                                }.buttonStyle(.glass)
                            }.frame(maxWidth: .infinity)
                        }
                    }
                }.padding(pageInset).frame(maxWidth: maximumPageWidth).frame(maxWidth: .infinity)
            }
        }
    }

    private var filters: some View {
        let startSelection = Binding(get: { start }, set: { value in
            start = value; if end < start { end = start }; period = .custom
        })
        let endSelection = Binding(get: { end }, set: { value in
            end = value; if start > end { start = end }; period = .custom
        })
        return AttendanceFilterBar(category: $category, period: period, start: startSelection, end: endSelection) { value in
            period = value
            if let newRange = value.range(now: model.now, semester: model.attendance.range) {
                start = newRange.start; end = newRange.end
            }
        }
    }

    private func overview(_ report: AttendanceReport, width: CGFloat, fillsRow: Bool = false) -> some View {
        let totals = report.totals
        return AttendanceOverviewPanel(totals: totals, rate: totals.rate, range: report.range, width: width,
                                       fillsRow: fillsRow, status: $status)
    }

    private func courseList(_ report: AttendanceReport, fillsRow: Bool = false) -> some View {
        let rows = report.courses.filter { course in status.map { course.counts[$0] > 0 } ?? true }
        return GlassCard(padding: 18, shape: .rect(cornerRadius: 18)) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("考勤详情").font(.headline).accessibilityAddTraits(.isHeader)
                    if let status {
                        Spacer()
                        Button { self.status = nil } label: {
                            Label("\(status.title) · 清除筛选", systemImage: "xmark.circle")
                                .font(.callout).frame(minHeight: 44)
                        }.buttonStyle(.plain).foregroundStyle(status.color)
                    }
                }
                if rows.isEmpty, status != nil {
                    StudentEmptyState(title: "没有匹配的课程", detail: "请选择其他考勤状态，或清除筛选。")
                } else {
                    AttendanceCourseTable(rows: rows.map(AttendanceCourseRow.init(course:))) { row in
                        if let counts = row.counts {
                            let course = AttendanceCourseSummary(id: row.id, name: row.name, counts: counts)
                            AttendanceCourseDetailView(course: course, report: report, initialStatus: status)
                        }
                    }
                }
            }
            .frame(maxHeight: fillsRow ? .infinity : nil, alignment: .topLeading)
        }
    }
}

/// Identical summary layout and status selection across the demo and the school. The caller owns the rate's provenance.
struct AttendanceOverviewPanel: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .callout) private var statusColumnWidth: CGFloat = 146
    private let summaryInset: CGFloat = 18
    let totals: AttendanceCounts
    let rate: Double?
    let range: SchoolDateRange
    let width: CGFloat
    var fillsRow = false
    @Binding var status: AttendanceStatus?

    var body: some View {
        let gap: CGFloat = 20
        let columnWidth = (width - 2 * summaryInset - gap) / 2
        let hasStatusColumn = !fillsRow && !typeSize.isAccessibilitySize && columnWidth >= max(200, statusColumnWidth)
        let layout = hasStatusColumn ? AnyLayout(HStackLayout(spacing: gap)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
        let column = hasStatusColumn || typeSize.isAccessibilitySize
            ? GridItem(.flexible()) : GridItem(.adaptive(minimum: statusColumnWidth), spacing: 12)
        return GlassCard(padding: summaryInset, shape: .rect(cornerRadius: 18)) {
            VStack(alignment: .leading, spacing: 14) {
                Text("考勤汇总").font(.headline).accessibilityAddTraits(.isHeader)
                layout {
                    AttendanceRing(counts: totals, rate: rate)
                        .id([range.start, range.end])
                        .frame(width: hasStatusColumn ? columnWidth : nil)
                    statusGrid(totals: totals, column: column)
                        .frame(width: hasStatusColumn ? columnWidth : nil)
                }
            }
            .frame(maxHeight: fillsRow ? .infinity : nil, alignment: .topLeading)
        }
    }

    private func statusGrid(totals: AttendanceCounts, column: GridItem) -> some View {
        LazyVGrid(columns: [column], spacing: 10) {
            ForEach(AttendanceStatus.allCases) { item in
                Button { status = status == item ? nil : item } label: {
                    HStack(spacing: 9) {
                        Circle().fill(item.color).frame(width: 8, height: 8)
                        Text(item.title).font(.callout)
                        Spacer()
                        Text("\(totals[item])").font(.body.weight(.semibold)).monospacedDigit()
                        Image(systemName: status == item ? "checkmark" : "chevron.right").font(.caption2)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10).frame(minHeight: 44)
                    .background(item.color.opacity(status == item ? 0.2 : 0.07), in: .rect(cornerRadius: 16))
                }.buttonStyle(.plain).accessibilityLabel("\(item.title) \(totals[item]) 次，筛选考勤")
                    .accessibilityAddTraits(status == item ? .isSelected : [])
            }
        }
    }

}

struct AttendanceFilterBar: View {
    @ScaledMetric(relativeTo: .callout) private var categoryWidth: CGFloat = 216
    @ScaledMetric(relativeTo: .callout) private var shortcutsWidth: CGFloat = 265
    @ScaledMetric(relativeTo: .callout) private var segmentControlHeight: CGFloat = 44
    @Binding var category: AttendanceCategory
    let period: AttendancePeriod
    @Binding var start: Date
    @Binding var end: Date
    let selectPeriod: (AttendancePeriod) -> Void

    var body: some View {
        GlassCard(padding: 12, shape: .rect(cornerRadius: 18)) {
            VStack(alignment: .leading, spacing: 10) {
                typeAndShortcuts
                ViewThatFits(in: .horizontal) {
                    dateRow
                    VStack(alignment: .leading, spacing: 8) { startPicker; endPicker }
                }
            }
        }
    }

    private var typeAndShortcuts: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                typeChoices
                shortcuts
            }
            .fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: 10) {
                fittingSegments(typeChoices)
                fittingSegments(shortcuts)
            }
        }
    }

    private func fittingSegments<Segments: View>(_ segments: Segments) -> some View {
        ViewThatFits(in: .horizontal) {
            segments.fixedSize(horizontal: true, vertical: false)
            ScrollView(.horizontal) { segments.fixedSize(horizontal: true, vertical: false) }
                .contentMargins(.vertical, 2, for: .scrollContent)
        }
    }

    private var typeChoices: some View {
        AttendanceSegmentedControl(label: "考勤类型", options: AttendanceCategory.allCases,
                                   title: \.title, selection: category) { value in
            category = value
        }
        .frame(width: categoryWidth, height: segmentControlHeight)
    }

    private var shortcuts: some View {
        AttendanceSegmentedControl(label: "快捷时段", options: AttendancePeriod.allCases.filter { $0 != .custom },
                                   title: \.title, selection: period, widthsFollowTitles: true, select: selectPeriod)
            .frame(width: shortcutsWidth, height: segmentControlHeight)
    }

    private var dateRow: some View {
        HStack(spacing: 14) { startPicker; endPicker }.fixedSize(horizontal: true, vertical: false)
    }

    private var startPicker: some View { datePicker("开始", selection: $start, id: "attendance-filter-start") }
    private var endPicker: some View { datePicker("结束", selection: $end, id: "attendance-filter-end") }

    private func datePicker(_ title: LocalizedStringKey, selection: Binding<Date>, id: String) -> some View {
        DatePicker(title, selection: selection, displayedComponents: .date)
            .datePickerStyle(.compact).fixedSize(horizontal: true, vertical: false)
            .accessibilityIdentifier(id)
            .frame(minHeight: 44)
    }
}

private struct AttendanceSegmentedControl<Option: Equatable>: UIViewRepresentable {
    @Environment(\.isEnabled) private var isEnabled
    let label: String
    let options: [Option]
    let title: KeyPath<Option, String>
    let selection: Option
    var widthsFollowTitles = false
    let select: (Option) -> Void

    func makeUIView(context: Context) -> UISegmentedControl {
        let control = UISegmentedControl(items: options.map { $0[keyPath: title] })
        control.accessibilityLabel = label
        control.apportionsSegmentWidthsByContent = widthsFollowTitles
        control.addAction(UIAction { [weak coordinator = context.coordinator] action in
            guard let control = action.sender as? UISegmentedControl else { return }
            coordinator?.selectIndex?(control.selectedSegmentIndex)
        }, for: .valueChanged)
        return control
    }

    func updateUIView(_ control: UISegmentedControl, context: Context) {
        context.coordinator.selectIndex = { [options, select] index in
            guard options.indices.contains(index) else { return }
            select(options[index])
        }
        control.isEnabled = isEnabled
        // A manually chosen date range is not represented by a visible segment.
        let index = options.firstIndex(of: selection) ?? UISegmentedControl.noSegment
        if control.selectedSegmentIndex != index { control.selectedSegmentIndex = index }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var selectIndex: ((Int) -> Void)?
    }
}

struct AttendanceCourseDetailView: View {
    let course: AttendanceCourseSummary
    let report: AttendanceReport
    let initialStatus: AttendanceStatus?
    @State private var filter = "all"
    var body: some View {
        StudentDetailSurface {
            StudentPageHeader(title: course.name, subtitle: report.source, portalSection: "我的考勤")
            GlassCard {
                VStack(alignment: .leading, spacing: 20) {
                    HStack { Text(attendancePercent(course.counts.rate)).font(.system(size: 52, weight: .semibold, design: .rounded)).foregroundStyle(.blue); Spacer(); Text("共 \(course.counts.total) 次").foregroundStyle(.secondary) }
                    Text("\(schoolDateLabel(report.range.start, format: "yyyy.MM.dd")) — \(schoolDateLabel(report.range.end, format: "yyyy.MM.dd"))").font(.callout).foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 18) {
                        ForEach(AttendanceStatus.allCases) { MetricValue(title: $0.title, value: "\(course.counts[$0]) 次", color: $0.color) }
                    }
                }
            }
            GlassCard {
                VStack(alignment: .leading, spacing: 18) {
                    Text("逐次考勤").font(.headline)
                    if let records = report.records {
                        Picker("状态", selection: $filter) {
                            Text("全部").tag("all")
                            ForEach(AttendanceStatus.allCases) { Text($0.title).tag($0.rawValue) }
                        }.pickerStyle(.menu)
                        let matching = records.filter { $0.courseID == course.id && (filter == "all" || $0.status.rawValue == filter) }.sorted { $0.date > $1.date }
                        if matching.isEmpty { StudentEmptyState(title: "没有匹配的记录", detail: "此课程在所选范围与状态下没有考勤记录。") }
                        ForEach(matching) { record in
                            HStack { VStack(alignment: .leading) { Text(schoolDateLabel(record.date, format: "M月d日 HH:mm")); if !record.note.isEmpty { Text(record.note).font(.caption).foregroundStyle(.secondary) } }; Spacer(); Text(record.status.title).foregroundStyle(record.status.color) }
                            Divider()
                        }
                    } else {
                        StudentEmptyState(title: "逐次记录尚未载入", detail: "当前只有汇总，没有每次考勤的日期、节次或原因。", symbol: "list.bullet.clipboard")
                    }
                }
            }
        }.navigationTitle("课程考勤").onAppear { filter = initialStatus?.rawValue ?? "all" }
    }
}
