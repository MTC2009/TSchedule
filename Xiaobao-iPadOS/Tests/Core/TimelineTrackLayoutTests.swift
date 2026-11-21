import XCTest
@testable import XiaobaoCore

final class TimelineTrackLayoutTests: XCTestCase {
    private let date = SchoolClock.date(2028, 3, 7)
    private func period(_ id: String, _ start: Int, _ end: Int) -> LessonTimeline.Period {
        .init(id: id, name: id, shortName: id, room: nil,
              start: SchoolClock.at(minute: start, on: date), end: SchoolClock.at(minute: end, on: date))
    }

    func testEqualSeparatorsForGapsAndTouchingIntervalsWithoutFlatteningDuration() throws {
        let plan = try XCTUnwrap(LessonTimeline(on: date, periods: [
            period("a", 501, 531), period("b", 559, 604), period("c", 604, 664), period("d", 681, 696)
        ]))
        let bounds = try XCTUnwrap(plan.bounds)
        for width in [14.0, 157, 436, 901] {
            let layout = TimelineTrackLayout(timeline: plan, bounds: bounds, width: width)
            let t = layout.tiles
            XCTAssertEqual(t.count, 4)
            let gaps = zip(t, t.dropFirst()).map { $1.points.lowerBound - $0.points.upperBound }
            XCTAssertGreaterThan(gaps[0], 0)
            for g in gaps { XCTAssertEqual(g, min(6, width/12), accuracy: 0.000001) }
            XCTAssertEqual(t[1].width/t[0].width, 1.5, accuracy: 0.000001)
            XCTAssertEqual(t[2].width/t[0].width, 2, accuracy: 0.000001)
            XCTAssertEqual(t[3].width/t[0].width, 0.5, accuracy: 0.000001)
            XCTAssertEqual(layout.minute(at: (t[0].points.upperBound + t[1].points.lowerBound)/2), 545, accuracy: 0.000001)
            XCTAssertEqual(layout.minute(at: (t[1].points.upperBound + t[2].points.lowerBound)/2), 604, accuracy: 0.000001)
            XCTAssertEqual(layout.position(at: 604), t[2].points.lowerBound, accuracy: 0.000001)
            XCTAssertEqual(layout.position(at: 634), t[2].center, accuracy: 0.000001)
            for m in bounds {
                XCTAssertEqual(layout.minute(at: layout.position(at: Double(m))), Double(m), accuracy: 0.000001)
            }
            XCTAssertEqual(layout.minute(at: -20), Double(bounds.lowerBound))
            XCTAssertEqual(layout.minute(at: width+20), Double(bounds.upperBound))
        }
    }

    func testPublishedOverlapsKeepTheSameCoordinateForSimultaneousMinutes() throws {
        let timeline = try XCTUnwrap(LessonTimeline(on: date, periods: [period("long", 547, 612), period("short", 587, 599)]))
        let layout = TimelineTrackLayout(timeline: timeline, bounds: try XCTUnwrap(timeline.bounds), width: 270)
        let p = layout.position(at: 594)
        XCTAssertTrue(layout.tiles.allSatisfy { $0.points.contains(p) })
        XCTAssertEqual(layout.minute(at: p), 594, accuracy: 0.000001)
    }
}
