import ActivityKit
import Foundation

/// The only school-derived payload sent to the system renderer. IDs, accounts,
/// locations and grades stay in the app. A closed state carries no course data.
struct LessonActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let startsAt: Date?
        let endsAt: Date?
        let nextLesson: String?
        let isDemo: Bool
        // Optional so a snapshot archived by the previous extension can still close.
        var appearance: LessonActivityAppearance? = nil

        static let closed = Self(startsAt: nil, endsAt: nil, nextLesson: nil, isDemo: false)
    }

    static let courseLink = URL(string: "tschedule://lesson-activity")
}
