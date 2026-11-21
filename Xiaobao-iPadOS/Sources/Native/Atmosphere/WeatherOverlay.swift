import SwiftUI

struct WeatherOverlay: View {
    let weather: Weather
    let style: WeatherStyle
    let daylight: Double
    let moving: Bool
    @State private var startedAt = Date()

    var body: some View {
        let still = style.frame()
        if moving && (still.hasParticles || style.upper != nil || style.lightning) {
            TimelineView(.animation(minimumInterval: 1 / 24)) { timeline in
                let seconds = max(0, timeline.date.timeIntervalSince(startedAt))
                layer(frame: style.frame(at: seconds), still: still, seconds: seconds)
            }
        } else {
            layer(frame: still, still: still, seconds: nil)
        }
    }

    private func layer(frame: WeatherFrame, still: WeatherFrame, seconds: Double?) -> some View {
        let tone = AtmosphereColors.veil(style.mood, daylight: daylight)
        return ZStack {
            if style.upper != nil {
                // Between-range veils breathe with precipitation without loading more cloud textures.
                AtmosphereColors.nightShading.opacity(max(0, frame.dimming - still.dimming) * 0.28)
            }
            veil(tone, frame: frame)
            if weather == .typhoon {
                LinearGradient(stops: [
                    .init(color: .clear, location: 0.12),
                    .init(color: tone.opacity(abs(frame.wind) * 0.29), location: 0.42),
                    .init(color: .clear, location: 0.63),
                    .init(color: tone.opacity(abs(frame.wind) * 0.19), location: 0.86)
                ], startPoint: .topTrailing, endPoint: .bottomLeading)
            }
            if weather == .freezingRain {
                LinearGradient(colors: [.clear, AtmosphereColors.snow.opacity(0.05), AtmosphereColors.snow.opacity(0.31)],
                               startPoint: .center, endPoint: .bottom)
            }
            if frame.hasParticles || style.lightning || weather == .freezingRain {
                Canvas { context, size in
                    SkyParticles.draw(frame, motion: still, seconds: seconds ?? 0, in: context, size: size, daylight: daylight)
                    if style.lightning { drawLightning(in: context, size: size, seconds: seconds) }
                    if weather == .freezingRain { drawIceRim(in: context, size: size) }
                }
            }
        }
    }

    private func veil(_ tone: Color, frame: WeatherFrame) -> some View {
        let strength = frame.veil
        let top: Double
        switch style.mood {
        case .mist: top = 0.64
        case .dust, .haze: top = 0.72
        default: top = 0.23
        }
        return LinearGradient(stops: [
            .init(color: tone.opacity(top * strength), location: 0),
            .init(color: tone.opacity((0.58 + 0.20 * top) * strength), location: 0.52),
            .init(color: tone.opacity(strength), location: 1)
        ], startPoint: .top, endPoint: .bottom)
    }

    private func drawLightning(in context: GraphicsContext, size: CGSize, seconds: Double?) {
        // Single low-contrast local branch: no full-screen flash, repeated bursts or popping.
        let glow = seconds.map { t in
            let progress = t.truncatingRemainder(dividingBy: 16)
            let distance = (progress - 2.2) / 0.7
            return 0.13 + 0.34 * exp(-distance * distance)
        } ?? 0.34
        func point(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: size.width * x, y: size.height * y) }
        var branch = Path()
        branch.move(to: point(0.88, 0.04))
        branch.addLines([point(0.91, 0.08), point(0.886, 0.12), point(0.933, 0.15), point(0.913, 0.207)])
        branch.move(to: point(0.886, 0.12))
        branch.addLines([point(0.855, 0.15), point(0.868, 0.186)])
        context.stroke(branch, with: .color(AtmosphereColors.lightning.opacity(glow * 0.28)), lineWidth: 4)
        context.stroke(branch, with: .color(AtmosphereColors.lightning.opacity(glow)), lineWidth: 1)
    }

    private func drawIceRim(in context: GraphicsContext, size: CGSize) {
        var crystals = Path()
        for index in 0..<30 {
            let spread = Double(index) / 29
            let x = size.width * (index.isMultiple(of: 2) ? spread * 0.44 : 1 - spread * 0.44)
            let y = size.height * (0.998 - 0.03 * abs(sin(Double(index) * 1.4)))
            let slit = 1.4 + abs(cos(Double(index) * 1.93)) * 5.3
            crystals.move(to: CGPoint(x: x - slit * 0.3, y: y + slit))
            crystals.addLine(to: CGPoint(x: x, y: y - slit))
            crystals.addLine(to: CGPoint(x: x + slit * 0.45, y: y + slit * 0.55))
            crystals.closeSubpath()
        }
        context.fill(crystals, with: .color(AtmosphereColors.snow.opacity(0.46)))
    }
}
