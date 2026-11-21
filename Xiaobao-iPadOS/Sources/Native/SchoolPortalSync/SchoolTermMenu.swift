import SwiftUI

/// One server-supplied selection across Tasks and GPA. Opening the menu never loads historical records.
struct SchoolTermMenu: View {
    @Environment(AppModel.self) private var model
    let didSelect: () -> Void

    var body: some View {
        let store = model.school
        Menu {
            if let list = store.terms {
                Picker("学期", selection: Binding(get: { store.selectedTermID ?? list.current }, set: { value in
                    model.selectAcademicTerm(value)
                    didSelect()
                })) {
                    ForEach(list.terms) { term in Text(verbatim: term.name).tag(term.id) }
                }
            } else if let issue = store.issues[.terms] {
                Button("重试读取学期") { Task { await store.loadTerms() } }
                Text(issue.message)
            } else { Text("正在读取学期") }
        } label: {
            TaskFilterLabel(title: "学期", value: store.selectedTermTitle ?? store.tasks?.term ?? store.grades?.term ?? "本学期")
        }
        .buttonStyle(.plain).hoverEffect(.highlight)
        .accessibilityIdentifier("school-term-menu")
        .task(id: store.epoch) { await store.loadTerms() }
    }
}
