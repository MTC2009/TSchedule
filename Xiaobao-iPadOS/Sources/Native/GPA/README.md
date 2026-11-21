# GPA page

- **Purpose:** Show the selected term's GPA above an adaptive grid of rounded course tiles. Tapping a course opens a separate detail page. Only categories with children are expandable in that detail.
- **Inputs / entry points:** `GPAOverviewView(isCurrentTerm:summary:unavailableMessage:courses:termLabel:gradeStatus:)` receives the readout and course list from the [GPA projection](../../Core/GPA/README.md). `GradesView` supplies local term selection. `CampusGradebookView()` reads the optional demo service’s saved gradebook and exposes its initial fetch or refresh. For the real school, `SchoolPortalGradebook` shows the verified student’s published grades on entry and exposes a refresh with no additional permission step. The status slot is for grade availability and refresh, not trial forms.
- **Outputs:** Course navigation, a page-local visibility control, native search and grading-status selection. `CourseGradesView(course:)` shows a compact course tile, tappable actual-score chart and one task table on the shared glass surface, with a solid fallback when Reduce Transparency is on. The tile shows the course-total caption directly below the value. The chart opens a range picker and a larger plot; the table's plus opens the form for hypothetical tasks. The eye only replaces the semester GPA readout, including in the accessibility tree.
- **Dependencies / consumers:** The native app's navigation, Today’s shared `GlassCard`, shared detail surface, empty state, and assessment chart; used by the native navigation for local demo, connected demo service and real-school grade screens. See the [reuse index](../../../../REUSABLE_MODULES.md#gpaoverviewview).
- **Files:** `GPAOverviewView.swift` handles the common screen; `CourseGradeList.swift` presents destination tiles; `CampusGradebookView.swift` is the connected adapter. `CourseGradesView.swift` owns the course layout, presentation and temporary draft state, `CourseTaskList.swift` owns the table/disclosure/feedback, `CourseHistorySheet.swift` owns the date window, and `CourseForecastSheet.swift` owns the editor. The standalone trials in `GradesView.swift` have a single entry through `SettingsView` → 成绩工具. They use the demo term or the active account's existing local grade cache; they never authorize or fetch grades. Do not mount them in the overview.
- **Limitations:** The unconnected demo has categories but no published weights. The demo service has individual weights but no GPA credits, conversion scale, published category tree or official semester GPA. In the connected overview show the published GPA first, otherwise an explicitly labeled credit-weighted estimate or the missing data. Old grade caches remain readable, and the connected client continues to show the current cached term only. Forecasts can be edited or removed while this course detail is open; they are not saved, included in the chart, or applied to the semester GPA. A draft may omit weight but cannot produce a preview total without explicit assumptions.
- **Test:** `swift test` for projection, calculation, chart window and cache compatibility. On an iPad simulator, build the Xiaobao scheme and verify course navigation, group-only disclosure and feedback, date filtering, invalid forecast input and edit/remove. Returning to the GPA page should leave the published total unchanged.

## Change History
### 2026-11-21 — Refresh is not a permission request
Model: Codex · Keywords: grade-refresh / settings-trial-copy  
Changed: Real school mode reads on GPA entry and offers 刷新 GPA; the optional demo service distinguishes its initial explicit read from subsequent refreshes. Settings trials explain which existing grades they use and never request them. Reason: reading an update is not enrollment or repeated consent. Affected interfaces: native status/action labels, no grade formula or server changes.

### 2026-11-21 — Enrolled foreground sign-in
Model: Codex · Keywords: explicit-gpa-selection / full-expiry  
Changed: A student who enabled device-only password use in Settings can sign in once during a deliberate GPA visit. Reason: distinguish opening the grade screen from a timer/resume or a consent prompt. Affected interfaces: route/adapter only; the shared grade overview and demo behavior are unchanged.

### 2026-11-21 — Real-school grade entry
Model: Codex · Keywords: foreground-grade-entry / live-source-only  
Changed: The real-school adapter shows pending on its first read, reads on selection, and reuses the existing refresh action. Reason: no second permission gesture is needed to view published results. Affected interfaces: real adapter only; `GPAOverviewView`, the cached demo consent button and course-detail controls retain their contracts.

### 2026-11-21 — 校宝本人资料
Model: Codex · Keywords: schoolis-webkit / scoped-student-reads  
Changed: `GPAOverviewView` accepts an optional course destination for on-demand WebKit detail; all other destinations and visuals are unchanged. The explicit grade action is also used for real school records. Reason: do not fetch all details at login. Affected interfaces: optional courseDestination; defaults to CourseGradesView.


### 2026-11-20 — Automatic GPA from confirmed inputs
Model: Codex · Keywords: gpa-overview / confirmed-credit-weighted-estimate  
Changed: The connected overview shows the school GPA if supplied; otherwise it automatically displays the core estimate or explains which authorized inputs are missing. The separate Settings trial remains in Settings.  
Reason: Keep grade lookup automatic while making the source of the result explicit.  
Affected interfaces: Grade provenance and unavailable-state text only; no changes to refresh controls or the real-school connection.  
Verification: The native sources passed Swift type checking against the iPad simulator SDK; no new executable build or UI run.

