import SwiftUI

struct OtherItemsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let section = model.otherItemsSection
        VStack(alignment: .leading, spacing: 0) {
            sectionControl
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .frame(maxWidth: 1100, alignment: .leading)
                .frame(maxWidth: .infinity)

            if model.school.selected {
                SchoolCollectionList(section: section)
            } else if model.campus.account != nil {
                // The existing pagination state belongs to the selected collection.
                CampusPageView(tab: .otherItems, otherItemsSection: section).id(section)
            } else if model.usesLocalTimetable {
                LocalOtherItemsView(section: section).id(section)
            }
        }
    }

    private var sectionControl: some View {
        @Bindable var model = model
        let picker = Picker("其余项目类别", selection: $model.otherItemsSection) {
            ForEach(OtherItemsSection.allCases) { Text($0.title).tag($0) }
        }
        return Group {
            if typeSize.isAccessibilitySize {
                picker.pickerStyle(.menu)
            } else {
                picker.pickerStyle(.segmented)
                    .controlSize(.large)
                    .frame(maxWidth: 550)
            }
        }
        .accessibilityIdentifier("other-items-sections")
    }
}

private struct LocalOtherItemsView: View {
    @Environment(AppModel.self) private var model
    @State private var filters = OtherItemsFilters()
    let section: OtherItemsSection

    var body: some View {
        ScrollView {
            OtherItemsGrid(section: section, records: records, filters: $filters,
                           showsLocalBookmarks: section == .resources)
                .padding(24)
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var records: [OtherItem] {
        switch section {
        case .exams:
            OtherItemsCatalog.localWork(StudentServices.work, kind: .exam, at: model.now)
        case .evaluations:
            OtherItemsCatalog.localWork(StudentServices.work, kind: .evaluation, at: model.now)
        case .resources:
            StudentServices.resources.sorted { $0.date > $1.date }.map { OtherItem(local: $0) }
        }
    }
}

@MainActor private extension SchoolWork {
    func isFinished(model: AppModel) -> Bool {
        status != .pending || (kind == .task && model.completedDemoTaskIDs.contains(id)) ||
            (kind == .exam && (end ?? date) < model.now)
    }
    func statusTitle(model: AppModel) -> String {
        if kind == .task && model.completedDemoTaskIDs.contains(id) { return String(localized: "本地完成") }
        if kind == .exam && isFinished(model: model) { return String(localized: "已结束") }
        if status == .submitted { return String(localized: "已提交") }
        if status == .completed { return String(localized: "已完成") }
        if kind == .exam { return String(localized: "待考试") }
        return date < model.now ? String(localized: "已逾期") : String(localized: "待完成")
    }
    func statusColor(model: AppModel) -> Color {
        isFinished(model: model) ? .teal : (date < model.now && kind != .exam ? .orange : .blue)
    }
}

struct SchoolWorkDetailView: View {
    @Environment(AppModel.self) private var model
    let item: SchoolWork
    var allowsLocalCompletion = true
    var body: some View {
        StudentDetailSurface {
            StudentPageHeader(title: item.title, subtitle: item.course, portalSection: item.kind.portalSection)
            GlassCard {
                VStack(alignment: .leading, spacing: 22) {
                    Label(item.statusTitle(model: model), systemImage: item.kind.symbol).font(.headline).foregroundStyle(item.statusColor(model: model))
                    LabeledContent(item.dateLabel, value: schoolDateLabel(item.date, format: "yyyy年M月d日 HH:mm"))
                    if let end = item.end { LabeledContent("结束时间", value: schoolDateLabel(end, format: "HH:mm")) }
                    if let location = item.location { LabeledContent("地点", value: location) }
                    Divider()
                    Text(item.detail).lineSpacing(7).textSelection(.enabled)
                }
            }
            if allowsLocalCompletion && item.kind == .task && item.status == .pending {
                VStack(alignment: .leading, spacing: 12) {
                    Button(model.completedDemoTaskIDs.contains(item.id) ? String(localized: "撤销本地完成") : String(localized: "标记本地完成"), systemImage: "checkmark.circle") { model.toggleDemoTask(item.id) }.buttonStyle(.glassProminent)
                    Text("仅保存在这台设备，不会向校宝提交作业或改变学校记录。").font(.caption).foregroundStyle(.secondary)
                }
            }
            if item.kind == .exam && item.isFinished(model: model) {
                Button("查看 GPA", systemImage: "chart.bar.xaxis") { model.tab = .grades }.buttonStyle(.glass)
            }
        }.navigationTitle(item.kind.title)
    }
}


/// List metadata is prefetched under the same verified owner as the rest of the native tabs.
private struct SchoolCollectionList: View {
    @Environment(AppModel.self) private var model
    let section: OtherItemsSection

    var body: some View {
        let store = model.school, kind = section.collection
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if let rows = store.collections[kind] {
                    if rows.isEmpty {
                        StudentEmptyState(title: section.emptyTitle, detail: String(localized: "校宝没有返回可显示的条目。"))
                    } else {
                        ForEach(rows) { item in
                            GlassCard {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(verbatim: item.title).font(.headline)
                                    if let detail = item.detailLabel { Text(verbatim: detail).font(.subheadline).foregroundStyle(.secondary) }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                } else if let issue = store.issues[.collection(kind)] {
                    SchoolPortalRetry(issue: issue) { await store.loadCollection(kind, force: true) }
                } else { ProgressView("正在读取") }
            }.padding(24).frame(maxWidth: 1100).frame(maxWidth: .infinity)
        }
        .task(id: kind) { await store.loadCollection(kind) }
        .refreshable { await store.loadCollection(kind, force: true) }
    }
}
