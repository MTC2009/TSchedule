import Foundation
import XCTest
@testable import XiaobaoCore

final class LocalPersonalizationTests: XCTestCase {
    func testLocalChoicesRoundTripAndBlankValuesRestoreDefaults() throws {
        var choices = LocalPersonalization()
        choices.setNickname("  Jun\n Park ")
        choices.setReminderSubtitle(" Studio session ")
        choices.setLessonActivity(.init(background: .softGray, nextHeading: " Up next "))

        let saved = try JSONEncoder().encode(choices)
        var restored = try JSONDecoder().decode(LocalPersonalization.self, from: saved)
        XCTAssertEqual(restored.nickname, "Jun Park")
        XCTAssertEqual(restored.reminderSubtitle, "Studio session")
        XCTAssertEqual(restored.lessonActivity, .init(background: .softGray, nextHeading: "Up next"))

        restored.setNickname(" \n ")
        restored.setReminderSubtitle("")
        restored.setLessonActivity(.init(background: .system, nextHeading: " "))
        XCTAssertEqual(restored, LocalPersonalization())
    }

    func testUnsupportedBackgroundFallsBackWithoutResettingOtherChoices() throws {
        let data = Data(#"{"nickname":"Ari","reminderSubtitle":false,"lessonActivity":{"background":"futureStyle","nextHeading":"On deck"}}"#.utf8)
        let restored = try JSONDecoder().decode(LocalPersonalization.self, from: data)
        XCTAssertEqual(restored.nickname, "Ari")
        XCTAssertNil(restored.reminderSubtitle)
        XCTAssertEqual(restored.lessonActivity, .init(nextHeading: "On deck"))
        XCTAssertEqual(try JSONDecoder().decode(LocalPersonalization.self, from: Data("{}".utf8)), .init())
    }

    func testLongPastedTextIsBoundedWithoutSplittingGraphemes() throws {
        var choices = LocalPersonalization()
        let composed = "🇨🇦"
        choices.setNickname(String(repeating: composed, count: 50))
        XCTAssertEqual(choices.nickname, String(repeating: composed, count: 12))
        choices.setReminderSubtitle(String(repeating: "a", count: 100))
        XCTAssertEqual(choices.reminderSubtitle?.count, 40)
        choices.setLessonActivity(.init(nextHeading: String(repeating: "课", count: 45)))
        XCTAssertEqual(choices.lessonActivity.nextHeading?.count, 16)
    }
}
