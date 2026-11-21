import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import XiaobaoCore

final class CityWeatherClientTests: XCTestCase {
    func testCityRequestHasOnlyPublicGridInputs() throws {
        let city = WeatherCity(id: "test-ridge", name: "Ridge", latitude: 44.25, longitude: -71.5)
        let request = OpenMeteoClient.request(for: city)
        let url = try XCTUnwrap(request.url)
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "api.open-meteo.com")
        XCTAssertEqual(url.path, "/v1/forecast")
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") }),
                       ["latitude": "44.25", "longitude": "-71.5", "current": "weather_code", "timeformat": "unixtime"])
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertNil(request.httpBody)
        XCTAssertFalse(request.httpShouldHandleCookies)
        XCTAssertEqual(request.allHTTPHeaderFields?.count, 1)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
    }

    func testAllDocumentedCodesMapWithoutInferringUnreportedPhenomena() {
        let groups: [(Weather, [Int])] = [
            (.fog, [45, 48]), (.sunny, [0, 1]), (.cloudy, [2]), (.overcast, [3]),
            (.lightRain, [51, 53, 55, 61]), (.freezingRain, [56, 57, 66, 67]),
            (.moderateRain, [63]), (.heavyRain, [65]), (.lightSnow, [71, 77]),
            (.moderateSnow, [73]), (.heavySnow, [75]), (.shower, [80, 81, 82]),
            (.snowShower, [85, 86]), (.thunderstorm, [95, 97]), (.thunderstormWithHail, [96, 99])
        ]
        for (weather, codes) in groups {
            for code in codes { XCTAssertEqual(weatherForWMOCode(code), weather, "code \(code)") }
        }
        for code in [-1, 12, 98, 1000] { XCTAssertNil(weatherForWMOCode(code)) }
        XCTAssertEqual(Set(groups.map(\.0)).count, 15)
    }

    func testReadsCurrentNotDailyAndRejectsUnknownMalformedAndNonSuccess() throws {
        let url = try XCTUnwrap(URL(string: "https://example.invalid/weather"))
        func decode(_ text: String, status: Int = 200) throws -> CityWeatherSample {
            let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil))
            return try OpenMeteoClient.decode(Data(text.utf8), response: response)
        }
        let body = #"{"daily":{"weather_code":[65]},"current":{"time":1730000300,"weather_code":77}}"#
        let sample = try decode(body)
        XCTAssertEqual(sample.weather, .lightSnow)
        XCTAssertEqual(sample.validAt, Date(timeIntervalSince1970: 1_730_000_300))
        for code in [204, 302, 429, 503] { XCTAssertThrowsError(try decode(body, status: code)) }
        for invalid in [#"{"daily":{"weather_code":[3]}}"#, #"{"current":{"time":-5,"weather_code":0}}"#,
                        #"{"current":{"time":25,"weather_code":712}}"#, #"{"current":{"time":25,"weather_code":null}}"#,
                        "<html>", String(repeating: " ", count: 17_000) + body] {
            XCTAssertThrowsError(try decode(invalid))
        }
    }
}

@MainActor
private final class WeatherReadGate {
    private(set) var calls = 0
    private var pending: [Int: CheckedContinuation<CityWeatherSample, Error>] = [:]

    func read(_ city: WeatherCity) async throws -> CityWeatherSample {
        calls += 1
        let id = calls
        return try await withCheckedThrowingContinuation { pending[id] = $0 }
    }

    func finish(_ id: Int, with result: Result<CityWeatherSample, Error>) {
        pending.removeValue(forKey: id)?.resume(with: result)
    }
}

@MainActor
final class CityWeatherStoreTests: XCTestCase {
    private let city = WeatherCity(id: "test-valley", name: "Valley", latitude: 48, longitude: 11)
    private var instant = Date(timeIntervalSince1970: 1_720_000_000)
    private let defaults = UserDefaults(suiteName: "city-weather-tests." + UUID().uuidString)!
    private let gate = WeatherReadGate()

    private func makeStore(for otherCity: WeatherCity? = nil) -> CityWeatherStore {
        CityWeatherStore(city: otherCity ?? city, defaults: defaults, clock: { self.instant },
                         read: { [gate] city in try await gate.read(city) })
    }

