import SwiftUI

struct CourseHistorySheet: View {
    @Environment(\.dismiss) private var dismiss
    let courseName: String
    let points: [AssessmentPoint]
    @State private var start: Date?
    @State private var end: Date?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(courseName).font(.headline).accessibilityAddTraits(.isHeader)
                    if let first = points.first?.day, let last = points.last?.day {
                        let range = AssessmentHistoryRange(start: start ?? first, end: end ?? last)
                        rangeControls(first...last)
                        if let range {
                            AssessmentHistoryChart(points: points.filter(range.contains), range: range)
                        } else {
                            Label("开始日期不能晚于结束日期。", systemImage: "exclamationmark.circle")
                                .font(.callout)
                        }
                    } else {
                        StudentEmptyState(title: "暂无得分走势", detail: "需要同时有日期和数值分数的已评分考核。", symbol: "chart.xyaxis.line")
                    }
                }
                .padding(24).frame(maxWidth: 840).frame(maxWidth: .infinity)
            }
            .navigationTitle("历次考核得分率")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
        .environment(\.calendar, SchoolClock.calendar)
        .environment(\.timeZone, SchoolClock.calendar.timeZone)
        .presentationSizing(.page)
    }

    private func rangeControls(_ bounds: ClosedRange<Date>) -> some View {
        VStack(spacing: 0) {
            DatePicker("开始日期", selection: Binding(get: { start ?? bounds.lowerBound }, set: { start = $0 }),
                       in: bounds, displayedComponents: .date)
                .accessibilityIdentifier("course-history-start")
            Divider()
            DatePicker("结束日期", selection: Binding(get: { end ?? bounds.upperBound }, set: { end = $0 }),
                       in: bounds, displayedComponents: .date)
                .accessibilityIdentifier("course-history-end")
        }
        .font(.subheadline)
    }
}
