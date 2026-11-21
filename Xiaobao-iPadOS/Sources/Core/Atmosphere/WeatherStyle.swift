import Foundation

enum WeatherMood: Equatable, Sendable {
    case clear, overcast, wet, ice, mist, dust, haze
}

/// Normalized illustration controls, not physical rates or forecast probabilities.
struct WeatherFrame: Equatable, Sendable {
    var cloudCover: Double = 0
    var dimming: Double = 0
    var veil: Double = 0
    var rain: Double = 0
    var snow: Double = 0
    var hail: Double = 0
    var dust: Double = 0
    var wind: Double = 0.08 // Signed horizontal gust, in -1...1.

    fileprivate func mixed(with end: Self, fraction t: Double) -> Self {
        func mix(_ lhs: Double, _ rhs: Double) -> Double { lhs + (rhs - lhs) * t }
        return Self(
            cloudCover: mix(cloudCover, end.cloudCover), dimming: mix(dimming, end.dimming),
            veil: mix(veil, end.veil), rain: mix(rain, end.rain), snow: mix(snow, end.snow),
            hail: mix(hail, end.hail), dust: mix(dust, end.dust), wind: mix(wind, end.wind)
        )
    }

    var hasParticles: Bool { rain > 0 || snow > 0 || hail > 0 || dust > 0 }
}

struct WeatherStyle: Equatable, Sendable {
    let mood: WeatherMood
    let lower: WeatherFrame
    let upper: WeatherFrame?
    let period: TimeInterval
    let lightning: Bool

    init(_ mood: WeatherMood, _ lower: WeatherFrame, upper: WeatherFrame? = nil,
         period: TimeInterval = 18, lightning: Bool = false) {
        self.mood = mood
        self.lower = lower
        self.upper = upper
        self.period = period
        self.lightning = lightning
    }

    /// Nil represents a still preview; show the midpoint of a range, not its weakest endpoint.
    func frame(at seconds: TimeInterval? = nil) -> WeatherFrame {
        guard let upper else { return lower }
        let fraction = seconds.flatMap { value in
            value.isFinite ? (1 - cos(2 * .pi * value.truncatingRemainder(dividingBy: period) / period)) * 0.5 : nil
        } ?? 0.5
        return lower.mixed(with: upper, fraction: fraction)
    }
}

