import Foundation

/// An illustration condition from the city model or a manual choice. Persist raw values, not titles.
public enum Weather: String, CaseIterable, Codable, Identifiable, Sendable {
    case sunny, cloudy, overcast
    case shower, lightRain, moderateRain = "rain", heavyRain, rainstorm, severeRainstorm, extremeRainstorm
    case lightToModerateRain, moderateToHeavyRain, heavyRainToRainstorm
    case rainstormToSevereRainstorm, severeToExtremeRainstorm
    case sleet, freezingRain, snowShower, lightSnow, moderateSnow = "snow", heavySnow, blizzard
    case lightToModerateSnow, moderateToHeavySnow, heavySnowToBlizzard
    case thunderstorm, thunderstormWithHail, hail, typhoon
    case fog, haze, floatingDust, blowingSand, dustStorm, severeDustStorm

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .sunny: String(localized: "晴")
        case .cloudy: String(localized: "多云")
        case .overcast: String(localized: "阴")
        case .shower: String(localized: "阵雨")
        case .lightRain: String(localized: "小雨")
        case .moderateRain: String(localized: "中雨")
        case .heavyRain: String(localized: "大雨")
        case .rainstorm: String(localized: "暴雨")
        case .severeRainstorm: String(localized: "大暴雨")
        case .extremeRainstorm: String(localized: "特大暴雨")
        case .lightToModerateRain: String(localized: "小雨–中雨")
        case .moderateToHeavyRain: String(localized: "中雨–大雨")
        case .heavyRainToRainstorm: String(localized: "大雨–暴雨")
        case .rainstormToSevereRainstorm: String(localized: "暴雨–大暴雨")
        case .severeToExtremeRainstorm: String(localized: "大暴雨–特大暴雨")
        case .sleet: String(localized: "雨夹雪")
        case .freezingRain: String(localized: "冻雨")
        case .snowShower: String(localized: "阵雪")
        case .lightSnow: String(localized: "小雪")
        case .moderateSnow: String(localized: "中雪")
        case .heavySnow: String(localized: "大雪")
        case .blizzard: String(localized: "暴雪")
        case .lightToModerateSnow: String(localized: "小雪–中雪")
        case .moderateToHeavySnow: String(localized: "中雪–大雪")
        case .heavySnowToBlizzard: String(localized: "大雪–暴雪")
        case .thunderstorm: String(localized: "雷阵雨")
        case .thunderstormWithHail: String(localized: "雷阵雨伴有冰雹")
        case .hail: String(localized: "冰雹")
        case .typhoon: String(localized: "台风")
        case .fog: String(localized: "雾")
        case .haze: String(localized: "霾")
        case .floatingDust: String(localized: "浮尘")
        case .blowingSand: String(localized: "扬沙")
        case .dustStorm: String(localized: "沙尘暴")
        case .severeDustStorm: String(localized: "强沙尘暴")
        }
    }

    public var category: WeatherCategory {
        switch self {
        case .sunny, .cloudy, .overcast: .sky
        case .shower, .lightRain, .moderateRain, .heavyRain, .rainstorm, .severeRainstorm, .extremeRainstorm,
             .lightToModerateRain, .moderateToHeavyRain, .heavyRainToRainstorm, .rainstormToSevereRainstorm,
             .severeToExtremeRainstorm: .rain
        case .sleet, .freezingRain, .snowShower, .lightSnow, .moderateSnow, .heavySnow, .blizzard,
             .lightToModerateSnow, .moderateToHeavySnow, .heavySnowToBlizzard: .snowAndIce
        case .thunderstorm, .thunderstormWithHail, .hail, .typhoon: .storm
        case .fog, .haze, .floatingDust, .blowingSand, .dustStorm, .severeDustStorm: .visibility
        }
    }

    public var symbol: String {
        switch self {
        case .sunny: "sun.max"
        case .cloudy: "cloud.sun"
        case .overcast: "cloud"
        case .shower, .lightRain, .lightToModerateRain: "cloud.drizzle"
        case .moderateRain, .moderateToHeavyRain: "cloud.rain"
        case .heavyRain, .rainstorm, .severeRainstorm, .extremeRainstorm, .heavyRainToRainstorm,
             .rainstormToSevereRainstorm, .severeToExtremeRainstorm: "cloud.heavyrain"
        case .sleet, .freezingRain: "cloud.sleet"
        case .snowShower, .lightSnow, .moderateSnow, .lightToModerateSnow, .moderateToHeavySnow: "cloud.snow"
        case .heavySnow, .blizzard, .heavySnowToBlizzard: "snowflake"
        case .thunderstorm, .thunderstormWithHail: "cloud.bolt.rain"
        case .hail: "cloud.hail"
        case .typhoon: "hurricane"
        case .fog: "cloud.fog"
        case .haze: "sun.haze"
        case .floatingDust, .blowingSand, .dustStorm, .severeDustStorm: "wind"
        }
    }
}

public enum WeatherCategory: String, CaseIterable, Identifiable, Sendable {
    case sky, rain, snowAndIce, storm, visibility

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .sky: String(localized: "晴空与云层")
        case .rain: String(localized: "降雨")
        case .snowAndIce: String(localized: "降雪与结冰")
        case .storm: String(localized: "雷暴与强风")
        case .visibility: String(localized: "雾、霾与沙尘")
        }
    }
    public var conditions: [Weather] { Weather.allCases.filter { $0.category == self } }
}
