import Foundation

/// Without explicit dates the reader uses the school's confirmed current term, not the demo calendar.
struct SchoolPortalAttendanceQuery: Equatable, Hashable {
    var category: AttendanceCategory = .classroom
    var from: String? = nil
    var to: String? = nil
    var page = 1
    var status: AttendanceStatus? = nil
}

struct SchoolPortalAttendance: Decodable {
    struct Counts: Decodable {
        let native: AttendanceCounts
        private enum CodingKeys: String, CodingKey { case present, late, early, absent }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            func count(_ key: CodingKeys) throws -> Int {
                let n = try c.decode(Int.self, forKey: key)
                guard (0...10_000_000).contains(n) else { throw SchoolPortalIssue.format }
                return n
            }
            native = try .init(present: count(.present), late: count(.late), early: count(.early), absent: count(.absent))
        }
    }
    struct Course: Decodable, Identifiable {
        let id, name: String
        let counts: Counts
        var row: AttendanceCourseRow { .init(course: .init(id: id, name: name, counts: counts.native)) }
    }
    struct Record: Decodable, Identifiable {
        let id: Int
        let name, start: String
        let end: String?
        let status: AttendanceStatus
        let allDay: Bool
        let excused: Bool?
    }
    struct Records: Decodable {
        let records: [Record]
        let recordTotal: Int
        func validate(page: Int) throws {
            guard (1...1_000_000).contains(page), (0...10_000_000).contains(recordTotal),
                  records.count == min(10, max(0, recordTotal - (page-1)*10)),
                  Set(records.map(\.id)).count == records.count,
                  records.allSatisfy({ !$0.name.isEmpty && campusInstant($0.start) != nil &&
                      ($0.end == nil || $0.end.flatMap(campusInstant) != nil) }) else { throw SchoolPortalIssue.format }
        }
    }
    let from, to, termStart, termEnd: String
    let counts: Counts
    let rate: Double?
    let courses: [Course]
    let records: [Record]
    let recordTotal: Int
    var list: Records { .init(records: records, recordTotal: recordTotal) }
    var semester: SchoolDateRange? {
        guard let a = SchoolClock.parseSchoolDate(termStart), let b = SchoolClock.parseSchoolDate(termEnd), a <= b else { return nil }
        return .init(start: a, end: b)
    }
    func validate(for query: SchoolPortalAttendanceQuery) throws {
        guard semester != nil, let a = SchoolClock.parseSchoolDate(from), let b = SchoolClock.parseSchoolDate(to), a <= b,
              from == (query.from ?? termStart), to == (query.to ?? termEnd),
              rate.map({ $0.isFinite && (0...1).contains($0) }) != false,
              Set(courses.map(\.id)).count == courses.count, courses.allSatisfy({ !$0.id.isEmpty && !$0.name.isEmpty }),
              query.category == .classroom ? (query.page == 1 && recordTotal == 0) : courses.isEmpty else { throw SchoolPortalIssue.format }
        try list.validate(page: query.page)
    }
}
