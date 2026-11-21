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
        case .sunny: "晴"
        case .cloudy: "多云"
        case .overcast: "阴"
        case .shower: "阵雨"
        case .lightRain: "小雨"
        case .moderateRain: "中雨"
        case .heavyRain: "大雨"
        case .rainstorm: "暴雨"
        case .severeRainstorm: "大暴雨"
        case .extremeRainstorm: "特大暴雨"
        case .lightToModerateRain: "小雨–中雨"
        case .moderateToHeavyRain: "中雨–大雨"
        case .heavyRainToRainstorm: "大雨–暴雨"
        case .rainstormToSevereRainstorm: "暴雨–大暴雨"
        case .severeToExtremeRainstorm: "大暴雨–特大暴雨"
        case .sleet: "雨夹雪"
        case .freezingRain: "冻雨"
        case .snowShower: "阵雪"
        case .lightSnow: "小雪"
        case .moderateSnow: "中雪"
        case .heavySnow: "大雪"
        case .blizzard: "暴雪"
        case .lightToModerateSnow: "小雪–中雪"
        case .moderateToHeavySnow: "中雪–大雪"
        case .heavySnowToBlizzard: "大雪–暴雪"
        case .thunderstorm: "雷阵雨"
        case .thunderstormWithHail: "雷阵雨伴有冰雹"
        case .hail: "冰雹"
        case .typhoon: "台风"
        case .fog: "雾"
        case .haze: "霾"
        case .floatingDust: "浮尘"
        case .blowingSand: "扬沙"
        case .dustStorm: "沙尘暴"
        case .severeDustStorm: "强沙尘暴"
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
        case .sky: "晴空与云层"
        case .rain: "降雨"
        case .snowAndIce: "降雪与结冰"
        case .storm: "雷暴与强风"
        case .visibility: "雾、霾与沙尘"
        }
    }
    public var conditions: [Weather] { Weather.allCases.filter { $0.category == self } }
}
