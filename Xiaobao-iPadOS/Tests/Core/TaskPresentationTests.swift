import XCTest
@testable import XiaobaoCore

final class TaskPresentationTests: XCTestCase {
    func testPublishedMarksAndSubmissionsAreIndependent() throws {
        let row = try work("""
          {"id":"sample","title":"地貌剖面","status":"submitted","kind":"task","course_id":"terrain",
           "due_at":"2027-04-05T09:00:00+08:00","published_at":"2027-04-02T07:30:00+08:00",
           "description":"绘制示意图","term":"2027-spring","work_type":"practice",
           "task":{"mode":"offline","grading_status":"graded","score":{"type":"numeric","earned":0,"possible":20},
             "opens_at":"2027-04-03T08:00:00+08:00","attachments":[{"name":"底图.pdf"}],
             "submission":{"submitted_at":"2027-04-04T07:28:00Z","text":"已按坡折点划分。","attachments":[{"name":"剖面.txt","size_bytes":300}]},
             "feedback":{"text":"请更新比例尺。","attachments":[{"name":"修订建议.txt"}]}}}
          """)
        let roster = ["terrain": CampusCourse(id: "terrain", name: "Earth Science", teacher: "Demo Teacher", room: nil)]
        let task = TaskRecord(campus: row, roster: roster)
        XCTAssertEqual(task.grading, .graded)
        XCTAssertEqual(task.mark, .numeric(earned: 0, possible: 20))
        XCTAssertEqual(task.submission(at: SchoolClock.date(2027, 4, 12), locallyCompleted: true), .submitted)
        XCTAssertFalse(task.permitsLocalCompletion)
        XCTAssertEqual(task.teacher, "Demo Teacher")
        XCTAssertEqual(task.opensAt, SchoolClock.date(2027, 4, 3, minute: 480))
        XCTAssertEqual(task.submittedAt, SchoolClock.date(2027, 4, 4, minute: 15 * 60 + 28))
        XCTAssertEqual(task.instructions.attachments.map(\.name), ["底图.pdf"])
        XCTAssertEqual(task.answer?.text, "已按坡折点划分。")
        XCTAssertEqual(task.answer?.attachments.first?.size_bytes, 300)
        XCTAssertEqual(task.feedback?.attachments.map(\.name), ["修订建议.txt"])
        let diskRoundTrip = try JSONDecoder().decode(CampusWork.self, from: JSONEncoder().encode(row))
        XCTAssertEqual(TaskRecord(campus: diskRoundTrip, roster: roster).feedback?.text, task.feedback?.text)
    }

    func testUnknownAndInProgressAreNotPublishedGrades() throws {
        let old = try work("""
          {"id":"old-task","title":"种子观察","status":"submitted","due_at":"2027-04-03T09:00:00+08:00","description":""}
          """)
        let oldTask = TaskRecord(campus: old, roster: [:])
        XCTAssertEqual(oldTask.grading, .unavailable)
        XCTAssertNil(oldTask.mark)
        XCTAssertNil(oldTask.publishedAt)
        XCTAssertNil(oldTask.answer)
        XCTAssertNil(oldTask.feedback)

        let reviewing = try work("""
          {"id":"review","title":"植物笔记","status":"submitted","due_at":"2027-04-09T09:00:00+08:00","description":"",
           "task":{"grading_status":"in_progress","score":{"type":"letter","value":"C"}}}
          """)
        let newTask = TaskRecord(campus: reviewing, roster: [:])
        XCTAssertEqual(newTask.grading, .inProgress)
        XCTAssertNil(newTask.mark)
        XCTAssertEqual(newTask.submission(at: .distantFuture, locallyCompleted: false), .submitted)
    }

