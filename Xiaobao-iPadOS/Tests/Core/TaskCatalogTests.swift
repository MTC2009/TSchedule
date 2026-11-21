import XCTest
@testable import XiaobaoCore

@MainActor final class TaskCatalogTests: XCTestCase {
    func testReadsEveryPageAndKeepsTheTaskTermDirectory() async throws {
        var requested: [Int] = []
        let result = try await TaskCatalog.load(term: "2027-spring") { query in
            XCTAssertEqual(query.term, "2027-spring")
            requested.append(query.offset)
            let rows = (query.offset..<min(query.offset + 2, 5)).map { item("record-\($0)") }
            return CampusList(items: rows, total: 5, offset: query.offset, limit: 2,
                              current_term: "2027-autumn", available_terms: ["2027-autumn", "2027-spring"])
        }
        XCTAssertEqual(requested, [0, 2, 4])
        XCTAssertEqual(result.rows.map(\.id), (0..<5).map { "record-\($0)" })
        XCTAssertEqual(result.directory?.current, "2027-autumn")
        XCTAssertEqual(result.directory?.available, ["2027-autumn", "2027-spring"])
    }

    func testRejectsDuplicateOrCrossTermDataRatherThanShowingPartialResults() async {
        var legacyCurrent = item("legacy-current")
        legacyCurrent.term = nil
        for bad in [item("same"), item("intruder", term: "2028-spring"), legacyCurrent] {
            do {
                _ = try await TaskCatalog.load(term: "2027-spring") { query in
                    CampusList(items: [query.offset == 0 ? item("same") : bad], total: 2, offset: query.offset, limit: 1)
                }
                XCTFail("A partial or mis-scoped list must not be published")
            } catch {
                guard let campusError = error as? CampusError, case .invalidResponse = campusError else {
                    return XCTFail("Expected a task response validation error, received \(error)")
                }
            }
        }
    }

    func testTaskTermsAreQueriableEvenWhenTheirKeysContainPunctuation() throws {
        let term = "2027/A+B & C"
        let route = TaskReadRequest(term: term, offset: 2, limit: 1).route
        let query = try XCTUnwrap(URLComponents(string: route)?.queryItems)
        XCTAssertTrue(route.contains("%2B"))
        XCTAssertEqual(query.first { $0.name == "term" }?.value, term)
        XCTAssertEqual(query.first { $0.name == "kind" }?.value, "task")
    }

    private func item(_ id: String, term: String = "2027-spring") -> CampusWork {
        CampusWork(id: id, title: "样本记录", due_at: "2027-05-05T08:00:00+08:00", status: "pending",
                   description: "", course_id: nil, kind: "task", term: term)
    }
}