    private func until(_ check: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = ContinuousClock.now + .seconds(3)
        while !check(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(check(), "Expected change did not occur", file: file, line: line)
    }

    func testManualColdStartAndFailureCooldownMakeNoExtraRequests() async {
        let oldSettings = Data(#"{"glass":"regular","weather":"snow"}"#.utf8)
        defaults.set(oldSettings, forKey: "xiaobao.native.preferences.v1")
        makeStore().setFollowsCity(false)
        let store = makeStore()
        defer { store.setForeground(false) }
        store.setForeground(true)
        try? await Task.sleep(for: .milliseconds(25))
        XCTAssertEqual(gate.calls, 0)
        XCTAssertEqual(store.display(at: instant, preview: .moderateSnow), .preview(.moderateSnow))
        store.setFollowsCity(true)
        await until { self.gate.calls == 1 }
        gate.finish(1, with: .failure(URLError(.notConnectedToInternet)))
        await until { store.display(at: self.instant, preview: .moderateSnow) == .unavailable }
        store.setForeground(false)
        instant.addTimeInterval(599)
        store.setForeground(true)
        try? await Task.sleep(for: .milliseconds(25))
        XCTAssertEqual(gate.calls, 1)
        XCTAssertEqual(defaults.data(forKey: "xiaobao.native.preferences.v1"), oldSettings)
    }

    func testOfflineCacheExpiresByWeatherTimeAndRecoversOnRetry() async {
        let store = makeStore()
        defer { store.setForeground(false) }
        let sample = CityWeatherSample(weather: .fog, validAt: instant.addingTimeInterval(-900))
        store.setForeground(true)
        await until { self.gate.calls == 1 }
        XCTAssertEqual(store.display(at: instant, preview: .sunny), .loading)
        gate.finish(1, with: .success(sample))
        await until { store.display(at: self.instant, preview: .sunny) == .current(sample) }
        store.setForeground(false)
        instant.addTimeInterval(31 * 60)
        store.setForeground(true)
        await until { self.gate.calls == 2 }
        gate.finish(2, with: .failure(URLError(.notConnectedToInternet)))
        await until { store.display(at: self.instant, preview: .sunny) == .cached(sample) }
        XCTAssertEqual(store.display(at: sample.validAt.addingTimeInterval(24 * 3600), preview: .sunny), .cached(sample))
        XCTAssertEqual(store.display(at: sample.validAt.addingTimeInterval(24 * 3600 + 1), preview: .sunny), .unavailable)
        store.setForeground(false)
        instant.addTimeInterval(601)
        store.setForeground(true)
        await until { self.gate.calls == 3 }
        let newer = CityWeatherSample(weather: .shower, validAt: instant)
        gate.finish(3, with: .success(newer))
        await until { store.display(at: self.instant, preview: .sunny) == .current(newer) }
    }

    func testManualAndInactiveIgnoreLateRepliesEvenAfterResuming() async {
        let store = makeStore()
        defer { store.setForeground(false) }
        store.setForeground(true)
        await until { self.gate.calls == 1 }
        store.setFollowsCity(false)
        let manual = makeStore()
        XCTAssertFalse(manual.followsCity)
        XCTAssertEqual(manual.display(at: instant, preview: .haze), .preview(.haze))
        store.setFollowsCity(true)
        await until { self.gate.calls == 2 }
        store.setForeground(false)
        store.setForeground(true)
        await until { self.gate.calls == 3 }
        let good = CityWeatherSample(weather: .fog, validAt: instant)
        gate.finish(3, with: .success(good))
        await until { store.display(at: self.instant, preview: .haze) == .current(good) }
        // These gates deliberately return AFTER cancellation, in reverse order.
        gate.finish(2, with: .failure(URLError(.timedOut)))
        gate.finish(1, with: .success(CityWeatherSample(weather: .overcast, validAt: instant)))
        try? await Task.sleep(for: .milliseconds(25))
        XCTAssertEqual(store.display(at: instant, preview: .haze), .current(good))
        XCTAssertEqual(makeStore().display(at: instant, preview: .haze), .cached(good))
        store.setFollowsCity(false)
        XCTAssertEqual(store.display(at: instant, preview: .haze), .preview(.haze))
    }

    func testColdCacheIsScopedAndForegroundDoesNotFetchAgainInsideInterval() async {
        let first = makeStore()
        first.setForeground(true)
        await until { self.gate.calls == 1 }
        let sample = CityWeatherSample(weather: .freezingRain, validAt: instant)
        gate.finish(1, with: .success(sample))
        await until { first.display(at: self.instant, preview: .haze) == .current(sample) }
        first.setForeground(false)
        let restored = makeStore()
        defer { restored.setForeground(false) }
        instant.addTimeInterval(25 * 60)
        restored.setForeground(true)
        restored.setForeground(true)
        try? await Task.sleep(for: .milliseconds(25))
        XCTAssertEqual(gate.calls, 1)
        XCTAssertEqual(restored.display(at: instant, preview: .haze), .cached(sample))
        let other = WeatherCity(id: "test-coast", name: "Coast", latitude: 51, longitude: 1)
        XCTAssertEqual(makeStore(for: other).display(at: instant, preview: .haze), .unavailable)
        XCTAssertEqual(first.display(at: sample.validAt.addingTimeInterval(7201), preview: .haze), .cached(sample))
        instant.addTimeInterval(25 * 3600)
        XCTAssertEqual(makeStore().display(at: instant, preview: .haze), .unavailable)
    }

    func testNoCacheAndUnusableReportsNeverInventCityWeather() async {
        let store = makeStore()
        defer { store.setForeground(false) }
        let reports: [Result<CityWeatherSample, Error>] = [
            .failure(URLError(.notConnectedToInternet)),
            .success(CityWeatherSample(weather: .heavyRain, validAt: instant.addingTimeInterval(-4 * 3600))),
            .success(CityWeatherSample(weather: .lightRain, validAt: instant.addingTimeInterval(3 * 3600)))
        ]
        for (i, result) in reports.enumerated() {
            store.setForeground(true)
            await until { self.gate.calls == i + 1 }
            gate.finish(i + 1, with: result)
            await until { store.display(at: self.instant, preview: .typhoon) == .unavailable }
            XCTAssertEqual(store.display(at: instant, preview: .typhoon).weather, .cloudy)
            store.setForeground(false)
            instant.addTimeInterval(601)
        }
    }

    func testOlderReportCannotReplaceNewerCachedSky() async {
        let store = makeStore()
        defer { store.setForeground(false) }
        let latest = CityWeatherSample(weather: .shower, validAt: instant)
        store.setForeground(true)
        await until { self.gate.calls == 1 }
        gate.finish(1, with: .success(latest))
        await until { store.display(at: self.instant, preview: .haze) == .current(latest) }
        store.setForeground(false)
        instant.addTimeInterval(1801)
        store.setForeground(true)
        await until { self.gate.calls == 2 }
        gate.finish(2, with: .success(CityWeatherSample(weather: .sunny, validAt: latest.validAt.addingTimeInterval(-900))))
        await until { store.display(at: self.instant, preview: .haze) == .cached(latest) }
    }
}
