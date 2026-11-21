import XCTest
@testable import XiaobaoCore

@MainActor final class SchoolPortalAccessTests: XCTestCase {
    @MainActor private final class Fixture {
        let original = String(repeating: "c", count: 64), other = String(repeating: "d", count: 64)
        var switched = false, identityIssue: SchoolPortalIssue?, gradeIssue: SchoolPortalIssue?
        var value = 2.1, entries = 0, reads: [SchoolPortalRead] = []
        lazy var store = SchoolPortalStore(selected: true) { [unowned self] op, expected in
            self.reads.append(op)
            let owner = self.switched ? self.other : self.original
            let reply: [String: Any]
            if op == .identity {
                if let issue = self.identityIssue { throw issue }
                reply = ["owner":owner]
            } else {
                XCTAssertEqual(op, .grades); XCTAssertEqual(expected, self.original)
                if let issue = self.gradeIssue { throw issue }
                reply = ["owner":owner,"value":["term":"Winter","termID":"w","gpa":self.value,"courses":[]]]
            }
            return try JSONSerialization.data(withJSONObject: reply)
        }
        @MainActor func visit(_ enter: @MainActor () async throws -> Void = {}) async {
            await store.openGrades { self.entries += 1; try await enter() }
        }
    }

    func testReadinessCannotCertifyExpiry() {
        let origin = SchoolPortalPage.origin.absoluteString
        func issue(_ url: String?, foreground: Bool = true, loading: Bool = false) -> SchoolPortalIssue? {
            SchoolPortalPage.issue(at: url.flatMap(URL.init(string:)), foreground: foreground, loading: loading)
        }
        XCTAssertNil(issue(origin + "/Home/Index#!/student"))
        XCTAssertEqual(issue(origin + "/Home", foreground: false), .notReady)
        XCTAssertEqual(issue(origin + "/Home", loading: true), .notReady)
        XCTAssertEqual(issue(origin + "/", loading: true), .notReady)
        XCTAssertEqual(issue(nil), .notReady); XCTAssertEqual(issue("about:blank"), .notReady)
        XCTAssertEqual(issue(origin + "/"), .login); XCTAssertEqual(issue(origin + "/Account/Login"), .login)
        for path in [origin + "/HomeElse", origin + ":444/Home", "https://outside.invalid/Home",
                     "https://user@tsinglanstudent.schoolis.cn/Home", "http://tsinglanstudent.schoolis.cn/Home"] {
            XCTAssertEqual(issue(path), .unavailable)
        }
    }

    func testValidVisitDoesNotReenterAndConfirmedExpiryReadsNewGradesOnce() async {
        let f = Fixture(), s = f.store
        await s.verify(); await f.visit()
        XCTAssertEqual(f.entries, 0); XCTAssertEqual(s.grades?.gpa, 2.1)
        f.gradeIssue = .expired
        await f.visit {
            XCTAssertNil(s.grades); XCTAssertNil(s.owner); XCTAssertTrue(s.isRecoveringGrades)
            f.gradeIssue = nil; f.value = 3.2
        }
        XCTAssertEqual(f.entries, 1); XCTAssertEqual(s.grades?.gpa, 3.2); XCTAssertEqual(s.owner, f.original)
        XCTAssertEqual(f.reads, [.identity,.grades,.grades,.identity,.grades]); XCTAssertFalse(s.isRecoveringGrades)
    }

    func testExpiredIdentityWaitsForVisitEvenAfterBackgroundOrDocumentLoad() async {
        for navigate in [false, true] {
            let f = Fixture(), s = f.store
            await s.verify()
            if navigate { s.beginNavigation() } else { s.suspend() }
            XCTAssertEqual(s.identityIssue, .notReady); XCTAssertNil(s.owner)
            f.identityIssue = .expired; await s.verify()
            XCTAssertEqual(s.identityIssue, .expired)
            await s.verify(); XCTAssertEqual(f.reads, [.identity,.identity])
            XCTAssertNil(s.grades); XCTAssertEqual(f.entries, 0)
            f.identityIssue = nil; await f.visit()
            XCTAssertEqual(f.entries, 1); XCTAssertEqual(s.grades?.gpa, 2.1)
        }
    }

