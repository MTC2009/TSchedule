import SwiftUI

struct CourseTaskList: View {
    let courseName: String
    let rows: [GradeBreakdownRow]
    let groups: ForecastGroups
    let estimates: [AssessmentForecast]
    let forecast: CourseForecast.Projection
    var canEditForecast = true
    let addEstimate: () -> Void
    let editEstimate: (AssessmentForecast) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("全部任务").font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
                Spacer()
                Button(action: addEstimate) {
                    Image(systemName: "plus").font(.body.weight(.medium)).foregroundStyle(.tint)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain).hoverEffect(.highlight)
                .disabled(!canEditForecast)
                .accessibilityLabel("添加预估")
                .accessibilityIdentifier("course-forecast-add")
            }
            Divider()
            if rows.isEmpty {
                Text("暂无已发布的任务").font(.callout).foregroundStyle(.secondary).padding(.vertical, 14)
            } else {
                TaskColumns(title: String(localized: "项目"), result: String(localized: "成绩"), isHeading: true).padding(.trailing, 24)
                ForEach(rows) { row in
                    Divider()
                    switch row {
                    case .assessment(let item):
                        assessment(item)
                    case .group(let title, let weight, let mark, let items):
                        DisclosureGroup {
                            VStack(spacing: 0) {
                                ForEach(items) { item in
                                    if item.id != items.first?.id { Divider() }
                                    assessment(item).padding(.leading, 14)
                                }
                            }
                            .background(.fill.tertiary, in: .rect(cornerRadius: 8))
                        } label: {
                            TaskColumns(title: title, weight: weight, result: mark?.displayText ?? "—", emphasizesTitle: true)
                        }
                        .disclosureGroupStyle(AssessmentDisclosureStyle(identifier: "gpa-assessment-group-\(title)"))
                    }
                }
            }
            if !estimates.isEmpty { forecastSection }
        }
        .padding(.horizontal, 16).padding(.bottom, 12)
    }

    @ViewBuilder private func assessment(_ item: AssessmentResult) -> some View {
        let feedback = item.feedback.flatMap { $0.isEmpty ? nil : $0 }
        let notes = [item.date.map { schoolDateLabel($0, format: "M月d日") }, feedback.map { _ in String(localized: "有反馈") }]
            .compactMap { $0 }.joined(separator: " · ")
        let identifier = "gpa-assessment-\(item.id)"
        let columns = TaskColumns(title: item.title, subtitle: notes.isEmpty ? nil : notes, weight: item.weight, result: item.resultText)
            .padding(.trailing, 24)
        if let feedback {
            NavigationLink {
                AssessmentFeedbackView(courseName: courseName, item: item, feedback: feedback)
            } label: {
                columns.contentShape(Rectangle())
            }
            .buttonStyle(.plain).hoverEffect(.highlight)
            .accessibilityHint("查看考核反馈")
            .accessibilityIdentifier(identifier)
        } else {
            columns.accessibilityIdentifier(identifier)
        }
    }

    private var forecastSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
            Text("预估任务").font(.subheadline.weight(.semibold)).padding(.top, 12).accessibilityAddTraits(.isHeader)
            ForEach(estimates) { estimate in
                let group = groups[groups.id(for: estimate)]
                Button { editEstimate(estimate) } label: {
                    HStack(spacing: 0) {
                        TaskColumns(title: estimate.name ?? String(localized: "未命名任务"),
                                    subtitle: group?.title ?? String(localized: "未提供分组"),
                                    weight: group?.weight, groupShare: true,
                                    result: estimate.mark.formatted(.number.precision(.fractionLength(0...2))) + "%")
                        Image(systemName: "pencil").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                            .frame(width: 24).accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).hoverEffect(.highlight)
                .disabled(!canEditForecast)
                .accessibilityHint("编辑或移除这项预估")
                .accessibilityIdentifier("course-forecast-item-\(estimate.id.uuidString)")
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                switch forecast.result {
                case .estimated(let result):
                    let value = result.formatted(.number.precision(.fractionLength(1))) + "%"
                    LabeledContent("预估总评", value: value)
                        .font(.subheadline.weight(.semibold))
                        .padding(.trailing, 24)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("预估总评")
                        .accessibilityValue(value)
                        .accessibilityIdentifier("course-forecast-result")
                    Text("按百分制试算，不修改正式成绩。")
                        .foregroundStyle(.secondary)
                case .missingCourseTotal:
                    Text("还没有可换算的课程总评，暂不能计算预估。")
                case .missingWeight:
                    Text("校宝未提供完整的分组占比，暂不能计算预估总评。")
                case .missingGroup:
                    Text("校宝未提供这项预估的分组，暂不能计算预估总评。")
                case .unknownAllocation:
                    Text("分组结构或各项占比无法核对，暂不能合成课程总评。")
                case .missingCount:
                    Text("请选择有分组资料的考核。")
                case .missingScoreScale, .nonNumericCourse:
                    Text("已有成绩缺少可换算的满分或采用等级制，不能按百分制合成总评。")
                case .selectLeaf:
                    Text("请选择任务所属的子分组；上级分组只用来汇总。")
                case .noEstimates:
                    EmptyView()
                }
                ForEach(forecast.partialSubtotals) { row in
                    LabeledContent(String(localized: "预估组分：\(row.title)"), value: row.percentage.formatted(.number.precision(.fractionLength(1))) + "%")
                        .accessibilityIdentifier("course-forecast-subtotal-" + row.id)
                }
            }
            .font(.footnote).padding(.vertical, 10)
        }
    }
}

