import Foundation
import Observation

/// One foreground refresh loop for the whole app, independent of navigation and drawing.
@MainActor @Observable
final class CityWeatherStore {
    let city: WeatherCity
    private(set) var followsCity: Bool
    private var sample: CityWeatherSample?
    private var verified = false
    private var fetching = false

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let read: @Sendable (WeatherCity) async throws -> CityWeatherSample
    @ObservationIgnored private let clock: @MainActor () -> Date
    @ObservationIgnored private var foreground = false
    @ObservationIgnored private var nextCheck: Date?
    @ObservationIgnored private var loop: Task<Void, Never>?

    private static let modeKey = "xiaobao.cityWeather.followsCity.v1"
    private static let interval: TimeInterval = 30 * 60
    private static let retry: TimeInterval = 10 * 60
    private static let fresh: TimeInterval = 2 * 3600
    private static let retain: TimeInterval = 24 * 3600
    private static let clockSkew: TimeInterval = 5 * 60
    private var cacheKey: String { "xiaobao.cityWeather.openMeteo.v1." + city.id }

    private struct Cache: Codable {
        let sample: CityWeatherSample
        let fetchedAt: Date
    }
    private enum SampleError: Error { case outOfDate }

    init(city: WeatherCity = .campus, defaults: UserDefaults = .standard,
         clock: @escaping @MainActor () -> Date = { Date() },
         read: @escaping @Sendable (WeatherCity) async throws -> CityWeatherSample) {
        self.city = city
        self.defaults = defaults
        self.clock = clock
        self.read = read
        followsCity = defaults.object(forKey: Self.modeKey) as? Bool ?? true
        let now = clock()
        if let data = defaults.data(forKey: cacheKey),
           let cache = try? JSONDecoder().decode(Cache.self, from: data),
           Self.usable(cache.sample.validAt, at: now, limit: Self.retain),
           Self.usable(cache.fetchedAt, at: now, limit: Self.retain) {
            sample = cache.sample
            if Self.usable(cache.sample.validAt, at: now, limit: Self.fresh) {
                nextCheck = min(cache.fetchedAt, now).addingTimeInterval(Self.interval)
            }
        }
    }

    deinit { loop?.cancel() }

    func display(at now: Date, preview: Weather) -> CityWeatherDisplay {
        guard followsCity else { return .preview(preview) }
        guard let sample, Self.usable(sample.validAt, at: now, limit: Self.retain) else {
            return fetching ? .loading : .unavailable
        }
        if verified && Self.usable(sample.validAt, at: now, limit: Self.fresh) { return .current(sample) }
        return .cached(sample)
    }

    func setForeground(_ active: Bool) {
        guard foreground != active else { return }
        foreground = active
        schedule()
    }

    func setFollowsCity(_ enabled: Bool) {
        guard followsCity != enabled else { return }
        followsCity = enabled
        defaults.set(enabled, forKey: Self.modeKey)
        schedule()
    }

    private func schedule() {
        loop?.cancel()
        loop = nil
        fetching = false
        guard foreground && followsCity else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let delay = await self?.refreshIfDue(), !Task.isCancelled else { return }
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            }
        }
    }

    private func refreshIfDue() async -> TimeInterval {
        let now = clock()
        if let remaining = nextCheck?.timeIntervalSince(now), remaining > 0, remaining <= Self.interval {
            return remaining
        }
        fetching = true
        let delay: TimeInterval
        do {
            let candidate = try await read(city)
            // A retired request must not mutate state even if its transport ignored cancellation.
            try Task.checkCancellation()
            let received = clock()
            guard Self.usable(candidate.validAt, at: received, limit: Self.fresh) else { throw SampleError.outOfDate }
            if let previous = sample, Self.usable(previous.validAt, at: received, limit: Self.retain),
               previous.validAt > candidate.validAt { throw SampleError.outOfDate }
            sample = candidate
            verified = true
            if let data = try? JSONEncoder().encode(Cache(sample: candidate, fetchedAt: received)) {
                defaults.set(data, forKey: cacheKey)
            }
            delay = Self.interval
        } catch {
            guard !Task.isCancelled else { return Self.retry }
            verified = false
            delay = Self.retry
        }
        fetching = false
        nextCheck = clock().addingTimeInterval(delay)
        return delay
    }

    private static func usable(_ date: Date, at now: Date, limit: TimeInterval) -> Bool {
        (-clockSkew...limit).contains(now.timeIntervalSince(date))
    }
}