    func testNonAuthenticationFailuresNeverInitiateAnEntry() async {
        for issue in [SchoolPortalIssue.notReady, .network, .denied, .format, .unavailable, .term, .changed, .login] {
            let f = Fixture(); await f.store.verify(); f.gradeIssue = issue
            await f.visit(); XCTAssertEqual(f.entries, 0, issue.rawValue); XCTAssertNil(f.store.grades)
        }
        let fresh = Fixture(); fresh.identityIssue = .expired
        await fresh.store.verify(); await fresh.visit()
        XCTAssertEqual(fresh.store.identityIssue, .login); XCTAssertEqual(fresh.entries, 0)
        let signedOut = Fixture(); await signedOut.store.verify(); signedOut.store.invalidate(.login)
        await signedOut.visit(); XCTAssertEqual(signedOut.entries, 0); XCTAssertEqual(signedOut.reads, [.identity])
    }

    func testRejectedEntryAndChangedStudentCannotRetryOrDisplayGrades() async {
        for outcome in [SchoolPortalIssue.login, .expired, .changed] {
            let f = Fixture(), s = f.store
            await s.verify(); f.gradeIssue = .expired
            await f.visit {
                if outcome == .login { throw outcome }
                if outcome == .expired { f.identityIssue = outcome }
                if outcome == .changed { f.switched = true }
            }
            await f.visit()
            XCTAssertEqual(f.entries, 1); XCTAssertNil(s.owner); XCTAssertNil(s.grades)
            XCTAssertEqual(s.identityIssue, outcome == .changed ? .changed : .login)
            XCTAssertEqual(f.reads.filter { $0 == .grades }.count, 1)
        }
    }

    func testSecondExpiryDuringFreshGradeReadCannotLoop() async {
        let f = Fixture(); await f.store.verify(); f.gradeIssue = .expired
        await f.visit(); await f.visit()
        XCTAssertEqual(f.entries, 1); XCTAssertEqual(f.reads, [.identity,.grades,.identity,.grades])
        XCTAssertEqual(f.store.identityIssue, .login); XCTAssertNil(f.store.grades)
    }

    func testOfflineIdentityCheckErasesScoresWithoutMisidentifyingTheNextStudent() async {
        let f = Fixture(), s = f.store
        await s.verify(); await f.visit(); f.identityIssue = .network; await s.verify()
        XCTAssertEqual(s.identityIssue, .network); XCTAssertNil(s.owner); XCTAssertNil(s.grades)
        s.suspend(); f.switched = true; f.identityIssue = nil
        await s.verify(); await f.visit()
        XCTAssertEqual(s.identityIssue, .changed); XCTAssertNil(s.owner); XCTAssertNil(s.grades)
        XCTAssertEqual(f.entries, 0)
    }

