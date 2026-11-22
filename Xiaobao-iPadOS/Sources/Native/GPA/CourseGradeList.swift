import SwiftUI

struct CourseGradeList: View {
    let courses: [CourseGradeDetail]
    var forecasts: [CourseGradeDetail.ID: CourseForecastDisplay] = [:]
    @Binding var status: AssessmentStatus?
    @Environment(\.dynamicTypeSize) private var typeSize

    private let tileSpacing: CGFloat = 16

    private var columns: [GridItem] {
        let size: GridItem.Size = typeSize.isAccessibilitySize ? .flexible() : .adaptive(minimum: 224)
        return [GridItem(size, spacing: tileSpacing, alignment: .topLeading)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack { heading; Spacer(); filter }
                VStack(alignment: .leading, spacing: 4) { heading; filter }
            }
            .padding(.horizontal, 4)
            if courses.isEmpty {
                GlassCard(padding: 22) {
                    StudentEmptyState(title: String(localized: "没有匹配的课程"), detail: String(localized: "可更换关键词或评分状态。"))
                }
            } else {
                GlassEffectContainer(spacing: 8) {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: tileSpacing) {
                        ForEach(courses) { course in
                            NavigationLink(value: course.id) {
                                courseTile(course)
                            }
                            .buttonStyle(.plain)
                            .hoverEffect(.highlight)
                            .accessibilityIdentifier("gpa-course-\(course.id.course)")
                        }
                    }
                }
            }
        }
    }

    private var heading: some View {
        Text("课程成绩").font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
    }

    private var filter: some View {
        Picker("评分状态", selection: $status) {
            Text("全部状态").tag(nil as AssessmentStatus?)
            ForEach(AssessmentStatus.allCases) { Text($0.title).tag(Optional($0)) }
        }
        .pickerStyle(.menu)
        .font(.subheadline)
        .frame(minHeight: 44)
        .accessibilityIdentifier("gpa-grade-filter")
    }

    private func courseTile(_ course: CourseGradeDetail) -> some View {
        let forecast = forecasts[course.id]
        let total = forecast?.percentage.map { $0.formatted(.number.precision(.fractionLength(1))) + "%" } ??
                    course.total?.displayText ?? String(localized: "待公布")
        return GlassCard(padding: 22) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    Text(course.name).font(.headline).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.forward").font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary).accessibilityHidden(true)
                }
                Spacer(minLength: 12)
                VStack(alignment: .leading, spacing: 3) {
                    if course.total != nil || forecast?.percentage != nil {
                        ViewThatFits(in: .horizontal) {
                            Text(total).font(.system(.largeTitle, design: .rounded, weight: .semibold)).fixedSize()
                            Text(total).font(.title2.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                        }
                        .monospacedDigit()
                    } else {
                        Text(total).font(.title3.weight(.medium))
                    }
                    HStack(alignment: .lastTextBaseline) {
                        Text("课程总评").font(.subheadline)
                        Spacer(minLength: 3)
                        if forecast != nil { Text("预测成绩").font(.caption) }
                    }.foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 144, alignment: .topLeading)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(course.name)
        .accessibilityValue(forecast?.percentage != nil ? String(localized: "预测成绩 \(total)") :
            forecast != nil ? String(localized: "总评 \(total)，有已保存的预估任务") : String(localized: "总评 \(total)"))
    }
}

