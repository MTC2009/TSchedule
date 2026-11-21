import Foundation
import Observation

enum SchoolPortalRead: Hashable {
    case identity, enrollmentName, week(String, String), grades, detail(term: String, subject: String, cls: String, type: Int)
    case collection(SchoolPortalCollection)
    case terms, archivedGrades(String), archivedTasks(String, includeScores: Bool)
    case tasks(includeScores: Bool)
    case attendance(SchoolPortalAttendanceQuery), attendanceSubject(String, from: String, to: String, page: Int)
}

/// Read-only, memory-only, and independent of the demo account/token/cache protocol.
/// An epoch also fences replies for a logout followed by a login to the *same* account.
@Observable @MainActor final class SchoolPortalStore {
    typealias Reader = @MainActor (SchoolPortalRead, String?) async throws -> Data
    private let reader: Reader
    private(set) var selected: Bool
    private(set) var owner: String?
    private(set) var epoch = UUID()
    // Unverified document transitions have no private navigation to discard. Resetting the
    // entire split view for each of them can swallow the sidebar tap made during startup.
    private(set) var navigationEpoch = UUID()
    private(set) var identityIssue: SchoolPortalIssue?
    private(set) var isRecoveringSession = false
    // An opaque comparison anchor, never authority to read. It is not stored on disk.
    private var lastVerifiedOwner: String?
    private struct ManualReview {
        let owner: String, at: Date
        let weeks: [String: SchoolPortalWeek], weekOrder: [String]
        let directory: SchoolPortalTerms?, selection: String?, activeTerm: TermSnapshot
        let collections: [SchoolPortalCollection: [SchoolPortalListItem]]
        let attendance: SchoolPortalAttendance?, query: SchoolPortalAttendanceQuery?
    }
    @ObservationIgnored private var manualReview: ManualReview?
    private var expiredOwner: String?
    private var expiredFromEpoch: UUID?
    private(set) var pending = Set<SchoolPortalRead>()
    private(set) var issues: [SchoolPortalRead: SchoolPortalIssue] = [:]
    private(set) var weeks: [String: SchoolPortalWeek] = [:]
    private(set) var grades: SchoolPortalGrades?
    private var gradesChecked: Date?
    private(set) var groups: [String: [SchoolPortalGrades.Group]] = [:]
    private(set) var tasks: SchoolPortalTasks?
    private(set) var attendanceQuery: SchoolPortalAttendanceQuery?
    private(set) var attendance: SchoolPortalAttendance?
    private(set) var attendanceSubjectKey: SchoolPortalRead?
    private(set) var attendanceSubject: SchoolPortalAttendance.Records?
    private(set) var allowsTaskScores = false
    private(set) var collections: [SchoolPortalCollection: [SchoolPortalListItem]] = [:]
    func loadCollection(_ collection: SchoolPortalCollection, force: Bool = false) async {
        guard force || collections[collection] == nil else { return }
        await load([SchoolPortalListItem].self, .collection(collection), sharedAcrossViews: true) { rows in
            guard rows.count <= 3200, rows.allSatisfy({ !$0.id.isEmpty && !$0.title.isEmpty }),
                  Set(rows.map(\.id)).count == rows.count else { throw SchoolPortalIssue.format }
            self.collections[collection] = rows
        } clear: { self.collections[collection] = nil }
    }

