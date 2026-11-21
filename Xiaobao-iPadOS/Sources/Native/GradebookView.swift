import SwiftUI

struct GradesView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedTermID: String?

    var body: some View {
        let book = model.gradebook
        let term = book.terms.first { $0.id == selectedTermID } ?? book.terms.first
        let isCurrentTerm = term?.id == book.terms.first?.id
        let reports = term.map { book.reports(termID: $0.id) } ?? []
        GPAOverviewView(
            isCurrentTerm: isCurrentTerm,
            summary: term.flatMap { book.gpaSummary(termID: $0.id, weighted: model.preferences.weightedGPA) },
            unavailableMessage: "暂无完整的课程总评可用于试算。",
            courses: reports.map(CourseGradeDetail.init(report:))
        ) {
            if let term {
                Picker("学期", selection: Binding(get: { term.id }, set: { selectedTermID = $0 })) {
                    ForEach(book.terms) { Text($0.title).tag($0.id) }
                }
                .pickerStyle(.menu)
                .frame(minHeight: 44)
                .accessibilityIdentifier("gpa-term-picker")
            }
        } gradeStatus: {
            EmptyView()
        }
    }
}
