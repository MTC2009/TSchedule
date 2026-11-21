import Foundation
import XCTest
@testable import XiaobaoCore

final class OtherItemsCatalogTests: XCTestCase {
    private let now = SchoolClock.date(2026, 11, 21)

    func testASingleExamCanMatchMultipleLinkedCoursesWithoutDuplicateTiles() throws {
        let json = """
        {"data":{"items":[{"id":"review","title":"End of unit review","kind":"exam","course_id":"earth",
        "status":"pending","description":"Bring a ruler.","due_at":"2026-11-24T10:00:00+08:00",
        "exam":{"start":"2026-11-24T09:00:00+08:00","end":"2026-11-24T10:00:00+08:00",
        "score":null,"results":[{"course_id":"earth","score":null},{"course_id":"math","score":null}]}}],
        "total":1,"offset":0,"limit":30}}
        """
        guard case .work(let page) = try CampusPage.work("exam").decode(Data(json.utf8)) else {
            return XCTFail("Missing work page")
        }
        let records = page.items.map { OtherItem(campus: $0, kind: .exam, courseNames: ["earth": "Earth Science", "math": "Mathematics"]) }
        XCTAssertEqual(OtherItemsCatalog.courses(in: records).map(\.id), ["earth", "math"])
        XCTAssertEqual(records.map(\.id), ["review"])
        var filters = OtherItemsFilters()
        for id in ["earth", "math"] {
            filters.course = .course(id)
            XCTAssertEqual(filters.results(in: records, at: now, bookmarks: []).map(\.id), ["review"])
        }
        guard case .exam(let exam) = try XCTUnwrap(records.first).detail else { return XCTFail("Expected exam") }
        XCTAssertEqual(exam.startsAt, SchoolClock.date(2026, 11, 24, minute: 540))
        XCTAssertEqual(exam.endsAt, SchoolClock.date(2026, 11, 24, minute: 600))
        XCTAssertNil(exam.room)
        XCTAssertEqual(exam.description, "Bring a ruler.")
    }

    func testDoNotGuessACourseOrCarryAFavoriteAcrossSources() throws {
        let file = CampusResource(id: "reference", title: "Earth Science readings", content: "Notes",
                                  scope: "shared", kind: "document")
        let connected = OtherItem(campus: file)
        let local = OtherItem(local: StudyResource(id: file.id, title: file.title, course: "AP Physics 1",
                                                   kind: "讲义", date: now, content: "Local notes."))
        XCTAssertEqual(connected.courseTitle, "未分科")
        XCTAssertEqual(OtherItemsCatalog.courses(in: [connected, local]).map(\.name), ["AP Physics 1"])
        XCTAssertFalse(connected.isBookmarked(in: [file.id]))
        XCTAssertTrue(local.isBookmarked(in: [file.id]))
        var filters = OtherItemsFilters(course: .unassigned)
        XCTAssertEqual(filters.results(in: [local, connected], at: now, bookmarks: []).count, 1)
        filters.bookmarksOnly = true
        XCTAssertTrue(filters.results(in: [local, connected], at: now, bookmarks: [file.id]).isEmpty)
    }

    func testCourseSearchAndStatusCombineAndPreserveTheSourceOrder() {
        let items = [
            CampusWork(id: "first", title: "Observation", due_at: "2026-11-25T08:00:00+08:00",
                       status: "pending", description: "First report.", course_id: "natural", kind: "evaluation"),
            CampusWork(id: "second", title: "Review", due_at: "2026-11-22T08:00:00+08:00",
                       status: "completed", description: "Review notes.", course_id: "natural", kind: "evaluation"),
            CampusWork(id: "third", title: "Survey", due_at: "2026-11-25T08:00:00+08:00",
                       status: "pending", description: "", course_id: nil, kind: "evaluation"),
        ].map { OtherItem(campus: $0, kind: .evaluation, courseNames: ["natural": "Natural Sciences"]) }
        var filters = OtherItemsFilters(course: .course("natural"), query: " NATURAL ")
        XCTAssertEqual(filters.results(in: items, at: now, bookmarks: []).map(\.id), ["first", "second"])
        filters.status = .finished
        XCTAssertEqual(filters.results(in: items, at: now, bookmarks: []).map(\.id), ["second"])
    }

    func testAnUndecodedRosterDoesNotTurnAnAssignedWorkIntoAnUnassignedWork() {
        let source = CampusWork(id: "named", title: "Practice", due_at: "2026-11-24T10:30:00+08:00",
                                status: "pending", description: "", course_id: "unloaded", kind: "exam")
        let item = OtherItem(campus: source, kind: .exam, courseNames: [:])
        XCTAssertEqual(item.courseTitle, "课程名称待载入")
        XCTAssertTrue(OtherItemsFilters(course: .unassigned).results(in: [item], at: now, bookmarks: []).isEmpty)
        guard case .exam(let exam) = item.detail else { return XCTFail("Expected exam") }
        XCTAssertNil(exam.startsAt)
        XCTAssertNil(exam.endsAt)
        XCTAssertEqual(exam.dueAt, SchoolClock.date(2026, 11, 24, minute: 630))
    }
}
