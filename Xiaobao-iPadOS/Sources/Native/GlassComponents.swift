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

struct LessonDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let lesson: Lesson
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(lesson.course.room).font(.system(size: 68, weight: .semibold, design: .rounded)).foregroundStyle(.blue)
                    Text(lesson.course.name).font(.title2.bold())
                    Label("Day \(lesson.day) · \(lesson.timeLabel)", systemImage: "clock")
                    Label(lesson.course.teacher, systemImage: "person")
                    Divider()
                    Text(schoolDateLabel(lesson.date)).foregroundStyle(.secondary)
                    Text(model.preferences.remindersEnabled ? (model.preferences.reminderLead == 0 ? String(localized: "上课时提醒") : String(localized: "提前 \(model.preferences.reminderLead) 分钟提醒")) : String(localized: "课前提醒未开启"))
                        .font(.callout).foregroundStyle(.secondary)
                    Button("查看提醒设置", systemImage: "bell") { dismiss(); model.tab = .settings }.buttonStyle(.glass)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(30)
            }
            .navigationTitle("课程详情").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}