    private(set) var terms: SchoolPortalTerms?
    private(set) var selectedTermID: String?
    var gradeRead: SchoolPortalRead { selectedTermID.map(SchoolPortalRead.archivedGrades) ?? .grades }
    var taskRead: SchoolPortalRead {
        selectedTermID.map { .archivedTasks($0, includeScores: allowsTaskScores) } ?? .tasks(includeScores: allowsTaskScores)
    }
    private struct TermSnapshot {
        let tasks: SchoolPortalTasks?, grades: SchoolPortalGrades?, checked: Date?, allowsScores: Bool
    }
    // Selection is shared by Tasks and GPA; nil means the server's current term.
    @ObservationIgnored private var termCache: [String?: TermSnapshot] = [:]
    var selectedTermTitle: String? {
        terms.flatMap { list in list.terms.first { $0.id == (selectedTermID ?? list.current) }?.name }
    }
    func loadTerms() async {
        guard terms == nil else { return }
        await load(SchoolPortalTerms.self, .terms, sharedAcrossViews: true) { list in
            guard !list.terms.isEmpty, list.terms.count <= 128, list.terms.contains(where: { $0.id == list.current }),
                  Set(list.terms.map(\.id)).count == list.terms.count,
                  list.terms.allSatisfy({ !$0.id.isEmpty && !$0.name.isEmpty }) else { throw SchoolPortalIssue.format }
            self.terms = list
        } clear: { self.terms = nil }
    }
    func selectTerm(_ id: String?) {
        guard let terms, id == nil || terms.terms.contains(where: { $0.id == id }) else { return }
        let next = id == terms.current ? nil : id
        guard next != selectedTermID else { return }
        termCache[selectedTermID] = .init(tasks: tasks, grades: grades, checked: gradesChecked, allowsScores: allowsTaskScores)
        for key in [taskRead, gradeRead] { requests[key] = nil; pending.remove(key); issues[key] = nil }
        invalidateDetails()
        selectedTermID = next
        let saved = termCache[next]
        tasks = saved?.tasks; grades = saved?.grades; gradesChecked = saved?.checked; allowsTaskScores = saved?.allowsScores ?? false
    }
    func hasRecentGrades(at now: Date = Date()) -> Bool {
        guard grades != nil, let gradesChecked else { return false }
        return (0..<300).contains(now.timeIntervalSince(gradesChecked))
    }
    private(set) var gradeRevision = UUID()
    @ObservationIgnored private var requests: [SchoolPortalRead: UUID] = [:]
    @ObservationIgnored private var weekOrder: [String] = []

    init(selected: Bool = false, reader: @escaping Reader) { self.selected = selected; self.reader = reader }

    func select(_ value: Bool) {
        guard selected != value else { return }
        selected = value; invalidate()
    }

    func invalidate(_ reason: SchoolPortalIssue? = nil) {
        if owner != nil { navigationEpoch = UUID() }
        manualReview = nil
        let prior = owner ?? lastVerifiedOwner
        expiredOwner = reason == .expired && !isRecoveringSession ? prior : nil
        expiredFromEpoch = expiredOwner == nil ? nil : epoch
        lastVerifiedOwner = nil; isRecoveringSession = false
        epoch = UUID(); owner = nil; pending = []; requests = [:]; issues = [:]
        identityIssue = reason == .expired && expiredOwner == nil ? .login : reason
        weeks = [:]; weekOrder = []; grades = nil; gradesChecked = nil; groups = [:]; tasks = nil; gradeRevision = UUID()
        attendanceQuery = nil; attendance = nil; attendanceSubjectKey = nil; attendanceSubject = nil
        allowsTaskScores = false; terms = nil; selectedTermID = nil; termCache = [:]; collections = [:]
    }

    /// Backgrounding hides all records. Keep only the in-memory comparison anchor
    /// for a subsequently rejected session; logout and manual navigation still drop it.
    func suspend() {
        let anchor = owner ?? lastVerifiedOwner, candidate = expiredOwner
        let reason = identityIssue ?? .notReady
        invalidate(reason)
        if reason == .expired { expiredOwner = candidate; identityIssue = candidate == nil ? .login : .expired }
        else if reason.permitsIdentityRecheck { lastVerifiedOwner = anchor }
    }

    /// Loading another document hides records immediately but is not a logout.
    /// An explicit account action clears the old anchor before starting navigation.
    func beginManualReview() {
        let snapshot = owner.map { ManualReview(owner: $0, at: Date(), weeks: weeks, weekOrder: weekOrder,
            directory: terms, selection: selectedTermID,
            activeTerm: .init(tasks: tasks, grades: grades, checked: gradesChecked, allowsScores: allowsTaskScores),
            collections: collections, attendance: attendance, query: attendanceQuery) }
        beginNavigation()
        manualReview = snapshot
    }

    func beginNavigation() {
        let snapshot = manualReview
        let anchor = owner ?? lastVerifiedOwner ?? expiredOwner
        invalidate(.notReady)
        manualReview = snapshot
        lastVerifiedOwner = anchor
    }

    private struct Reply<T: Decodable>: Decodable {
        let owner: String?
        let error: String?
        let value: T?
    }
    private struct Empty: Decodable {}

