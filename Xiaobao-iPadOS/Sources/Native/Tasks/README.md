# My Tasks

- **Purpose:** One grade-style glass grid and the top filters for both built-in and connected tasks. A task card opens a read-only detail, except for the original local demo completion action.
- **Input / entry:** `TasksView()` from the My Tasks destination in `RootView`. Reads the active account or built-in sample through the [task projection](../../Core/Tasks/README.md); the navigation identity clears filters and detail when the account or its task availability changes.
- **Output:** Term/course/type/mode filters, separate submission and grading filters, school-local due-date range, title search and reset. Cards put the published score above the deadline and teacher; when no score is published, the row is omitted. A bottom-trailing diagonal ribbon with distinct symbols uses gray for unsubmitted, yellow for overdue unsubmitted, blue for submitted work awaiting grading or publication, and green for published grading. VoiceOver reads the submission and grading states separately. Detail shows both as text, along with instructions, answer, published score or released preview, feedback and available file names; no upload or download UI.
- **Files:** `TasksView.swift` coordinates results and read states; `TaskFilterBar.swift` owns filter controls and date entry; `TaskCard.swift` renders tiles and status; `TaskDetailView.swift` uses `StudentDetailSurface` and the shared glass styling. At usable wide widths, instructions and answer share a row, as do the score and feedback; small panes stack them. No behavior changes in the exam/evaluation/resource pages or in the Planner's existing school-entry detail.
- **Limits:** Task rows and attachment names are unmodified service or synthetic source values. The real school session supplies its own term directory; Tasks and GPA share the selection. Historical task records are requested only for a selected term. Attachments and submission remain in the school web entry. Grade info, optional fields and archive availability are shown separately from submission and from local offline completion.
- **Test:** Open My Tasks on an iPad simulator, combine facets, open a graded and an ungraded record, return with the same filters, and switch terms. Check the same route with the loopback demo and a previously cached current term. Core tests cover case-insensitive title matching, inclusive dates, paging, old caches and authorization.

## Change History

### 2026-11-21 — annual-timetable / cache-first-today
Model: Codex. Refresh the currently selected verified school term on entering the task list; foreground cached Today also refreshes current tasks. No changes to filters, task completion or the backend.


### 2026-11-21 — verified-semesters
Model: Codex · Keywords: verified-semesters / deadline-layout
Changed: Replace the current-term caption with the verified semester menu. Put deadline in the second-row middle slot at three columns.
Reason: Keep account boundaries explicit and avoid blocking navigation on redundant reads. Affected interfaces: Existing task filters and shared school semester; no submission changes.


### 2026-11-21 — Task grid order
Model: Codex · Keywords: my-tasks / newest-publication  
Changed: The grid shows the latest published task first for all sources. If the school portal omits timestamps, its undated rows retain their returned order after filtering. Reason: no scrolling through old work to find newly assigned tasks. Affected interface: existing grid ordering only; no new control, network request or cache.

### 2026-11-21 — Real task-card results
Model: Codex · Keywords: task-card / grade-consent  
Changed: Real-mode list loading and errors follow the current grade-consent scope. Returning after first opt-in refreshes a metadata-only list and uses the existing card/detail mark presentation. Reason: a corrected task is not proof that a mark was published. Affected interfaces: internal task load key only.

### 2026-11-21 — 校宝本人资料
Model: Codex · Keywords: schoolis-webkit / scoped-student-reads  
Changed: real mode consumes the portal’s complete current-term list using the existing cards, filters and read-only detail. Reason: never fall through to sample tasks on a failed read. Affected interfaces: existing TasksView, no submission or new route.


### 2026-11-20 — Authorized pre-publication score preview
Model: Codex · Keywords: task-detail / pending-publication / authorized-score-preview  
Changed: Detail shows 「已批改，待发布」 when explicitly reported. Only a provider-released preview displays a number labeled 「预估分」 and 「校方提供 · 非正式成绩」. Task cards still show only published marks.  
Reason: Keep a permitted estimate visibly distinct from a released grade.  
Affected interfaces: Task detail presentation and the existing grading badge; no new screen, request or connection to real school grades.  
Verification: The native sources passed Swift type checking against the iPad simulator SDK; no new executable build or UI run.

