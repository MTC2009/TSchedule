# Task presentation and reads

- **Responsibility:** Project the authenticated work payload or the built-in sample into task cards and detail; keep task-only filters, term decoding and complete-page validation out of SwiftUI. No task submissions, GPA calculation, or file retrieval.
- **Inputs:** Current `CampusWork` rows and the active `CampusCourse` roster, or `DemoTasks`; Shanghai clock, optional facets, and local demo completion IDs. Historical pages are supplied by an authorized reader.
- **Outputs / entry points:** `TaskRecord(campus:roster:)` and `DemoTasks.records`; `TaskRecord.mark` for the published result, `estimatedMark` only for an authorized preview, and `cardStage(at:)` for the optional source-only card stage. `TaskFilters.results(in:at:completed:preservingUndatedSourceOrder:)`, `TaskTermDirectory` and `TaskCatalog.load(term:read:)` compose reading. `CampusConnection.cachedTaskList` exposes the full current cache; `readTaskPage(_:scope:)` is a scoped GET that does not persist history or read grades.
- **Files:** `TaskPresentation.swift` keeps optional detail and grading separate from submission. `TaskFilters.swift` matches facets, status, title and Shanghai deadline days, then sorts by original publication time, newest first. Equal known timestamps use a stable ID. Undated rows follow, in the school's list order for the portal or stable ID order for other sources. `TaskCatalog.swift` validates paging and term IDs. `DemoTasks.swift` enriches current sample tasks and supplies one archived sample without altering Planner's dated entries.
- **Dependencies / consumers:** Existing campus auth/offline snapshot, `SchoolClock` and shared `GradeMark` formatting. Consumed by the [native Tasks page](../../Native/Tasks/README.md) and by task, offline and client integration tests.
- **Limits:** Old caches may lack a publication date, a task classification or a grading state. They stay readable and can backfill on the next authorized ordinary check. No deadline or grade is fabricated. The current term is cached; a past term is fetched on selection, held for the current page visit only, and never exposed as a partial page. Legacy catalog endpoints without task term metadata cannot advertise prior terms.
- **Test:** Run `swift test` from the iPad project. See `TaskPresentationTests`, `TaskCatalogTests`, `CampusOfflineTests` and `CampusConnectionTests` (loopback test enabled with `XIAOBAO_TEST_ORIGIN`).

A future authorized provider can explicitly report `grading_status: graded_unpublished`. Only for that state may it separately send `released_score_estimate`, a valid numeric score expressly approved to display to that student. Without it, the detail shows the pending publication state without a number. The client never treats an ordinary score on an unpublished record as an estimate, queries the gradebook for a hidden mark, or reconstructs one from aggregates. The current demo service does not emit this authority signal.

## Change History

### 2026-11-21 — Newest published task first
Model: Codex · Keywords: task-grid / publication-order  
Changed: Reversed only the publication-time comparison, and added the optional undated-source-order policy (default: stable ID). Reason: new assignments belong at the top; identifiers and due dates do not establish when undated portal records were published. Affected interface: `TaskFilters.results`, native lists only.
Verification: The former ordering failed the new newest-first assertion. After the fix, all 179 Swift tests (including loopback integration) and 13 reader tests passed; the signed Release build was updated in place and relaunched on iPad Air Simulator. No live student records were inspected.

### 2026-11-20 — Authorized task-score preview
Model: Codex · Keywords: task-publication / authorized-score-preview  
Reason: Distinguish grading from publication, and never treat an unapproved grade as an estimate.  
Changed: Decode the explicit pending-publication state and separately validate the provider's released estimate. The preview remains unavailable to task scores, grading completion and GPA.  
Affected interfaces: Optional Swift payload field and `TaskRecord.estimatedMark`; existing task readers, endpoints and permissions are unchanged.  
Verification: Projection tests cover an authorized preview, invalid estimates and protection of unreleased marks as part of the passing 168-test Swift suite.

### 2026-11-20
Model: Codex · Keywords: task-facets / task-term-history / source-grading / offline-task-catalog  
Changed: Added the normalized task projection, composable filters, stable publication order, optional answer and feedback, and validated historical reads.  
Reason: The same task page needs accurate options and details for both offline and connected reading without touching submission or grades.  
Affected interfaces: Native task projection and the optional fields on the existing work payload. No new route, database table, dependency or environment variable.

### 2026-11-20 — Card stage
Model: Codex · Keywords: task-corner-ribbon / deadline / source-status  
Changed: Project the card stage from published grading, the source submission state and the supplied clock. Only confirmed submission with pending or in-progress grading gets the waiting stage. Unknown grading does not imply waiting, and the device-only completion flag is not an input.  
Reason: The card needs one reliable badge without merging the detail or filter states.  
Affected interfaces: Added `TaskRecord.cardStage(at:)` and `TaskCardStage` to the existing native projection; no change to the work payload or storage.

### 2026-11-21 — bilingual UI / verbatim school data
Model: Codex. Task filter fallbacks and app-defined enum labels are localized; portal-supplied work types use the verbatim display path even when they match a fixture type code. IDs, filter values, task titles and grades are unchanged. [Language boundary and regression tests](../Localization/README.md).
