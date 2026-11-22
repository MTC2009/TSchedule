import SwiftUI

struct SchoolPortalGradebook: View {
    @Environment(AppModel.self) private var model
    @State private var failedRestore: CourseForecastStore.Scope?
    private struct DetailRead: Hashable {
        let scope: CourseForecastStore.Scope?
        let revision: UUID
        let courses: Set<String>
    }

    var body: some View {
        let store = model.school, book = model.displayedGradeBook
        let scope = model.courseForecastScope
        let drafts = scope.flatMap { model.courseForecasts.read(in: $0) } ?? [:]
        let read = DetailRead(scope: scope, revision: store.gradeRevision, courses: Set(drafts.keys))
        Group {
            if book == nil && store.pending.contains(store.gradeRead) {
                ProgressView("正在读取所选学期成绩")
            } else { overview(store, book, scope: scope, drafts: drafts) }
        }
        .task(id: scope) {
            guard model.courseForecastScope == scope, model.tab == .grades else { return }
            model.courseForecasts.open(scope)
        }
        .task(id: read) {
            // Only the selected GPA view rereads details for courses with saved
            // drafts. Honor the existing roster, identity, session and read bounds.
            guard let scope = read.scope, let book, model.canUseLiveSchool,
                  store.owner == scope.owner, store.grades?.termID == book.termID, !read.courses.isEmpty else { return }
            for course in book.courses where read.courses.contains(course.id) {
                guard !Task.isCancelled, model.courseForecastScope == scope, model.tab == .grades,
                      store.gradeRevision == read.revision else { return }
                await store.loadDetail(course)
            }
        }
    }

    private func overview(_ store: SchoolPortalStore, _ book: SchoolPortalGrades?, scope: CourseForecastStore.Scope?,
                          drafts: CourseForecastStore.Term) -> some View {
        let actual = book?.gpa.flatMap { $0.isFinite && $0 >= 0 ? GPASummary(value: $0, source: .published) : nil }
        let courses = book.map { term in
            term.courses.map { term.courseDetail($0, groups: model.displayedGroups(term: term.termID, course: $0.id)) }
        } ?? []
        var forecastCards: [CourseGradeDetail.ID: CourseForecastDisplay] = [:]
        for course in courses {
            guard let rows = drafts[course.id.course], !rows.isEmpty else { continue }
            let result = CourseForecast.project(current: course.totalPercentage, groups: course.forecastGroups, estimates: rows)
            forecastCards[course.id] = .init(percentage: result.percentage)
        }
        let predictions = forecastCards
        let forecastGPA = book.flatMap { term in
            TermForecastGPA.calculate(term.courses.map { course in
                let forecast = predictions[.init(term: term.termID, course: course.id)]
                return .init(title: course.evaluationName ?? course.name, published: course.forecastPercentage,
                             prediction: forecast?.percentage, hasForecast: forecast != nil)
            })
        }
        let updating = predictions.keys.contains { id in
            guard model.canUseLiveSchool, model.displayedGroups(term: id.term, course: id.course) == nil,
                  let course = book?.courses.first(where: { $0.id == id.course }),
                  let request = store.detailKey(course) else { return false }
            return store.issues[request] == nil
        }
        let restoreScope = drafts.isEmpty ? nil : scope
        let currentTerm = store.terms?.current ?? (model.canShowCachedGrades ? model.gradeCache.currentTerm : nil)
        let isCurrent = currentTerm.map { $0 == book?.termID } ?? (store.selectedTermID == nil && model.offlineGradeTerm == nil)
        return GPAOverviewView(isCurrentTerm: isCurrent, summary: forecastGPA ?? actual,
            unavailableMessage: book == nil ? String(localized: "尚未获取所选学期成绩。") :
                (book?.gpaUnavailable == true ? String(localized: "本次未能读取学期 GPA。") : String(localized: "校宝未提供所选学期 GPA。")),
            courses: courses, forecasts: predictions,
            courseDestination: { AnyView(SchoolPortalCoursePage(id: $0.id)) }) {
                SchoolTermMenu(supportsSavedGrades: true) {}
            } gradeStatus: {
                if let saved = model.cachedGradeSnapshot, saved.overview.termID == book?.termID {
                    let checked = schoolDateLabel(saved.checked, format: "M月d日 HH:mm")
                    Text("上次同步：\(checked)").foregroundStyle(.secondary)
                }
                if !model.schoolNetworkAvailable, book != nil { Text("当前未联网，显示上次保存的成绩。").foregroundStyle(.secondary) }
                else if let issue = store.issues[store.gradeRead] ?? (store.owner == nil ? store.identityIssue : nil) {
                    Text(issue.message).foregroundStyle(.secondary).accessibilityIdentifier("school-grade-sync-issue")
                } else if book?.gpaUnavailable == true {
                    Text("本次未能读取学期 GPA。").foregroundStyle(.secondary)
                }
                if model.gradeCache.writeFailed { Text("本次成绩未能保存到本机。").foregroundStyle(.secondary) }
                if let book, book.courses.isEmpty { Text("校宝尚未公布所选学期的课程成绩。") }
                if updating { Text("正在更新预测成绩").foregroundStyle(.secondary) }
                if let scope, model.courseForecasts.failedScope == scope || failedRestore == scope {
                    Text("暂时无法读取或保存本机预测。").foregroundStyle(.secondary)
                }
                ViewThatFits(in: .horizontal) {
                    HStack { refresh(store); restore(restoreScope) }
                    VStack(alignment: .leading) { refresh(store); restore(restoreScope) }
                }
            }
    }

