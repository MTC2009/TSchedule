# GPA presentation data

- **Responsibility:** Project the local gradebook or the signed-in account's saved grades into a term GPA and per-course breakdown. Calculate course forecasts separately, from explicit assumptions. This module does not fetch, persist, or calculate an official school GPA. The on-device portal reader can pass explicitly published group rows; the existing demo service still uses flat assessments.
- **Inputs:** `Gradebook` / `CourseReport` for the local mode; `CampusGrades`, `SavedCampusGrades` and the roster for connected mode. Grade calculation, normalization of percentages, and dated chart points reuse the app's existing grade calculator and assessment-history code.
- **Outputs and entry points:** `CampusGPA.swift` projects `CampusGrades.gpaReadout` into a published GPA, an automatic credit-weighted estimate, or the ordered reasons no estimate is possible. `GradePresentation.swift` handles `Gradebook.gpaSummary(termID:weighted:)` for the built-in sample, `CourseGradeDetail(report:)` and `SavedCampusGrades.courseGradeDetails`. A course exposes the published score, optional class, GPA and first-publication time, known categories, rows and lazily produced actual history points. `AssessmentWeight` preserves whether a fraction is scoped to a course or group. `CourseForecast.swift` validates `AssessmentForecast` and provides `CourseForecast.calculate(current:estimates:)`, returning the hypothetical percentage or a specific missing/invalid-input state.
- **Consumers:** The [native GPA page](../../Native/GPA/README.md), its local adapter, and grade projection tests. See the [reuse index](../../../../REUSABLE_MODULES.md#gpa-presentation).
- **Limitations:** Multiple items with the same explicit local category can form a group; its score and weight are not made up. The demo service supplies only flat assessments and doesn't provide their categories. A course forecast requires a known numeric total on a known scale and explicit assumed shares for all forecasts, summing to at most 100%. It treats the current total as the unmodeled portion of the course, not a result of a school grading rule. An absent value is not zero.
- **Test:** From the iPad project, run `swift test`; see `GradePresentationTests`, `CourseForecastTests`, `StudentChartTests`, `CampusOfflineTests` and `CampusConnectionTests`.

### Optional authorized GPA inputs

A valid published term GPA takes priority. Otherwise the complete, authorized term roster needs a finite `gpa_credits` on each course. An explicit zero excludes a course; an absent value does not. A published course GPA supplies the course points directly. For other included courses, a published numeric total with a known maximum is converted using the term's explicit `gpa_scale` bands (`minimum_percent`, `grade_points`); the bands must cover zero with unique cutoffs and non-decreasing points. The client does not infer AP, course inclusion or a conversion scale. Task previews and forecast drafts are never GPA inputs.

The Swift client accepts these optional fields on existing grade payloads. The term policy travels with each grade snapshot or delta; omission clears the rule rather than reusing an older one. A future authorized provider must include the scale in the term version and credits in course revisions. Older caches and the current Rust demo source need no migration; absent fields simply make the connected estimate unavailable. No new API call is made.

## Change History

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
