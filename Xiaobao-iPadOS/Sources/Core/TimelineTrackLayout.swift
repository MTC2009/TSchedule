import Foundation

/// A single strip: every occupied minute has the same width, but every pair
/// of tiles gets the same visual separator. Drawing and scrubbing share the map.
struct TimelineTrackLayout {
    struct Tile: Identifiable {
        let block: LessonTimeline.Block
        let points: ClosedRange<Double>
        var id: LessonTimeline.Block.ID { block.id }
        var width: Double { points.upperBound - points.lowerBound }
        var center: Double { points.lowerBound + width / 2 }
    }

    private struct Section {
        let minutes, points: ClosedRange<Double>
    }
    let tiles: [Tile]
    private let sections: [Section]

    init(timeline: LessonTimeline, bounds: ClosedRange<Int>, width: Double) {
        let size = max(0, width)
        let domain = Double(bounds.lowerBound)...Double(bounds.upperBound)
        let blocks = timeline.blocks
        let times = blocks.map { timeline.minute(of: $0.start)...timeline.minute(of: $0.end) }
        let neighbors = zip(times, times.dropFirst())
        guard let first = times.first, let last = times.last,
              neighbors.allSatisfy({ $0.upperBound <= $1.lowerBound }) else {
            // Actual lessons may overlap. Preserve their common clock rather than
            // serializing them and making two simultaneous minutes look different.
            let points = 0.0...size
            sections = [Section(minutes: domain, points: points)]
            tiles = zip(blocks, times).map { block, time in
                let left = Self.convert(time.lowerBound, from: domain, to: points)
                let right = Self.convert(time.upperBound, from: domain, to: points)
                return Tile(block: block, points: left...right)
            }
            return
        }

        let seams = Double(blocks.count - 1)
        // On compact widths reserve at least three quarters for the time spans themselves.
        let gutter = seams > 0 ? min(6, size / (4 * seams)) : 0
        let breakMinutes = neighbors.reduce(0.0) { $0 + ($1.1.lowerBound - $1.0.upperBound) }
        let scaledMinutes = domain.upperBound - domain.lowerBound - breakMinutes
        let scale = scaledMinutes > 0 ? (size - seams * gutter) / scaledMinutes : 0

        var parts: [Section] = [], placed: [Tile] = []
        var x = 0.0
        @discardableResult func append(_ time: ClosedRange<Double>, width: Double) -> ClosedRange<Double> {
            let points = x...min(size, x + width)
            parts.append(Section(minutes: time, points: points))
            x = points.upperBound
            return points
        }
        if first.lowerBound > domain.lowerBound {
            append(domain.lowerBound...first.lowerBound, width: (first.lowerBound - domain.lowerBound) * scale)
        }
        for (index, time) in times.enumerated() {
            if index > 0 {
                // For a real recess the gutter maps to its actual minutes. At touching
                // boundaries the entire gutter selects the single shared clock instant.
                append(times[index - 1].upperBound...time.lowerBound, width: gutter)
            }
            let points = append(time, width: (time.upperBound - time.lowerBound) * scale)
            placed.append(Tile(block: blocks[index], points: points))
        }
        if last.upperBound < domain.upperBound {
            append(last.upperBound...domain.upperBound, width: size - x)
        }
        sections = parts
        tiles = placed
    }

    /// End-exclusive lookup puts the pointer on the new block at a shared boundary.
    func position(at minute: Double) -> Double {
        guard let part = sections.first(where: { minute < $0.minutes.upperBound })
        else { return sections.last?.points.upperBound ?? 0 }
        return Self.convert(minute, from: part.minutes, to: part.points)
    }

    func minute(at position: Double) -> Double {
        guard let part = sections.first(where: { position < $0.points.upperBound })
        else { return sections.last?.minutes.upperBound ?? 0 }
        return Self.convert(position, from: part.points, to: part.minutes)
    }

    private static func convert(_ value: Double, from a: ClosedRange<Double>, to b: ClosedRange<Double>) -> Double {
        guard a.upperBound > a.lowerBound else { return b.lowerBound }
        let fraction = min(1, max(0, (value - a.lowerBound) / (a.upperBound - a.lowerBound)))
        return b.lowerBound + fraction * (b.upperBound - b.lowerBound)
    }
}
