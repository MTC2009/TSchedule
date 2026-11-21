import Foundation

/// A public city centre, not a school address or a device location.
struct WeatherCity: Sendable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double

    static let campus = WeatherCity(id: "cn-guangdong-dongguan", name: "东莞",
                                    latitude: 23.02, longitude: 113.75)
}

struct CityWeatherSample: Codable, Equatable, Sendable {
    let weather: Weather
    /// The time the model describes, not the time the response arrived.
    let validAt: Date
}

enum CityWeatherDisplay: Equatable {
    case current(CityWeatherSample), cached(CityWeatherSample)
    case preview(Weather), loading, unavailable

    var weather: Weather {
        switch self {
        case .current(let sample), .cached(let sample): sample.weather
        case .preview(let weather): weather
        case .loading, .unavailable: .cloudy // Decorative fallback, never displayed as a city report.
        }
    }
}

/// Match only the phenomena described by the published Open-Meteo weather-code table.
/// A rain shower is not a local rainstorm warning; snow grains are not hail.
func weatherForWMOCode(_ code: Int) -> Weather? {
    switch code {
    case 0, 1: .sunny
    case 2: .cloudy
    case 3: .overcast
    case 45, 48: .fog
    case 51, 53, 55, 61: .lightRain
    case 56, 57, 66, 67: .freezingRain
    case 63: .moderateRain
    case 65: .heavyRain
    case 71, 77: .lightSnow
    case 73: .moderateSnow
    case 75: .heavySnow
    case 80, 81, 82: .shower
    case 85, 86: .snowShower
    case 95, 97: .thunderstorm
    case 96, 99: .thunderstormWithHail
    default: nil
    }
}
