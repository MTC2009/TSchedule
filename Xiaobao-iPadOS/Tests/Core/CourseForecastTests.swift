import XCTest
@testable import XiaobaoCore

final class CourseForecastTests: XCTestCase {
    func testReportedGroupWithoutCountStartsWithForecastsRatherThanInventingHistory() throws {
        let def = ForecastGroup(id: "design", title: "Methods", parentID: nil, weight: .init(0.75, scope: .course),
            published: .numeric(earned: 92, possible: nil), hasItems: true,
            samples: .init(released: [], excludesUnreleased: true), reportedPercentage: 92)
        let verified = ForecastGroup(id: "model", title: "Applied", parentID: nil, weight: .init(0.25, scope: .course),
            published: .numeric(earned: 23, possible: 100), hasItems: false, samples: .init(released: [], excludesUnreleased: false))
        let results = try [45.0, 85].map { try AssessmentForecast(groupID: "design", mark: $0) }
        XCTAssertEqual(CourseForecast.project(current: nil, groups: .init([def, verified]), estimates: results).percentage, 54.5)
    }

    @MainActor func testSavedWhatIfSurvivesSessionAndTermChangesButRestoreIsTermOnly() throws {
        let path = URL.temporaryDirectory.appending(path: "forecast-check-" + UUID().uuidString)
        let year = CourseForecastStore.Scope(owner: "account-a", term: "early", session: UUID())
        let otherTerm = CourseForecastStore.Scope(owner: "account-a", term: "late", session: year.session)
        let differentOwner = CourseForecastStore.Scope(owner: "account-b", term: "early", session: UUID())
        let laterSession = CourseForecastStore.Scope(owner: year.owner, term: year.term, session: UUID())
        let forecast = try AssessmentForecast(groupID: "row", groupAnchor: "anchor", mark: 61.25)
        let store = CourseForecastStore(directory: path)
        store.open(year)
        XCTAssertEqual(store.read(in: year), [:])
        try store.save(forecast, course: "course", in: year)
        store.open(otherTerm)
        XCTAssertNil(store.read(in: year))
        try store.save(forecast, course: "other-course", in: otherTerm)

        let relaunched = CourseForecastStore(directory: path)
        relaunched.open(differentOwner)
        XCTAssertEqual(relaunched.read(in: differentOwner), [:])
        relaunched.open(laterSession)
        XCTAssertEqual(relaunched.read(in: laterSession)?["course"], [forecast])
        XCTAssertThrowsError(try relaunched.restore(in: year))
        try relaunched.restore(in: laterSession)
        XCTAssertEqual(relaunched.read(in: laterSession), [:])
        relaunched.open(otherTerm)
        XCTAssertEqual(relaunched.read(in: otherTerm)?["other-course"], [forecast])
    }

    func testForecastIdentityFollowsTheGroupNotItsCurrentPosition() throws {
        func group(_ id: String, _ label: String) -> ForecastGroup {
            .init(id: id, title: label, parentID: nil, weight: .init(0.5, scope: .course),
                  published: nil, hasItems: false, samples: .init(released: [], excludesUnreleased: false))
        }
        let current = ForecastGroups([group("0", "Material"), group("1", "Studio")])
        let guess = try AssessmentForecast(groupID: "0", groupAnchor: XCTUnwrap(current.anchor(for: "0")), mark: 75)
        let reordered = ForecastGroups([group("1", "Material"), group("0", "Studio")])
        XCTAssertEqual(reordered.id(for: guess), "1")
        let collision = ForecastGroups([group("1", "Material"), group("0", "Material")])
        XCTAssertNil(collision.id(for: guess))
    }

    func testTermForecastReplacesOnlyTheEditedCourseAndKeepsOfficialNumbersSeparate() throws {
        let normal = TermForecastGPA.Course(title: "IGCSE Botany", published: 96, prediction: nil, hasForecast: false)
        let changed = TermForecastGPA.Course(title: "AP Geology", published: 70, prediction: 90, hasForecast: true)
        let excluded = TermForecastGPA.Course(title: "Homeroom", published: 100, prediction: nil, hasForecast: false)
        let partial = TermForecastGPA.Course(title: "Optics", published: 89, prediction: nil, hasForecast: true)
        let original = try XCTUnwrap(TermForecastGPA.calculate([normal, changed, excluded]))
        XCTAssertEqual(original.value, 4.1, accuracy: 1e-9)
        XCTAssertEqual(original.source, .forecast)
        XCTAssertNil(TermForecastGPA.calculate([normal, excluded]))
        XCTAssertNil(TermForecastGPA.calculate([normal, changed, partial]))
        XCTAssertEqual(changed.published, 70)
    }
    func testAReleasedZeroAndDifferentPointScalesCanShareANonemptyGroupWithANewScore() throws {
        func score(_ earned: Double, _ possible: Double?) -> CampusScore {
            .init(type: "numeric", earned: earned, possible: possible, value: nil)
        }
        func item(_ id: String, _ status: String, _ value: CampusScore) -> CampusAssessment {
            .init(id: id, title: "Studio exercise", status: status, date: nil, feedback: nil, score: value)
        }
        let subject = SchoolPortalGrades.Course(id: "folio", subject: "f", name: "Materials", cls: nil, className: nil, type: 1, score: nil)
        let report = SchoolPortalGrades(term: "Winter", termID: "w", gpa: nil, gpaUnavailable: nil, courses: [subject])
        let groups: [SchoolPortalGrades.Group] = [
            .init(id: "0", title: "Process", nested: false, weight: 0.6, mark: score(37.5, nil),
                  items: [item("a", "graded", score(0, 18)), item("b", "graded", score(12, 16)),
                          item("held", "unpublished", score(99, 100))]),
            .init(id: "1", title: "Journal", nested: false, weight: 0.4, mark: score(81, nil), items: [])
        ]
        let detail = report.courseDetail(subject, groups: groups)
        let drafts = [try AssessmentForecast(groupID: "0", mark: 90)]
        guard case let .estimated(number) = CourseForecast.calculate(current: detail.totalPercentage, groups: detail.forecastGroups, estimates: drafts) else {
            return XCTFail("Released component data suffice without a published course total")
        }
        XCTAssertEqual(number, 65.4, accuracy: 1e-9)
        XCTAssertNil(detail.totalPercentage, "Forecasts must not publish a course mark")
    }

