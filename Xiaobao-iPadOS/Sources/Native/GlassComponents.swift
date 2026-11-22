import SwiftUI

struct GlassCard<Content: View>: View {
    let padding: CGFloat
    private let shape: RoundedRectangle
    let content: Content
    init(padding: CGFloat = 26, shape: RoundedRectangle = .rect(cornerRadius: 30),
         @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.shape = shape
        self.content = content()
    }
    var body: some View {
        content.padding(padding).frame(maxWidth: .infinity, alignment: .leading)
            .modifier(NativeGlassSurface(shape: shape))
    }
}

private struct NativeGlassSurface: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let shape: RoundedRectangle

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(uiColor: .secondarySystemBackground), in: shape)
        } else {
            content.glassEffect(model.preferences.glass == .clear ? .clear : .regular, in: shape)
        }
    }
}

@MainActor private var schoolDateFormatters: [String: DateFormatter] = [:]

@MainActor func schoolDateLabel(_ date: Date, format: String = "M月d日 EEEE") -> String {
    let locale = AppLanguage.locale
    let key = locale.identifier + "|" + format
    if let saved = schoolDateFormatters[key] { return saved.string(from: date) }
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.calendar = SchoolClock.calendar
    formatter.timeZone = SchoolClock.calendar.timeZone
    // The callers describe school time in Shanghai; date order and month/weekday names are UI.
    let templates = ["M月d日 EEEE": "MMMMdEEEE", "M月d日": "MMMd", "yyyy年M月": "yMMMM",
                     "yyyy年M月d日": "yMMMd", "yyyy年M月d日 HH:mm": "yMMMdjm", "M月d日 HH:mm": "MMMdjm",
                     "EEE M/d": "MMMEd", "M/d": "Md", "yyyy.MM.dd": "yMd"]
    if let template = templates[format] { formatter.setLocalizedDateFormatFromTemplate(template) }
    else { formatter.dateFormat = format }
    schoolDateFormatters[key] = formatter
    return formatter.string(from: date)
}

extension SkyColor {
    var color: Color { Color(red: red, green: green, blue: blue) }
}

struct TimetableDetail: Identifiable {
    let id = UUID()
    let title: String
    let start, end: Date
    let location: String?
    let metadata: TimetableLessonMetadata?
    let isCourse: Bool

    init(_ lesson: Lesson) {
        self.init(title: lesson.course.name, start: lesson.start, end: lesson.end,
                  location: lesson.course.room, metadata: .init(teacher: lesson.course.teacher), isCourse: true)
    }

    init(_ block: LessonTimeline.Block) {
        self.init(title: block.title, start: block.start, end: block.end, location: block.location,
                  metadata: block.metadata, isCourse: block.isCourse)
    }

    init(title: String, start: Date, end: Date, location: String?, metadata: TimetableLessonMetadata?, isCourse: Bool) {
        self.title = title; self.start = start; self.end = end; self.location = location
        self.metadata = metadata; self.isCourse = isCourse
    }
}

struct LessonDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let detail: TimetableDetail
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("日期", value: schoolDateLabel(detail.start))
                    LabeledContent("时间") {
                        Text(verbatim: timeRange).monospacedDigit()
                            .accessibilityIdentifier("planner-school-time-range")
                    }
                    if let location = detail.location, !location.isEmpty {
                        LabeledContent("场地", value: location)
                    }
                    if let grade = detail.metadata?.grade { LabeledContent("年级", value: grade) }
                    if let name = detail.metadata?.className { LabeledContent("班级", value: name) }
                    Text("教师：\(detail.metadata?.teacher ?? "—")")
                        .accessibilityIdentifier("timetable-detail-teacher")
                    if detail.isCourse { LabeledContent("备注", value: detail.metadata?.note ?? "—") }
                }
                if detail.isCourse, model.usesLocalTimetable {
                    Text(model.preferences.remindersEnabled ? (model.preferences.reminderLead == 0 ? String(localized: "上课时提醒") : String(localized: "提前 \(model.preferences.reminderLead) 分钟提醒")) : String(localized: "课前提醒未开启"))
                        .font(.callout).foregroundStyle(.secondary)
                    Button("查看提醒设置", systemImage: "bell") { dismiss(); model.tab = .settings }.buttonStyle(.glass)
                }
            }
            .navigationTitle(detail.title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
        .accessibilityIdentifier("timetable-entry-detail")
    }

    private var timeRange: String {
        let begin = schoolDateLabel(detail.start, format: "HH:mm")
        let finish = schoolDateLabel(detail.end, format: "HH:mm")
        return SchoolClock.calendar.isDate(detail.start, inSameDayAs: detail.end) ?
            begin + " – " + finish : String(localized: "\(begin) – 次日 \(finish)")
    }
}
