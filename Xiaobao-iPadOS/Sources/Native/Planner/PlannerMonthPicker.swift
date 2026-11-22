import SwiftUI

struct PlannerMonthPicker: View {
    let selectedDate: Date
    let publication: PublishedSchoolCalendar?
    let select: (Date) -> Void
    @State private var displayedMonth: Date

    init(selectedDate: Date, publication: PublishedSchoolCalendar?, select: @escaping (Date) -> Void) {
        self.selectedDate = selectedDate
        self.publication = publication
        self.select = select
        _displayedMonth = State(initialValue: selectedDate)
    }

    private var month: PlannerCalendarMonth { .init(containing: displayedMonth, publication: publication) }
    private var noticeList: [PlannerCalendarMonth.Notice] {
        let month = month
        var result: [PlannerCalendarMonth.Notice] = []
        for date in month.cells.compactMap({ $0 }) {
            for notice in month.notices(on: date) where !result.contains(notice) { result.append(notice) }
        }
        return result
    }

    var body: some View {
        let notices = noticeList
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(schoolDateLabel(month.first, format: "yyyy年M月"))
                        .font(.headline).accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("planner-month-title")
                    if publication != nil { Text("主校区 · 高中部").font(.caption2).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 4)
                step(-1, title: String(localized: "上个月"), symbol: "chevron.left")
                step(1, title: String(localized: "下个月"), symbol: "chevron.right")
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 44), spacing: 0), count: 7), spacing: 0) {
                ForEach([String(localized: "周一"), String(localized: "周二"), String(localized: "周三"), String(localized: "周四"), String(localized: "周五"), String(localized: "周六"), String(localized: "周日")], id: \.self) {
                    Text($0).font(.caption).foregroundStyle(.secondary).frame(minHeight: 26)
                }
                ForEach(Array(month.cells.enumerated()), id: \.offset) { _, date in
                    if let date { cell(date) }
                    else { Color.clear.frame(height: 44).accessibilityHidden(true) }
                }
            }
            if !notices.isEmpty {
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(Array(notices.enumerated()), id: \.offset) { _, notice in
                            Label("\(span(notice)) · \(notice.title)", systemImage: notice.isClosed ? "minus.circle" : "circle.fill")
                                .font(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 116)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(idealWidth: 352, maxWidth: 440)
    }

    private func span(_ notice: PlannerCalendarMonth.Notice) -> String {
        let first = schoolDateLabel(notice.first, format: "M月d日")
        guard notice.first != notice.last else { return first }
        return first + "–" + schoolDateLabel(notice.last, format: "M月d日")
    }

    private func cell(_ date: Date) -> some View {
        let day = month.schoolDay(date)
        let isSelected = date == selectedDate
        let closed = day?.status == .noClass
        let event = day?.notices.isEmpty == false
        let dayNumber = SchoolClock.calendar.component(.day, from: date)
        let details = (closed ? [String(localized: "不上课")] : []) + (day?.notices ?? [])
        let surface: AnyShapeStyle = isSelected ? AnyShapeStyle(.fill.secondary) : AnyShapeStyle(.fill.tertiary)
        let ink: Color = day?.status == .weekend && !isSelected && !event ? .secondary : .primary
        return Button { select(date) } label: {
            ZStack(alignment: .bottom) {
                Text(dayNumber.formatted()).monospacedDigit()
                    .foregroundStyle(ink)
                    .frame(maxWidth: .infinity, minHeight: 44)
                if closed || event {
                    Image(systemName: closed ? "minus" : "circle.fill")
                        .font(.system(size: 5, weight: .heavy)).foregroundStyle(.tint)
                        .padding(.bottom, 4).accessibilityHidden(true)
                }
            }
            .background {
                if isSelected || closed { PlannerCorners.inset.fill(surface).padding(2) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).hoverEffect(.highlight)
        .accessibilityLabel(([schoolDateLabel(date, format: "M月d日 EEEE")] + details).joined(separator: String(localized: "，")))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("planner-month-\(SchoolClock.key(date))")
    }

    private func step(_ offset: Int, title: String, symbol: String) -> some View {
        let target = SchoolClock.calendar.date(byAdding: .month, value: offset, to: month.first)
        return Button {
            if let target { displayedMonth = target }
        } label: {
            Label(title, systemImage: symbol).labelStyle(.iconOnly).frame(width: 44, height: 44)
        }
        .buttonStyle(.plain).hoverEffect(.highlight)
        .disabled(target.map { !PlannerCalendarMonth.selectableDates.contains($0) } ?? true)
        .accessibilityIdentifier(offset < 0 ? "planner-month-previous" : "planner-month-next")
    }
}
