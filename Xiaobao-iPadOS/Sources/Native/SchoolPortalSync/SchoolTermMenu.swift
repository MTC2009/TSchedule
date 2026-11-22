import SwiftUI

/// One server-supplied selection across Tasks and GPA. Opening the menu never loads historical records.
struct SchoolTermMenu: View {
    @Environment(AppModel.self) private var model
    var supportsSavedGrades = false
    let didSelect: () -> Void

    var body: some View {
        let store = model.school
        let cached = supportsSavedGrades && model.canShowCachedGrades ?
            model.gradeCache.cachedTerms(verifiedOwner: store.owner) : []
        let savedSelection = model.cachedGradeSnapshot?.overview
        Menu {
            if !cached.isEmpty && (!model.schoolNetworkAvailable || store.terms == nil || store.owner == nil) {
                Picker("学期", selection: Binding(get: { savedSelection?.termID ?? cached[0].id }, set: {
                    model.selectCachedGradeTerm($0); didSelect()
                })) {
                    ForEach(cached) { term in Text(verbatim: term.displayName).tag(term.id) }
                }
            } else if let list = store.terms {
                Picker("学期", selection: Binding(get: { store.selectedTermID ?? list.current }, set: { value in
                    model.selectAcademicTerm(value)
                    didSelect()
                })) {
                    ForEach(list.terms) { term in Text(verbatim: term.displayName).tag(term.id) }
                }
            } else if let issue = store.issues[.terms] {
                Button("重试读取学期") { Task { await store.loadTerms() } }
                Text(issue.message)
            } else { Text("正在读取学期") }
        } label: {
            TaskFilterLabel(title: String(localized: "学期"), value: (supportsSavedGrades ? savedSelection?.displayTerm : nil) ??
                store.selectedTermTitle ?? store.tasks?.displayTerm ?? store.grades?.displayTerm ?? String(localized: "本学期"))
        }
        .buttonStyle(.plain).hoverEffect(.highlight)
        .accessibilityIdentifier("school-term-menu")
        .task(id: TermRead(epoch: store.epoch, owner: store.owner, online: model.schoolNetworkAvailable)) {
            if model.canUseLiveSchool, store.owner != nil { await store.loadTerms() }
        }
    }

    private struct TermRead: Hashable { let epoch: UUID; let owner: String?; let online: Bool }
}
