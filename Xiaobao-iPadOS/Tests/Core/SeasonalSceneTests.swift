import XCTest
@testable import XiaobaoCore

final class SeasonalSceneTests:XCTestCase {
    func testCuesAreStableAcrossFrameSkipsButFreshAcrossVisitsAndLaunches() {
        let a=SeasonalMotion(seed:193),b=SeasonalMotion(seed:194)
        let first=(0..<24).map{a.sample(3,1,$0)}
        XCTAssertEqual(first,(0..<24).map{a.sample(3,1,$0)})
        XCTAssertNotEqual(first,(0..<24).map{a.sample(3,2,$0)})
        XCTAssertNotEqual(first,(0..<24).map{b.sample(3,1,$0)})
        XCTAssertTrue(first.allSatisfy{(0..<1).contains($0)})
    }
    func testIgnitionHasThreeLandingsBeforeItsSingleTurn() {
        var m=SeasonalMotion()
        XCTAssertFalse(m.touch(.water,scene:.halloween,time:0,point:.zero,chance:0))
        XCTAssertFalse(m.touch(.subject,scene:.halloween,time:0,point:.zero,chance:0,holding:true))
        XCTAssertTrue(m.touch(.subject,scene:.halloween,time:0,point:.zero,chance:1))
        XCTAssertFalse(m.touch(.subject,scene:.halloween,time:0.1,point:.zero,chance:0))
        for beat in 0..<3 {
            let start=Float(beat)*0.48
            XCTAssertEqual(m.haunt(start).rise,0,accuracy:0.0001)
            XCTAssertGreaterThan(m.haunt(start+0.24).rise,0.18)
            XCTAssertEqual(m.haunt(start+0.47).turn,0)
        }
        XCTAssertEqual(m.haunt(1.44).rise,0);XCTAssertEqual(m.haunt(1.865).turn,.pi,accuracy:0.003)
        XCTAssertEqual(m.haunt(2.31).turn,2 * .pi,accuracy:0.0001)
        XCTAssertEqual(m.haunt(6).fire,0)
        XCTAssertTrue(m.touch(.subject,scene:.halloween,time:6,point:.zero,chance:0))
    }
    func testWholeTermCatalogAndPublishedVariableDates() {
        XCTAssertEqual(Set(Festival.solarTerms).count,24)
        for y in SolarTermCalendar.firstYear..<(SolarTermCalendar.firstYear+SolarTermCalendar.days.count) {
            let all = (1...12).flatMap { m in (1...31).compactMap { SolarTermCalendar.scene(year:y,month:m,day:$0) } }
            XCTAssertEqual(all.count,24); XCTAssertEqual(Set(all),Set(Festival.solarTerms))
        }
        XCTAssertEqual(Festival.automatic(on:SchoolClock.date(2024,4,4)),.qingming)
        XCTAssertEqual(Festival.automatic(on:SchoolClock.date(2026,4,5)),.qingming)
        XCTAssertEqual(Festival.automatic(on:SchoolClock.date(2026,11,22)),.lightSnow)
        XCTAssertNil(SolarTermCalendar.scene(year:2300,month:11,day:22))
        for legacy in ["none","spring","christmas","newyear","midautumn"] {
            XCTAssertNotNil(try? JSONDecoder().decode(Festival.self,from:Data(("\""+legacy+"\"").utf8)))
        }
    }
    func testFestivalPrecedenceLeapMonthAndLastLunarDay() {
        XCTAssertEqual(Festival.automatic(on:SchoolClock.date(2025,1,28)),.lunarEve)
        XCTAssertEqual(Festival.automatic(on:SchoolClock.date(2024,2,9)),.lunarEve)
        XCTAssertEqual(Festival.automatic(on:SchoolClock.date(2026,11,26)),.thanksgiving)
        XCTAssertNotEqual(Festival.automatic(on:SchoolClock.date(2026,11,19)),.thanksgiving)
        XCTAssertNotEqual(Festival.automatic(on:SchoolClock.date(2009,6,27)),.dragonBoat) // leap fifth month
        XCTAssertEqual(Festival.automatic(on:SchoolClock.date(2026,3,3)),.lantern)
        XCTAssertEqual(Festival.automatic(on:SchoolClock.date(2026,6,19)),.dragonBoat)
        XCTAssertEqual(Festival.automatic(on:SchoolClock.date(2026,12,24)),.christmasEve)
        XCTAssertEqual(Festival.automatic(on:SchoolClock.date(2026,12,31)),.yearEve)
    }
    func testWaterHitAndBrushAreTransientAndDirectional() {
        var m=SeasonalMotion()
        let p=SIMD3<Float>(1.2,0.4,7.0)
        XCTAssertFalse(m.touch(.none,scene:.coldDew,time:2,point:p,chance:0))
        XCTAssertTrue(m.touch(.subject,scene:.coldDew,time:2,point:p,chance:0,holding:true))
        m.pull(-0.7); XCTAssertEqual(m.bend(3),-0.7); m.release(at:3)
        XCTAssertEqual(m.bend(3),-0.7); XCTAssertEqual(m.bend(8),0)
        XCTAssertTrue(m.touch(.water,scene:.autumnEquinox,time:5,point:p,chance:1))
        XCTAssertEqual(m.gesture?.point,p)
        XCTAssertEqual(m.lift(12),0)
    }
    func testFlightDirectionLandingAndGiftSeparation() throws {
        var m=SeasonalMotion()
        let rabbit:Festival = .midautumn, santa:Festival = .christmas
        let p=SIMD3<Float>(1.5,3,8)
        func pose(_ f:Festival,_ t:Float,_ fall:Float?=nil) throws -> SIMD3<Float> {
            try XCTUnwrap(SeasonalMotion.flight(f,time:t,landing:fall))
        }
        XCTAssertLessThan(try pose(rabbit,2).x,try pose(rabbit,1).x)
        XCTAssertGreaterThan(try pose(santa,2).x,try pose(santa,1).x)
        XCTAssertTrue(m.touch(.rabbit,scene:rabbit,time:1,point:p,chance:1))
        XCTAssertEqual(try pose(rabbit,1,m.landing),try pose(rabbit,1))
        XCTAssertGreaterThan(try pose(rabbit,1.8,m.landing).y,try pose(rabbit,1.8).y)
        XCTAssertNil(SeasonalMotion.flight(rabbit,time:4,landing:m.landing))
        XCTAssertEqual(try pose(rabbit,24,m.landing),try pose(rabbit,24))
        m=SeasonalMotion()
        XCTAssertFalse(m.touch(.sleigh,scene:santa,time:1,point:p,chance:0.98))
        XCTAssertNil(m.present)
        XCTAssertTrue(m.touch(.sleigh,scene:santa,time:2,point:p,chance:0.12))
        XCTAssertEqual(m.present?.origin,p); XCTAssertNil(m.landing)
        XCTAssertEqual(try pose(santa,3,m.landing),try pose(santa,3))
        XCTAssertFalse(m.touch(.sleigh,scene:santa,time:2.1,point:p,chance:0.1))
    }
}
