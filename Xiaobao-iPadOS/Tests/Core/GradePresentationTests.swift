import XCTest
@testable import XiaobaoCore

final class GradePresentationTests: XCTestCase {
    func testOnlyExistingCategoriesWithMultipleItemsBecomeGroups() {
        let day = SchoolClock.date(2027, 2, 7)
        let course = makeReport(term: "term-x", id: "ceramics", score: 88.4, assessments: [
            Assessment(id: "glaze", title: "釉色取样", category: "材料实验", date: day,
                       status: .graded, earned: 14.8, possible: 16, feedback: "准确记录了烧成条件。"),
            Assessment(id: "kiln", title: "烧成记录", category: "材料实验", date: day.addingTimeInterval(86_400),
                       status: .pending, earned: nil, possible: 18, feedback: ""),
            Assessment(id: "journal", title: "观摩笔记", category: "观察", date: day,
                       status: .excused, earned: nil, possible: 16, feedback: "")
        ])

        let detail = CourseGradeDetail(report: course)
        XCTAssertEqual(detail.total, .numeric(earned: 88.4, possible: nil))
        XCTAssertEqual(detail.totalPercentage, 88.4)
        XCTAssertEqual(Set(detail.forecastGroups.options.map(\.title)), ["材料实验", "观察"], "Singleton categories remain available to forecasts")
        XCTAssertNil(detail.publishedGPA)
        XCTAssertNil(detail.firstPublishedAt)
        XCTAssertEqual(detail.rows.count, 2)
        guard case .group(let title, let weight, let groupScore, let items) = detail.rows.first,
              case .assessment(let standalone) = detail.rows.last else { return XCTFail("Wrong assessment hierarchy") }
        XCTAssertEqual(title, "材料实验")
        XCTAssertNil(weight)
        XCTAssertNil(groupScore)
        XCTAssertEqual(items.map(\.id), ["kiln", "glaze"])
        XCTAssertNil(items[0].mark)
        XCTAssertEqual(items[1].mark, .numeric(earned: 14.8, possible: 16))
        XCTAssertEqual(standalone.id, "journal")
        XCTAssertTrue(detail.matches(query: "材料实验 ", status: .pending))
        XCTAssertFalse(detail.matches(query: "材料实验", status: .excused))
        XCTAssertTrue(detail.matches(query: "釉色", status: nil))
        XCTAssertFalse(detail.matches(query: "缺失项目", status: nil))
    }

    func testServiceWeightsStayFlatAndDoNotBecomeScores() throws {
        let data = Data("""
        {
          "course_id":"studio-b",
          "published_score":{"type":"numeric","earned":29.125,"possible":32},
          "published_letter_grade":"A−",
          "published_gpa":3.67,
          "class_name":"Workshop B",
          "first_published_at":"2027-02-07T04:41:00.500Z",
          "assessments":[
            {"id":"joinery","title":"接合样片","status":"graded","score":{"type":"letter","value":"B+"},"weight":0.375},
            {"id":"structure","title":"纸构件","status":"pending","score":null,"weight":0},
            {"id":"sketch","title":"结构草图","status":"excused","score":null}
          ]
        }
        """.utf8)
        let grade = try JSONDecoder().decode(CampusGrade.self, from: data)
        let detail = CourseGradeDetail(term: "term-y", name: "材料工作室", grade: grade)
        XCTAssertEqual(detail.total, .numeric(earned: 29.125, possible: 32, letter: "A−"))
        XCTAssertEqual(try XCTUnwrap(detail.totalPercentage), 29.125 / 32 * 100, accuracy: 0.0001)
        XCTAssertEqual(detail.publishedGPA, 3.67)
        XCTAssertEqual(detail.className, "Workshop B")
        XCTAssertEqual(detail.firstPublishedAt, SchoolClock.date(2027, 2, 7, minute: 12 * 60 + 41).addingTimeInterval(0.5))
        XCTAssertTrue(detail.forecastGroups.options.isEmpty)
        XCTAssertEqual(detail.rows.map(\.id), [.assessment("joinery"), .assessment("structure"), .assessment("sketch")])
        let items = detail.rows.flatMap(\.items)
        XCTAssertEqual(items[0].mark, .letter("B+"))
        XCTAssertEqual(items[0].weight, AssessmentWeight(0.375, scope: .course))
        XCTAssertNil(items[0].percentage)
        XCTAssertEqual(items[1].weight, AssessmentWeight(0, scope: .course))
        XCTAssertEqual(items[1].statusTitle, "待评分")
        XCTAssertNil(items[1].mark)
        XCTAssertNil(items[2].weight)
        XCTAssertNil(items[2].mark)
        XCTAssertNotEqual(AssessmentWeight(0.375, scope: .course), AssessmentWeight(0.375, scope: .group))
        for invalid in [-0.1, 1.01, .infinity, .nan] {
            XCTAssertNil(AssessmentWeight(invalid, scope: .course))
        }
    }

