import Foundation

/// An allowlist, deliberately not Codable on the wire model: a future grade/answer
/// field must never become persistent merely because the online card gains it.
struct SavedAssignment: Codable, Equatable {
    let localID: UUID
    let id, title, status: String
    let due, published, course, courseName, kind: String?
    let eligible: Bool

    init(_ row: SchoolPortalTasks.Row, preserving previous: Self?) {
        localID = previous?.localID ?? UUID()
        id = row.id; title = row.title; status = row.status
        due = row.due; published = row.published; course = row.course
        courseName = row.courseName; kind = row.kind
        eligible = row.deadlineEligible == true && status == "pending" && due != nil
    }

    var displayRow: SchoolPortalTasks.Row {
        .init(id: id, title: title, status: status, due: due, published: published, course: course,
              courseName: courseName, kind: kind, grading: nil, score: nil, deadlineEligible: eligible)
    }
}

struct AssignmentDeadline: Equatable, Sendable {
    static let prefix = "tschedule.assignment.v1."
    static let leadMinutes = 60
    let id: String
    let fire: Date
    let title: String?

    static func make(_ rows: [SavedAssignment], now: Date, showTitles: Bool) -> [Self] {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return rows.compactMap { row -> Self? in
            guard row.eligible, let value = row.due, let end = iso.date(from: value) else { return nil }
            let fire = end.addingTimeInterval(-Double(leadMinutes * 60))
            guard fire > now else { return nil } // Never replay a missed reminder after relaunch.
            return .init(id: prefix + row.localID.uuidString, fire: fire, title: showTitles ? row.title : nil)
        }.sorted { ($0.fire, $0.id) < ($1.fire, $1.id) }
    }
}
