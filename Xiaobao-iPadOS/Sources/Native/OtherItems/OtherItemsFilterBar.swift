import SwiftUI

struct OtherItemsFilterBar: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let section: OtherItemsSection
    let courses: [OtherItem.Course]
    let includesUnassigned: Bool
    let showsLocalBookmarks: Bool
    @Binding var filters: OtherItemsFilters
    private let spacing: CGFloat = 8
    private let inset: CGFloat = 14
    private let courseWidth: CGFloat = 162
    private let statusWidth: CGFloat = 112
    private let searchWidth: CGFloat = 210
    private let bookmarksWidth: CGFloat = 170

    var body: some View {
        GlassCard(padding: inset, shape: .rect(cornerRadius: 18)) {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: spacing) {
                    courseMenu
                    if section != .resources { statusMenu }
                    searchField
                    if showsLocalBookmarks { bookmarksToggle }
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: spacing) {
                        courseMenu.frame(width: courseWidth)
                        if section != .resources { statusMenu.frame(width: statusWidth) }
                        searchField.frame(width: searchWidth)
                        if showsLocalBookmarks { bookmarksToggle.frame(width: bookmarksWidth) }
                    }
                    VStack(alignment: .leading, spacing: spacing) {
                        if section == .resources {
                            besideSearch(courseMenu, width: courseWidth)
                            if showsLocalBookmarks { bookmarksToggle }
                        } else {
                            courseMenu
                            besideSearch(statusMenu, width: statusWidth)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : preferredWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var preferredWidth: CGFloat {
        let base = inset * 2 + courseWidth + spacing + searchWidth
        if section != .resources { return base + spacing + statusWidth }
        return base + (showsLocalBookmarks ? spacing + bookmarksWidth : 0)
    }

    private func besideSearch<Control: View>(_ control: Control, width: CGFloat) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: spacing) {
                control.frame(width: width)
                searchField.frame(minWidth: 136, maxWidth: searchWidth)
            }
            VStack(alignment: .leading, spacing: spacing) {
                control
                searchField.frame(maxWidth: searchWidth)
            }
        }
    }

    private var bookmarksToggle: some View {
        Toggle("只看已收藏", isOn: $filters.bookmarksOnly)
            .font(.subheadline).padding(.horizontal, 10).frame(minHeight: 46)
            .background(.fill.tertiary, in: .rect(cornerRadius: 10))
            .accessibilityIdentifier("other-items-saved-only")
    }

    private var courseMenu: some View {
        Menu {
            Picker("课程", selection: $filters.course) {
                Text("全部课程").tag(OtherItemsFilters.Course.all)
                ForEach(courses) { course in
                    Text(course.name ?? String(localized: "课程名称待载入")).tag(OtherItemsFilters.Course.course(course.id))
                }
                if includesUnassigned || filters.course == .unassigned {
                    Text("未分科").tag(OtherItemsFilters.Course.unassigned)
                }
                // A page change must not reset a legacy page's active course restriction.
                if case .course(let id) = filters.course, !courses.contains(where: { $0.id == id }) {
                    Text(courseLabel).tag(OtherItemsFilters.Course.course(id))
                }
            }
            .pickerStyle(.inline)
        } label: {
            TaskFilterLabel(title: String(localized: "课程"), value: courseLabel)
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityIdentifier("other-items-course")
    }

    private var courseLabel: String {
        switch filters.course {
        case .all: String(localized: "全部课程")
        case .unassigned: String(localized: "未分科")
        case .course(let id): courses.first { $0.id == id }?.name ?? String(localized: "所选课程")
        }
    }

    private var statusMenu: some View {
        Menu {
            Picker("状态", selection: $filters.status) {
                ForEach(OtherItemsFilters.Status.allCases, id: \.self) { status in
                    Text(status.title(in: section)).tag(status)
                }
            }
            .pickerStyle(.inline)
        } label: {
            TaskFilterLabel(title: String(localized: "状态"), value: filters.status.title(in: section))
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityIdentifier("other-items-status")
    }

    private var searchField: some View {
        let label = section == .resources ? String(localized: "搜索资料或科目") : String(localized: "搜索标题或科目")
        return HStack(spacing: 9) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField(label, text: $filters.query, prompt: Text(""))
                .textInputAutocapitalization(.never)
                .frame(minHeight: 46)
                .background(alignment: .leading) {
                    if filters.query.isEmpty {
                        Text(label).foregroundStyle(.secondary).allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
                .accessibilityIdentifier("other-items-search")
        }
        .padding(.horizontal, 11)
        .background(.fill.tertiary, in: .rect(cornerRadius: 10))
    }
}

extension OtherItemsFilters.Status {
    func title(in section: OtherItemsSection) -> String {
        switch self {
        case .all: String(localized: "全部")
        case .open: section == .exams ? String(localized: "未结束") : String(localized: "待处理")
        case .finished: section == .exams ? String(localized: "已结束") : String(localized: "已完成")
        }
    }
}