    func testUnscaledServiceTotalIsDisplayedButCannotBeUsedAsAPercentage() {
        let grade = CampusGrade(course_id: "lab", published_score: CampusScore(type: "numeric", earned: 16, possible: nil, value: nil),
                                published_gpa: nil, assessments: [])
        let detail = CourseGradeDetail(term: "term-z", name: "Lab", grade: grade)
        XCTAssertEqual(detail.total, .numeric(earned: 16, possible: nil))
        XCTAssertNil(detail.totalPercentage)
        XCTAssertNil(detail.className)
        XCTAssertNil(detail.firstPublishedAt)
    }

    func testOfficialGPAHasPriorityAndMissingGradeIsNotZero() {
        let numeric = CampusGrade(course_id: "drawing", published_score: CampusScore(type: "numeric", earned: 19, possible: 20, value: nil),
                                  published_gpa: nil, assessments: [])
        let letter = CampusGrade(course_id: "design", published_score: CampusScore(type: "letter", earned: nil, possible: nil, value: "A"),
                                 published_gpa: nil, assessments: [])
        let current = CampusGrades(term: "t1", published_gpa: 3.683, courses: [numeric, letter])
        XCTAssertEqual(current.gpaSummary, GPASummary(value: 3.683, source: .published))
        XCTAssertEqual(CampusGrades(term: "t1", published_gpa: 0, courses: []).gpaSummary, GPASummary(value: 0, source: .published))
        XCTAssertNil(CampusGrades(term: "t1", published_gpa: nil, courses: [numeric, letter]).gpaSummary)
        XCTAssertNil(CampusGrades(term: "t1", published_gpa: nil, courses: []).gpaSummary)
        XCTAssertEqual(CampusGrades(term: "t1", published_gpa: nil, courses: [numeric]).gpaReadout,
                       .unavailable([.credits, .conversionRule]))
    }

    func testCampusGPAUsesPublishedTotalsOrPointsWithExplicitCredits() throws {
        let studio = CampusGrade(course_id: "studio", published_score: .init(type: "numeric", earned: 37, possible: 40, value: nil),
                                 published_gpa: nil, assessments: [], gpa_credits: 1.5)
        let lab = CampusGrade(course_id: "lab", published_score: nil,
                              published_gpa: 2.2, assessments: [], gpa_credits: 2.5)
        let excluded = CampusGrade(course_id: "orientation", published_score: nil,
                                   published_gpa: nil, assessments: [], gpa_credits: 0)
        let rule = [CampusGPAScaleBand(minimum_percent: 91, grade_points: 3.9),
                    .init(minimum_percent: 0, grade_points: 0),
                    .init(minimum_percent: 68, grade_points: 1.75)]
        let grades = CampusGrades(term: "current", published_gpa: nil, courses: [studio, lab, excluded], gpa_scale: rule)
        let estimate = try XCTUnwrap(grades.gpaSummary)
        XCTAssertEqual(estimate.value, 2.8375, accuracy: 0.000001)
        XCTAssertEqual(estimate.source, .creditWeightedEstimate)
        XCTAssertEqual(CampusGrades(term: "current", published_gpa: nil, courses: [lab]).gpaSummary?.value, 2.2)

        let zero = CampusGrade(course_id: "zero", published_score: .init(type: "numeric", earned: 0, possible: 30, value: nil),
                                published_gpa: nil, assessments: [], gpa_credits: 1)
        XCTAssertEqual(CampusGrades(term: "current", published_gpa: nil, courses: [zero], gpa_scale: rule).gpaSummary?.value, 0)
    }

