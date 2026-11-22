import Foundation
import XCTest
@testable import XiaobaoCore

final class LocalPersonalizationTests: XCTestCase {
    func testNewDisplayCategoriesRemainVisibleWhenReadingAnOlderDevicePreference() throws {
        let bytes = Data(#"{"showsBoardingRoutine":true,"hiddenTimetableCategories":["lunch","futureOption"]}"#.utf8)
        var settings = try JSONDecoder().decode(LocalPersonalization.self, from: bytes)
        XCTAssertFalse(settings.shows(.lunch))
        XCTAssertTrue(settings.shows(.dinner))
        settings.setShown(false, for: .examCourse)
        let saved = try JSONDecoder().decode(LocalPersonalization.self, from: JSONEncoder().encode(settings))
        XCTAssertFalse(saved.shows(.examCourse))
        XCTAssertTrue(saved.showsBoardingRoutine)
        XCTAssertTrue(saved.shows(.schoolCourse))
        XCTAssertTrue(try JSONDecoder().decode(LocalPersonalization.self, from: Data("{}".utf8)).shows(.lunch))
    }

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

    func testBoardingDisplayIsLocalAndOptInIncludingOlderPreferences() throws {
        var old = try JSONDecoder().decode(LocalPersonalization.self, from: Data(#"{"nickname":"Sky"}"#.utf8))
        XCTAssertFalse(old.showsBoardingRoutine)
        old.showsBoardingRoutine = true
        let restored = try JSONDecoder().decode(LocalPersonalization.self, from: JSONEncoder().encode(old))
        XCTAssertTrue(restored.showsBoardingRoutine)
        XCTAssertEqual(restored.nickname, "Sky")
        XCTAssertEqual(restored.lessonActivity, .init())
        let invalid = try JSONDecoder().decode(LocalPersonalization.self, from: Data(#"{"showsBoardingRoutine":"yes"}"#.utf8))
        XCTAssertFalse(invalid.showsBoardingRoutine)
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
