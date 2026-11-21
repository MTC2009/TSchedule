import SwiftUI

private let coursePanelShape = RoundedRectangle(cornerRadius: 16, style: .continuous)

struct CourseGradesView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let course: CourseGradeDetail
    @State private var sheet: Sheet?
    @State private var estimates: [AssessmentForecast] = []

    private enum Sheet: Identifiable {
        case history, addForecast, editForecast(AssessmentForecast)

        var id: String {
            switch self {
            case .history: "history"
            case .addForecast: "add-forecast"
            case .editForecast(let estimate): estimate.id.uuidString
            }
        }
    }

    var body: some View {
        let points = course.history()
        StudentDetailSurface {
            // Share the backdrop sampling without merging the separate panels.
            GlassEffectContainer(spacing: 8) {
                VStack(alignment: .leading, spacing: 22) {
                    overview(points)
                    GlassCard(padding: 0, shape: coursePanelShape) {
                        CourseTaskList(courseName: course.name, rows: course.rows, estimates: estimates,
                                       forecast: CourseForecast.calculate(current: course.totalPercentage, estimates: estimates),
                                       addEstimate: { sheet = .addForecast }, editEstimate: { sheet = .editForecast($0) })
                    }
                }
            }
        }
        .navigationTitle("课程成绩")
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .history:
                CourseHistorySheet(courseName: course.name, points: points)
            case .addForecast:
                forecastEditor(existing: nil)
            case .editForecast(let estimate):
                forecastEditor(existing: estimate)
            }
        }
        .onChange(of: course.id) { _, _ in
            // Drafts must not follow a destination if its source course or term changes.
            sheet = nil
            estimates = []
        }
    }

    private func overview(_ points: [AssessmentPoint]) -> some View {
        ViewThatFits(in: .horizontal) {
            if !typeSize.isAccessibilitySize {
                HStack(alignment: .top, spacing: 16) {
                    CourseGradeSummary(course: course).frame(width: 224)
                    historyButton(points).frame(minWidth: 224, maxWidth: .infinity)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                CourseGradeSummary(course: course)
                historyButton(points)
            }
        }
    }

    private func historyButton(_ points: [AssessmentPoint]) -> some View {
        Button { sheet = .history } label: {
            GlassCard(padding: 16, shape: coursePanelShape) {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("历次考核得分率").font(.headline)
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary).accessibilityHidden(true)
                    }
                    AssessmentHistoryChart(points: points, presentation: .preview)
                    if !points.isEmpty {
                        Text("点按放大 · 可选日期").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(minHeight: 136, alignment: .topLeading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).hoverEffect(.highlight)
        .accessibilityLabel("放大历次考核得分率图")
        .accessibilityValue(points.isEmpty ? "暂无可绘制记录" : "\(points.count) 次已评分考核")
        .accessibilityIdentifier("course-history-preview")
    }

    private func forecastEditor(existing: AssessmentForecast?) -> some View {
        CourseForecastSheet(courseName: course.name, categories: course.categories, existing: existing,
                            saveEstimate: { estimate in
            if let index = estimates.firstIndex(where: { $0.id == estimate.id }) {
                estimates[index] = estimate
            } else {
                estimates.append(estimate)
            }
        }, removeEstimate: { id in
            estimates.removeAll { $0.id == id }
        })
    }
}

private struct CourseGradeSummary: View {
    let course: CourseGradeDetail

    var body: some View {
        GlassCard(padding: 16, shape: coursePanelShape) {
            VStack(alignment: .leading, spacing: 8) {
                Text(course.name).font(.headline).fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let className = course.className {
                    Text(className).font(.caption).foregroundStyle(.secondary)
                } else if let teacher = course.teacher, let credits = course.credits {
                    Text("\(teacher) · \(compactNumber(credits)) 学分").font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    score.font(.system(.largeTitle, design: .rounded, weight: .semibold)).monospacedDigit()
                    Text("课程总评").font(.caption).foregroundStyle(.secondary)
                    let metadata = scoreMetadata
                    if !metadata.isEmpty { Text(metadata).font(.caption).foregroundStyle(.secondary) }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("course-published-total")
                if let publishedAt = course.firstPublishedAt {
                    Text("首次公布 \(schoolDateLabel(publishedAt, format: "yyyy年M月d日 HH:mm"))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 136, alignment: .topLeading)
        }
    }

    @ViewBuilder private var score: some View {
        if case .numeric(let earned, let possible, _) = course.total {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(earned.formatted(.number))
                    if let possible {
                        Text("/ \(possible.formatted(.number))").font(.callout).foregroundStyle(.secondary)
                    }
                }.fixedSize()
                Text(earned.formatted(.number) + (possible.map { " / " + $0.formatted(.number) } ?? ""))
                    .font(.title2.weight(.semibold))
            }
        } else {
            Text(course.total?.displayText ?? "待公布")
        }
    }

    private var scoreMetadata: String {
        var details = [String]()
        if case .numeric(_, _, let letter?) = course.total { details.append("等级 \(letter)") }
        if let gpa = course.publishedGPA { details.append("绩点 \(gpa.formatted(.number))") }
        return details.joined(separator: " · ")
    }
}
