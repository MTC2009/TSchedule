public struct SkyColor: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(hex: UInt32) {
        red = Double((hex >> 16) & 255) / 255
        green = Double((hex >> 8) & 255) / 255
        blue = Double(hex & 255) / 255
    }
    private init(_ red: Double, _ green: Double, _ blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
    public func mixed(with other: SkyColor, amount: Double) -> SkyColor {
        let t = max(0, min(1, amount))
        return SkyColor(red + (other.red - red) * t, green + (other.green - green) * t, blue + (other.blue - blue) * t)
    }
}

public struct SkyPalette: Equatable, Sendable {
    public let top: SkyColor
    public let middle: SkyColor
    public let bottom: SkyColor
    public let glow: SkyColor

    public static func at(minute: Int, weather: Weather) -> SkyPalette {
        at(time: SkyTime(minute: minute), style: weather.style)
    }

    static func at(time: SkyTime, style: WeatherStyle) -> SkyPalette {
        let next = Self.keyframes.firstIndex { $0.minute > time.cycleMinute } ?? Self.keyframes.count - 1
        let a = Self.keyframes[next - 1], b = Self.keyframes[next]
        let t = (time.cycleMinute - a.minute) / (b.minute - a.minute)
        let sky = a.palette.mixed(with: b.palette, amount: t)
        let tint = style.mood.tint
        let color = SkyColor(hex: tint.night).mixed(with: SkyColor(hex: tint.day), amount: time.daylight)
        let weight = tint.weight + style.frame().dimming * 0.17
        // Seasonal warmth only touches the sunlit layers. Midnight stays a seamless loop.
        let warmth = (1 - time.season) * 0.06 * time.twilight
        let gold = SkyColor(hex: 0xffdcac)
        return SkyPalette(
            top: sky.top.mixed(with: color, amount: weight * 0.78),
            middle: sky.middle.mixed(with: color, amount: weight),
            bottom: sky.bottom.mixed(with: gold, amount: warmth).mixed(with: color, amount: weight * 0.62),
            glow: sky.glow.mixed(with: gold, amount: warmth).mixed(with: color, amount: weight * 0.68)
        )
    }

    private func mixed(with other: SkyPalette, amount: Double) -> SkyPalette {
        Self(top: top.mixed(with: other.top, amount: amount), middle: middle.mixed(with: other.middle, amount: amount),
             bottom: bottom.mixed(with: other.bottom, amount: amount), glow: glow.mixed(with: other.glow, amount: amount))
    }

    private static func colors(_ top: UInt32, _ middle: UInt32, _ bottom: UInt32, _ glow: UInt32) -> SkyPalette {
        Self(top: SkyColor(hex: top), middle: SkyColor(hex: middle), bottom: SkyColor(hex: bottom), glow: SkyColor(hex: glow))
    }

    private static let keyframes: [(minute: Double, palette: SkyPalette)] = [
        (0, colors(0x06152e, 0x14274a, 0x1c3858, 0x497299)),
        (300, colors(0x182a4f, 0x5a6688, 0xa3a8bd, 0xb9b0c1)),
        (390, colors(0x567db3, 0x9aabc9, 0xf1d5bd, 0xffdbc2)),
        (480, colors(0x3988ca, 0x97c5e9, 0xe5f1f9, 0xffefd4)),
        (720, colors(0x2e80c7, 0x8cbee5, 0xdceef9, 0xffffe3)),
        (960, colors(0x3d83bd, 0x9fbcdb, 0xf1ddc9, 0xffdfab)),
        (1080, colors(0x474f83, 0xaf7e8f, 0xe2ad8c, 0xffce96)),
        (1170, colors(0x162a52, 0x4a577d, 0x777891, 0x9f8293)),
        (1220, colors(0x0a1a37, 0x203658, 0x315273, 0x6390b1)),
        (1440, colors(0x06152e, 0x14274a, 0x1c3858, 0x497299))
    ]
}

private extension WeatherMood {
    var tint: (day: UInt32, night: UInt32, weight: Double) {
        switch self {
        case .clear: (0x8cc6e8, 0x173552, 0)
        case .overcast: (0x849dae, 0x233647, 0.46)
        case .wet: (0x63869f, 0x1b2c42, 0.49)
        case .ice: (0xa5c5d9, 0x365471, 0.61)
        case .mist: (0xc1d4dd, 0x455c6e, 0.66)
        case .dust: (0xc29461, 0x524134, 0.75)
        case .haze: (0xb2b4a9, 0x3a4147, 0.69)
        }
    }
}
