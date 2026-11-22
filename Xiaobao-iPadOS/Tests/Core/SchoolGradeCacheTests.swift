import Foundation
import XCTest
@testable import XiaobaoCore

final class SchoolGradeCacheTests: XCTestCase {
    @MainActor private func document() throws -> (URL, UserDefaults) {
        let id = UUID().uuidString
        let file = URL.temporaryDirectory.appending(path: "grade-archive-" + id).appending(path: "snapshot.plist")
        return (file, try XCTUnwrap(UserDefaults(suiteName: "grades.tests." + id)))
    }

    @MainActor func testTransientFailureDoesNotTurnReceiptIntoAnEmptyGradebook() async throws {
        let (file, defaults) = try document(), owner = String(repeating: "3", count: 64)
        let cache = SchoolGradeCache(file: file, defaults: defaults)
        var gradeReads = 0
        let store = SchoolPortalStore(selected: true) { read, _ in
            switch read {
            case .identity:
                return try JSONSerialization.data(withJSONObject: ["owner": owner])
            case .grades:
                gradeReads += 1
                if gradeReads == 2 { throw SchoolPortalIssue.network }
                return try JSONSerialization.data(withJSONObject: [
                    "owner": owner, "value": ["term": "Quarter", "termID": "q", "courses": [],
                                               "gpa": 2.8] as [String: Any]
                ])
            default: throw SchoolPortalIssue.format
            }
        }
        store.onAccountConfirmation = { if let owner = $0 { cache.verified(owner) } }
        store.onGradeOverview = { cache.accept($0, owner: $1, current: $2, checked: $3) }
        await store.verify()
        await store.loadGrades()
        let first = try XCTUnwrap(cache.snapshot(term: nil, verifiedOwner: owner))
        await store.loadGrades()
        XCTAssertEqual(store.issues[.grades], .network)
        XCTAssertEqual(store.grades?.gpa, first.overview.gpa)
        XCTAssertEqual(cache.snapshot(term: nil, verifiedOwner: owner)?.checked, first.checked)
        store.suspend()
        XCTAssertNil(store.grades, "The online store still suspends and grants no read authority")
        let cold = SchoolGradeCache(file: file, defaults: defaults)
        XCTAssertEqual(cold.snapshot(term: nil, verifiedOwner: nil)?.overview.gpa, 2.8)
        XCTAssertEqual(gradeReads, 2, "Offline reopening does not use the reader")
    }

    @MainActor func testPartialGPAAndBadCourseReadDoNotEraseSuccessfulSections() throws {
        let (file, defaults) = try document()
        let cache = SchoolGradeCache(file: file, defaults: defaults)
        let saved = SchoolPortalGrades.Course(id: "field", subject: "drawing", name: "Contour study",
            cls: "enrollment", className: nil, type: 1, score: .init(type: "numeric", earned: 75, possible: 100, value: nil))
        let original = SchoolPortalGrades(term: "First", termID: "term1", gpa: 2.2, gpaUnavailable: false, courses: [saved])
        cache.accept(original, owner: "first", current: true, checked: Date.distantPast)
        let withheld = CampusAssessment(id: "held", title: "Exercise", status: "unpublished", date: nil, feedback: "private",
                                        score: .init(type: "numeric", earned: 88, possible: 100, value: nil))
        let group = SchoolPortalGrades.Group(id: "0", title: "Practice", nested: false, weight: 1, mark: nil, items: [withheld])
        cache.accept(groups: [group], course: saved.id, term: original.termID, owner: "first")
        let partial = SchoolPortalGrades(term: "First", termID: "term1", gpa: nil, gpaUnavailable: true, courses: [saved])
        cache.accept(partial, owner: "first", current: true, checked: Date())
        cache.accept(partial, owner: "different", current: true, checked: Date())
        let snapshot = try XCTUnwrap(cache.snapshot(term: nil, verifiedOwner: "first"))
        XCTAssertEqual(snapshot.overview.gpa, 2.2)
        let row = try XCTUnwrap(snapshot.groups[saved.id]?.first?.items.first)
        XCTAssertNil(row.feedback); XCTAssertNil(row.score)
        cache.revoke(.detail(term: original.termID, subject: saved.subject, cls: "enrollment", type: 1))
        XCTAssertNil(cache.snapshot(term: nil, verifiedOwner: "first")?.groups[saved.id])
        XCTAssertEqual(cache.snapshot(term: nil, verifiedOwner: "first")?.overview.gpa, 2.2)
    }

    @MainActor func testAccountReviewPersistsAndLogoutRevokesOnlyRegisteredDocument() throws {
        let (file, defaults) = try document()
        let cache = SchoolGradeCache(file: file, defaults: defaults)
        let current = SchoolPortalGrades(term: "Current", termID: "c", gpa: 2, gpaUnavailable: nil, courses: [])
        let previous = SchoolPortalGrades(term: "Archive", termID: "a", gpa: 3, gpaUnavailable: nil, courses: [])
        cache.accept(current, owner: "same", current: true, checked: Date())
        cache.accept(previous, owner: "same", current: false, checked: Date())
        XCTAssertEqual(cache.snapshot(term: nil, verifiedOwner: nil)?.overview.termID, "c")
        XCTAssertNil(cache.snapshot(term: nil, verifiedOwner: "other"))
        cache.reviewAccount()
        let newCache = SchoolGradeCache(file: file, defaults: defaults)
        XCTAssertNil(newCache.snapshot(term: "a", verifiedOwner: nil))
        newCache.verified("same")
        XCTAssertEqual(newCache.snapshot(term: "a", verifiedOwner: nil)?.overview.gpa, 3)
        newCache.revoke(.grades)
        XCTAssertNil(newCache.snapshot(term: nil, verifiedOwner: "same"))
        XCTAssertNotNil(newCache.snapshot(term: "a", verifiedOwner: "same"))
        newCache.verified("different")
        XCTAssertNil(SchoolGradeCache(file: file, defaults: defaults).snapshot(term: "a", verifiedOwner: nil))
    }
}
