import SwiftUI

struct SchoolPortalGradebook: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let store = model.school, book = store.grades
        if book == nil && store.pending.contains(.grades) {
            ProgressView("正在读取本学期成绩")
        } else { overview(store, book) }
    }

    private func overview(_ store: SchoolPortalStore, _ book: SchoolPortalGrades?) -> some View {
        let summary = book?.gpa.flatMap { $0.isFinite && $0 >= 0 ? GPASummary(value: $0, source: .published) : nil }
        return GPAOverviewView(isCurrentTerm: true, summary: summary,
            unavailableMessage: book == nil ? "尚未获取本学期成绩。" :
                (book?.gpaUnavailable == true ? "本次未能读取学期 GPA。" : "校宝未提供本学期 GPA。"),
            courses: book.map { source in source.courses.map { source.courseDetail($0, groups: store.groups[$0.id]) } } ?? [],
            courseDestination: { AnyView(SchoolPortalCoursePage(id: $0.id)) }) {
                if let book { Text(book.term) }
            } gradeStatus: {
                if let issue = store.issues[.grades] { Text(issue.message).foregroundStyle(.secondary) }
                if let book, book.courses.isEmpty { Text("校宝尚未公布本学期的课程成绩。") }
                Button {
                    model.requestSchoolGrades()
                } label: {
                    if store.pending.contains(.grades) { Label { Text("正在读取成绩") } icon: { ProgressView() } }
                    else { Label("刷新 GPA", systemImage: "arrow.clockwise") }
                }.buttonStyle(.glass).disabled(store.pending.contains(.grades)).accessibilityIdentifier("gpa-check-grades")
            }
    }
}

struct SchoolPortalCoursePage: View {
    @Environment(AppModel.self) private var model
    let id: CourseGradeDetail.ID
    var body: some View {
        let store = model.school
        if let book = store.grades, book.term == id.term, let course = book.courses.first(where: { $0.id == id.course }) {
            Group {
                if let groups = store.groups[course.id] {
                    CourseGradesView(course: book.courseDetail(course, groups: groups))
                } else if let key = store.detailKey(course) {
                    if let issue = store.issues[key] { SchoolPortalRetry(issue: issue) { await store.loadDetail(course) } }
                    else { ProgressView("正在读取课程明细") }
                } else {
                    StudentEmptyState(title: "校宝未提供明细入口", detail: "课程总评仍可在 GPA 页查看。")
                }
            }.navigationTitle(course.name).task(id: store.gradeRevision) { await store.loadDetail(course) }
        } else { StudentEmptyState(title: "课程成绩不可用", detail: "请返回 GPA 页查看当前账号的课程。") }
    }
}
