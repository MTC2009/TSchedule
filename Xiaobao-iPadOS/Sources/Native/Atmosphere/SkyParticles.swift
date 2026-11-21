import SwiftUI

enum SkyParticles {
    private struct Seed {
        let x: Double
        let y: Double
        let depth: Double
        let wave: Double
    }

    private enum Kind: Int, CaseIterable {
        case rain, snow, hail, dust

        var limit: Int {
            switch self {
            case .rain: 202
            case .snow: 168
            case .hail: 94
            case .dust: 146
            }
        }

        func strength(_ frame: WeatherFrame) -> Double {
            switch self {
            case .rain: frame.rain
            case .snow: frame.snow
            case .hail: frame.hail
            case .dust: frame.dust
            }
        }
    }

    // Stable, independent seed fields avoid random placement and allocation on every frame.
    private static let seeds: [[Seed]] = Kind.allCases.map { kind in
        var state = UInt64(9137 + 11939 * kind.rawValue)
        func next() -> Double {
            state = 2862933555777941757 &* state &+ 3037000493
            return Double((state >> 40) & 0xFFFFFF) / 16_777_216
        }
        return (0..<kind.limit).map { _ in Seed(x: next(), y: next(), depth: next(), wave: next()) }
    }

    static func draw(_ frame: WeatherFrame, motion: WeatherFrame, seconds: Double,
                     in context: GraphicsContext, size: CGSize, daylight: Double) {
        guard size.width > 0, size.height > 0 else { return }
        let area = max(0.45, min(1, sqrt(size.width * size.height / 570_000)))
        for kind in Kind.allCases {
            let strength = kind.strength(frame)
            guard strength > 0 else { continue }
            let count = min(kind.limit, max(3, Int(area * Double(kind.limit) * strength)))
            var far = Path()
            var near = Path()
            var glints = Path()
            for seed in seeds[kind.rawValue].prefix(count) {
                // Use stable velocities: multiplying elapsed time by a changing velocity teleports every drop.
                let point = position(kind: kind, seed: seed, strength: kind.strength(motion), wind: motion.wind, seconds: seconds, in: size)
                if seed.depth < 0.63 {
                    mark(kind, at: point, seed: seed, strength: strength, wind: frame.wind, body: &far, glints: &glints)
                } else {
                    mark(kind, at: point, seed: seed, strength: strength, wind: frame.wind, body: &near, glints: &glints)
                }
            }
            paint(kind, far: far, near: near, glints: glints, in: context, strength: strength, daylight: daylight)
        }
    }

    private static func position(kind: Kind, seed: Seed, strength: Double, wind: Double, seconds: Double, in size: CGSize) -> CGPoint {
        let speed: CGVector
        switch kind {
        case .rain:
            let fall = 200 + 370 * strength + seed.depth * 220
            speed = CGVector(dx: fall * wind * 1.36, dy: fall)
        case .snow:
            speed = CGVector(dx: wind * (27 + seed.depth * 165), dy: 17 + seed.depth * (28 + 61 * strength))
        case .hail:
            let fall = 330 + 170 * strength + seed.depth * 250
            speed = CGVector(dx: fall * wind * 0.7, dy: fall)
        case .dust:
            speed = CGVector(dx: 14 + wind * (57 + 197 * seed.depth), dy: 1 + 18 * seed.depth)
        }

        let flutter: Double = kind == .snow || kind == .dust ? sin(seconds * (0.52 + seed.wave) + seed.wave * 13) : 0
        // A padded torus wraps marks outside the visible frame, even in diagonal gusts.
        let padding = 72.0
        let width = size.width + padding * 2, height = size.height + padding * 2
        func wrap(_ value: Double, across length: Double) -> Double {
            let phase = value / length
            return (phase - floor(phase)) * length - padding
        }
        return CGPoint(x: wrap(seed.x * width + seconds * speed.dx + flutter * 14, across: width),
                       y: wrap(seed.y * height + seconds * speed.dy + flutter * 5, across: height))
    }

    private static func mark(_ kind: Kind, at point: CGPoint, seed: Seed, strength: Double, wind: Double,
                             body: inout Path, glints: inout Path) {
        switch kind {
        case .rain:
            let length = (8 + 25 * seed.depth) * (0.76 + 0.91 * strength)
            body.move(to: point)
            body.addLine(to: CGPoint(x: point.x + length * wind * 1.36, y: point.y + length))
        case .snow:
            let diameter = 0.8 + (0.7 + 5.5 * strength) * seed.depth
            body.addEllipse(in: CGRect(x: point.x, y: point.y, width: diameter, height: diameter * 0.94))
            if seed.depth > 0.82 {
                let d = diameter * 0.55
                glints.addEllipse(in: CGRect(x: point.x + d * 0.2, y: point.y + d * 0.2, width: d, height: d))
            }
        case .hail:
            let diameter = 1.8 + (2.5 + 2.5 * strength) * seed.depth
            let pellet = CGRect(x: point.x, y: point.y, width: diameter, height: diameter * 0.88)
            body.addRoundedRect(in: pellet, cornerSize: CGSize(width: diameter * 0.35, height: diameter * 0.35))
            let glint = diameter * 0.32
            glints.addEllipse(in: CGRect(x: point.x + diameter * 0.19, y: point.y + diameter * 0.12, width: glint, height: glint))
        case .dust:
            let width = 0.7 + (2 + 10.5 * abs(wind)) * seed.depth
            let height = 0.45 + 1.65 * seed.depth
            body.addEllipse(in: CGRect(x: point.x, y: point.y, width: width, height: height))
        }
    }

    private static func paint(_ kind: Kind, far: Path, near: Path, glints: Path, in context: GraphicsContext,
                              strength: Double, daylight: Double) {
        switch kind {
        case .rain:
            if daylight > 0.1 {
                context.stroke(near, with: .color(AtmosphereColors.waterShadow.opacity(daylight * (0.15 + strength * 0.31))), lineWidth: 1.9 + strength)
            }
            context.stroke(far, with: .color(AtmosphereColors.rain.opacity(0.30 + strength * 0.24)), lineWidth: 0.6 + 0.24 * strength)
            context.stroke(near, with: .color(AtmosphereColors.rain.opacity(0.49 + strength * 0.33)), lineWidth: 1.02 + 0.66 * strength)
        case .snow:
            context.fill(far, with: .color(AtmosphereColors.snow.opacity(0.53)))
            context.stroke(near, with: .color(AtmosphereColors.waterShadow.opacity(daylight * 0.19)), lineWidth: 0.75)
            context.fill(near, with: .color(AtmosphereColors.snow.opacity(0.70)))
            context.fill(glints, with: .color(AtmosphereColors.snow.opacity(0.84)))
        case .hail:
            context.fill(far, with: .color(AtmosphereColors.hail.opacity(0.70)))
            context.stroke(near, with: .color(AtmosphereColors.waterShadow.opacity(0.31)), lineWidth: 0.9)
            context.fill(near, with: .color(AtmosphereColors.hail.opacity(0.94)))
            context.fill(glints, with: .color(AtmosphereColors.snow.opacity(0.94)))
        case .dust:
            context.fill(far, with: .color(AtmosphereColors.dustShadow.opacity(0.32 + strength * 0.15)))
            context.fill(near, with: .color(AtmosphereColors.dust.opacity(0.57 + strength * 0.17)))
        }
    }
}