    func testInvalidIdentityIsNotAnExpiredSession() async {
        let s = SchoolPortalStore(selected: true) { _,_ in Data(#"{"owner":"-"}"#.utf8) }
        await s.verify()
        await s.openGrades { XCTFail("Malformed identity must not launch a navigation") }
        XCTAssertEqual(s.identityIssue,.format); XCTAssertNil(s.owner); XCTAssertNil(s.grades)
    }

    func testNewSignInAfterBothSessionAndHomeRejectUsesVerifiedStudentAndFreshRead() async {
        for homeRedirects in [false,true] {
            let f = Fixture(), s = f.store
            await s.verify(); await f.visit(); f.gradeIssue = .expired
            var submits = 0
            await s.openGrades(boundOwner:f.original, signIn: { expected in
                XCTAssertNil(s.owner); XCTAssertNil(s.grades); XCTAssertEqual(expected,f.original)
                submits += 1; f.identityIssue = nil; f.gradeIssue = nil; f.value = 3.7
            }) {
                if homeRedirects { throw SchoolPortalIssue.login }
                f.identityIssue = .expired
            }
            XCTAssertEqual(submits,1); XCTAssertEqual(s.owner,f.original); XCTAssertEqual(s.grades?.gpa,3.7)
        }
    }

    func testNeverSupplyACredentialForAnotherOwnerOrInteractiveChallenge() async {
        for (issue, mismatch) in [(SchoolPortalIssue.network,false),(.interaction,false),(.denied,false),(.login,true)] {
            let f = Fixture(); await f.store.verify(); f.gradeIssue = .expired
            await f.store.openGrades(boundOwner:mismatch ? f.other : f.original,signIn:{_ in XCTFail("Unexpected credential use")}) {
                throw issue
            }
            XCTAssertNil(f.store.owner); XCTAssertNil(f.store.grades)
        }
    }

    func testChangedOwnerAfterSuccessfulSignInDoesNotReadGrades() async {
        let f = Fixture(); await f.store.verify(); f.gradeIssue = .expired
        await f.store.openGrades(boundOwner:f.original,signIn:{ _ in f.switched = true; f.gradeIssue = nil }) {
            throw SchoolPortalIssue.login
        }
        XCTAssertEqual(f.store.identityIssue,.changed); XCTAssertNil(f.store.grades)
        XCTAssertEqual(f.reads,[.identity,.grades,.identity])
    }

    func testColdBindingIsNotAuthorizationAndCanSignInOnlyOnAnExplicitBoundVisit() async {
        let f = Fixture(), s = f.store
        s.rememberComparison(f.original); XCTAssertNil(s.owner); XCTAssertNil(s.grades)
        s.invalidate(.login); await f.visit(); XCTAssertTrue(f.reads.isEmpty)
        var submits = 0
        await s.openGrades(boundOwner:f.original, signIn:{ owner in submits += 1; XCTAssertEqual(owner,f.original) }) {
            XCTFail("Known login page must not be treated as an old Home session")
        }
        XCTAssertEqual(submits,1); XCTAssertEqual(f.reads,[.identity,.grades]); XCTAssertEqual(s.owner,f.original)
    }

    func testInFlightEntryCoalescesAndLogoutFencesSameAccount() async throws {
        let f = Fixture(), s = f.store
        await s.verify(); f.gradeIssue = .expired
        let started = expectation(description: "one navigation started")
        var release: CheckedContinuation<Void, Never>?
        let old = Task { await f.visit { await withCheckedContinuation { release = $0; started.fulfill() } } }
        await fulfillment(of: [started], timeout: 2)
        await f.visit(); await s.verify(); XCTAssertEqual(f.entries, 1)
        s.invalidate(.login); await s.verify()
        try XCTUnwrap(release).resume(); await old.value
        XCTAssertEqual(s.owner, f.original); XCTAssertNil(s.grades); XCTAssertFalse(s.isRecoveringGrades)
        XCTAssertEqual(f.reads, [.identity,.grades,.identity])
    }

    func testCancellingVisitFencesFreshGradeReply() async throws {
        var block = false, release: CheckedContinuation<Data, Never>?
        let started = expectation(description: "fresh grades in flight")
        let owner = String(repeating: "e", count: 64)
        let store = SchoolPortalStore(selected: true) { op, _ in
            if op == .identity { return Data("{\"owner\":\"\(owner)\"}".utf8) }
            if !block { throw SchoolPortalIssue.expired }
            return await withCheckedContinuation { release = $0; started.fulfill() }
        }
        await store.verify()
        let visit = Task { await store.openGrades { block = true } }
        await fulfillment(of: [started], timeout: 2); visit.cancel()
        try XCTUnwrap(release).resume(returning: Data("{\"owner\":\"\(owner)\",\"value\":{\"term\":\"T\",\"termID\":\"t\",\"courses\":[]}}".utf8))
        await visit.value
        XCTAssertNil(store.grades); XCTAssertTrue(store.pending.isEmpty); XCTAssertFalse(store.isRecoveringGrades)
    }
}
