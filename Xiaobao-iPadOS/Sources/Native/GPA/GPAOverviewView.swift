import SwiftUI

/// Presence means the course has saved what-ifs, even while its detail reloads.
struct CourseForecastDisplay {
    let percentage: Double?
}

struct GPAOverviewView<TermLabel: View, GradeStatus: View>: View {
    let isCurrentTerm: Bool
    let summary: GPASummary?
    let unavailableMessage: String
    let courses: [CourseGradeDetail]
    var forecasts: [CourseGradeDetail.ID: CourseForecastDisplay] = [:]
    // The live source reads details on first navigation; cached sources already have them.
    var courseDestination: ((CourseGradeDetail) -> AnyView)? = nil
    @ViewBuilder let termLabel: () -> TermLabel
    // This area is for grade availability and refresh only. Keep the
    // semester trial in Settings → 成绩工具; do not add it back here.
    @ViewBuilder let gradeStatus: () -> GradeStatus

    @State private var isGPAHidden = false
    @State private var search = ""
    @State private var status: AssessmentStatus?
    @ScaledMetric(relativeTo: .largeTitle) private var headingSize: CGFloat = 52
    @ScaledMetric(relativeTo: .largeTitle) private var readoutSize: CGFloat = 76

    var body: some View {
        if courses.isEmpty {
            overview
        } else {
            overview.searchable(text: $search, placement: .toolbar, prompt: String(localized: "搜索课程或考核"))
        }
    }

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                summaryCard
                if !courses.isEmpty {
                    CourseGradeList(courses: courses.filter { $0.matches(query: search, status: status) },
                                    forecasts: forecasts, status: $status)
                }
                gradeStatus()
            }
            .padding(24).frame(maxWidth: 980).frame(maxWidth: .infinity)
        }
        .navigationDestination(for: CourseGradeDetail.ID.self) { id in
            if let course = courses.first(where: { $0.id == id }) {
                if let courseDestination { courseDestination(course) }
                else { CourseGradesView(course: course) }
            } else {
                StudentDetailSurface {
                    StudentEmptyState(title: String(localized: "课程成绩不可用"), detail: String(localized: "请返回查看当前可用的课程。"))
                }.navigationTitle("课程成绩")
            }
        }
    }

    private var summaryCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .lastTextBaseline, spacing: 20) {
                        heading.fixedSize()
                        Spacer(minLength: 0)
                        VStack(alignment: .trailing, spacing: 4) {
                            if summary != nil { visibilityButton }
                            readout.fixedSize()
                        }
                    }
                    // A narrow split or large type can put the value below, still right-aligned.
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top) {
                            heading
                            Spacer(minLength: 4)
                            if summary != nil { visibilityButton }
                        }
                        readout.frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) {
                        termLabel().fixedSize()
                        provenance.fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 4) { termLabel(); provenance }
                }
            }
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(summary?.source == .forecast ? String(localized: "预测") :
                    isCurrentTerm ? String(localized: "当前") : String(localized: "学期")).font(.title2.weight(.semibold))
            Text("GPA").font(.system(size: headingSize, weight: .bold, design: .rounded))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary?.source == .forecast ? String(localized: "预测 GPA") :
                            isCurrentTerm ? String(localized: "当前 GPA") : String(localized: "学期 GPA"))
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("gpa-heading")
    }

    private var visibilityButton: some View {
        Button {
            isGPAHidden.toggle()
        } label: {
            Image(systemName: isGPAHidden ? "eye.slash" : "eye")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel(isGPAHidden ? String(localized: "显示 GPA") : String(localized: "隐藏 GPA"))
        .accessibilityIdentifier("gpa-visibility")
    }

    @ViewBuilder private var readout: some View {
        if let summary {
            // The number is not part of the view or accessibility tree while hidden.
            Text(isGPAHidden ? "••••" : summary.formattedValue)
                .font(.system(size: readoutSize, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .accessibilityLabel(isGPAHidden ? String(localized: "GPA 已隐藏") : summary.formattedValue)
                .accessibilityIdentifier("gpa-readout")
        } else {
            Text("暂无 GPA").font(.title2.weight(.semibold))
                .accessibilityIdentifier("gpa-readout")
        }
    }

    private var provenance: some View {
        Text(summary?.sourceTitle ?? unavailableMessage)
            .font(.subheadline).foregroundStyle(.primary)
    }
}

private extension GPASummary {
    var sourceTitle: String {
        switch source {
        case .published: String(localized: "校方公布")
        case .localEstimate(let weighted): weighted ? String(localized: "试算 · AP 加权") : String(localized: "试算 · 未加权")
        case .creditWeightedEstimate: String(localized: "估算 · 按学分加权")
        case .forecast: String(localized: "本机试算 · OpenGCalc")
        }
    }

    var formattedValue: String {
        switch source {
        case .published: value.formatted(.number.precision(.fractionLength(0...15)))
        default: value.formatted(.number.precision(.fractionLength(2)))
        }
    }
}