    func testCampusGPAReportsMissingAndUnusableInformationWithoutGuessing() {
        let incomplete = CampusGrade(course_id: "survey", published_score: nil, published_gpa: nil, assessments: [])
        XCTAssertEqual(CampusGrades(term: "current", published_gpa: nil, courses: [incomplete]).gpaReadout,
                       .unavailable([.credits, .publishedTotals, .conversionRule]))
        let lab = CampusGrade(course_id: "lab", published_score: .init(type: "numeric", earned: 31, possible: 40, value: nil),
                              published_gpa: nil, assessments: [], gpa_credits: 2)
        let broken = [CampusGPAScaleBand(minimum_percent: 0, grade_points: 0),
                      .init(minimum_percent: 0, grade_points: 4)]
        XCTAssertEqual(CampusGrades(term: "current", published_gpa: nil, courses: [lab], gpa_scale: broken).gpaReadout,
                       .unavailable([.invalidConversionRule]))
        XCTAssertEqual(CampusGrades(term: "current", published_gpa: nil, courses: [lab, lab], gpa_scale: broken).gpaReadout,
                       .unavailable([.courseList]))
        var invalid = lab
        invalid.gpa_credits = -.infinity
        XCTAssertEqual(CampusGrades(term: "current", published_gpa: nil, courses: [invalid]).gpaReadout,
                       .unavailable([.credits, .conversionRule]))
    }

    func testCampusGradeChangesDoNotCarryAWithdrawnConversionRuleForward() throws {
        let term = "test-spring"
        let roster = [CampusCourseVersion(course_id: "archive", name: "Archival Lab", revision: "a")]
        let course = CampusGrade(course_id: "archive", published_score: .init(type: "numeric", earned: 40, possible: 50, value: nil),
                                 published_gpa: nil, assessments: [], gpa_credits: 2)
        let scale = [CampusGPAScaleBand(minimum_percent: 0, grade_points: 0),
                     .init(minimum_percent: 79, grade_points: 2.6)]
        let stamp = Date(timeIntervalSince1970: 5_000)
        let published = CampusGradeChanges(version: "one", term: term, published_gpa: nil,
                                          courses: roster, changed: [course], gpa_scale: scale)
        let saved = try published.applying(to: nil, at: stamp)
        let cached = try JSONDecoder().decode(SavedCampusGrades.self, from: JSONEncoder().encode(saved))
        XCTAssertEqual(cached.grades.gpa_scale, scale)
        XCTAssertEqual(try XCTUnwrap(cached.grades.gpaSummary?.value), 2.6, accuracy: 0.000001)
        let withdrawn = CampusGradeChanges(version: "two", term: term, published_gpa: nil, courses: roster, changed: [])
        let restored = try withdrawn.applying(to: cached, at: stamp)
        XCTAssertEqual(restored.grades.courses.first?.gpa_credits, 2)
        XCTAssertEqual(restored.grades.gpaReadout, .unavailable([.conversionRule]))
    }

    func testLocalEstimateReadsOnlyTheSelectedTermAndRequiresAllTotals() {
        let book = Gradebook(terms: [], courses: [
            makeReport(term: "first", id: "sculpture", score: 92.6),
            makeReport(term: "second", id: "design", score: 73.4),
            makeReport(term: "second", id: "workshop", score: nil)
        ])
        XCTAssertEqual(book.gpaSummary(termID: "first", weighted: true), GPASummary(value: 5, source: .localEstimate(weighted: true)))
        XCTAssertEqual(book.gpaSummary(termID: "first", weighted: false), GPASummary(value: 4, source: .localEstimate(weighted: false)))
        XCTAssertNil(book.gpaSummary(termID: "second", weighted: true))
        XCTAssertNil(book.gpaSummary(termID: "unknown", weighted: false))
    }

    private func makeReport(term: String, id: String, score: Double?, assessments: [Assessment] = []) -> CourseReport {
        CourseReport(termID: term, courseID: id, name: "陶艺工作室", teacher: "", credits: 1,
                     advanced: true, publishedScore: score, assessments: assessments)
    }
}