private struct TaskColumns: View {
    let title: String
    var subtitle: String? = nil
    var weight: AssessmentWeight? = nil
    var groupShare = false
    let result: String
    var emphasizesTitle = false
    var isHeading = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .subheadline) private var valueWidth: CGFloat = 102

    var body: some View {
        Group {
            if isHeading {
                if !typeSize.isAccessibilitySize {
                    ViewThatFits(in: .horizontal) { columns; EmptyView() }
                }
            } else if typeSize.isAccessibilitySize {
                stacked
            } else {
                ViewThatFits(in: .horizontal) { columns; stacked }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue([subtitle, weight.map { "\(scopeLabel($0)) \($0.displayText)" } ?? String(localized: "权重未提供"), String(localized: "成绩 \(result)")]
            .compactMap { $0 }.joined(separator: String(localized: "，")))
        .accessibilityHidden(isHeading)
    }

    private var columns: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            name.frame(minWidth: 112, maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 2) {
                Text(isHeading ? String(localized: "权重") : weight?.displayText ?? "—").monospacedDigit()
                if let weight { Text(scopeLabel(weight)).font(.caption2).foregroundStyle(.secondary) }
            }
            .frame(width: valueWidth, alignment: .trailing)
            Text(result).monospacedDigit()
                .frame(width: valueWidth, alignment: .trailing)
        }
        .font(isHeading ? .caption.weight(.medium) : .subheadline)
        .foregroundStyle(isHeading ? .secondary : .primary)
        .padding(.vertical, isHeading ? 8 : 10)
        .frame(minHeight: isHeading ? nil : 44)
    }

    private var stacked: some View {
        VStack(alignment: .leading, spacing: 5) {
            name
            Text("成绩 \(result)")
            Text(weight.map { "\(scopeLabel($0)) \($0.displayText)" } ?? String(localized: "权重未提供"))
                .foregroundStyle(.secondary)
        }
        .font(.subheadline).padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }

    private func scopeLabel(_ weight: AssessmentWeight) -> String {
        groupShare ? (weight.scope == .course ? String(localized: "分组占总评") : String(localized: "分组占上级")) : weight.scopeTitle
    }

    private var name: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(isHeading ? .caption.weight(.medium) : emphasizesTitle ? .subheadline.weight(.semibold) : .subheadline)
            if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct AssessmentDisclosureStyle: DisclosureGroupStyle {
    let identifier: String

    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 0) {
            Button {
                configuration.isExpanded.toggle()
            } label: {
                HStack(spacing: 0) {
                    configuration.label
                    Image(systemName: configuration.isExpanded ? "chevron.down" : "chevron.forward")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .frame(width: 24).accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).hoverEffect(.highlight)
            .accessibilityHint(configuration.isExpanded ? String(localized: "收起评估项目") : String(localized: "展开评估项目"))
            .accessibilityIdentifier(identifier)
            if configuration.isExpanded { configuration.content }
        }
    }
}

private struct AssessmentFeedbackView: View {
    let courseName: String
    let item: AssessmentResult
    let feedback: String

    var body: some View {
        StudentDetailSurface {
            VStack(alignment: .leading, spacing: 14) {
                Text(item.title).font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
                Text(courseName).foregroundStyle(.secondary)
                LabeledContent("成绩", value: item.resultText)
                if let date = item.date { LabeledContent("日期", value: schoolDateLabel(date)) }
                if let weight = item.weight { LabeledContent(weight.scopeTitle, value: weight.displayText) }
                if let percentage = item.percentage {
                    LabeledContent("得分率", value: (percentage / 100).formatted(.percent.precision(.fractionLength(0...1))))
                }
                Divider()
                Text("反馈").font(.headline)
                Text(feedback).textSelection(.enabled)
            }
            .padding(24).frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: .rect(cornerRadius: 30))
        }.navigationTitle("成绩详情")
    }
}

private extension AssessmentResult {
    var resultText: String {
        mark?.displayText ?? (status == AssessmentStatus.graded.rawValue ? String(localized: "未提供") : statusTitle)
    }
}

extension AssessmentWeight {
    var scopeTitle: String { scope == .course ? String(localized: "占课程总评") : String(localized: "占所属分组") }
    var displayText: String { fraction.formatted(.percent.precision(.fractionLength(0...2))) }
}