    func testOnlyExplicitlyReleasedPreviewAppearsBeforePublication() throws {
        var row = try work("""
          {"id":"survey","title":"河床取样记录","status":"completed","due_at":"2027-05-11T10:00:00+08:00",
           "description":"",
           "task":{"grading_status":"graded_unpublished","score":{"type":"numeric","earned":13,"possible":25},
                   "released_score_estimate":{"type":"numeric","earned":18,"possible":25}}}
          """)
        let task = TaskRecord(campus: row, roster: [:])
        XCTAssertEqual(task.grading, .gradedUnpublished)
        XCTAssertNil(task.sourceMark)
        XCTAssertNil(task.mark)
        XCTAssertEqual(task.estimatedMark, .numeric(earned: 18, possible: 25))
        XCTAssertEqual(task.cardStage(at: .distantFuture), .awaitingGrading)

        row.task?.released_score_estimate = nil
        XCTAssertNil(TaskRecord(campus: row, roster: [:]).estimatedMark)
        row.task?.released_score_estimate = .init(type: "numeric", earned: 26, possible: 25, value: nil)
        XCTAssertNil(TaskRecord(campus: row, roster: [:]).estimatedMark)
        row.task = .init(mode: nil, grading_status: "graded", score: .init(type: "numeric", earned: 20, possible: 25, value: nil),
                         attachments: nil, opens_at: nil, submission: nil, feedback: nil,
                         released_score_estimate: .init(type: "numeric", earned: 18, possible: 25, value: nil))
        let published = TaskRecord(campus: row, roster: [:])
        XCTAssertEqual(published.mark, .numeric(earned: 20, possible: 25))
        XCTAssertNil(published.estimatedMark)
    }

    func testUnsubmittedCornerChangesOnlyAfterDeadline() throws {
        let task = ribbonTask(status: "pending", grading: .pending)
        let due = try XCTUnwrap(task.dueAt)
        XCTAssertEqual(task.cardStage(at: due.addingTimeInterval(-1)), .unsubmitted)
        XCTAssertEqual(task.cardStage(at: due), .unsubmitted)
        XCTAssertEqual(task.cardStage(at: due.addingTimeInterval(1)), .overdue)
        XCTAssertEqual(ribbonTask(status: "pending", grading: nil, due: "").cardStage(at: .distantFuture), .unsubmitted)
    }

    func testSubmittedCornerRequiresKnownGradingState() {
        let now = Date.distantFuture
        XCTAssertEqual(ribbonTask(status: "submitted", grading: .pending).cardStage(at: now), .awaitingGrading)
        XCTAssertEqual(ribbonTask(status: "submitted", grading: .inProgress).cardStage(at: now), .awaitingGrading)
        let graded = ribbonTask(status: "completed", grading: .graded)
        XCTAssertEqual(graded.cardStage(at: now), .graded)
        XCTAssertNil(graded.mark) // A confirmed grading state does not require a score payload.
        XCTAssertEqual(ribbonTask(status: "submitted", grading: .graded).cardStage(at: now), .graded)
        XCTAssertNil(ribbonTask(status: "submitted", grading: nil).cardStage(at: now))
        XCTAssertNil(ribbonTask(status: "submitted", grading: .excused).cardStage(at: now))
        XCTAssertNil(ribbonTask(status: "completed", grading: .pending).cardStage(at: now))
        XCTAssertNil(ribbonTask(status: "unknown", grading: .pending).cardStage(at: now))
    }

    func testLocalCompletionDoesNotChangeSourceCorner() {
        var task = ribbonTask(status: "pending", grading: .pending)
        task.isLocalDemo = true
        XCTAssertEqual(task.submission(at: .distantFuture, locallyCompleted: true), .localCompletion)
        XCTAssertEqual(task.cardStage(at: .distantFuture), .overdue)
    }

