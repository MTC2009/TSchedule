import XCTest
@testable import XiaobaoCore

final class SkyPlaybackClockTests: XCTestCase {
    func testPausingAndResumingDoesNotAdvanceCloudsWhileHidden() {
        var clock = SkyPlaybackClock()
        clock.setRunning(true, at: 13)
        XCTAssertEqual(clock.elapsed(at: 17), 4)
        clock.setRunning(false, at: 17)
        XCTAssertEqual(clock.elapsed(at: 90), 4)
        clock.setRunning(true, at: 90)
        XCTAssertEqual(clock.elapsed(at: 93), 7)
    }

    func testRepeatedVisibilityAndUnsupportedTimestampsDoNotResetMotion() {
        var clock = SkyPlaybackClock()
        clock.setRunning(true, at: 20)
        clock.setRunning(true, at: 22)
        clock.setRunning(false, at: .nan)
        XCTAssertEqual(clock.elapsed(at: 23), 3)
        XCTAssertEqual(clock.elapsed(at: 19), 0)
        clock.setRunning(false, at: 25)
        clock.setRunning(false, at: 30)
        XCTAssertEqual(clock.elapsed(at: .infinity), 5)
    }
}
