import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Isolated public-data transport: never uses the school client, cookies, credentials or location APIs.
struct OpenMeteoClient: Sendable {
    enum ReadError: Error { case invalidResponse, unknownWeather }
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        session = URLSession(configuration: config, delegate: NoWeatherRedirects(), delegateQueue: nil)
    }

    static func request(for city: WeatherCity) -> URLRequest {
        var url = URLComponents()
        url.scheme = "https"
        url.host = "api.open-meteo.com"
        url.path = "/v1/forecast"
        url.queryItems = [URLQueryItem(name: "latitude", value: String(city.latitude)),
                          URLQueryItem(name: "longitude", value: String(city.longitude)),
                          URLQueryItem(name: "current", value: "weather_code"),
                          URLQueryItem(name: "timeformat", value: "unixtime")]
        // All components are constants or finite coordinates from app configuration.
        var request = URLRequest(url: url.url!)
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    func read(_ city: WeatherCity) async throws -> CityWeatherSample {
        let (data, response) = try await session.data(for: Self.request(for: city))
        return try Self.decode(data, response: response)
    }

    static func decode(_ data: Data, response: URLResponse) throws -> CityWeatherSample {
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 16_384 else {
            throw ReadError.invalidResponse
        }
        struct Payload: Decodable {
            struct Current: Decodable {
                let time: Int
                let weatherCode: Int
                enum CodingKeys: String, CodingKey { case time, weatherCode = "weather_code" }
            }
            let current: Current
        }
        let current = try JSONDecoder().decode(Payload.self, from: data).current
        guard current.time > 0 else { throw ReadError.invalidResponse }
        guard let weather = weatherForWMOCode(current.weatherCode) else { throw ReadError.unknownWeather }
        return CityWeatherSample(weather: weather, validAt: Date(timeIntervalSince1970: Double(current.time)))
    }
}

private final class NoWeatherRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