    func testFiltersComposeAndRespectSchoolDates() throws {
        let start = SchoolClock.date(2027, 4, 5)
        let end = SchoolClock.date(2027, 4, 6)
        let roster = ["field": CampusCourse(id: "field", name: "Botany", teacher: nil, room: nil)]
        var row = CampusWork(id: "birch", title: "Birch Survey", due_at: "2027-04-05T16:00:00Z", status: "submitted",
                             description: "", course_id: "field", kind: "task")
        row.work_type = "reflection"
        row.task = CampusTaskDetails(mode: "offline", grading_status: "graded",
                                     score: CampusScore(type: "letter", earned: nil, possible: nil, value: "C+"),
                                     attachments: [], opens_at: nil, submission: nil, feedback: nil)
        let first = TaskRecord(campus: row, roster: roster)
        let other = TaskRecord(campus: CampusWork(id: "other", title: "Birch Marker", due_at: row.due_at,
            status: "pending", description: "", course_id: "field", kind: "task"), roster: roster)
        let range = try XCTUnwrap(TaskDeadlineRange(start: start, end: end))
        let filters = TaskFilters(course: .known("field"), workType: .known("reflection"), mode: .known("offline"),
                                  submission: .submitted, grading: .graded, deadlines: range, query: "  birch ")
        XCTAssertEqual(filters.results(in: [other, first], at: end, completed: ["other"]).map(\.id), ["birch"])
        XCTAssertEqual(first.mark, .letter("C+"))
        XCTAssertTrue(range.contains(end.addingTimeInterval(86_399)))
        XCTAssertFalse(range.contains(start.addingTimeInterval(-1)))
        XCTAssertFalse(range.contains(nil))
        XCTAssertNil(TaskDeadlineRange(start: end, end: start))
        XCTAssertEqual(Set(TaskFilters.workTypes(in: [other, first]).map(\.value)), [.known("reflection"), .unavailable])
    }

    func testNewestPublicationFirstDoesNotChangeWithDeadlineOrCompletion() throws {
        let first = try work("""
          {"id":"early","title":"木材纹理","status":"pending","due_at":"2027-08-05T15:00:00+08:00",
           "published_at":"2027-08-02T09:00:00+08:00","description":""}
          """)
        let later = try work("""
          {"id":"late","title":"树叶分类","status":"pending","due_at":"2027-08-04T15:00:00+08:00",
           "published_at":"2027-08-03T09:00:00+08:00","description":""}
          """)
        let tied = try work("""
          {"id":"tie","title":"树冠宽度","status":"submitted","due_at":"2027-08-03T15:00:00+08:00",
           "published_at":"2027-08-03T09:00:00+08:00","description":""}
          """)
        let undated = CampusWork(id: "aaa", title: "待补数据", due_at: first.due_at, status: "pending",
                                 description: "", course_id: nil, kind: nil)
        let rows = [undated, tied, later, first].map { TaskRecord(campus: $0, roster: [:]) }
        let deadline = try XCTUnwrap(rows[2].dueAt)
        for now in [deadline.addingTimeInterval(-1), deadline.addingTimeInterval(1)] {
            XCTAssertEqual(TaskFilters().results(in: rows, at: now, completed: ["early"]).map(\.id), ["late", "tie", "early", "aaa"])
        }
        XCTAssertEqual(rows[2].submission(at: deadline.addingTimeInterval(-1), locallyCompleted: false), .pending)
        XCTAssertEqual(rows[2].submission(at: deadline.addingTimeInterval(1), locallyCompleted: false), .overdue)
    }

    private func work(_ json: String) throws -> CampusWork {
        try JSONDecoder().decode(CampusWork.self, from: Data(json.utf8))
    }

    private func ribbonTask(status: String, grading: TaskGradingState?, due: String = "2028-04-21T17:00:00+08:00") -> TaskRecord {
        var row = CampusWork(id: "river-transect", title: "溪流剖面测量", due_at: due, status: status,
                             description: "", course_id: nil, kind: "task")
        row.task = grading.map {
            CampusTaskDetails(mode: nil, grading_status: $0.rawValue, score: nil,
                              attachments: nil, opens_at: nil, submission: nil, feedback: nil)
        }
        return TaskRecord(campus: row, roster: [:])
    }
}