extension Weather {
    var style: WeatherStyle {
        switch self {
        case .sunny: .init(.clear, .init(cloudCover: 0.05))
        case .cloudy: .init(.clear, .init(cloudCover: 0.50, veil: 0.04))
        case .overcast: .init(.overcast, .init(cloudCover: 0.93, dimming: 0.11, veil: 0.11, wind: 0.12))
        case .shower: .init(.wet, .init(cloudCover: 0.58, veil: 0.06, rain: 0.07, wind: 0.14), upper: Self.rainfall(.heavy), period: 12)
        case .lightRain: .init(.wet, Self.rainfall(.light))
        case .moderateRain: .init(.wet, Self.rainfall(.moderate))
        case .heavyRain: .init(.wet, Self.rainfall(.heavy))
        case .rainstorm: .init(.wet, Self.rainfall(.storm))
        case .severeRainstorm: .init(.wet, Self.rainfall(.severe))
        case .extremeRainstorm: .init(.wet, Self.rainfall(.extreme))
        case .lightToModerateRain: Self.rainRange(.light, .moderate)
        case .moderateToHeavyRain: Self.rainRange(.moderate, .heavy)
        case .heavyRainToRainstorm: Self.rainRange(.heavy, .storm)
        case .rainstormToSevereRainstorm: Self.rainRange(.storm, .severe)
        case .severeToExtremeRainstorm: Self.rainRange(.severe, .extreme)
        case .sleet: .init(.ice, .init(cloudCover: 0.89, dimming: 0.11, veil: 0.19, rain: 0.35, snow: 0.34, wind: 0.24))
        case .freezingRain: .init(.ice, .init(cloudCover: 0.86, dimming: 0.07, veil: 0.32, rain: 0.24, wind: 0.09))
        case .snowShower: .init(.ice, .init(cloudCover: 0.56, veil: 0.10, snow: 0.05, wind: -0.08),
                                upper: Self.snowfall(.heavy), period: 14)
        case .lightSnow: .init(.ice, Self.snowfall(.light))
        case .moderateSnow: .init(.ice, Self.snowfall(.moderate))
        case .heavySnow: .init(.ice, Self.snowfall(.heavy))
        case .blizzard: .init(.ice, Self.snowfall(.blizzard))
        case .lightToModerateSnow: Self.snowRange(.light, .moderate)
        case .moderateToHeavySnow: Self.snowRange(.moderate, .heavy)
        case .heavySnowToBlizzard: Self.snowRange(.heavy, .blizzard)
        case .thunderstorm: .init(.wet, .init(cloudCover: 0.94, dimming: 0.31, veil: 0.12, rain: 0.39, wind: 0.28),
                                 upper: .init(cloudCover: 1, dimming: 0.47, veil: 0.22, rain: 0.78, wind: 0.49),
                                 period: 13, lightning: true)
        case .thunderstormWithHail: .init(.wet, .init(cloudCover: 0.94, dimming: 0.32, veil: 0.14, rain: 0.43, hail: 0.33, wind: 0.3),
                                         upper: .init(cloudCover: 1, dimming: 0.49, veil: 0.25, rain: 0.76, hail: 0.76, wind: 0.52),
                                         period: 14, lightning: true)
        case .hail: .init(.ice, .init(cloudCover: 0.97, dimming: 0.18, veil: 0.15, hail: 0.72, wind: 0.27))
        case .typhoon: .init(.wet, .init(cloudCover: 1, dimming: 0.32, veil: 0.28, rain: 0.77, wind: -0.65),
                             upper: .init(cloudCover: 1, dimming: 0.52, veil: 0.43, rain: 1, wind: -1), period: 10)
        case .fog: .init(.mist, .init(cloudCover: 0.79, veil: 0.86, wind: 0.04))
        case .haze: .init(.haze, .init(cloudCover: 0.42, dimming: 0.09, veil: 0.62, wind: 0.04))
        case .floatingDust: .init(.dust, .init(cloudCover: 0.29, veil: 0.35, dust: 0.19, wind: 0.16))
        case .blowingSand: .init(.dust, .init(cloudCover: 0.44, dimming: 0.08, veil: 0.5, dust: 0.44, wind: 0.51))
        case .dustStorm: .init(.dust, .init(cloudCover: 0.66, dimming: 0.19, veil: 0.68, dust: 0.72, wind: 0.75))
        case .severeDustStorm: .init(.dust, .init(cloudCover: 0.91, dimming: 0.31, veil: 0.88, dust: 1, wind: 1))
        }
    }

    private enum RainLevel { case light, moderate, heavy, storm, severe, extreme }
    private enum SnowLevel { case light, moderate, heavy, blizzard }

    private static func rainfall(_ level: RainLevel) -> WeatherFrame {
        switch level {
        case .light: .init(cloudCover: 0.72, dimming: 0.09, veil: 0.09, rain: 0.16, wind: 0.12)
        case .moderate: .init(cloudCover: 0.82, dimming: 0.16, veil: 0.12, rain: 0.32, wind: 0.17)
        case .heavy: .init(cloudCover: 0.91, dimming: 0.23, veil: 0.17, rain: 0.50, wind: 0.25)
        case .storm: .init(cloudCover: 0.96, dimming: 0.31, veil: 0.23, rain: 0.67, wind: 0.38)
        case .severe: .init(cloudCover: 0.99, dimming: 0.40, veil: 0.32, rain: 0.84, wind: 0.53)
        case .extreme: .init(cloudCover: 1, dimming: 0.50, veil: 0.43, rain: 1, wind: 0.70)
        }
    }

    private static func snowfall(_ level: SnowLevel) -> WeatherFrame {
        switch level {
        case .light: .init(cloudCover: 0.67, veil: 0.13, snow: 0.18, wind: -0.09)
        case .moderate: .init(cloudCover: 0.78, dimming: 0.04, veil: 0.23, snow: 0.39, wind: -0.18)
        case .heavy: .init(cloudCover: 0.88, dimming: 0.10, veil: 0.39, snow: 0.67, wind: -0.36)
        case .blizzard: .init(cloudCover: 0.98, dimming: 0.21, veil: 0.62, snow: 1, wind: -0.92)
        }
    }

    private static func rainRange(_ lower: RainLevel, _ upper: RainLevel) -> WeatherStyle {
        .init(.wet, rainfall(lower), upper: rainfall(upper))
    }
    private static func snowRange(_ lower: SnowLevel, _ upper: SnowLevel) -> WeatherStyle {
        .init(.ice, snowfall(lower), upper: snowfall(upper))
    }
}