### 2026-11-20 — Standalone trials in Settings only
Model: Codex · Keywords: gpa-overview / settings-grade-tools / cache-only-trial  
Changed: Moved the demo and connected trial forms to Settings → 成绩工具. The overview's trailing slot is now for grade status and refresh only; the course detail's temporary forecast stays where it is.  
Reason: Keep the GPA page for looking up results; trial inputs should not appear beside real grades.  
Affected interfaces: Native view composition and the two `GPAOverviewView` consumers. No changes to grade calculations, authorization, cache format, backend, database or configuration.  
Verification: Signed iPad Simulator Release build, 164 Swift tests with loopback demo service, and an iPadOS 27 UI test passed. With the local demo gradebook, neither trial was shown at the bottom of GPA; the Settings trial expanded, the score input worked, and returning to GPA left its readout unchanged. No live school sign-in or grade access was tested.

### 2026-11-20 — Unified course detail glass
Model: Codex · Keywords: course-detail-glass / total-caption-below  
Changed: Reused the Today glass surface for all three outer panels, with no per-row material. Moved the course total caption below the value and grouped the pair for accessibility.  
Reason: Match the app's existing appearance without changing which content is shown or how it opens.  
Affected interfaces: Course detail presentation only; shared glass defaults, overview, sheet contents and grade data are unchanged.

Verification: The workspace built with Xcode and passed 123 Swift tests, including loopback Rust integration. On an iPad Air 11-inch simulator (iPadOS 27), the total preceded its caption and retained the same value; landscape and portrait detail, disclosure, chart and forecast entry were checked. Enabling system Reduce Transparency gave all three panels the opaque fallback without blocking the actions. [Simulator capture](../../../../docs/verification/student-interface/gpa-course-glass.png) uses the existing demo gradebook.

### 2026-11-20 — Course workspace
Model: Codex · Keywords: compact-course-detail / date-range / assessment-forecast  
Changed: Replaced the three full-width panels with a small grade tile paired with a preview, and a single task table beneath. The preview opens a date-scoped chart of actual assessments. Add/edit/remove affects temporary forecasts only.  
Reason: Keep the grade and chart in view while giving most of the space to the tasks.  
Affected interfaces: Course detail and its native sheets. The overview, semester trial, school web entry, permissions and service contracts are unchanged.

Verification: The current workspace built for iPadOS 27 Simulator with Xcode. Three UI cases passed on an 11-inch iPad Air simulator: portrait and landscape detail with group disclosure and feedback, opening and narrowing the actual-history chart to a single date, and forecast validation/add/edit/remove with unchanged published totals. The 120-test Swift suite included the local Rust HTTP integration, not a school connection. [Course detail](../../../../docs/verification/student-interface/gpa-course-workspace.png) · [Enlarged history](../../../../docs/verification/student-interface/gpa-course-history-range.png) · [Forecast](../../../../docs/verification/student-interface/gpa-course-forecast.png). All captures use synthetic data; no physical iPad was tested.

### 2026-11-20 — Today-style overview
Model: Codex · Keywords: gpa-glass / stacked-heading / course-tiles  
Changed: Adopted the Today card material for the overview and an adaptive grid of round-corner course cards. The heading stacks at left, the readout aligns at right, and the neutral eye retains its full touch target.  
Reason: Visually unify the student pages while keeping the semester readout, totals and navigation easy to find.  
Affected interfaces: GPA overview presentation only. Course detail, disclosure, source labels, permissions, APIs and persistence are unchanged.

Verification: The two revised views built and passed iPadOS 27 simulator checks on the last buildable app snapshot: three columns in landscape, two in portrait, single-column reflow at accessibility text size, a 44 pt eye target, no numeric accessibility value while hidden, and course navigation and group disclosure. [Landscape](../../../../docs/verification/student-interface/gpa-glass-landscape.png) · [Portrait](../../../../docs/verification/student-interface/gpa-glass-portrait.png). The current workspace build was separately blocked by an out-of-scope opaque-return error in `ScheduleView.swift`; that file was not modified for this change.

### 2026-11-20
Model: Codex · Keywords: gpa-overview / course-detail / grouped-assessment  
Changed: Shared one GPA-first screen across local and connected modes; kept course totals visible, nested assessment disclosure in course detail, and moved trials below the list.  
Reason: Make the GPA and totals immediately readable without removing access to individual grades.  
Affected interfaces: Native grade route label and view composition only. No portal URL, HTTP contract, dependency, environment, database or deployment change.

Verification: The app built with Xcode; 109 Swift tests passed, including the loopback Rust integration. Three cases passed on the 11-inch iPad Air simulator (iPadOS 27): portrait/landscape course navigation and group disclosure, hidden GPA across a term change, and explicitly authorized connected grades with source weights. Captures use the app's existing synthetic records: [overview](../../../../docs/verification/student-interface/gpa-overview.png), [expanded assessment group](../../../../docs/verification/student-interface/gpa-course-detail.png), [service weights](../../../../docs/verification/student-interface/gpa-service-weights.png). No physical iPad or live school grades were tested.