    func verify() async {
        guard selected, !isRecoveringSession, expiredOwner == nil, pending.insert(.identity).inserted else { return }
        let ticket = epoch
        defer { if ticket == epoch { pending.remove(.identity) } }
        do {
            let next = try await verifiedOwner()
            guard ticket == epoch else { return }
            if let previous = owner ?? lastVerifiedOwner, previous != next {
                invalidate(.changed); return
            }
            owner = next; lastVerifiedOwner = next; identityIssue = nil
            if let saved = manualReview, saved.owner == next, (0..<300).contains(Date().timeIntervalSince(saved.at)) {
                weeks = saved.weeks; weekOrder = saved.weekOrder; collections = saved.collections
                attendance = saved.attendance; attendanceQuery = saved.query
                terms = saved.directory; selectedTermID = saved.selection
                tasks = saved.activeTerm.tasks; grades = saved.activeTerm.grades; gradesChecked = saved.activeTerm.checked
                allowsTaskScores = saved.activeTerm.allowsScores
            }
            manualReview = nil
        } catch {
            guard ticket == epoch else { return }
            // If identity cannot be established, no profile's school records stay on screen.
            let issue = error as? SchoolPortalIssue ?? .network
            let anchor = owner ?? lastVerifiedOwner
            invalidate(issue)
            if issue.permitsIdentityRecheck { lastVerifiedOwner = anchor }
        }
    }

    /// A separate foreground startup opt-in may restore identity, never request a gradebook.
    func restoreLogin(for expected: String, signIn: @MainActor () async throws -> Void) async {
        guard selected, owner == nil, !isRecoveringSession,
              identityIssue == .login || (identityIssue == .expired && expiredOwner == expected) else { return }
        let ticket = epoch
        isRecoveringSession = true
        defer { if epoch == ticket { isRecoveringSession = false } }
        do {
            try await signIn()
            try Task.checkCancellation()
            guard epoch == ticket else { return }
            let actual = try await verifiedOwner()
            try Task.checkCancellation()
            guard epoch == ticket else { return }
            guard actual == expected else { throw SchoolPortalIssue.changed }
            expiredOwner = nil; expiredFromEpoch = nil
            owner = actual; lastVerifiedOwner = actual; identityIssue = nil
        } catch {
            guard epoch == ticket, !(error is CancellationError) else { return }
            invalidate(error as? SchoolPortalIssue ?? .network)
        }
    }

    private func verifiedOwner() async throws -> String {
        let result = try await reply(Empty.self, .identity, nil)
        guard let id = result.owner, id.count == 64, id.allSatisfy({ $0.isHexDigit }) else { throw SchoolPortalIssue.format }
        return id
    }

    /// Explicit enrollment only. The student cannot provide a different account's login name.
    func enrollmentName(for expected: String) async throws -> String {
        let ticket = epoch
        guard selected, owner == expected else { throw SchoolPortalIssue.changed }
        let result = try await reply(String.self, .enrollmentName, expected)
        guard selected, ticket == epoch, owner == expected, !Task.isCancelled else { throw CancellationError() }
        guard let name = result.value, !name.isEmpty, name.utf8.count <= 512 else { throw SchoolPortalIssue.unavailable }
        return name
    }

    /// An opted-in device binding can compare a future identity, never authorize a data read.
    func rememberComparison(_ expected: String) {
        guard selected, owner == nil, identityIssue == nil, lastVerifiedOwner == nil else { return }
        lastVerifiedOwner = expected
    }

    private func reply<T: Decodable>(_ type: T.Type, _ key: SchoolPortalRead, _ owner: String?) async throws -> Reply<T> {
        let data = try await reader(key, owner)
        let decoded: Reply<T>
        do { decoded = try JSONDecoder().decode(Reply<T>.self, from: data) } catch { throw SchoolPortalIssue.format }
        if let error = decoded.error { throw SchoolPortalIssue(rawValue: error) ?? .unavailable }
        if let owner, decoded.owner != owner { throw SchoolPortalIssue.changed }
        return decoded
    }

    private func load<T: Decodable>(_ type: T.Type, _ key: SchoolPortalRead, sharedAcrossViews: Bool = false,
                apply: (T) throws -> Void, clear: () -> Void) async {
        guard selected, !Task.isCancelled, let owner, pending.insert(key).inserted else { return }
        let ticket = epoch, request = UUID()
        requests[key] = request
        func current() -> Bool { ticket == epoch && requests[key] == request }
        // A newly mounted attendance view observes the same in-flight query. Its predecessor
        // disappearing must not discard the only response. A new filter, logout or suspension
        // always invalidates the ticket, regardless of which view started it.
        func canApply() -> Bool { current() && (sharedAcrossViews || !Task.isCancelled) }
        defer { if current() { pending.remove(key); requests[key] = nil } }
        do {
            let result = try await reply(type, key, owner)
            guard canApply() else { return }
            guard let value = result.value else { throw SchoolPortalIssue.format }
            try apply(value); issues[key] = nil
        } catch {
            guard canApply() else { return }
            let issue = error as? SchoolPortalIssue ?? .network
            if issue == .expired || issue == .login || issue == .changed {
                invalidate(issue)
            } else {
                clear(); issues[key] = issue
            }
        }
    }

