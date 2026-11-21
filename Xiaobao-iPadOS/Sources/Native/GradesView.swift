import SwiftUI

/// The GPA overview displays results. Settings owns the semester trial forms.
struct GradeTrialSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let client = model.campus
        let scope = client.account?.scope
        Section("成绩工具") {
            if model.school.selected {
                if let book = model.school.grades, let saved = model.school.trialInput(book) {
                    OfflineGradeLab(saved: saved).id(model.school.epoch)
                } else {
                    Text("打开 GPA 读取本学期成绩后，即可在这里试算。")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("settings-school-trial-hint")
                }
            } else if let scope {
                if let saved = client.savedGrades {
                    OfflineGradeLab(saved: saved).id(scope)
                } else {
                    Text(!client.readSavedGrades && client.errors[.grades] == nil
                         ? "正在读取本机成绩。"
                         : "请先在 GPA 页获取成绩。试算只使用本机已保存的成绩。")
                        .foregroundStyle(.secondary)
                }
            } else {
                let book = model.gradebook
                let grades = book.terms.first.map { book.grades(termID: $0.id) } ?? []
                GPAPreviewView(grades: grades, weighted: $model.preferences.weightedGPA)
            }
        }
        .task(id: scope) {
            // A non-forced grade read only opens the current account's cache.
            // Leave any network check or permission action on the GPA page.
            if !model.school.selected, scope != nil { await client.load(.grades, force: false) }
        }
    }
}

private struct GPAPreviewView: View {
    let grades: [Grade]
    @Binding var weighted: Bool
    @State private var selectedID: String?
    @State private var expectedScore: Double?
    private let assessmentWeight = 0.3

    var body: some View {
        if let course = grades.first(where: { $0.id == selectedID }) ?? grades.first {
            DisclosureGroup("GPA 试算") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("计入 AP 加权", isOn: $weighted)
                    Picker("预测课程", selection: Binding(get: { course.id }, set: { selectedID = $0; expectedScore = nil })) {
                        ForEach(grades) { Text($0.name).tag($0.id) }
                    }
                    let mark = expectedScore ?? course.score
                    LabeledContent("预计考核分数", value: compactNumber(mark))
                    Slider(value: Binding(get: { mark }, set: { expectedScore = $0 }), in: 0...100, step: 1) {
                        Text("预计考核分数")
                    }
                    if let result = try? GradeCalculator.projectedScore(current: course.score, assessment: mark, weight: assessmentWeight) {
                        let forecast = grades.map {
                            $0.id == course.id
                                ? Grade(id: $0.id, name: $0.name, score: result, credits: $0.credits, advanced: $0.advanced)
                                : $0
                        }
                        LabeledContent("预测课程总分", value: compactNumber(result))
                        if let gpa = try? GradeCalculator.average(forecast, weighted: weighted) {
                            LabeledContent("预测 GPA", value: gpa.formatted(.number.precision(.fractionLength(2))))
                        }
                    }
                    Text("假设下一次考核占课程总评 30%。试算不会更改成绩。")
                        .font(.caption).foregroundStyle(.secondary)
                    Divider()
                    Text("试算绩点").font(.subheadline.weight(.semibold))
                    ForEach(grades) { grade in
                        if let points = try? GradeCalculator.points(score: grade.score, advanced: grade.advanced, weighted: weighted) {
                            LabeledContent(grade.name, value: compactNumber(points))
                        }
                    }
                    Text("演示规则：90、80、70、60 分分别对应 4、3、2、1 点；及格的 AP 课程可加 1 点。")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(.top, 12)
            }
        } else {
            Text("暂无可试算的课程总评。").foregroundStyle(.secondary)
        }
    }
}

private struct OfflineGradeLab: View {
    let saved: SavedCampusGrades
    @State private var selected = ""
    @State private var mark = 90.0
    @State private var weight = 30.0

    var body: some View {
        let courses = saved.grades.courses.filter { $0.published_score?.percentage != nil }
        if let first = courses.first {
            let course = courses.first { $0.course_id == selected } ?? first
            DisclosureGroup("离线试算") {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("预测科目", selection: Binding(get: { course.course_id }, set: { selected = $0 })) {
                        ForEach(courses, id: \.course_id) { row in
                            Text(saved.roster.first { $0.course_id == row.course_id }?.name ?? "课程名称待载入").tag(row.course_id)
                        }
                    }
                    LabeledContent("预计考核分数", value: "\(Int(mark)) / 100")
                    Slider(value: $mark, in: 0...100, step: 1) { Text("预计考核分数") }
                    LabeledContent("考核占总评", value: "\(Int(weight))%")
                    Slider(value: $weight, in: 0...100, step: 1) { Text("考核占比") }
                    if let current = course.published_score?.percentage,
                       let result = try? GradeCalculator.projectedScore(current: current, assessment: mark, weight: weight / 100) {
                        LabeledContent("预测总评", value: result.formatted(.number.precision(.fractionLength(1))) + "%")
                    }
                }.padding(.top, 12)
            }
        } else {
            Text("暂无可试算的课程总评。").foregroundStyle(.secondary)
        }
    }
}
