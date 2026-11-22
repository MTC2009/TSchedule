import Foundation

/// Display choices, not enrollment, residence or notification permissions.
enum TimetableCategory: String, CaseIterable, Sendable {
    case schoolCourse, examCourse, optionalBlock, freeblock, assembly, tssa, study, sport
    case breakfast, lunch, dinner, wash, sleep

    var title: String {
        switch self {
        case .schoolCourse: String(localized: "校内课程")
        case .examCourse: String(localized: "外考课程")
        case .optionalBlock: String(localized: "未选的 Block 9 / 10")
        case .freeblock: String(localized: "空节")
        case .assembly: String(localized: "班会／集会")
        case .tssa: "TSSA"
        case .study: String(localized: "晚自习")
        case .sport: String(localized: "体育活动")
        case .breakfast: String(localized: "早餐")
        case .lunch: String(localized: "午餐")
        case .dinner: String(localized: "晚餐")
        case .wash: String(localized: "洗漱")
        case .sleep: String(localized: "就寝")
        }
    }
}

/// Device preferences only. This is deliberately not a profile or a credential.
struct LocalPersonalization: Codable, Equatable {
    private(set) var nickname: String?
    private(set) var reminderSubtitle: String?
    private(set) var lessonActivity = LessonActivityAppearance()
    var showsBoardingRoutine = false
    private var hiddenTimetableCategories: Set<String> = []

    init() {}

    func shows(_ category: TimetableCategory) -> Bool { !hiddenTimetableCategories.contains(category.rawValue) }

    mutating func setShown(_ visible: Bool, for category: TimetableCategory) {
        if visible { hiddenTimetableCategories.remove(category.rawValue) }
        else { hiddenTimetableCategories.insert(category.rawValue) }
    }

    mutating func setNickname(_ text: String) {
        nickname = PersonalizationText.singleLine(text, limit: 24)
    }

    mutating func setReminderSubtitle(_ text: String) {
        reminderSubtitle = PersonalizationText.singleLine(text, limit: 40)
    }

    mutating func setLessonActivity(_ appearance: LessonActivityAppearance) {
        lessonActivity = appearance
    }

    private enum CodingKeys: String, CodingKey { case nickname, reminderSubtitle, lessonActivity, showsBoardingRoutine, hiddenTimetableCategories }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        setNickname((try? values.decode(String.self, forKey: .nickname)) ?? "")
        setReminderSubtitle((try? values.decode(String.self, forKey: .reminderSubtitle)) ?? "")
        lessonActivity = (try? values.decode(LessonActivityAppearance.self, forKey: .lessonActivity)) ?? .init()
        showsBoardingRoutine = (try? values.decode(Bool.self, forKey: .showsBoardingRoutine)) ?? false
        hiddenTimetableCategories = (try? values.decode(Set<String>.self, forKey: .hiddenTimetableCategories)) ?? []
    }
}

/// Only this small style value is copied to a newly started ActivityKit snapshot.
struct LessonActivityAppearance: Codable, Hashable {
    enum Background: String, CaseIterable, Codable {
        case system, campusBlue, softGray
    }

    let background: Background
    let nextHeading: String?

    init(background: Background = .system, nextHeading: String? = nil) {
        self.background = background
        self.nextHeading = nextHeading.flatMap { PersonalizationText.singleLine($0, limit: 16) }
    }

    private enum CodingKeys: String, CodingKey { case background, nextHeading }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(background: (try? values.decode(Background.self, forKey: .background)) ?? .system,
                  nextHeading: try? values.decode(String.self, forKey: .nextHeading))
    }
}

private enum PersonalizationText {
    static func singleLine(_ text: String, limit: Int) -> String? {
        let line = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        // Bound both user-facing characters and serialized bytes (one grapheme
        // can contain many scalars), without splitting a composed character.
        var safe = ""
        var bytes = 0
        for character in line.prefix(limit) {
            let width = String(character).utf8.count
            guard bytes + width <= limit * 4 else { break }
            safe.append(character)
            bytes += width
        }
        while safe.last == " " { safe.removeLast() }
        return safe.isEmpty ? nil : safe
    }
}
