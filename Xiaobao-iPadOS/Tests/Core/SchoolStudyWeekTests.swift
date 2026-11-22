import Foundation
import XCTest
@testable import XiaobaoCore

final class SchoolStudyWeekTests: XCTestCase {
    private func calendar() throws -> PublishedSchoolCalendar {
        let root = (0..<4).reduce(URL(fileURLWithPath:#filePath)) { url, _ in url.deletingLastPathComponent() }
        return try JSONDecoder().decode(PublishedSchoolCalendar.self,from: Data(contentsOf:root.appendingPathComponent("xiaobao-backend/src/provider/academic-calendar-hs-2026-2027.json")))
    }
    /// Two different held-out academic weeks, unrelated enrollments and times, not a recorded roster.
    private func book(_ cal: PublishedSchoolCalendar, slots:[Int], lateChange:Bool = false, weeks:Int = 4, attends:Set<Int> = Set(2...5)) throws -> SchoolTimetable {
        let anchor = SchoolClock.date(2026,10,11)
        var result = SchoolTimetable(owner:UUID().uuidString,calendar:cal,now:anchor)
        for weekIndex in 0..<weeks {
            let week = TimetableWeek(containing: SchoolClock.calendar.date(byAdding:.day,value:7*weekIndex,to:anchor)!)
            var rows:[SchoolPortalWeek.Row]=[]
            for date in week.dates {
                guard let rotation=cal.day(on:date).teachingDay else {continue}
                let key=SchoolClock.key(date), weekday=SchoolClock.calendar.component(.weekday,from:date)
                func add(_ name:String, at start:Int, minutes:Int) {
                    rows.append(.init(id:key+name,name:name,start:key+"T"+SchoolClock.time(start)+":00+08:00",course:name,kind:.lesson,
                                      end:key+"T"+SchoolClock.time(start+minutes)+":00+08:00",room:nil,allDay:false))
                }
                add("Seminar \(rotation)",at:610,minutes:40)
                if !slots.isEmpty && attends.contains(weekday) { add("TSSA · Workshop",at:slots[weekIndex % slots.count] + (lateChange && weekIndex == 2 && weekday == 3 ? 9 : 0),minutes:43) }
            }
            try result.absorb(.init(week:week,rows:rows),calendar:cal)
        }
        return result
    }
    func testSparseEnrollmentAndThreeWeekPhasesDoNotBecomeADailySchedule() throws {
        let cal = try calendar()
        let roster = try book(cal, slots:[1160,1215,1116], weeks:6, attends:[4])
        func start(_ month: Int, _ day: Int) -> [Int] {
            let date = SchoolClock.date(2026,month,day)
            return (roster.day(on:date,calendar:cal)?.timeline?.blocks.compactMap(\.lesson) ?? [])
                .filter { $0.name.hasPrefix("TSSA") }.map { SchoolClock.minute(in:$0.start) }
        }
        XCTAssertEqual(start(11,25),[1160]); XCTAssertEqual(start(12,2),[1215]); XCTAssertEqual(start(12,9),[1116])
        XCTAssertEqual(start(11,23),[]); XCTAssertEqual(start(11,26),[])
        XCTAssertEqual(start(11,22),[1160], "The return night uses the incoming school week")
        let single = try book(cal,slots:[1135],weeks:1,attends:[4])
        let returning = try XCTUnwrap(single.day(on:SchoolClock.date(2026,11,22),calendar:cal))
        XCTAssertTrue(returning.studyTimePending, "Enrollment without an established time can label a return but must not choose a slot")
    }

    func testEveningAssignmentsArePersonalWeekBasedAndNeverClaimTheWholeSchoolDay() throws {
        let cal=try calendar(), alternating=try book(cal,slots:[1162,1214]), fixed=try book(cal,slots:[1121]), none=try book(cal,slots:[])
        func times(_ b:SchoolTimetable,_ date:Date)->[Int] { (b.day(on:date,calendar:cal)?.timeline?.blocks.compactMap(\.lesson) ?? []).filter{$0.name.hasPrefix("TSSA")}.map{SchoolClock.minute(in:$0.start)} }
        let sunday=SchoolClock.date(2026,11,8), monday=SchoolClock.date(2026,11,9), fri=SchoolClock.date(2026,11,13)
        XCTAssertEqual(times(alternating,monday),[1162]); XCTAssertEqual(times(alternating,sunday),[1162])
        XCTAssertEqual(times(alternating,SchoolClock.date(2026,11,15)),[], "Closed conference day is not a return")
        XCTAssertEqual(times(alternating,SchoolClock.date(2026,11,30)),[1214])
        XCTAssertEqual(times(fixed,monday),[1121]); XCTAssertEqual(times(none,monday),[]); XCTAssertEqual(times(none,sunday),[])
        XCTAssertEqual(times(alternating,fri),[]); XCTAssertEqual(times(fixed,fri),[])
        let returnDay=SchoolClock.date(2027,4,5)
        XCTAssertEqual(times(fixed,returnDay),[1121]); XCTAssertEqual(times(fixed,SchoolClock.date(2027,4,4)),[])
        XCTAssertEqual(times(alternating,returnDay),[], "Do not carry alternating phase across a holiday without fresh observations")
        XCTAssertFalse(try XCTUnwrap(fixed.day(on:returnDay,calendar:cal)).hasDatedException)
        let bare=PlannerSchoolDay(rotationDay:nil,hasTimetable:false,hasCalendar:false,entries:[])
        let overnight=bare.withCampusRoutine(on:returnDay,calendar:cal,showsBoardingRoutine:true)
        XCTAssertTrue(overnight.entries.contains{ $0.id == .routine(.secondStudy,anchor:returnDay) })
        XCTAssertTrue(bare.withCampusRoutine(on:returnDay,calendar:cal,showsBoardingRoutine:false).entries.isEmpty)
        let unreliable=try book(cal,slots:[1162,1214],lateChange:true)
        XCTAssertEqual(times(unreliable,monday),[])
        XCTAssertTrue(try XCTUnwrap(unreliable.day(on:monday,calendar:cal)).studyTimePending)
        XCTAssertEqual(times(unreliable,SchoolClock.date(2026,10,27)),[1171], "A dated time change wins")
        XCTAssertFalse(try XCTUnwrap(none.day(on:sunday,calendar:cal)).studyTimePending)
        var restored = try PropertyListDecoder().decode(SchoolTimetable.self,from:PropertyListEncoder().encode(alternating))
        restored.rebuildRotations(calendar:cal)
        XCTAssertEqual(times(restored,sunday),[1162])
        let forecastFire = SchoolClock.at(minute:1162,on:monday)
        XCTAssertFalse(restored.lessonReminders(now:sunday,lead:0,calendar:cal).contains { $0.fireDate == forecastFire })
        let observed = try XCTUnwrap(fixed.day(on:SchoolClock.date(2026,10,13),calendar:cal))
        let datedPlanner=PlannerSchoolDay.connected(on:SchoolClock.date(2026,10,13),schedule:observed.schedule,calendar:observed.events){$0}
        let withRoutine=datedPlanner.withCampusRoutine(on:SchoolClock.date(2026,10,13),calendar:cal,showsBoardingRoutine:true)
        XCTAssertFalse(withRoutine.entries.contains { $0.id == .routine(.firstStudy,anchor:SchoolClock.date(2026,10,13)) })
        XCTAssertFalse(withRoutine.entries.contains { $0.id == .routine(.secondStudy,anchor:SchoolClock.date(2026,10,13)) },
                       "This off-grid synthetic lesson overlaps both study periods")
        XCTAssertEqual(times(alternating,SchoolClock.date(2026,11,29)),[1214])
    }
}