    static func weekKey(_ date: Date) -> SchoolPortalRead {
        let week = TimetableWeek(containing: date)
        return .week(SchoolClock.key(week.start), SchoolClock.key(week.end))
    }

    /// Forget the superseded read ticket as well as its data: the first filter may finish after the second.
    private func discardAttendanceRead(_ key: SchoolPortalRead?) {
        guard let key else { return }
        requests[key] = nil; pending.remove(key); issues[key] = nil
    }

    func loadAttendance(_ query: SchoolPortalAttendanceQuery, force: Bool = false) async {
        guard selected, owner != nil, !Task.isCancelled, (1...1_000_000).contains(query.page) else { return }
        let key = SchoolPortalRead.attendance(query)
        guard !pending.contains(key), force || attendanceQuery != query || attendance == nil else { return }
        if let old = attendanceQuery { discardAttendanceRead(.attendance(old)) }
        discardAttendanceRead(attendanceSubjectKey)
        attendanceQuery = query; attendance = nil; attendanceSubject = nil; attendanceSubjectKey = nil
        await load(SchoolPortalAttendance.self, key, sharedAcrossViews: true) { value in
            try value.validate(for: query); self.attendance = value
        } clear: { self.attendance = nil }
    }

    /// Only the selected course returned for this student and these exact dates may load its details.
    func loadAttendanceSubject(_ subject: String, page: Int, force: Bool = false) async {
        guard !Task.isCancelled, let report = attendance, attendanceQuery?.category == .classroom,
              report.courses.contains(where: { $0.id == subject }), (1...1_000_000).contains(page) else { return }
        let key = SchoolPortalRead.attendanceSubject(subject, from: report.from, to: report.to, page: page)
        guard !pending.contains(key), force || attendanceSubjectKey != key || attendanceSubject == nil else { return }
        discardAttendanceRead(attendanceSubjectKey); attendanceSubject = nil; attendanceSubjectKey = key
        await load(SchoolPortalAttendance.Records.self, key, sharedAcrossViews: true) { value in
            try value.validate(page: page); self.attendanceSubject = value
        } clear: { self.attendanceSubject = nil }
    }
    func week(on date: Date) -> SchoolPortalWeek? { weeks[SchoolClock.key(TimetableWeek(containing: date).start)] }

    func loadWeek(_ date: Date, force: Bool = false) async {
        let week = TimetableWeek(containing: date), start = SchoolClock.key(week.start)
        guard force || weeks[start] == nil else { return }
        await load([SchoolPortalWeek.Row].self, Self.weekKey(date), sharedAcrossViews: true) { rows in
            self.weeks[start] = try SchoolPortalWeek(week: week, rows: rows)
            self.weekOrder.removeAll { $0 == start }; self.weekOrder.append(start)
            if self.weekOrder.count > 12 { self.weeks[self.weekOrder.removeFirst()] = nil }
        } clear: { self.weeks[start] = nil }
    }

    /// Only a foreground grade visit or explicit refresh may initiate recovery.
    /// The navigation callback must use the school's normal entry; credentials never enter this store.
    func openGrades(boundOwner: String? = nil, signIn: (@MainActor (String) async throws -> Void)? = nil,
                    reopen: @MainActor () async throws -> Void) async {
        guard selected, !Task.isCancelled, !isRecoveringSession, !pending.contains(gradeRead) else { return }
        // After relaunch an already-enrolled student may deliberately tap GPA on a
        // known login screen. This is a new sign-in, not a claim that a URL proved expiry.
        let direct = owner == nil && expiredOwner == nil && identityIssue == .login && signIn != nil && boundOwner != nil
        guard let requestedOwner = owner ?? expiredOwner ?? (direct ? boundOwner : nil) else { return }
        let initialTerm = selectedTermID
        if owner != nil {
            let origin = epoch
            await loadGrades()
            // A late read cannot recover a different login, even for the same student.
            guard expiredFromEpoch == origin else { return }
        }
        guard !Task.isCancelled, direct || (identityIssue == .expired && expiredOwner == requestedOwner) else { return }
        let ticket = epoch
        isRecoveringSession = true
        defer { if ticket == epoch { isRecoveringSession = false } }
        do {
            let actual: String
            do {
                if direct { throw SchoolPortalIssue.login }
                try await reopen()
                guard ticket == epoch else { return }
                try Task.checkCancellation()
                actual = try await verifiedOwner()
            } catch let issue as SchoolPortalIssue where issue == .login || issue == .expired {
                guard ticket == epoch else { return }
                try Task.checkCancellation()
                guard boundOwner == requestedOwner, let signIn else { throw issue }
                try await signIn(requestedOwner)
                guard ticket == epoch else { return }
                try Task.checkCancellation()
                actual = try await verifiedOwner()
            }
            guard ticket == epoch else { return }
            try Task.checkCancellation()
            guard actual == requestedOwner else { throw SchoolPortalIssue.changed }
            expiredOwner = nil; expiredFromEpoch = nil
            owner = actual; lastVerifiedOwner = actual; identityIssue = nil
            if let initialTerm {
                await loadTerms()
                guard epoch == ticket, terms?.terms.contains(where: { $0.id == initialTerm }) == true else { return }
                selectTerm(initialTerm)
            }
            await loadGrades()
        } catch {
            guard ticket == epoch else { return }
            // A cancelled visit has not proved either sign-in or sign-out. Keep only its
            // original comparison anchor; a later deliberate visit can start a new attempt.
            if error is CancellationError { return }
            let issue = error as? SchoolPortalIssue ?? .network
            invalidate(issue)
            if issue.permitsIdentityRecheck { lastVerifiedOwner = requestedOwner }
        }
    }

