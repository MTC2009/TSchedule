import SwiftUI

/// Art and contrast only. Semantic UI colors remain in the system design system.
enum AtmosphereColors {
    static let nightShading = SkyColor(hex: 0x031027).color
    static let darkReadability = SkyColor(hex: 0x091423).color
    static let lightReadability = SkyColor(hex: 0xf3f9fc).color

    static let rain = SkyColor(hex: 0xdceefa).color
    static let waterShadow = SkyColor(hex: 0x283e57).color
    static let snow = SkyColor(hex: 0xf4fbff).color
    static let hail = SkyColor(hex: 0xbfd8ed).color
    static let dust = SkyColor(hex: 0xf7c482).color
    static let dustShadow = SkyColor(hex: 0x574132).color
    static let lightning = SkyColor(hex: 0xd4dfff).color
    static let lanternLight = SkyColor(hex: 0xffb45c).color
    static let lanternShadow = SkyColor(hex: 0xbc412c).color
    static let festiveLight = SkyColor(hex: 0xffde9e).color

    static func veil(_ mood: WeatherMood, daylight: Double) -> Color {
        let tones: (day: UInt32, night: UInt32)
        switch mood {
        case .clear: tones = (0xe2edf5, 0x3a5679)
        case .overcast: tones = (0xd1e0ea, 0x3b4c63)
        case .wet: tones = (0xa8bfce, 0x354c63)
        case .ice: tones = (0xe2f3fa, 0x56728b)
        case .mist: tones = (0xeff5f6, 0x677f93)
        case .dust: tones = (0xdbaa75, 0x785034)
        case .haze: tones = (0xc5c5b9, 0x4f5250)
        }
        return SkyColor(hex: tones.night).mixed(with: SkyColor(hex: tones.day), amount: daylight).color
    }
}
