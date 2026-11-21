# School portal data

Memory-only student reads, independent of the optional Rust demo account. Inputs are narrowly projected, same-account WebKit replies; outputs are a dated week, a published gradebook, current-term tasks, and the selected attendance report. No networking, WebKit, credential vault, or persistence in this module.

- `SchoolPortalAccess.swift`: fixed Home origin and document readiness, interaction and failure classifications. `SchoolPortalStore.swift`: select/invalidate the source, verify identity and load scoped records. `openGrades(boundOwner:signIn:reopen:)` reads on a grade visit and tries the existing school session first. If a new login is required, only a matching opt-in may supply the optional foreground sign-in callback. The store independently verifies the student before requesting fresh marks. A new navigation, expiry or account change clears the old snapshot and fences late replies. An owner remembered after relaunch is only for comparison; it grants no read access.
- `SchoolPortalData.swift`: map the approved fields into existing CampusSchedule, CampusCalendar, CourseGradeDetail and TaskRecord presentation contracts. The floating dates use Shanghai time; category weights retain their parent scope. No inferred marks or inferred bells/rotation.
- `SchoolPortalAttendance.swift`: validate the date interval, school-supplied counts/rate, unique course list and one bounded record page. `loadAttendance(_:force:)` loads one category/date/page (default: current school term); `loadAttendanceSubject(_:page:force:)` requires a course actually listed in that student’s active report. A newly mounted view shares an already-started read of the same query; a newer filter supersedes an older reply. Leaving the app still invalidates every ticket immediately. Invalidation also drops all attendance and detail data. Neither operation can request grades or claim a password.
- Consumers: the native [portal reader and page adapters](../../Native/SchoolPortalSync/README.md), app account selection, Planner and Tasks. Dependencies: existing timetable, grade, and task types. Tests: `swift test --filter SchoolPortal` from the iPad project. See the root reusable module index for individual consumers.
- Limits: grades/tasks use the selected school-listed term (the school’s current term by default); attendance uses that term by default or the explicitly selected dates; at most 12 recently viewed weeks in memory, no grades, tasks or attendance on disk. See the separate [saved timetable](../SchoolTimetable/README.md) for the timetable-only exception. Personal Planner records use a separate per-account on-device owner.

Session state is memory-only. `loadTerms()/selectTerm(_:)` share a server-issued semester between Tasks and GPA; unselected semesters never initiate reads. The grade overview has a five-minute reuse limit, invalidated by changes in the loaded task snapshot; manual refresh always reads the school. `loadCollection(_:force:)` stores confirmed list metadata by collection. While the manual sheet is open no academic values are exposed. Reuse after closing requires re-verification of the same owner; logout, denial of a module, expiry, background and changed identity are not cache hits. `restoreLogin(for:signIn:)` verifies identity only and never reads grades.

## Change History

### 2026-11-21 — main-document-outage / local-reminders
Model: Codex. The existing page-readiness check accepts an optional main-frame HTTP status. A 429 or 5xx at the entry or Home is a temporary network failure, never a sign-out or authority to read data. Native callers bind the status to the matching document; subframe responses do not affect it. No school endpoint or request changed.

### 2026-11-21 — annual-timetable / cache-first-today
Model: Codex. Added fenced readTimetableWeek, synchronous onAccountConfirmation and a current-term passive GPA read without recovery or task-score enablement. Dynamic records stay in this store’s memory; only scoped timetable projections may reach the separate annual store.


### 2026-11-21 — login-result-handoff
Model: Codex · Keywords: login-outcomes / manual-handoff
Changed: Distinguish an explicit refusal, a sign-in deadline and an interactive step. `SchoolPortalPage.canContinueManually(at:after:)` preserves a first-party document for review without proving identity. None of these three outcomes initiates another password attempt.
Reason: Keep the school's response available rather than replacing it with a newly loaded form. Interfaces: local issue classification and page handoff only.

### 2026-11-21 — verified-session-cache
Model: Codex · Keywords: verified-session-cache / term-selection
Changed: Cache the verified student’s overview and semester selection, fence late responses and separate startup identity recovery from explicit grade reads.
Reason: Keep account boundaries explicit and avoid blocking navigation on redundant reads. Affected interfaces: SchoolPortalRead; restoreLogin, loadCollection, loadTerms, selectTerm and hasRecentGrades.

### 2026-11-21 — Selected-student attendance
Model: Codex · Keywords: attendance-query / course-allowlist / epoch-fence  
Changed: Added validated attendance projections, the two scoped read operations and invalidation tests. Reason: show records in the native app without re-opening the website or retaining another account’s records. Affected interfaces: in-process student reader/store only.
### 2026-11-21 — Distinct password sign-in boundary
Model: Codex · Keywords: same-student-grant / cold-grade-visit  
Changed: Added same-owner enrollment-name reading and an optional bound sign-in callback to `openGrades(boundOwner:signIn:reopen:)`. A cold-start comparison anchor cannot read records; every new sign-in must independently match the bound owner. Reason: re-entering an expired Home shell is not reauthentication. Affected interfaces: native-only reader operation and scoped store; no password storage in Core.
### 2026-11-21 — Foreground grade entry
Model: Codex · Keywords: confirmed-expiry / same-student / navigation-epoch  
Changed: Added `SchoolPortalPage.issue(at:foreground:loading:)`, `openGrades(reopen:)`, navigation and suspension boundaries. Reason: waiting for a web document is not evidence of expiry. A timer, an explicit logout, an unknown owner or a rejected second read cannot initiate another entry. A different owner requires explicit confirmation. Affected interfaces: in-process store/reader only. Tests: `SchoolPortalAccessTests`, `SchoolPortalTests` and the [loopback WebKit fixture](../../../Tests/SchoolPortalSync/README.md).
### 2026-11-21 — Published task marks
Model: Codex · Keywords: task-mark / session-consent  
Changed: The GPA action enables optional task-list marks for the current verified session; the former metadata-only request/cache is invalidated and late replies are ignored. The next task read carries that choice, independently of overview availability. Unexpected marks on a metadata-only read are rejected. Reason: published marks were previously replaced with nil. Affected interfaces: `SchoolPortalRead.tasks(includeScores:)`, `SchoolPortalTasks.Row.score`, typed store task key. No storage changes.

### 2026-11-21
Model: Codex · Keywords: schoolis-read / portal-epoch / published-grades  
Changed: Added real-mode projections and identity-fenced reads. Reason: a demo session is not a Schoolis login. Affected interfaces: native-only `SchoolPortalRead` and `SchoolPortalStore`; no service route.