    /// Entering the real GPA page is the scoped request to read published grades.
    func loadGrades() async {
        guard selected, owner != nil else { return }
        if !allowsTaskScores {
            // The old metadata-only snapshot (or a late reply) cannot satisfy a
            // score-enabled read. Do not visit the task list until it is opened.
            let old = taskRead
            requests[old] = nil; pending.remove(old); issues[old] = nil
            tasks = nil; allowsTaskScores = true
        }
        await load(SchoolPortalGrades.self, gradeRead) { values in
            guard self.selectedTermID == nil || values.termID == self.selectedTermID,
                  !values.term.isEmpty, Set(values.courses.map(\.id)).count == values.courses.count else { throw SchoolPortalIssue.format }
            self.grades = values; self.gradesChecked = Date(); self.invalidateDetails()
        } clear: { self.grades = nil; self.gradesChecked = nil; self.invalidateDetails() }
    }

    private func invalidateDetails() {
        gradeRevision = UUID(); groups = [:]
        for key in pending.union(issues.keys) {
            if case .detail = key { requests[key] = nil; pending.remove(key); issues[key] = nil }
        }
    }

    /// An in-memory input for the existing what-if form, never passed to a cache writer.
    func trialInput(_ book: SchoolPortalGrades) -> SavedCampusGrades? {
        guard owner != nil, let checked = gradesChecked, grades?.termID == book.termID else { return nil }
        let courses = book.courses.map { course in
            CampusGrade(course_id: course.id, published_score: course.score, published_gpa: nil,
                        assessments: groups[course.id]?.flatMap(\.items) ?? [])
        }
        let roster = book.courses.map { CampusCourseVersion(course_id: $0.id, name: $0.name, revision: "") }
        return .init(grades: .init(term: book.term, published_gpa: book.gpa, courses: courses), roster: roster,
                     version: nil, updated: checked, checked: checked)
    }
    func detailKey(_ course: SchoolPortalGrades.Course) -> SchoolPortalRead? {
        guard let grades, let listed = grades.courses.first(where: { $0.id == course.id }), let cls = listed.cls else { return nil }
        return .detail(term: grades.termID, subject: listed.subject, cls: cls, type: listed.type)
    }
    func loadDetail(_ course: SchoolPortalGrades.Course) async {
        guard let key = detailKey(course), groups[course.id] == nil else { return }
        let generation = gradeRevision
        await load([SchoolPortalGrades.Group].self, key) { value in
            if self.gradeRevision == generation { self.groups[course.id] = value }
        } clear: { if self.gradeRevision == generation { self.groups[course.id] = nil } }
    }
    func loadTasks(force: Bool = false) async {
        guard force || tasks == nil else { return }
        let includeScores = allowsTaskScores
        await load(SchoolPortalTasks.self, taskRead, sharedAcrossViews: true) { value in
            guard Set(value.rows.map(\.id)).count == value.rows.count,
                  value.rows.allSatisfy({ $0.score == nil || (includeScores && $0.grading == "graded") })
            else { throw SchoolPortalIssue.format }
            if let before = self.tasks, before.rows != value.rows { self.gradesChecked = nil }
            self.tasks = value
        } clear: { self.tasks = nil }
    }
}
