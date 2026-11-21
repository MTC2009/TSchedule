import Foundation

/// A continuous visual clock in Shanghai time, independent from the schedule.
/// Seasonally shifts artwork around fixed anchors. This is not a sunrise/sunset calculator.
struct SkyTime: Equatable, Sendable {
    private static let visualAnchors: [Double] = [0, 390, 720, 1080, 1440]
    private let localAnchors: [Double]
    let cycleMinute: Double
    let season: Double

    init(minute: Int, on date: Date? = nil) {
        if let date {
            let calendar = SchoolClock.calendar
            let day = Double(calendar.ordinality(of: .day, in: .year, for: date) ?? 172)
            let year = Double(calendar.range(of: .day, in: .year, for: date)?.count ?? 365)
            season = cos(2 * .pi * (day - 172) / year)
            localAnchors = [0, 390 - 52 * season - 15, 720, 1080 + 66 * season - 12, 1440]
        } else {
            season = 0
            localAnchors = Self.visualAnchors
        }
        cycleMinute = Self.interpolate(Double(minute), from: localAnchors, to: Self.visualAnchors)
    }

    var phase: DayPhase { .at(minute: Int(min(cycleMinute, 1439))) }

    var daylight: Double {
        let rise = Self.eased((cycleMinute - 290) / 210)
        let set = Self.eased((1210 - cycleMinute) / 250)
        return rise * set
    }

    var twilight: Double {
        let dawn = 1 - Self.eased(abs(cycleMinute - 390) / 110)
        let sunset = 1 - Self.eased(abs(cycleMinute - 1075) / 140)
        return max(dawn, sunset)
    }

    func previewMinute(for phase: DayPhase) -> Int {
        let key: Double
        switch phase {
        case .dawn: key = 390
        case .day: key = 720
        case .sunset: key = 1080
        case .night: key = 1320
        }
        return Int(Self.interpolate(key, from: Self.visualAnchors, to: localAnchors).rounded())
    }

    private static func interpolate(_ value: Double, from: [Double], to: [Double]) -> Double {
        let value = max(0, min(1440, value))
        for index in 0..<(from.count - 1) where value <= from[index + 1] {
            let fraction = (value - from[index]) / (from[index + 1] - from[index])
            return to[index] + (to[index + 1] - to[index]) * fraction
        }
        return 1440
    }

    private static func eased(_ value: Double) -> Double {
        let t = max(0, min(1, value))
        return t * t * (3 - 2 * t)
    }
}