    private func group(_ id: String, parent: String? = nil, share: Double?, published: GradeMark? = nil,
                       hasItems: Bool = false) -> ForecastGroup {
        .init(id: id, title: "Studio", parentID: parent, weight: AssessmentWeight(share, scope: parent == nil ? .course : .group),
              published: published, hasItems: hasItems)
    }

    func testEmptyRootUsesPublishedShareAndLeavesGradedRemainderUnchanged() throws {
        let groups = ForecastGroups([group("work", share: 0.65, published: .numeric(earned: 72, possible: nil)),
                                     group("review", share: 0.35)])
        let draft = try AssessmentForecast(name: "  Ribbon  ", groupID: "review", mark: 80)
        XCTAssertEqual(draft.name, "Ribbon")
        guard case let .estimated(result) = CourseForecast.calculate(current: 72, groups: groups, estimates: [draft]) else {
            return XCTFail("The remaining root groups already contribute to the published course subtotal")
        }
        XCTAssertEqual(result, 74.8, accuracy: 1e-10)
        XCTAssertEqual(CourseForecast.calculate(current: 68, groups: groups, estimates: [draft]), .unknownAllocation,
                       "A group score on an unconfirmed scale cannot stand in for the remaining course subtotal")
        XCTAssertEqual(CourseForecast.calculate(current: nil, groups: groups, estimates: [draft]), .missingCourseTotal)
    }

    func testNestedSharesUseParentPathRatherThanNamesAndNeverDoubleCount() throws {
        let groups = ForecastGroups([group("a", share: 0.6), group("b", share: 0.4, published: .numeric(earned: 8, possible: 10)),
            group("a.0", parent: "a", share: 0.25),
            group("a.1", parent: "a", share: 0.75, published: .numeric(earned: 13, possible: 20))])
        let draft = try AssessmentForecast(groupID: "a.0", mark: 90)
        guard case let .estimated(value) = CourseForecast.calculate(current: 71, groups: groups, estimates: [draft]) else {
            return XCTFail("All sibling weights and component scores are known")
        }
        XCTAssertEqual(value, 74.75, accuracy: 1e-10)
        let second = try AssessmentForecast(groupID: "a.0", mark: 21)
        guard case .estimated(let two) = CourseForecast.calculate(current: 71, groups: groups, estimates: [draft, second]) else {
            return XCTFail("Two drafts in one leaf share it, not its whole course weight twice")
        }
        XCTAssertEqual(two, 69.575, accuracy: 1e-9)
        XCTAssertEqual(CourseForecast.calculate(current: 71, groups: groups, estimates: [draft, try .init(groupID: "a", mark: 21)]), .selectLeaf)
        XCTAssertEqual(CourseForecast.calculate(current: 71, groups: groups, estimates: [draft, try .init(groupID: "a.1", mark: 21)]), .missingCount)
    }

    func testUnknownGroupAllocationAndWeightsAreNotFilledIn() throws {
        let draft = try AssessmentForecast(groupID: "leaf", mark: 0)
        func result(_ groups: [ForecastGroup]) -> CourseForecast.Result {
            CourseForecast.calculate(current: 72, groups: ForecastGroups(groups), estimates: [draft])
        }
        XCTAssertEqual(result([]), .missingGroup)
        XCTAssertEqual(result([group("leaf", share: nil)]), .missingWeight)
        XCTAssertEqual(result([group("leaf", parent: "missing", share: 0.8)]), .missingWeight)
        XCTAssertEqual(result([group("leaf", share: 1, hasItems: true)]), .missingCount)
        XCTAssertEqual(result([group("leaf", share: 0.4), group("other", share: 0.6)]), .unknownAllocation)
        XCTAssertEqual(result([group("leaf", share: 0.8)]), .unknownAllocation)
        XCTAssertEqual(result([group("leaf", share: 1), group("leaf", parent: "leaf", share: 1)]), .unknownAllocation)
        XCTAssertEqual(result([group("leaf", share: 0)]), .estimated(72))
        XCTAssertEqual(result([group("leaf", share: 1)]), .estimated(0))
        XCTAssertEqual(CourseForecast.calculate(current: 72, groups: ForecastGroups(), estimates: []), .noEstimates)
        XCTAssertEqual(CourseForecast.calculate(current: 72, groups: ForecastGroups(), estimates: [try .init(mark: 78)]), .missingGroup)
        for mark in [-1.0, 101, .nan, .infinity] { XCTAssertThrowsError(try AssessmentForecast(mark: mark)) }
    }