    private func refresh(_ store: SchoolPortalStore) -> some View {
        Button {
            if let scope = model.courseForecastScope { model.courseForecasts.open(scope) }
            model.requestSchoolGrades(force: true)
        } label: {
            if store.pending.contains(store.gradeRead) { Label { Text("正在读取成绩") } icon: { ProgressView() } }
            else { Label("刷新 GPA", systemImage: "arrow.clockwise") }
        }.buttonStyle(.glass).disabled(store.pending.contains(store.gradeRead)).accessibilityIdentifier("gpa-check-grades")
    }

    @ViewBuilder private func restore(_ scope: CourseForecastStore.Scope?) -> some View {
        if let scope {
            Button("恢复真实成绩", systemImage: "arrow.uturn.backward") {
                guard model.courseForecastScope == scope else { return }
                do { try model.courseForecasts.restore(in: scope); failedRestore = nil }
                catch { failedRestore = scope }
            }
            .buttonStyle(.glass)
            .accessibilityHint("只清除此学期的本机预测")
            .accessibilityIdentifier("gpa-restore-actual")
        }
    }
}

struct SchoolPortalCoursePage: View {
    @Environment(AppModel.self) private var model
    let id: CourseGradeDetail.ID
    var body: some View {
        let store = model.school
        if let book = model.displayedGradeBook, book.termID == id.term, let course = book.courses.first(where: { $0.id == id.course }) {
            let scope = model.courseForecastScope
            Group {
                if let groups = model.displayedGroups(term: id.term, course: id.course) {
                    CourseGradesView(course: book.courseDetail(course, groups: groups), editing: editor(scope))
                } else if model.canUseLiveSchool, store.grades?.termID == id.term, let key = store.detailKey(course) {
                    if let issue = store.issues[key] { SchoolPortalRetry(issue: issue) { await store.loadDetail(course) } }
                    else { ProgressView("正在读取课程明细") }
                } else if !model.schoolNetworkAvailable || store.grades?.termID != id.term {
                    CourseGradesView(course: book.courseDetail(course, groups: nil),
                                     editing: .init(drafts: [], available: false, save: { _ in }, remove: { _ in }))
                        .safeAreaInset(edge: .bottom) {
                            Text("没有已保存的课程明细，联网后可读取。").font(.callout)
                                .foregroundStyle(.secondary).padding()
                        }
                } else {
                    StudentEmptyState(title: String(localized: "校宝未提供明细入口"), detail: String(localized: "课程总评仍可在 GPA 页查看。"))
                }
            }
            .navigationTitle(course.name)
            .task(id: scope) {
                guard model.courseForecastScope == scope, model.tab == .grades else { return }
                model.courseForecasts.open(scope)
            }
            .task(id: DetailRevision(revision: store.gradeRevision, online: model.schoolNetworkAvailable)) {
                guard model.canUseLiveSchool else { return }
                if store.grades?.termID == id.term {
                    await store.loadDetail(course)
                } else if store.owner != nil, model.displayedGroups(term: id.term, course: id.course) == nil {
                    model.requestSchoolGrades(explicit: false, force: true)
                }
            }
        } else { StudentEmptyState(title: String(localized: "课程成绩不可用"), detail: String(localized: "请返回 GPA 页查看当前账号的课程。")) }
    }

    private struct DetailRevision: Hashable { let revision: UUID; let online: Bool }

    private func editor(_ scope: CourseForecastStore.Scope?) -> CourseGradesView.Editing {
        let term = scope.flatMap { model.courseForecasts.read(in: $0) }
        return .init(drafts: term?[id.course] ?? [], available: term != nil, save: { draft in
            guard let scope, scope == model.courseForecastScope else { throw CourseForecastStore.Failure.scopeChanged }
            try model.courseForecasts.save(draft, course: id.course, in: scope)
        }, remove: { draft in
            guard let scope, scope == model.courseForecastScope else { throw CourseForecastStore.Failure.scopeChanged }
            try model.courseForecasts.remove(draft, course: id.course, in: scope)
        })
    }
}

private extension AppModel {
    var displayedGradeBook: SchoolPortalGrades? {
        guard schoolContentVisible, !portalPresented, !portal.manualSheet, school.identityIssue != .changed else { return nil }
        let saved = cachedGradeSnapshot?.overview
        if let live = school.grades, offlineGradeTerm == nil || offlineGradeTerm == live.termID {
            return live.retainingGPA(from: saved)
        }
        return saved
    }

    func displayedGroups(term: String, course: String) -> [SchoolPortalGrades.Group]? {
        if offlineGradeTerm == nil || offlineGradeTerm == term,
           school.grades?.termID == term, let groups = school.groups[course] { return groups }
        guard let cached = cachedGradeSnapshot, cached.overview.termID == term else { return nil }
        return cached.groups[course]
    }

    var courseForecastScope: CourseForecastStore.Scope? {
        guard school.selected, schoolContentVisible, !portalPresented, !portal.manualSheet,
              let owner = school.owner ?? (canShowCachedGrades ? gradeCache.owner : nil),
              let term = displayedGradeBook?.termID else { return nil }
        return .init(owner: owner, term: term, session: school.epoch)
    }
}
