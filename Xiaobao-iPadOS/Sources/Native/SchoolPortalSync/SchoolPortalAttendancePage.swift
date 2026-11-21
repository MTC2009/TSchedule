import SwiftUI

/// Only the selected date range, category and page are read. No browser presentation or demo fallback.
struct SchoolPortalAttendancePage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var category: AttendanceCategory = .classroom
    @State private var period: AttendancePeriod = .semester
    @State private var range: SchoolDateRange?
    @State private var semester: SchoolDateRange?
    @State private var page = 1
    @State private var status: AttendanceStatus?

    private var query: SchoolPortalAttendanceQuery {
        .init(category: category, from: range.map { SchoolClock.key($0.start) },
              to: range.map { SchoolClock.key($0.end) }, page: page, status: category == .classroom ? nil : status)
    }
    var body: some View {
        let store = model.school, request = query
        let book = store.attendanceQuery == request ? store.attendance : nil
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let term = semester ?? book?.semester { filters(term) }
                    if let book {
                        if book.counts.native.total == 0 && book.courses.isEmpty && book.recordTotal == 0 {
                            StudentEmptyState(title: "暂无考勤记录", detail: "校宝在所选时段没有这类考勤。")
                        } else {
                            if geometry.size.width > 1080 && !typeSize.isAccessibilitySize {
                                HStack(alignment: .top, spacing: 20) {
                                    summary(book, width: 408, fillsRow: true).frame(width: 408)
                                    details(book, fillsRow: true)
                                }
                                .fixedSize(horizontal: false, vertical: true)
                            } else {
                                summary(book, width: max(0, min(1400, geometry.size.width) - 48))
                                details(book)
                            }
                        }
                    } else if let issue = store.issues[.attendance(request)] {
                        SchoolPortalRetry(issue: issue) { await store.loadAttendance(request, force: true) }
                    } else {
                        ProgressView("正在读取考勤").frame(maxWidth: .infinity)
                    }
                }
                .padding(24).frame(maxWidth: 1400).frame(maxWidth: .infinity)
            }
            .refreshable { await store.loadAttendance(request, force: true) }
        }
        .task(id: request) {
            await store.loadAttendance(request)
            if !Task.isCancelled, store.attendanceQuery == request, let term = store.attendance?.semester { semester = term }
        }
    }

    private func filters(_ term: SchoolDateRange) -> some View {
        let selected = range ?? term
        return AttendanceFilterBar(category: Binding(get: { category }, set: { category = $0; status = nil; page = 1 }),
            period: period, start: Binding(get: { selected.start }, set: {
                range = .init(start: $0, end: max($0, selected.end)); period = .custom; page = 1
            }), end: Binding(get: { selected.end }, set: {
                range = .init(start: min($0, selected.start), end: $0); period = .custom; page = 1
            })) { choice in
                period = choice; page = 1
                range = choice == .semester ? nil : choice.range(now: model.now, semester: term)
            }
    }

    @ViewBuilder private func summary(_ book: SchoolPortalAttendance, width: CGFloat, fillsRow: Bool = false) -> some View {
        if let dates = range ?? book.semester {
            AttendanceOverviewPanel(totals: book.counts.native, rate: book.rate, range: dates, width: width,
                                    fillsRow: fillsRow, status: Binding(get: { status }, set: { status = $0; page = 1 }))
        }
    }

    private func details(_ book: SchoolPortalAttendance, fillsRow: Bool = false) -> some View {
        GlassCard(padding: 18, shape: .rect(cornerRadius: 18)) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("考勤详情").font(.headline).accessibilityAddTraits(.isHeader)
                    if let status {
                        Spacer()
                        Button("\(status.title) · 清除筛选") { self.status = nil; page = 1 }.buttonStyle(.plain)
                    }
                }
                if category == .classroom {
                    let courses = book.courses.filter { c in status.map { c.counts.native[$0] > 0 } ?? true }
                    AttendanceCourseTable(rows: courses.map(\.row)) { course in
                        SchoolPortalAttendanceSubject(id: course.id)
                    }
                } else {
                    SchoolPortalAttendanceList(list: book.list, category: category, page: $page)
                }
            }
            .frame(maxHeight: fillsRow ? .infinity : nil, alignment: .topLeading)
        }
    }
}

private struct SchoolPortalAttendanceSubject: View {
    @Environment(AppModel.self) private var model
    let id: String
    @State private var page = 1
    var body: some View {
        let store = model.school
        if let book = store.attendance, let course = book.courses.first(where: { $0.id == id }) {
            let key = SchoolPortalRead.attendanceSubject(id, from: book.from, to: book.to, page: page)
            ScrollView {
                GlassCard(padding: 18, shape: .rect(cornerRadius: 18)) {
                    if store.attendanceSubjectKey == key, let list = store.attendanceSubject {
                        SchoolPortalAttendanceList(list: list, category: .classroom, page: $page)
                    } else if let issue = store.issues[key] {
                        SchoolPortalRetry(issue: issue) { await store.loadAttendanceSubject(id, page: page, force: true) }
                    } else { ProgressView("正在读取课程考勤").frame(maxWidth: .infinity) }
                }.padding(24).frame(maxWidth: 980).frame(maxWidth: .infinity)
            }
            .navigationTitle(course.name)
            .task(id: key) { await store.loadAttendanceSubject(id, page: page) }
            .refreshable { await store.loadAttendanceSubject(id, page: page, force: true) }
        } else {
            StudentEmptyState(title: "课程考勤不可用", detail: "请返回考勤页查看当前账号的记录。")
        }
    }
}

private struct SchoolPortalAttendanceList: View {
    let list: SchoolPortalAttendance.Records
    let category: AttendanceCategory
    @Binding var page: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if list.records.isEmpty { Text("所选时段暂无明细。").foregroundStyle(.secondary) }
            ForEach(list.records) { record in
                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent(record.name, value: record.status.title)
                    HStack {
                        if let start = campusInstant(record.start) {
                            Text(start, format: .dateTime.year().month().day())
                            if category != .daily {
                                if record.allDay { Text("全天") }
                                else {
                                    Text(start, format: .dateTime.hour().minute())
                                    if let end = record.end.flatMap(campusInstant) { Text("–"); Text(end, format: .dateTime.hour().minute()) }
                                }
                            }
                        }
                        if let excused = record.excused { Text(excused ? "已请假" : "未请假") }
                    }.font(.footnote).foregroundStyle(.secondary)
                }.accessibilityElement(children: .combine)
            }
            if page > 1 || page * 10 < list.recordTotal {
                HStack {
                    Button("上一页") { page -= 1 }.disabled(page <= 1)
                    Spacer()
                    Button("下一页") { page += 1 }.disabled(page * 10 >= list.recordTotal)
                }
            }
        }
        .accessibilityIdentifier("school-attendance-records")
    }
}