    func testVisibleOnlySamplesDoNotBackSolveHiddenMarksOrInventAWeight() throws {
        let samples = ForecastSamples(released: [.numeric(earned: 0, possible: 12), .numeric(earned: 8, possible: 10)], excludesUnreleased: true)
        var leaf = ForecastGroup(id: "f", title: "Materials", parentID: nil, weight: nil, published: .numeric(earned: 94, possible: nil),
                                 hasItems: true, samples: samples, reportedPercentage: 94)
        let draft = try AssessmentForecast(groupID: "f", mark: 70)
        func calc() -> CourseForecast.Projection { CourseForecast.project(current: nil, groups: .init([leaf]), estimates: [draft]) }
        XCTAssertEqual(calc().result, .missingWeight)
        XCTAssertEqual(calc().subtotals.first?.percentage, 50, "Neither the unknown weight nor a withheld item is inferred")
        leaf = .init(id: "f", title: "M", parentID: nil, weight: .init(1, scope: .course), published: nil, hasItems: true,
                     samples: .init(released: [.numeric(earned: 7, possible: nil)], excludesUnreleased: false))
        XCTAssertEqual(calc().result, .missingScoreScale)
        XCTAssertTrue(calc().subtotals.isEmpty)
        let nonnumeric = ForecastGroups([leaf], supportsNumericForecast: false)
        XCTAssertEqual(CourseForecast.calculate(current: nil, groups: nonnumeric, estimates: [draft]), .nonNumericCourse)
    }

    func testPublishedNumericAverageUsesKnownCountAndEmptySiblingsAreNotZeroes() throws {
        let active = ForecastGroup(id: "s", title: "Process", parentID: nil, weight: .init(0.6, scope: .course),
                                   published: .numeric(earned: 81, possible: nil), hasItems: true,
                                   samples: .init(released: [.numeric(earned: 7, possible: nil), .numeric(earned: 5, possible: nil)], excludesUnreleased: false),
                                   reportedPercentage: 81)
        let empty = ForecastGroup(id: "e", title: "Review", parentID: nil, weight: .init(0.4, scope: .course), published: nil,
                                  hasItems: false, samples: .init(released: [], excludesUnreleased: false))
        let groups = ForecastGroups([active, empty]), added = try AssessmentForecast(groupID: "s", mark: 48)
        XCTAssertEqual(CourseForecast.calculate(current: nil, groups: groups, estimates: [added]), .estimated(70))
        guard case let .estimated(result) = CourseForecast.calculate(current: nil, groups: groups, estimates: [added, try .init(groupID: "e", mark: 20)]) else { return XCTFail() }
        XCTAssertEqual(result, 50, accuracy: 1e-10)
    }

    func testEqualItemAndRelativeGroupWeightsAcrossDifferentVisibleRosters() throws {
        // Independent reference arithmetic across mixed scales and differently sized groups.
        for count in 1...8 {
            for weight in [0.15, 0.375, 0.7, 1.0] {
                let previous = (0..<count).map { ($0 * 13 + 5) % 71 }
                let observed = previous.map { GradeMark.numeric(earned: Double($0), possible: 80) }
                let marks = [0.0, 82.5, 100.0]
                let drafts = try marks.map { try AssessmentForecast(groupID: "ink", mark: $0) }
                let options = ForecastGroups([
                    ForecastGroup(id: "ink", title: "Ink", parentID: nil, weight: .init(weight, scope: .course), published: nil,
                                  hasItems: true, samples: .init(released: observed, excludesUnreleased: false)),
                    ForecastGroup(id: "wire", title: "Wire", parentID: nil, weight: .init(1-weight, scope: .course),
                                  published: .numeric(earned: 7, possible: 10), hasItems: false, samples: .init(released: [], excludesUnreleased: false)),
                    ForecastGroup(id: "future", title: "Future", parentID: nil, weight: nil, published: nil, hasItems: false,
                                  samples: .init(released: [], excludesUnreleased: false))])
                let group = (Double(previous.reduce(0, +)) * 1.25 + marks.reduce(0, +)) / Double(count + marks.count)
                guard case .estimated(let result) = CourseForecast.calculate(current: nil, groups: options, estimates: drafts) else { return XCTFail() }
                XCTAssertEqual(result, group * weight + 70 * (1 - weight), accuracy: 1e-9)
            }
        }
    }
}