### 2026-11-20
Model: Codex · Keywords: tasks-glass-grid / selectable-facets / grading-badge / task-detail  
Changed: Replaced the task counter and long list with compact filters and task cards; added the task-specific detail with separate answers and feedback.  
Reason: Read the assignment and grading status immediately, then drill into just the chosen item.  
Affected interfaces: Only My Tasks is re-routed; native navigation and ordinary cache access are reused. GPA, Planner, other work pages and the school web entry remain separate.

Verification: Xcode simulator build and 136 Swift tests (including loopback integration) passed. Three iPad Air 11-inch simulator cases covered local combined filters, detail and terms; connected current and archived tasks; and reopening with the demo service stopped, including detail reflow and preserving filters on back. The [task grid](../../../../docs/verification/student-interface/my-tasks-grid.png) and [task detail](../../../../docs/verification/student-interface/my-tasks-detail.png) use synthetic records.

### 2026-11-20 — Corner ribbons
Model: Codex · Keywords: task-corner-ribbon / status-ink  
Changed: Replaced the footer status and grading chip with a four-state ribbon clipped to the existing glass tile. Existing marks and the device-only completion label stay on the tile.  
Reason: Keep task cards readable at a glance without labeling an unsubmitted task as waiting for grading.  
Affected interfaces: The tile consumes the projected card stage; the task navigation, detail, filter options and data sources are unchanged.

Verification: Xcode simulator build and all 142 Swift tests passed, including the local demo-service integration. An iPad Air 11-inch simulator run checked the four accessible states, tapping a ribbon-covered corner, score and detail labels, filtering by submission, device-only completion, and portrait reflow. The [four-state screenshot](../../../../docs/verification/student-interface/my-tasks-corner-ribbons.png) uses synthetic QA records, not additional built-in tasks.

### 2026-11-20 — Score hierarchy and ribbon tones
Model: Codex · Keywords: task-score-first / deeper-ribbon  
Changed: Put the score directly below the task heading and course/type, then show the deadline and teacher in secondary text. Omit the score row when there is no published mark. Shade the four ribbon colors more deeply without changing their symbols.  
Reason: Make the score easier to find and keep the status ribbon from competing for attention.  
Affected interfaces: Task-card presentation only; the task projection, detail and filters are unchanged.

Verification: Xcode simulator build passed. The iPad Air UI check verified score-before-deadline-before-teacher reading order, no score on ungraded cards, card navigation and filters. A [dark-appearance capture](../../../../docs/verification/student-interface/my-tasks-score-first.png) confirmed all four ribbons were darker than the previous capture.

### 2026-11-20 — Ribbon tone refinement
Model: Codex · Keywords: task-corner-ribbon / mid-brightness  
Changed: Lifted all four ribbon fills. Use medium-bright blue and green, with gentler shading on the existing gray and yellow.  
Reason: Avoid both the previous heavy tones and the initial bright glass highlights.  
Affected interfaces: Color tokens only; status mapping, symbols, card layout and task data are unchanged.

Verification: Xcode simulator build and the existing iPad Air task-card UI check passed. The [dark-appearance capture](../../../../docs/verification/student-interface/my-tasks-ribbon-tones.png) shows all four tones between the initial and previous fills.

### 2026-11-20 — Ribbon angle and width
Model: Codex · Keywords: task-corner-ribbon / ribbon-geometry  
Changed: Reduced the slope and widened the parallel ribbon edges. Reserve horizontal and vertical space independently to keep the status symbol and task metadata clear of each other.  
Reason: Make the corner treatment easier to see without taking attention away from the score.  
Affected interfaces: Task-card ribbon geometry only; colors, states, navigation and data are unchanged.

Verification: The Xcode simulator build and iPad Air task UI test passed. The [portrait capture](../../../../docs/verification/student-interface/my-tasks-ribbon-shape.png) measured about 40° and 20 pt of visible ribbon, compared with 45° and 16 pt in the previous capture.
