import XCTest
@testable import XiaobaoCore

@MainActor final class SchoolPortalTests: XCTestCase {
    private let a = String(repeating: "a", count: 64), b = String(repeating: "b", count: 64)
    private let day = SchoolClock.dayDate("2025-02-18")!
    private func bytes(_ object: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: object) }

    @MainActor private final class FixtureOwner {
        var value: String
        init(_ value: String) { self.value = value }
    }

    func testSharedSemesterSelectionAndManualSheetCacheRequireTheSameVerifiedOwner() async throws {
        let current = FixtureOwner(a)
        var calls: [SchoolPortalRead] = []
        let store = SchoolPortalStore(selected: true) { [self] read, _ in
            calls.append(read)
            let value: Any
            switch read {
            case .identity: return try bytes(["owner": current.value])
            case .terms: value = ["current":"spring", "terms":[["id":"spring","name":"Spring"],["id":"fall","name":"Fall"]]] as [String:Any]
            case .tasks: value = ["term":"Spring","rows":[]] as [String:Any]
            case .archivedTasks("fall", _): value = ["term":"Fall","rows":[]] as [String:Any]
            case .archivedGrades("fall"): value = ["term":"Fall","termID":"fall","courses":[],"gpa":2.5] as [String:Any]
            case .collection(.exams): value = [["id":"p","title":"Portfolio"]]
            default: throw SchoolPortalIssue.unavailable
            }
            return try bytes(["owner":current.value,"value":value])
        }
        await store.verify(); await store.loadTasks(); await store.loadTerms(); store.selectTerm("missing")
        XCTAssertNil(store.selectedTermID); XCTAssertFalse(calls.contains(.archivedGrades("fall")))
        store.selectTerm("fall"); XCTAssertNil(store.tasks); await store.loadTasks()
        XCTAssertEqual(store.tasks?.term, "Fall"); await store.loadGrades(); XCTAssertTrue(store.hasRecentGrades())
        XCTAssertFalse(store.hasRecentGrades(at: Date().addingTimeInterval(301)))
        store.selectTerm(nil); XCTAssertNil(store.grades); XCTAssertEqual(store.tasks?.term, "Spring")
        store.selectTerm("fall"); XCTAssertEqual(store.grades?.termID, "fall")
        await store.loadCollection(.exams); store.beginManualReview(); store.beginNavigation()
        XCTAssertNil(store.owner); XCTAssertNil(store.grades); XCTAssertTrue(store.collections.isEmpty)
        await store.verify(); XCTAssertEqual(store.grades?.termID, "fall"); XCTAssertEqual(store.collections[.exams]?.count,1)
        store.beginManualReview(); current.value = b; await store.verify()
        XCTAssertEqual(store.identityIssue, .changed); XCTAssertNil(store.grades); XCTAssertTrue(store.collections.isEmpty)
    }

    func testChangingTaskRowsMakesTheSameTermGradeOverviewStale() async throws {
        var title = "Lab preparation"
        let store = SchoolPortalStore(selected: true) { [self] read, _ in
            switch read {
            case .identity: return try bytes(["owner":a])
            case .grades: return try bytes(["owner":a,"value":["term":"Spring","termID":"s","courses":[],"gpa":3.0] as [String:Any]])
            case .tasks: return try bytes(["owner":a,"value":["term":"Spring","rows":[["id":"p","title":title,"status":"submitted"]]] as [String:Any]])
            default: throw SchoolPortalIssue.unavailable
            }
        }
        await store.verify(); await store.loadGrades(); await store.loadTasks()
        await store.loadTasks(force:true); XCTAssertTrue(store.hasRecentGrades())
        title = "Revised lab preparation"; await store.loadTasks(force:true)
        XCTAssertFalse(store.hasRecentGrades()); XCTAssertNotNil(store.grades)
    }

    func testLaunchRecoveryReadsOnlyIdentityAndWillNotAdoptAnotherStudent() async throws {
        let current = FixtureOwner(a)
        var reads: [SchoolPortalRead] = [], signIns = 0
        let store = SchoolPortalStore(selected:true) { [self] read,_ in
            reads.append(read); return try bytes(["owner": current.value])
        }
        let firstNavigation = store.navigationEpoch
        store.beginNavigation(); store.invalidate(.login)
        XCTAssertEqual(store.navigationEpoch, firstNavigation)
        await store.restoreLogin(for: a) { signIns += 1 }
        XCTAssertEqual(store.navigationEpoch, firstNavigation)
        XCTAssertEqual(store.owner, a); XCTAssertEqual(reads,[.identity]); XCTAssertEqual(signIns,1)
        store.invalidate(.network); XCTAssertNotEqual(store.navigationEpoch, firstNavigation)
        await store.restoreLogin(for: a) { signIns += 1 }
        XCTAssertEqual(signIns,1)
        store.invalidate(.login); current.value = b; await store.restoreLogin(for: a) { signIns += 1 }
        XCTAssertNil(store.owner); XCTAssertEqual(store.identityIssue,.changed); XCTAssertNil(store.grades)
    }

    private func attendanceReport(courses: [Any] = [], present: Int = 0) -> [String:Any] {
        ["from":"2025-02-01","to":"2025-06-30","termStart":"2025-02-01","termEnd":"2025-06-30",
         "counts":["present":present,"late":0,"early":0,"absent":0],"records":[],"recordTotal":0,"courses":courses]
    }

    func testAttendanceReadsOnlyTheVerifiedStudentAndReturnedCourse() async throws {
        let q = SchoolPortalAttendanceQuery()
        let course:[String:Any] = ["id":"ceramics","name":"Ceramics","counts":["present":2,"late":0,"early":0,"absent":0]]
        var calls:[SchoolPortalRead] = []
        let s = SchoolPortalStore(selected:true) { [self] op,expected in
            calls.append(op)
            if op == .identity { return try bytes(["owner":a]) }
            XCTAssertEqual(expected,a)
            if op == .attendance(q) { return try bytes(["owner":a,"value":attendanceReport(courses:[course],present:2)]) }
            return try bytes(["owner":a,"value":["records":[],"recordTotal":0]])
        }
        await s.loadAttendance(q); XCTAssertTrue(calls.isEmpty)
        await s.verify(); await s.loadAttendance(q); await s.loadAttendance(q)
        XCTAssertEqual(s.attendance?.counts.native.present,2); XCTAssertNil(s.grades)
        await s.loadAttendanceSubject("not-listed",page:1)
        XCTAssertEqual(calls,[.identity,.attendance(q)])
        await s.loadAttendanceSubject("ceramics",page:1)
        XCTAssertEqual(s.attendanceSubject?.recordTotal,0)
        s.suspend(); XCTAssertNil(s.attendance); XCTAssertNil(s.attendanceSubject); XCTAssertNil(s.owner)
    }

    func testAttendanceDoesNotPublishStaleFiltersOrTurnDeniedIntoEmpty() async throws {
        let first = SchoolPortalAttendanceQuery(), second = SchoolPortalAttendanceQuery(category:.activity)
        var late: CheckedContinuation<Data,Never>?
        var deny = false
        let s = SchoolPortalStore(selected:true) { [self] op,_ in
            if op == .identity { return try bytes(["owner":a]) }
            if op == .attendance(first) { return await withCheckedContinuation { late = $0 } }
            if deny { return try bytes(["error":"denied"]) }
            return try bytes(["owner":a,"value":attendanceReport()])
        }
        await s.verify()
        let old = Task { await s.loadAttendance(first) }
        while late == nil { await Task.yield() }
        await s.loadAttendance(second); XCTAssertEqual(s.attendance?.recordTotal,0)
        late?.resume(returning: try bytes(["owner":a,"value":attendanceReport(present:9)])); await old.value
        XCTAssertEqual(s.attendanceQuery,second); XCTAssertEqual(s.attendance?.counts.native.present,0)
        deny = true; await s.loadAttendance(second,force:true)
        XCTAssertNil(s.attendance); XCTAssertEqual(s.issues[.attendance(second)],.denied); XCTAssertEqual(s.owner,a)
    }

    func testReturningToAnInFlightAttendanceReportDoesNotLoseTheOnlyReply() async throws {
        let q = SchoolPortalAttendanceQuery()
        var continuation: CheckedContinuation<Data,Never>?
        var reads = 0
        let s = SchoolPortalStore(selected:true) { [self] op,_ in
            if op == .identity { return try bytes(["owner":a]) }
            reads += 1
            return await withCheckedContinuation { continuation = $0 }
        }
        await s.verify()
        let leaving = Task { await s.loadAttendance(q) }
        while continuation == nil { await Task.yield() }
        leaving.cancel()
        await s.loadAttendance(q) // The new view observes the existing request.
        continuation?.resume(returning: try bytes(["owner":a,"value":attendanceReport(present:4)]))
        await leaving.value
        XCTAssertEqual(reads,1); XCTAssertEqual(s.attendance?.counts.native.present,4)
        XCTAssertTrue(s.pending.isEmpty)

        continuation = nil
        let backgrounded = Task { await s.loadAttendance(q,force:true) }
        while continuation == nil { await Task.yield() }
        s.suspend()
        continuation?.resume(returning: try bytes(["owner":a,"value":attendanceReport(present:9)]))
        await backgrounded.value
        XCTAssertNil(s.owner); XCTAssertNil(s.attendance)
    }

    func testAttendanceRejectsMalformedCountsAndChangedOwnerWithoutGradeRecovery() async throws {
        let q = SchoolPortalAttendanceQuery()
        var changed = false
        let s = SchoolPortalStore(selected:true) { [self] op,_ in
            if op == .identity { return try bytes(["owner":a]) }
            return try bytes(["owner":changed ? b : a,"value":attendanceReport(present: changed ? 0 : -1)])
        }
        await s.verify(); await s.loadAttendance(q)
        XCTAssertEqual(s.issues[.attendance(q)],.format); XCTAssertNil(s.attendance)
        changed = true
        // Supply a well-formed reply so the distinct same-owner fence is exercised.
        await s.loadAttendance(q,force:true)
        XCTAssertEqual(s.identityIssue,.changed); XCTAssertNil(s.owner); XCTAssertNil(s.attendance)
    }

    func testWeekCoverageAndUnknownRotationDoNotInventSchoolBlocks() async throws {
        var reads: [SchoolPortalRead] = []
        let row: [String: Any] = ["id":"l1","kind":"lesson","course":"c1","name":"Materials",
            "start":"2025-02-18T00:10:00Z","end":"2025-02-18T01:00:00Z","allDay":false,"room":"Workshop"]
        let store = SchoolPortalStore(selected: true) { [self] request, _ in
            reads.append(request)
            return try bytes(request == .identity ? ["owner":a] : ["owner":a,"value":[row]])
        }
        await store.verify(); await store.loadWeek(day); await store.loadWeek(day)
        let week = try XCTUnwrap(store.week(on: day))
        let schedule = try XCTUnwrap(week.schedule(on: day))
        XCTAssertEqual(schedule.lessons.first?.room, "Workshop"); XCTAssertNil(schedule.day)
        let timeline = try XCTUnwrap(schedule.timeline { week.names[$0] ?? "" })
        XCTAssertEqual(timeline.blocks.count, 1); XCTAssertEqual(timeline.blocks[0].title, "Materials")
        XCTAssertEqual(week.schedule(on: SchoolClock.dayDate("2025-02-19")!)?.lessons.count, 0)
        XCTAssertNil(week.schedule(on: SchoolClock.dayDate("2025-02-25")!))
        XCTAssertNil(store.grades); XCTAssertEqual(reads, [.identity, .week("2025-02-16","2025-02-22")])
    }

    func testMalformedRangeOrDeniedRefreshDoesNotBecomeFreeDay() async throws {
        var response: Any = [["id":"r","course":"c","kind":"lesson","name":"Studio","start":"not a date","allDay":false]]
        var denied = false
        let store = SchoolPortalStore(selected: true) { [self] r, _ in
            if r == .identity { return try bytes(["owner":a]) }
            return try bytes(denied ? ["error":"denied"] : ["owner":a,"value":response])
        }
        await store.verify(); await store.loadWeek(day)
        XCTAssertNil(store.week(on: day)); XCTAssertEqual(store.issues[SchoolPortalStore.weekKey(day)], .format)
        response = []; await store.loadWeek(day)
        XCTAssertEqual(store.week(on: day)?.schedule(on: day)?.lessons.count, 0)
        denied = true; await store.loadWeek(day, force: true)
        XCTAssertNil(store.week(on: day)); XCTAssertEqual(store.issues[SchoolPortalStore.weekKey(day)], .denied)
    }

    func testLateTaskCannotReturnAfterLogoutAndAnotherLogin() async throws {
        var active = a, awaiting: CheckedContinuation<Data, Never>?
        let store = SchoolPortalStore(selected: true) { [self] req, _ in
            if req == .identity { return try bytes(["owner":active]) }
            return await withCheckedContinuation { awaiting = $0 }
        }
        await store.verify()
        let initial = store.epoch, old = Task { await store.loadTasks() }
        while awaiting == nil { await Task.yield() }
        store.invalidate(.login); active = b; await store.verify()
        awaiting?.resume(returning: try bytes(["owner":a,"value":["term":"old","rows":[]]]))
        await old.value
        XCTAssertEqual(store.owner, b); XCTAssertNotEqual(store.epoch, initial); XCTAssertNil(store.tasks)
        XCTAssertNil(store.issues[.tasks(includeScores:false)]); XCTAssertTrue(store.pending.isEmpty)
    }

    func testLoginExpiryStaysInRealModeAndForgetsGradesAndCourses() async throws {
        var expired = false, calls: [SchoolPortalRead] = []
        let store = SchoolPortalStore(selected: true) { [self] op, _ in
            calls.append(op)
            if op == .identity { return try bytes(["owner":a]) }
            if expired { return try bytes(["error":"expired"]) }
            return try bytes(["owner":a,"value":["term":"Studio term","termID":"S",
                "gpa":0,"courses":[["id":"c","subject":"5","cls":"7","name":"Type","type":1]]]])
        }
        await store.verify(); XCTAssertEqual(calls, [.identity]); XCTAssertNil(store.grades)
        await store.loadGrades(); let book = try XCTUnwrap(store.grades)
        XCTAssertEqual(book.gpa, 0); XCTAssertNotNil(store.trialInput(book))
        expired = true; await store.loadTasks()
        XCTAssertTrue(store.selected); XCTAssertNil(store.owner); XCTAssertNil(store.grades)
        XCTAssertNil(store.trialInput(book)); XCTAssertTrue(store.groups.isEmpty); XCTAssertEqual(store.identityIssue, .expired)
        await store.loadGrades(); XCTAssertEqual(calls, [.identity,.grades,.tasks(includeScores:true)])
    }

    func testIdentityMismatchErasesEveryModuleAndInvalidatesPlanOwner() async throws {
        var active = a
        let store = SchoolPortalStore(selected:true) { [self] r, _ in
            try bytes(r == .identity ? ["owner":active] : ["owner":active,"value":[]])
        }
        await store.verify(); let old = store.epoch; await store.loadWeek(day)
        active = b; await store.verify()
        XCTAssertNotEqual(store.epoch,old); XCTAssertNil(store.owner); XCTAssertEqual(store.identityIssue,.changed)
        XCTAssertNil(store.week(on: day)); XCTAssertTrue(store.selected)
        store.invalidate() // The student intentionally opens the official account screen.
        await store.verify(); XCTAssertEqual(store.owner,b)
    }

    func testOldGradeResponseCannotSurviveLogoutAndReloginToSameAccount() async throws {
        var waiting: CheckedContinuation<Data, Never>?
        let store = SchoolPortalStore(selected: true) { [self] op, _ in
            if op == .identity { return try bytes(["owner":a]) }
            return await withCheckedContinuation { waiting = $0 }
        }
        await store.verify()
        let stale = Task { await store.loadGrades() }
        while waiting == nil { await Task.yield() }
        store.invalidate(.login); await store.verify()
        waiting?.resume(returning: try bytes(["owner":a,"value":["term":"previous","termID":"old","gpa":0,"courses":[]]]))
        await stale.value
        XCTAssertNil(store.grades); XCTAssertTrue(store.pending.isEmpty); XCTAssertEqual(store.owner,a)
    }

    func testTaskGridKeepsUndatedPortalRowsInSourceOrderAfterSearch() throws {
        func row(_ id: String, _ title: String, _ published: String?, _ due: String) -> [String:Any] {
            var row = ["id":id, "title":title, "status":"submitted", "due":due]
            row["published"] = published
            return row
        }
        let late = "2025-03-11T08:00:00Z", early = "2025-03-09T08:00:00Z"
        let rows = [row("90","Atlas notes",nil,early), row("14","Atlas survey",early,late),
                    row("48","Palette",nil,late), row("2","Atlas inks",nil,late),
                    row("7","Atlas index",late,early)]
        let tasks = try JSONDecoder().decode(SchoolPortalTasks.self, from: bytes(["term":"Studio","rows":rows])).records
        let filtered = TaskFilters(query:"Atlas")
        let ids = filtered.results(in:tasks,at:day,completed:[],preservingUndatedSourceOrder:true).map(\.id)
        XCTAssertEqual(ids,["7","14","90","2"])
        let undated = tasks.filter { $0.publishedAt == nil }
        XCTAssertEqual(filtered.results(in:undated,at:day,completed:[],preservingUndatedSourceOrder:true).map(\.id),["90","2"])
        // Demo/legacy sources without a portal list keep the deterministic ID fallback.
        XCTAssertEqual(filtered.results(in:undated,at:day,completed:[]).map(\.id),["2","90"])
    }

    func testReleasedTaskMarkReachesTheExistingCardAndNonGradedMarksStayHidden() throws {
        let zero: [String:Any] = ["type":"numeric","earned":0,"possible":16]
        let level: [String:Any] = ["type":"letter","value":"Pass"]
        func row(_ id: String, _ grading: String, _ mark: Any) -> [String:Any] {
            ["id":id,"title":"Colour study","status":"submitted","grading":grading,"score":mark]
        }
        let data = try bytes(["term":"Studio","rows":[row("a","graded",zero),row("b","graded",level),
            row("c","graded_unpublished",zero),row("d","graded",NSNull())]])
        let cards = try JSONDecoder().decode(SchoolPortalTasks.self, from: data).records
        XCTAssertEqual(cards[0].mark,.numeric(earned:0,possible:16))
        XCTAssertEqual(cards[1].mark,.letter("Pass"))
        XCTAssertNil(cards[2].mark); XCTAssertNil(cards[3].mark)
    }

    func testTaskScoreConsentIsLazyScopedAndNotAnOverviewAvailabilityFlag() async throws {
        var calls: [SchoolPortalRead] = []
        let store = SchoolPortalStore(selected:true) { [self] op, _ in
            calls.append(op)
            if op == .identity { return try bytes(["owner":a]) }
            // A temporarily unavailable GPA must not defeat local consent for a
            // result the independent student task list itself publishes.
            if op == .grades { return try bytes(["error":"network"]) }
            guard case .tasks(let includeScores) = op else { throw SchoolPortalIssue.format }
            var row: [String:Any] = ["id":"pattern","title":"Pattern","status":"submitted","grading":"graded"]
            if includeScores { row["score"] = ["type":"letter","value":"P"] }
            return try bytes(["owner":a,"value":["term":"Studio","rows":[row]]])
        }
        await store.loadGrades(); XCTAssertFalse(store.allowsTaskScores)
        await store.verify(); await store.loadTasks(); XCTAssertNil(store.tasks?.records.first?.mark)
        await store.loadGrades(); XCTAssertTrue(store.allowsTaskScores); XCTAssertNil(store.tasks)
        XCTAssertEqual(calls,[.identity,.tasks(includeScores:false),.grades])
        await store.loadTasks(); await store.loadTasks()
        XCTAssertEqual(store.tasks?.records.first?.mark,.letter("P")); XCTAssertEqual(calls.last,.tasks(includeScores:true))
        XCTAssertEqual(calls.count,4)
        store.invalidate(.login); await store.verify(); await store.loadTasks()
        XCTAssertFalse(store.allowsTaskScores); XCTAssertNil(store.tasks?.records.first?.mark)
        XCTAssertEqual(calls.last,.tasks(includeScores:false))
    }

    func testPreConsentReplyCannotOverwriteAuthorizedCardsAndUnexpectedMarksAreRejected() async throws {
        var waiting: CheckedContinuation<Data,Never>?
        let scored = try bytes(["owner":a,"value":["term":"Studio","rows":[
            ["id":"tile","title":"Tile","status":"submitted","grading":"graded","score":["type":"letter","value":"P"]]]]])
        let store = SchoolPortalStore(selected:true) { [self] op, _ in
            if op == .identity { return try bytes(["owner":a]) }
            if op == .grades { return try bytes(["owner":a,"value":["term":"Studio","termID":"4","courses":[]]]) }
            if op == .tasks(includeScores:false) { return await withCheckedContinuation { waiting = $0 } }
            return scored
        }
        await store.verify()
        let plain = Task { await store.loadTasks() }
        while waiting == nil { await Task.yield() }
        await store.loadGrades(); await store.loadTasks()
        waiting?.resume(returning:try bytes(["owner":a,"value":["term":"Old","rows":[]]])); await plain.value
        XCTAssertEqual(store.tasks?.records.first?.mark,.letter("P"))
        let untrusted = SchoolPortalStore(selected:true) { [self] op, _ in
            if op == .identity { return try bytes(["owner":a]) }; return scored
        }
        await untrusted.verify(); await untrusted.loadTasks()
        XCTAssertNil(untrusted.tasks); XCTAssertEqual(untrusted.issues[untrusted.taskRead],.format)
    }

    func testPublishedWeightScopeAndUnknownSubmissionSurviveNativeProjection() throws {
        let raw = try bytes(["term":"T","termID":"term","gpa":NSNull(),"courses":[
            ["id":"c","name":"Ceramics","type":1,"subject":"7","cls":"2",
             "score":["type":"numeric","earned":58,"possible":60]]]])
        let book = try JSONDecoder().decode(SchoolPortalGrades.self, from: raw)
        let group = SchoolPortalGrades.Group(id:"0.1",title:"Portfolio / Firing",nested:true,weight:0.25,mark:nil,
            items:[.init(id:"a",title:"Glaze",status:"graded",date:"2025-02-18T08:00:00Z",feedback:nil,
                         score:.init(type:"numeric",earned:0,possible:5,value:nil))])
        let projection = book.courseDetail(book.courses[0], groups:[group])
        guard case .group(_, let weight, _, let rows) = projection.rows.first else { return XCTFail("Expected a real group") }
        XCTAssertEqual(weight?.scope,.group); XCTAssertEqual(weight?.fraction,0.25); XCTAssertNil(rows[0].weight)
        XCTAssertEqual(rows[0].percentage,0); XCTAssertEqual(projection.history().count,1)
        let task = SchoolPortalTasks(term:"T",rows:[.init(id:"t",title:"Studio notes",status:"unavailable",
            due:nil,published:nil,course:nil,courseName:nil,kind:nil,grading:nil,score:nil)]).records[0]
        XCTAssertEqual(task.submission(at:day,locallyCompleted:false),.unavailable)
        XCTAssertFalse(task.permitsLocalCompletion); XCTAssertNil(task.mark)
    }
}

extension SchoolPortalTests {
    func testPortalLabelsDoNotPassThroughTheAppVocabulary() throws {
        let data = try bytes(["term":"档案馆", "rows":[["id":"w","title":"开卷 / Archive","course":"s","courseName":"设置",
                            "kind":"reading","status":"pending"]]] as [String: Any])
        let tasks = try JSONDecoder().decode(SchoolPortalTasks.self, from: data)
        let record = try XCTUnwrap(tasks.records.first)
        XCTAssertEqual(tasks.displayTerm, "档案馆")
        XCTAssertEqual(record.title, "开卷 / Archive")
        XCTAssertEqual(record.courseName, "设置")
        XCTAssertEqual(record.workTypeLabel, "reading")
        XCTAssertEqual(TaskFilters.workTypes(in: [record]).first?.title, "reading")
        let supplied = SchoolPortalTerms.Term(id: "a", name: "期末 / Finals")
        XCTAssertEqual(supplied.displayName, supplied.name)
        let malformed = SchoolPortalTerms.Term(id: "b", name: "Archive", year: .max, semester: 2)
        XCTAssertEqual(malformed.displayName, "Archive")
    }
}
