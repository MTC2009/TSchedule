import XCTest
@testable import XiaobaoCore

final class EnvironmentTests: XCTestCase {
    func testGregorianAndLunarFestivals() {
        XCTAssertEqual(Festival.automatic(on: SchoolClock.date(2026, 2, 17)), .spring)
        XCTAssertEqual(Festival.automatic(on: SchoolClock.date(2026, 9, 25)), .midautumn)
        XCTAssertEqual(Festival.automatic(on: SchoolClock.date(2026, 12, 25)), .christmas)
        XCTAssertEqual(Festival.automatic(on: SchoolClock.date(2027, 1, 1)), .newyear)
        XCTAssertEqual(Festival.automatic(on: SchoolClock.date(2026, 11, 17)), .none)
    }
    func testPausedSeasonalScenesIgnoreSavedAndAutomaticChoices() {
        XCTAssertFalse(Festival.decorationsEnabled)
        for date in [SchoolClock.date(2026, 12, 25), SchoolClock.date(2026, 11, 22)] {
            XCTAssertNotEqual(Festival.automatic(on: date), .none, "Exercise a real holiday and a solar term")
            for choice in Festival.allCases {
                XCTAssertEqual(Festival.displayed(on: date, automatic: true, manual: choice), .none)
                XCTAssertEqual(Festival.displayed(on: date, automatic: false, manual: choice), .none)
            }
        }
    }

    func testFestivalUsesShanghaiMidnight() {
        let date = ISO8601DateFormatter().date(from: "2026-12-31T16:01:00Z")!
        XCTAssertEqual(Festival.automatic(on: date), .newyear)
    }
    func testPhaseBoundaries() {
        XCTAssertEqual(DayPhase.at(minute: 299), .night)
        XCTAssertEqual(DayPhase.at(minute: 300), .dawn)
        XCTAssertEqual(DayPhase.at(minute: 480), .day)
        XCTAssertEqual(DayPhase.at(minute: 1020), .sunset)
        XCTAssertEqual(DayPhase.at(minute: 1170), .night)
    }
    func testColorsRemainValidAndTimeTransitionIsContinuous() {
        for weather in Weather.allCases {
            for minute in stride(from: 0, to: 1440, by: 17) {
                let palette = SkyPalette.at(minute: minute, weather: weather)
                for color in [palette.top, palette.middle, palette.bottom, palette.glow] {
                    XCTAssertTrue([color.red, color.green, color.blue].allSatisfy { $0.isFinite && (0...1).contains($0) })
                }
            }
        }
        let a = SkyPalette.at(minute: 719, weather: .sunny)
        let b = SkyPalette.at(minute: 720, weather: .sunny)
        XCTAssertLessThan(abs(a.top.blue - b.top.blue), 0.01)
        XCTAssertNotEqual(b, SkyPalette.at(minute: 720, weather: .moderateRain))
    }

    func testSeasonChangesActualClockOfLightNotTheClockItself() {
        let summer = SchoolClock.date(2028, 6, 23)
        let winter = SchoolClock.date(2028, 12, 23)
        let summerEvening = SkyTime(minute: 1095, on: summer)
        let winterEvening = SkyTime(minute: 1095, on: winter)
        XCTAssertGreaterThan(summerEvening.daylight, winterEvening.daylight + 0.3)
        XCTAssertGreaterThan(summerEvening.previewMinute(for: .sunset), winterEvening.previewMinute(for: .sunset))
        XCTAssertLessThan(summerEvening.previewMinute(for: .dawn), winterEvening.previewMinute(for: .dawn))
        XCTAssertEqual(SchoolClock.minute(in: SchoolClock.date(2028, 12, 23, minute: 1095)), 1095)
    }

    func testPreviewShortcutsLandInsideTheirPhasesAcrossSeasonAndLeapDay() {
        let dates = [SchoolClock.date(2028, 2, 29), SchoolClock.date(2028, 6, 23), SchoolClock.date(2028, 12, 23)]
        for date in dates {
            for expected: DayPhase in [.dawn, .day, .sunset, .night] {
                let time = SkyTime(minute: 0, on: date)
                XCTAssertEqual(SkyTime(minute: time.previewMinute(for: expected), on: date).phase, expected)
            }
        }
    }

    func testLoopAcrossShanghaiMidnightAndNoJumpAtPhaseBoundaries() {
        let day = SchoolClock.date(2028, 10, 8)
        let nextDay = SchoolClock.date(2028, 10, 9)
        let times = (0..<1440).map { SkyTime(minute: $0, on: day) } + [SkyTime(minute: 0, on: nextDay)]
        for weather in [.sunny, .overcast, .extremeRainstorm, .heavySnow, .dustStorm] as [Weather] {
            let palette = times.map { SkyPalette.at(time: $0, style: weather.style) }
            for (before, after) in zip(palette, palette.dropFirst()) {
                for (a, b) in zip([before.top, before.middle, before.bottom, before.glow],
                                  [after.top, after.middle, after.bottom, after.glow]) {
                    XCTAssertLessThan(max(abs(a.red - b.red), abs(a.green - b.green), abs(a.blue - b.blue)), 0.022)
                }
            }
        }
    }
}
