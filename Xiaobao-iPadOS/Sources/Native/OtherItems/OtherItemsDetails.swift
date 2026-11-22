import SwiftUI

struct OtherItemDetailView: View {
    @Environment(AppModel.self) private var model
    let item: OtherItem
    let section: OtherItemsSection
    let campusPage: CampusPage?
    let campusScope: UUID?

    var body: some View {
        StudentDetailSurface {
            if !sourceIsAvailable {
                StudentEmptyState(title: String(localized: "这项资料已不可用"), detail: String(localized: "返回列表后再试。"))
            } else {
                switch item.detail {
                case .exam(let work): exam(work)
                case .evaluation(let work): evaluation(work)
                case .resource(let resource): reading(resource)
                }
            }
        }
        .navigationTitle(navigationTitle)
        .toolbar {
            if sourceIsAvailable, case .resource = item.detail {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("在校宝查看", systemImage: "safari") { model.openPortal(section: section.portalSection) }
                }
            }
        }
    }

    private var navigationTitle: String {
        switch item.detail {
        case .exam: String(localized: "考试详情")
        case .evaluation: String(localized: "测评详情")
        case .resource: String(localized: "资料预览")
        }
    }

    private var sourceIsAvailable: Bool {
        guard let campusPage else { return true }
        // A pushed record is still scoped to the same visible, authorized source collection.
        return campusScope != nil && model.campus.account?.scope == campusScope &&
            (model.campus.pages[campusPage] != nil || model.campus.cachedOtherItems(for: campusPage) != nil)
    }

    @ViewBuilder private func exam(_ work: OtherItem.Work) -> some View {
        StudentPageHeader(title: item.title, subtitle: item.courseTitle, portalSection: section.portalSection)
        GlassCard(padding: 20, shape: .rect(cornerRadius: 16)) {
            VStack(alignment: .leading, spacing: 16) {
                if let status = item.status(at: model.now) {
                    Label(status.title, systemImage: SchoolWorkKind.exam.symbol).font(.subheadline.weight(.medium))
                }
                if let timing = work.examTime(includeYear: true) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 32) {
                            focus(timing.label, timing.value).fixedSize(horizontal: true, vertical: false)
                            if let room = work.room { focus(String(localized: "考场"), room).fixedSize(horizontal: true, vertical: false) }
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            focus(timing.label, timing.value)
                            if let room = work.room { focus(String(localized: "考场"), room) }
                        }
                    }
                } else if let room = work.room {
                    focus(String(localized: "考场"), room)
                }
                if let due = work.dueAt, (work.startsAt != nil || work.endsAt != nil), due != work.endsAt {
                    LabeledContent("截止时间", value: otherItemsDate(due, includeYear: true))
                }
            }
        }
        notes(String(localized: "考试范围与说明"), text: work.description)
        if work.isLocal, item.status(at: model.now)?.finished == true {
            Button("查看 GPA", systemImage: "chart.bar.xaxis") { model.tab = .grades }.buttonStyle(.glass)
        }
    }

    @ViewBuilder private func evaluation(_ work: OtherItem.Work) -> some View {
        StudentPageHeader(title: item.title, subtitle: item.courseTitle, portalSection: section.portalSection)
        GlassCard(padding: 20, shape: .rect(cornerRadius: 16)) {
            VStack(alignment: .leading, spacing: 14) {
                if let status = item.status(at: model.now) { focus(String(localized: "测评状态"), status.title) }
                if let due = work.dueAt { LabeledContent("截止时间", value: otherItemsDate(due, includeYear: true)) }
                if let room = work.room { LabeledContent("地点", value: room) }
            }
        }
        notes(String(localized: "测评要求"), text: work.description)
    }

    @ViewBuilder private func reading(_ resource: OtherItem.Resource) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                readingTitle(resource).fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 0)
                bookmark(resource)
            }
            VStack(alignment: .leading, spacing: 10) {
                readingTitle(resource)
                bookmark(resource)
            }
        }
        GlassCard(padding: 24, shape: .rect(cornerRadius: 16)) {
            if resource.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("暂无可预览的内容。").foregroundStyle(.secondary)
            } else {
                Text(resource.body).lineSpacing(9).textSelection(.enabled)
                    .frame(maxWidth: 680, alignment: .leading)
            }
        }
    }

    private func readingTitle(_ resource: OtherItem.Resource) -> some View {
        let date = resource.date.map { otherItemsDate($0, includeYear: true, dateOnly: true) }
        let values = [item.courseTitle, resource.kindTitle, resource.scopeTitle, date].compactMap { $0 }
        return VStack(alignment: .leading, spacing: 7) {
            Text(item.title).font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
            Text(values.joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func bookmark(_ resource: OtherItem.Resource) -> some View {
        if resource.permitsLocalBookmark {
            let saved = item.isBookmarked(in: model.savedDemoResourceIDs)
            Button(saved ? String(localized: "取消收藏") : String(localized: "收藏"), systemImage: saved ? "bookmark.fill" : "bookmark") {
                model.toggleSavedResource(item.id)
            }.buttonStyle(.glass)
        }
    }

    private func focus(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Text(value).font(.system(.title2, design: .rounded, weight: .semibold)).monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func notes(_ title: String, text: String) -> some View {
        GlassCard(padding: 20, shape: .rect(cornerRadius: 16)) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.headline).accessibilityAddTraits(.isHeader)
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("未提供说明。").foregroundStyle(.secondary)
                } else {
                    Text(text).lineSpacing(7).textSelection(.enabled)
                }
            }
        }
    }
}

@MainActor func otherItemsDate(_ date: Date, includeYear: Bool = false, dateOnly: Bool = false) -> String {
    let day = includeYear ? "yyyy年M月d日" : "M月d日"
    return schoolDateLabel(date, format: dateOnly ? day : day + " HH:mm")
}

extension OtherItem.Work {
    @MainActor func examTime(includeYear: Bool) -> (label: String, value: String)? {
        if let start = startsAt {
            let begins = otherItemsDate(start, includeYear: includeYear)
            guard let end = endsAt else { return (String(localized: "考试时间"), begins) }
            let ends = SchoolClock.calendar.isDate(start, inSameDayAs: end) ?
                schoolDateLabel(end, format: "HH:mm") : otherItemsDate(end, includeYear: includeYear)
            return (String(localized: "考试时间"), begins + "–" + ends)
        }
        if let end = endsAt { return (String(localized: "结束时间"), otherItemsDate(end, includeYear: includeYear)) }
        if let due = dueAt { return (String(localized: "截止时间"), otherItemsDate(due, includeYear: includeYear)) }
        return nil
    }
}

extension OtherItem.Resource {
    var kindTitle: String? {
        switch kind {
        case "document": String(localized: "文档")
        case "image": String(localized: "图片")
        case "video": String(localized: "视频")
        case "audio": String(localized: "音频")
        default: kind
        }
    }

    var scopeTitle: String? {
        switch scope {
        case "shared": String(localized: "分享给我的")
        case "personal": String(localized: "个人资料")
        default: scope
        }
    }
}
