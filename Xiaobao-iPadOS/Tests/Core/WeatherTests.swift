import XCTest
@testable import XiaobaoCore

final class WeatherTests: XCTestCase {
    func testEveryConditionAppearsInExactlyOnePickerSectionAndHasItsOwnStyle() {
        let displayed = WeatherCategory.allCases.flatMap(\.conditions)
        let available = Weather.allCases
        XCTAssertEqual(available.count, 35)
        XCTAssertEqual(displayed.count, available.count)
        XCTAssertEqual(Set(displayed), Set(available))
        XCTAssertEqual(Set(displayed.map(\.title)).count, displayed.count)
        for (index, condition) in available.enumerated() {
            for other in available.dropFirst(index + 1) {
                XCTAssertNotEqual(condition.style, other.style, "\(condition.id) / \(other.id)")
            }
        }
    }

    func testV1RainAndSnowPreferencesKeepTheirMeaningAndAllOptionsRoundTrip() throws {
        let decoder = JSONDecoder(), encoder = JSONEncoder()
        XCTAssertEqual(try decoder.decode(Weather.self, from: Data("\"rain\"".utf8)), .moderateRain)
        XCTAssertEqual(try decoder.decode(Weather.self, from: Data("\"snow\"".utf8)), .moderateSnow)
        for weather in Weather.allCases {
            XCTAssertEqual(try decoder.decode(Weather.self, from: encoder.encode(weather)), weather)
        }
    }

    func testRainsAndSnowsIncreaseBothDensityAndReducedVisibility() {
        let rain: [Weather] = [.lightRain, .moderateRain, .heavyRain, .rainstorm, .severeRainstorm, .extremeRainstorm]
        let snow: [Weather] = [.lightSnow, .moderateSnow, .heavySnow, .blizzard]
        for series in [rain, snow] {
            let frames = series.map { $0.style.frame() }
            for (weak, strong) in zip(frames, frames.dropFirst()) {
                XCTAssertLessThan(weak.rain + weak.snow, strong.rain + strong.snow)
                XCTAssertLessThan(weak.veil, strong.veil)
                XCTAssertLessThan(weak.dimming, strong.dimming)
            }
        }
    }

    func testRangesInterpolateBetweenCorrectConditionsAndPauseAtMidpoint() {
        let ranges: [(Weather, Weather, Weather)] = [
            (.lightToModerateRain, .lightRain, .moderateRain),
            (.moderateToHeavyRain, .moderateRain, .heavyRain),
            (.heavyRainToRainstorm, .heavyRain, .rainstorm),
            (.rainstormToSevereRainstorm, .rainstorm, .severeRainstorm),
            (.severeToExtremeRainstorm, .severeRainstorm, .extremeRainstorm),
            (.lightToModerateSnow, .lightSnow, .moderateSnow),
            (.moderateToHeavySnow, .moderateSnow, .heavySnow),
            (.heavySnowToBlizzard, .heavySnow, .blizzard),
        ]
        for (weather, lower, upper) in ranges {
            let style = weather.style
            let low = lower.style.frame()
            let high = upper.style.frame()
            XCTAssertEqual(style.lower, low)
            XCTAssertEqual(style.upper, high)
            XCTAssertEqual(style.frame(at: 0), low)
            XCTAssertEqual(style.frame(at: style.period), low)
            XCTAssertEqual(style.frame(at: style.period / 2), high)
            let midpoint = style.frame()
            XCTAssertEqual(midpoint.rain + midpoint.snow, (low.rain + low.snow + high.rain + high.snow) / 2, accuracy: 1e-10)
            XCTAssertEqual(style.frame(at: .nan), midpoint)
        }
    }

    func testIceWindAndVisibilityAreIndependentEffects() {
        XCTAssertTrue(Weather.sleet.style.frame().rain > 0 && Weather.sleet.style.frame().snow > 0)
        XCTAssertGreaterThan(Weather.freezingRain.style.frame().rain, 0)
        XCTAssertEqual(Weather.freezingRain.style.frame().snow, 0)
        XCTAssertGreaterThan(Weather.hail.style.frame().hail, 0)
        XCTAssertFalse(Weather.hail.style.lightning)
        XCTAssertTrue(Weather.thunderstorm.style.lightning)
        XCTAssertEqual(Weather.thunderstorm.style.frame().hail, 0)
        XCTAssertTrue(Weather.thunderstormWithHail.style.lightning)
        XCTAssertGreaterThan(Weather.thunderstormWithHail.style.frame().hail, 0)
        XCTAssertLessThan(Weather.typhoon.style.frame().wind, -0.72)
        XCTAssertFalse(Weather.fog.style.frame().hasParticles)
        XCTAssertFalse(Weather.haze.style.frame().hasParticles)
        XCTAssertNotEqual(Weather.fog.style.mood, Weather.haze.style.mood)
        XCTAssertGreaterThan(Weather.severeDustStorm.style.frame().dust, Weather.floatingDust.style.frame().dust)
    }

    func testAllModesStayWithinDrawableBoundsAcrossACycle() {
        for weather in Weather.allCases {
            let style = weather.style
            XCTAssertGreaterThan(style.period, 0)
            for part in 0...24 {
                let frame = style.frame(at: style.period * Double(part) / 24)
                for value in [frame.cloudCover, frame.dimming, frame.veil, frame.rain, frame.snow, frame.hail, frame.dust] {
                    XCTAssertTrue((0...1).contains(value), weather.id)
                }
                XCTAssertTrue((-1...1).contains(frame.wind), weather.id)
            }
        }
    }
}
