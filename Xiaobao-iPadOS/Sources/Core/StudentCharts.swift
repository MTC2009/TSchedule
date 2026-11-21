import Foundation

struct AssessmentReading {
    let id, title: String
    let date: Date
    let percentage: Double?
}

struct AssessmentPoint: Identifiable {
    let id, title: String
    let day: Date
    let percentage: Double
    let segment: Int

    static func history(_ readings: [AssessmentReading]) -> [Self] {
        let days = Dictionary(grouping: readings) { SchoolClock.calendar.startOfDay(for: $0.date) }
        var points: [Self] = []
        var segment = 0
        for day in days.keys.sorted() {
            let entries = days[day]!.sorted { $0.id < $1.id }
            // Several results on a single date have no defined order.
            for item in entries {
                if entries.count > 1 { segment += 1 }
                guard let score = item.percentage, (0...100).contains(score) else { segment += 1; continue }
                points.append(Self(id: item.id, title: item.title, day: day, percentage: score, segment: segment))
            }
            if entries.count > 1 { segment += 1 }
        }
        return points
    }
}

struct AssessmentHistoryRange: Equatable {
    let start: Date
    let end: Date

    init?(start: Date, end: Date) {
        let startDay = SchoolClock.calendar.startOfDay(for: start)
        let endDay = SchoolClock.calendar.startOfDay(for: end)
        guard startDay <= endDay else { return nil }
        self.start = startDay
        self.end = endDay
    }

    func contains(_ point: AssessmentPoint) -> Bool {
        // Assessment points are normalized to the school's day, so both date pickers are inclusive.
        (start...end).contains(point.day)
    }
}

extension CourseReport {
    var assessmentHistory: [AssessmentPoint] {
        AssessmentPoint.history(assessments.map {
            AssessmentReading(id: $0.id, title: $0.title, date: $0.date, percentage: $0.percentage)
        })
    }
}

extension CampusGrade {
    var assessmentHistory: [AssessmentPoint] {
        AssessmentPoint.history(assessments.compactMap { item in
            guard let raw = item.date, let date = SchoolClock.dayDate(raw) ?? campusInstant(raw) else { return nil }
            return AssessmentReading(id: item.id, title: item.title, date: date,
                                     percentage: item.status == "graded" ? item.score?.percentage : nil)
        })
    }
}

struct AttendanceCourseRow: Identifiable {
    let id, name: String
    let counts: AttendanceCounts?
    let presentRate: Double?

    init(course: AttendanceCourseSummary) {
        id = course.id
        name = course.name
        counts = course.counts
        presentRate = course.counts.rate
    }

    init(id: String, name: String, summary: CampusCounts) {
        self.id = id
        self.name = name
        counts = Self.validatedCounts(summary)
        // Preserve the service's reported rate rather than filling a missing field.
        presentRate = (counts?.total ?? 0) > 0 ? summary.present_rate.flatMap { (0...1).contains($0) ? $0 : nil } : nil
    }

    private static func validatedCounts(_ summary: CampusCounts) -> AttendanceCounts? {
        // Subtract from the reported total to check agreement without overflowing on malformed data.
        var remaining = summary.total
        for count in [summary.present, summary.late, summary.early, summary.absent] {
            guard count >= 0, count <= remaining else { return nil }
            remaining -= count
        }
        guard remaining == 0 else { return nil }
        return AttendanceCounts(present: summary.present, late: summary.late, early: summary.early, absent: summary.absent)
    }
}

struct AttendanceComposition {
    struct Segment: Identifiable {
        let status: AttendanceStatus
        let fractionRange: Range<Double>
        let share: Double
        var id: AttendanceStatus { status }
        var midpoint: Double { (fractionRange.lowerBound + fractionRange.upperBound) / 2 }
    }

    let segments: [Segment]

    init(counts: AttendanceCounts) {
        let total = Double(counts.total)
        var preceding = 0
        segments = AttendanceStatus.allCases.compactMap { status in
            let count = counts[status]
            guard count > 0 else { return nil }
            let start = preceding
            preceding += count
            return Segment(status: status, fractionRange: (Double(start) / total)..<(Double(preceding) / total),
                           share: Double(count) / total)
        }
    }
}

struct AttendanceRingLayout {
    typealias Segment = AttendanceComposition.Segment
    let segments: [Segment]

    init(counts: AttendanceCounts) {
        segments = AttendanceComposition(counts: counts).segments
    }

    /// Angle zero is at the top and increases clockwise, as in the painted ring.
    func hit(at point: CGPoint, center: CGPoint, radius: CGFloat, hitWidth: CGFloat) -> (segment: Segment, turn: Double)? {
        let dx = Double(point.x - center.x), dy = Double(point.y - center.y)
        let distance = hypot(dx, dy)
        guard radius > 0, distance > 0, abs(distance - Double(radius)) <= Double(hitWidth / 2) else { return nil }
        let angle = atan2(dx, -dy) / (2 * .pi)
        let turn = angle < 0 ? (1 + angle).truncatingRemainder(dividingBy: 1) : angle
        return segments.first { $0.fractionRange.contains(turn) }.map { ($0, turn) }
    }

    static func direction(at turn: Double) -> (dx: CGFloat, dy: CGFloat) {
        let angle = turn * 2 * .pi
        return (CGFloat(sin(angle)), CGFloat(-cos(angle)))
    }
}
