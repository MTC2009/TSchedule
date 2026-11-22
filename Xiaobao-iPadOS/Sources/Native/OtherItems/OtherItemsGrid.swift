import SwiftUI

struct OtherItemsGrid: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    let section: OtherItemsSection
    let records: [OtherItem]
    @Binding var filters: OtherItemsFilters
    var showsLocalBookmarks = false
    var isPartialPage = false
    var campusPage: CampusPage?

    var body: some View {
        let visible = filters.results(in: records, at: model.now, bookmarks: model.savedDemoResourceIDs)
        VStack(alignment: .leading, spacing: 18) {
            OtherItemsFilterBar(section: section, courses: OtherItemsCatalog.courses(in: records),
                                includesUnassigned: records.contains { $0.courses.isEmpty },
                                showsLocalBookmarks: showsLocalBookmarks, filters: $filters)
            Text(title).font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 3)
            if isPartialPage {
                Text("资料按页读取，筛选仅作用于本页。").font(.caption).foregroundStyle(.secondary)
            }
            if visible.isEmpty {
                StudentEmptyState(title: emptyTitle,
                                  detail: records.isEmpty ? "" : String(localized: "试试调整筛选项或搜索词。"), symbol: symbol)
            } else {
                GlassEffectContainer(spacing: 8) {
                    LazyVGrid(columns: [GridItem(typeSize.isAccessibilitySize ? .flexible() : .adaptive(minimum: 250),
                                                 spacing: 16, alignment: .topLeading)], spacing: 16) {
                        ForEach(visible) { item in
                            NavigationLink {
                                OtherItemDetailView(item: item, section: section, campusPage: campusPage,
                                                    campusScope: model.campus.account?.scope)
                            } label: {
                                OtherItemCard(item: item, now: model.now, isBookmarked: item.isBookmarked(in: model.savedDemoResourceIDs))
                            }
                            .buttonStyle(.plain)
                            .hoverEffect(.highlight)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("other-items-record-\(item.id)")
                        }
                    }
                }
            }
        }
    }

    private var title: String {
        switch section {
        case .exams: String(localized: "考试列表")
        case .evaluations: String(localized: "测评列表")
        case .resources: String(localized: "资料列表")
        }
    }

    private var symbol: String {
        switch section {
        case .exams: SchoolWorkKind.exam.symbol
        case .evaluations: SchoolWorkKind.evaluation.symbol
        case .resources: "folder"
        }
    }

    private var emptyTitle: String {
        if !records.isEmpty { return isPartialPage ? String(localized: "本页没有匹配的记录") : String(localized: "没有匹配的记录") }
        return section.emptyTitle
    }

}

private struct OtherItemCard: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let item: OtherItem
    let now: Date
    let isBookmarked: Bool

    var body: some View {
        GlassCard(padding: 0) {
            if typeSize.isAccessibilitySize {
                cardContent
            } else {
                cardContent.aspectRatio(4.0 / 3.0, contentMode: .fit)
            }
        }
        .contentShape(Rectangle())
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.title).font(.title2.weight(.semibold))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.forward").font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary).accessibilityHidden(true)
                }
                Text(subtitle).font(.body)
            }
            .fixedSize(horizontal: false, vertical: true)

            // Use the tile's height between groups, while letting wrapped text grow beyond the aspect ratio.
            Spacer(minLength: 18)
            VStack(alignment: .leading, spacing: 8) {
                metadata
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: 161, alignment: .topLeading)
        .padding(18)
    }

    private var subtitle: String {
        if case .resource(let resource) = item.detail, let kind = resource.kindTitle {
            return String(localized: "\(item.courseTitle) · \(kind)")
        }
        return item.courseTitle
    }

    @ViewBuilder private var metadata: some View {
        switch item.detail {
        case .exam(let work):
            if let time = work.examTime(includeYear: false) {
                field(work.startsAt != nil ? time.value : "\(time.label) \(time.value)",
                      icon: "clock", font: .body.weight(.medium))
            }
            examRoomAndStatus(room: work.room, status: item.status(at: now)?.title)
        case .evaluation(let work):
            if let due = work.dueAt {
                field(String(localized: "截止 \(otherItemsDate(due))"), icon: "clock", font: .body.weight(.medium))
            }
            if let status = item.status(at: now) { statusLabel(status.title) }
        case .resource(let resource):
            if let date = resource.date {
                field(schoolDateLabel(date, format: "M月d日"), icon: "calendar", font: .body.weight(.medium))
            }
            if let scope = resource.scopeTitle { field(scope, icon: "doc.text") }
            if isBookmarked { field(String(localized: "已收藏"), icon: "bookmark.fill") }
        }
    }

    @ViewBuilder private func examRoomAndStatus(room: String?, status: String?) -> some View {
        if let room, let status {
            let location = field(room, icon: "mappin.and.ellipse")
            let state = statusLabel(status)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    location
                    Spacer(minLength: 0)
                    state
                }
                VStack(alignment: .leading, spacing: 8) {
                    location
                    state
                }
            }
        } else if let room {
            field(room, icon: "mappin.and.ellipse")
        } else if let status {
            statusLabel(status)
        }
    }

    private func field(_ title: String, icon: String, font: Font = .subheadline) -> some View {
        Label(title, systemImage: icon).font(font)
    }

    private func statusLabel(_ title: String) -> some View {
        Text(title).font(.subheadline.weight(.medium))
    }
}
