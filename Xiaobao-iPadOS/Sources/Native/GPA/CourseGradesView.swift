import SwiftUI

private let coursePanelShape = RoundedRectangle(cornerRadius: 16, style: .continuous)

struct CourseGradesView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let course: CourseGradeDetail
    struct Editing {
        let drafts: [AssessmentForecast]
        let available: Bool
        let save: (AssessmentForecast) throws -> Void
        let remove: (UUID) throws -> Void
    }
    var editing: Editing? = nil
    @State private var sheet: Sheet?
    @State private var transientEstimates: [AssessmentForecast] = []
    private var estimates: [AssessmentForecast] { editing?.drafts ?? transientEstimates }

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
        let projection = CourseForecast.project(current: course.totalPercentage, groups: course.forecastGroups, estimates: estimates)
        StudentDetailSurface {
            // Share the backdrop sampling without merging the separate panels.
            GlassEffectContainer(spacing: 8) {
                VStack(alignment: .leading, spacing: 22) {
                    overview(points, projection: projection)
                    GlassCard(padding: 0, shape: coursePanelShape) {
                        CourseTaskList(courseName: course.name, rows: course.rows, groups: course.forecastGroups, estimates: estimates,
                                       forecast: projection, canEditForecast: editing?.available ?? true,
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
            transientEstimates = []
        }
        .onChange(of: course.forecastGroups) { _, _ in
            // An open picker depends on this snapshot; saved drafts instead rebind by their anchor.
            sheet = nil
            transientEstimates = []
        }
    }

    private func overview(_ points: [AssessmentPoint], projection: CourseForecast.Projection) -> some View {
        ViewThatFits(in: .horizontal) {
            if !typeSize.isAccessibilitySize {
                HStack(alignment: .top, spacing: 16) {
                    CourseGradeSummary(course: course, prediction: projection.percentage).frame(width: 224)
                    historyButton(points).frame(minWidth: 224, maxWidth: .infinity)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                CourseGradeSummary(course: course, prediction: projection.percentage)
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
        .accessibilityValue(points.isEmpty ? String(localized: "暂无可绘制记录") : String(localized: "\(points.count) 次已评分考核"))
        .accessibilityIdentifier("course-history-preview")
    }

    private func forecastEditor(existing: AssessmentForecast?) -> some View {
        CourseForecastSheet(courseName: course.name, groups: course.forecastGroups, existing: existing,
                            saveEstimate: { estimate in
            if let editing {
                try editing.save(estimate)
            } else if let index = transientEstimates.firstIndex(where: { $0.id == estimate.id }) {
                transientEstimates[index] = estimate
            } else {
                transientEstimates.append(estimate)
            }
            sheet = nil
        }, removeEstimate: { id in
            if let editing { try editing.remove(id) }
            else { transientEstimates.removeAll { $0.id == id } }
            sheet = nil
        })
    }
}

private struct CourseGradeSummary: View {
    let course: CourseGradeDetail
    let prediction: Double?

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
                    if prediction != nil { Text("预测成绩").font(.caption).foregroundStyle(.secondary) }
                    else if !scoreMetadata.isEmpty { Text(scoreMetadata).font(.caption).foregroundStyle(.secondary) }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(prediction == nil ? "course-published-total" : "course-forecast-effective-total")
                if let publishedAt = course.firstPublishedAt {
                    Text("首次公布 \(schoolDateLabel(publishedAt, format: "yyyy年M月d日 HH:mm"))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 136, alignment: .topLeading)
        }
    }

    @ViewBuilder private var score: some View {
        if let prediction {
            Text(prediction.formatted(.number.precision(.fractionLength(1))) + "%")
        } else if case .numeric(let earned, let possible, _) = course.total {
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
            Text(course.total?.displayText ?? String(localized: "待公布"))
        }
    }

    private var scoreMetadata: String {
        var details = [String]()
        if case .numeric(_, _, let letter?) = course.total { details.append(String(localized: "等级 \(letter)")) }
        if let gpa = course.publishedGPA { details.append(String(localized: "绩点 \(gpa.formatted(.number))")) }
        return details.joined(separator: " · ")
    }
}
