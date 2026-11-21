import Foundation

struct VolumetricSkyState: Equatable, Sendable {
    let time: SkyTime
    let style: WeatherStyle
    let festival: Festival

    /// Packed as float4s on both sides of the Swift/Metal boundary (176 bytes).
    func uniforms(width: Int, height: Int, steps: Int, elapsed: Double, moving: Bool) -> SkyUniforms {
        let sky = SkyPalette.at(time: time, style: style)
        let stable = style.frame()
        let weather = (moving || elapsed > 0) ? style.frame(at: elapsed) : stable
        let sunProgress = Float(max(0, min(1, (time.cycleMinute - 315) / 815)))
        let sunHeight = 0.19 + 0.72 * sin(.pi * sunProgress)
        let moonAngle = Float(time.cycleMinute / 1440 * .pi * 2)
        // These are art directions, not ephemerides. The two lights depend only on the civil sky time.
        // Cloud elapsed time never changes the lights. This also makes a held-clock test unambiguous.
        let sun = unit(SIMD3<Float>(-0.53 + 2.12 * sunProgress, sunHeight, 0.64))
        let moon = unit(SIMD3<Float>(0.28 + cos(moonAngle) * 0.066, 0.568 + sin(moonAngle) * 0.091, 1))
        let autumn = festival == .midautumn
        let moonColor = SkyColor(hex: autumn ? 0xffdc9f : 0xe8f4ff)
        let sunColor = sky.glow.mixed(with: SkyColor(hex: 0xfff2dc), amount: time.daylight * 0.68)
        let fill = SkyColor(hex: 0x9cbade).mixed(with: sky.middle, amount: 0.31 + 0.61 * weather.dimming)
        return SkyUniforms(
            viewport: SIMD4(Float(width) / Float(max(height, 1)), Float(steps), Float(width), Float(height)),
            clock: SIMD4(Float(time.daylight), Float(time.twilight), Float(elapsed), Float(0.93 + 0.32 * weather.cloudCover)),
            weather: SIMD4(Float(weather.cloudCover), Float(weather.dimming), Float(weather.veil), Float(weather.wind)),
            sun: SIMD4(sun.x, sun.y, sun.z, 0.91 + Float(time.twilight) * 0.24),
            moon: SIMD4(moon.x, moon.y, moon.z, autumn ? 0.037 : 0.023),
            skyTop: linear(sky.top), skyMiddle: linear(sky.middle), skyBottom: linear(sky.bottom),
            sunlight: linear(sunColor), moonlight: linear(moonColor), cloudAmbient: linear(fill)
        )
    }

    private func unit(_ v: SIMD3<Float>) -> SIMD3<Float> {
        v / sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
    }

    private func linear(_ c: SkyColor) -> SIMD4<Float> {
        func component(_ x: Double) -> Float {
            Float(x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4))
        }
        return SIMD4(component(c.red), component(c.green), component(c.blue), 0)
    }
}

struct SkyUniforms {
    var viewport: SIMD4<Float>
    var clock: SIMD4<Float>
    var weather: SIMD4<Float>
    var sun: SIMD4<Float>
    var moon: SIMD4<Float>
    var skyTop: SIMD4<Float>
    var skyMiddle: SIMD4<Float>
    var skyBottom: SIMD4<Float>
    var sunlight: SIMD4<Float>
    var moonlight: SIMD4<Float>
    var cloudAmbient: SIMD4<Float>
}
