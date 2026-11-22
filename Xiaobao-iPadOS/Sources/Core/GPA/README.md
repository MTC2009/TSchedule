# GPA presentation data

- **Responsibility:** Project the local gradebook or the signed-in account's saved grades into a term GPA and per-course breakdown. Calculate course forecasts separately, from explicit assumptions. This module does not fetch or store official grades; its own store persists only student-authored what-ifs. School publication snapshots have a separate [grade cache](../SchoolPortalData/README.md). The on-device portal reader can pass explicitly published group rows; the existing demo service still uses flat assessments.
- **Inputs:** `Gradebook` / `CourseReport` for the local mode; `CampusGrades`, `SavedCampusGrades` and the roster for connected mode. Grade calculation, normalization of percentages, and dated chart points reuse the app's existing grade calculator and assessment-history code.
- **Outputs and entry points:** `CampusGPA.swift` projects `CampusGrades.gpaReadout` into a published GPA, an automatic credit-weighted estimate, or the ordered reasons no estimate is possible. `GradePresentation.swift` handles `Gradebook.gpaSummary(termID:weighted:)` for the built-in sample, `CourseGradeDetail(report:)` and `SavedCampusGrades.courseGradeDetails`. A course exposes the published score, optional class, GPA and first-publication time, known categories, rows and lazily produced actual history points. `AssessmentWeight` preserves whether a fraction is scoped to a course or group. `CourseForecast.swift` validates `AssessmentForecast` and provides `CourseForecast.project(current:groups:estimates:)` (overall result plus available edited-group subtotals); `calculate` remains a result-only convenience. `ForecastGroups.swift` defines the tree and a transient count/sum of released numeric items for each leaf.
- **Consumers:** The [native GPA page](../../Native/GPA/README.md), its local adapter, and grade projection tests. See the [reuse index](../../../../REUSABLE_MODULES.md#gpa-presentation).
- **Calculation and limits:** A draft belongs to a leaf, not a parent. Existing released task percentages and one or more hypothetical percentages count equally within a leaf. If a published group percentage and the count of its contributing released numeric items are known, they can anchor the existing average. If some rows are withheld, use only directly normalizable released marks, never solve for the withheld row. Recursively combine scored siblings using their relative published weights; ungraded groups do not consume weight until they have a score. A zero is a score. A Schoolis group with no visible graded rows starts with the added scores even if a published total exists, following OpenGCalc. Zero remains a counted score. The published course total is optional for numeric portal courses. Missing weights can still allow a group subtotal; nonnumeric courses do not gain a made-up percentage. Local categories need their own published weights to roll up to a course; flat service records do not supply a group directory.
- **Test:** From the iPad project, run `swift test`; see `GradePresentationTests`, `CourseForecastTests`, `StudentChartTests`, `CampusOfflineTests` and `CampusConnectionTests`.

### Saved course forecasts and term estimate

`CourseForecastStore` accepts a live, verified owner/term/session and a course ID. It atomically saves only the draft ID, hypothetical name/score and group address to an independent protected, backup-excluded file. Derived totals and all school marks remain in memory. Group anchors use a digest of lineage; a missing or ambiguous anchor requires reselecting rather than assigning the entry to a different group. The same owner and term can reopen the archive across launches; refreshing is not a write. `restore(in:)` clears only that term. A failed read never overwrites a damaged archive.

`TermForecastGPA.calculate` combines the forecasted totals with the unchanged published percentages of other eligible courses. Its scale and weights are the mathematical model in [OpenGCalc](https://github.com/Haoxuan1016/OpenGCalc/blob/7207ed6e5e8c48c6e2406cad7500105a99e2f25c/background.js#L1135-L1196), not confirmation of a school policy. Grades without a percentage are not treated as zero. This distinct readout is only visible when there is a calculated forecast for an included course and every forecasted included course has a result.

### Optional authorized GPA inputs

A valid published term GPA takes priority outside a deliberately activated course forecast. Otherwise the complete, authorized term roster needs a finite `gpa_credits` on each course. An explicit zero excludes a course; an absent value does not. A published course GPA supplies the course points directly. For other included courses, a published numeric total with a known maximum is converted using the term's explicit `gpa_scale` bands (`minimum_percent`, `grade_points`); the bands must cover zero with unique cutoffs and non-decreasing points. The client does not infer AP, course inclusion or a conversion scale. Task previews and forecast drafts never enter this official-grade path.

The Swift client accepts these optional fields on existing grade payloads. The term policy travels with each grade snapshot or delta; omission clears the rule rather than reusing an older one. A future authorized provider must include the scale in the term version and credits in course revisions. Older caches and the current Rust demo source need no migration; absent fields simply make the connected estimate unavailable. No new API call is made.

## Change History

### 2026-11-22 — offline-published-input
Model: OpenAI Codex. In the Schoolis screen the existing grade projection and prediction model can use the matching successful offline detail. The grade cache never contains calculated forecasts, and Restore continues to clear only user input.

### 2026-11-22 — persistent-course-forecast / term-restore
Model: OpenAI Codex. Preserve verified local draft sessions and use the public OpenGCalc weights only in a separately labeled forecast. Changed interfaces: `CourseForecastStore`, `TermForecastGPA`, `ForecastGroups.anchor(for:)`, and a read-only percentage on `CourseForecast.Projection`. Scope, relaunch, restore, group reorder and zero rows are covered by CourseForecastTests. No server mutation or official score storage.

### 2026-11-22 — open-forecast / released-count / partial-subtotal
Model: OpenAI Codex. The old projection discarded released contributors and refused a draft in a populated group. Reimplemented the [OpenGCalc item calculation](https://github.com/Haoxuan1016/OpenGCalc/blob/7207ed6e5e8c48c6e2406cad7500105a99e2f25c/content.js#L2334-L2344) and [relative group weighting](https://github.com/Haoxuan1016/OpenGCalc/blob/7207ed6e5e8c48c6e2406cad7500105a99e2f25c/content.js#L2401-L2419) in native Swift, with typed publication/scale checks, nested weights and separate partial results. No extension JavaScript or other plugin features are included. Changed interfaces: `ForecastGroups`, `ForecastSamples`, `CourseForecast.project`; no storage, request or official-grade change. Tests: `CourseForecastTests` and the native fixture.

### 2026-11-21 — published-group-forecast
Model: Codex · Changed: `ForecastGroups` carries category identity and parent-scoped weights; `AssessmentForecast` accepts a group ID instead of a weight. Reason: keep a single assessment from silently claiming a whole category. Interface: course detail and local calculation only; no network or storage changes.

### 2026-11-21 — 校宝本人资料
Model: Codex · Keywords: schoolis-webkit / scoped-student-reads  
Changed: `CourseGradeDetail(term:name:grade:publishedRows:)` accepts already-authorized category rows; default nil preserves all previous consumers. Reason: do not turn a category weight into an individual task weight. Affected interfaces: additive internal initializer; no remote contract changes.


### 2026-11-20 — Authorized automatic GPA estimate
Model: Codex · Keywords: gpa-direct-estimate / confirmed-credits / explicit-scale  
Reason: Estimate only when the source supplies usable credits and grade-point data or an explicit scale.  
Changed: Apply an explicit term scale and GPA credits to published course data only; show missing prerequisites and carry term metadata through existing authorized caches.  
Affected interfaces: Optional grade inputs on the Swift client, plus `CampusGrades.gpaReadout`. No new endpoint, backend behavior, cache migration, dependency or setting.  
Verification: 168 Swift tests passed, including the local Rust demo integration. Real school data was not used.

### 2026-11-20 — Share score text
Model: Codex · Keywords: tasks-glass-grid / shared-grade-mark  
Changed: Moved the existing numeric/letter display formatter from the GPA tile into `GradeMark`. Both task cards and task detail read the same formatter.  
Reason: Render a source-provided score consistently without involving GPA calculation.  
Affected interfaces: Native display text only; format, grade math and GPA screens are unchanged.

### 2026-11-20 — Course workspace
Model: Codex · Keywords: course-workspace / explicit-shares / history-range  
Changed: Preserve existing service fields `class_name` and `first_published_at`, project only known values, and include known local categories even when they contain one item. Add an independent forecast calculation. The typed grades metadata marker is now 2; older data stays readable and may backfill these fields on the next already-authorized grade check. Forecast values stay out of history points, the gradebook and the semester GPA.  
Reason: The course workspace can show the full context received and support a what-if without treating it as school data.  
Affected interfaces: Additive native projection and draft types; no backend, REST contract, database, environment or dependency changes.  
Verification: 120 Swift tests passed on macOS, including the local Rust HTTP integration, both cache paths, date-range boundaries and missing forecast inputs.

### 2026-11-20
Model: Codex · Keywords: gpa-overview / assessment-groups / published-weight  
Changed: Added result, weight and source-preserving projections for both grade sources.  
Reason: The same course interface needs to handle real source categories, flat records, and unavailable values without guessing.  
Affected interfaces: Native grade presentation only; no HTTP or academic policy changes.

Verification: Independent fixtures cover category grouping, flat weights, valid zero vs. missing data, letter marks, GPA provenance, and term scope. The current 109-test Swift suite also checks the old offline and per-course cache paths, including failed/partial backfills that must keep the saved copy.

### 2026-11-21 — bilingual UI / verbatim school data
Model: Codex. Localize authored assessment status labels and unavailable-course fallback wording, not school marks, group names or feedback. The internal projection distinguishes missing, unpublished and absent marks without changing any calculation. [Language boundary and regression tests](../Localization/README.md).
