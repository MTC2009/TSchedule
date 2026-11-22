import simd

/// Chooses authored three-dimensional scenery. A normal day has no extra GPU passes.
enum SkyDetails {
    static func scene(_ theme: Festival, aspect:Float, time:Float, motion:SeasonalMotion,moon:SIMD4<Float>? = nil) -> SeasonalScene? {
        guard theme != .none else { return nil }
        var s = SeasonalScene(aspect:aspect,t:time,motion:motion)
        switch theme {
        case .spring,.qixi,.midautumn,.christmasEve,.christmas: break
        case .lantern: s.foregroundReach=8.6
        default: s.foregroundReach = .greatestFiniteMagnitude
        }
        s.setting(theme)
        s.frameStudy(theme)
        switch theme {
        case .none: return nil
        case .midautumn, .christmas, .christmasEve:
            s.flightScene(theme,moon:moon ?? VolumetricSkyState.moon(at:1260,autumn:theme == .midautumn))
        case .springBegins, .springRain, .awakening, .springEquinox, .qingming, .grainRain: s.springStudy(theme)
        case .summerBegins, .grainBuds, .grainInEar, .summerSolstice, .lesserHeat, .greaterHeat: s.summerStudy(theme)
        case .autumnBegins, .endOfHeat, .whiteDew, .autumnEquinox, .coldDew, .frostDescent: s.autumnStudy(theme)
        case .winterBegins, .lightSnow, .heavySnow, .winterSolstice, .lesserCold, .greaterCold: s.winterStudy(theme)
        case .lunarEve, .spring, .lantern, .dragonBoat, .qixi, .doubleNinth, .halloween, .thanksgiving,
             .yearEve, .newyear: s.holiday(theme)
        }
        return s
    }
}
