# Portal reader integration tests

Developer-only, not in the app bundle. Inputs are locally authored synthetic fixtures, not student exports. Outputs are pass/fail and assertion locations. These tests never send requests to a school or use a real account.

- `node --test Tests/SchoolPortalSync/*.test.cjs` exercises the two shipped reader/projection scripts with a fixed mock transport and the separate sign-in script with synthetic form controls. It covers release flags, session changes, paging, enrollment identity, and refusal of unknown login screens and challenges.
- On macOS, `python3 Tests/SchoolPortalSync/webkit-smoke.py` runs the shipping store, `SchoolPortalEntry` and reader in Apple WebKit, without a visible window. The loopback server rejects the old HttpOnly session, changes the synthetic grade, then either honors a separate synthetic device authorization or redirects to a login page. It verifies entry/grade counts and no credential POSTs. Only the test copy uses the loopback origin.
- `python3 -B Tests/SchoolPortalSync/ipad-smoke.py <QA-simulator-UUID>` builds a throwaway fixture app and performs actual GPA sidebar taps using XCUITest. Requires Xcode and the Ruby `xcodeproj` gem. Only the disposable build has a loopback-only host substitution; it has a separate bundle ID. The shipping project, installed student app, credential store and school site are not used.
- `--delegated`: enroll a randomly generated local password, invalidate the fixture session, terminate and relaunch on Today. The sign-in button goes busy before navigation and Home loads a local subframe. Verify one startup submission, the same student and **no grade read** until GPA opens. Wrong input stays paused; opening the school page preserves its inline refusal.
- `--planner-removal`: exercises the two dated removal scopes in the actual editor, an ordinary one-off plan, and undo. Uses the same synthetic calendar and verifies no schedule refetch.
- `--planner-rotation`: use the same loopback calendar fixture to save a Day-based personal plan, inspect its dated occurrences and change it to weekday or no recurrence. Check that no additional school timetable requests occur.
- `--annual`: populate an annual course rotation from synthetic weekly replies; exercise Today, multiple Planner weeks, a failed Settings update, live summaries and cold offline relaunch. The fixture also fixes the clock after school and on a holiday, checks the next teaching date, first subject and room, and follows the action to the displayed Planner date. Server counters must show no schedule read while browsing or offline.
- `--native-reads`: verify explicit GPA refresh versus cached return, native attendance failure/retry, and the course-detail forecast editor. Add/edit/remove a score in an empty group and add two scores in succession to a populated nested group; the independently computed totals include a released zero and exclude a withheld item.
- `--settings`: test the default product with legacy source preferences; school-only settings, no sample reminder controls, native activity preview and narrow/large text. Open Privacy → Terms, switch to English and back to the privacy page; assert both documents are native rather than school web views. The fixture checks there are no GPA reads or password submissions in this flow.
- `--account-boundary`: a separate, Debug-only fixture host enables `TSCHEDULE_INTERNAL_FIXTURES`. It exercises real simulator Keychain/WebKit, successful test-service logout, HTTP 401 and cold-restart cancellation. The standard Debug and Release schemes do not enable this flag.
- `--navigation`: verify overview prefetch without grades or archives, shared term selection, returning from a same-document route and a held identity read that times out and retries.
- `--lesson-activity`: exercise the actual ActivityKit start/stop button on an embedded widget fixture. Its current lesson and long next-course name are generated for a local Shanghai date, not a real timetable. It requests no grades or login page. For visual acceptance, start the card on a QA simulator, open the actual Lock Screen surface, check whole minutes without an end clock or seconds, and confirm the next-course title remains readable or ellipsized. Do not use a live student account to capture it.
- Swift store/projection tests: `swift test --filter SchoolPortal` covers `SchoolPortalTests.swift` and `SchoolPortalAccessTests.swift`. The native [reader module](../../Sources/Native/SchoolPortalSync/README.md) documents the separate live acceptance check. No production build references to the fixtures.

**Distinguish the three paths on a personal iPad:** after the first normal sign-in, leave the school's session intact until it expires naturally. In a local debug run, use auto-continuing breakpoints at `PortalSession.reopenForGrades()` and `SchoolPortalLoginVault.claim(for:)` without inspecting variables. A fresh result without either marker used an existing session. A Home recovery without a claim used existing school authorization; it did not submit a password. A claim identifies a new password attempt, not success: only a fresh result after the same-student check counts. No screenshots, accounts, score values or network captures are needed.

## Change History

### 2026-11-22 — failed-grade-read / offline-cold-relaunch
Model: OpenAI Codex. The native grade fixture proves a failed refresh preserves the displayed GPA, then cold-launches with networking disabled in the throwaway target and opens saved course details. Planner's timed school card now opens the shared detail, where the actual corrected time and teacher row are read. Fixtures never read an actual account.

### 2026-11-22 — forecast-round-trip / late-focus
Model: OpenAI Codex. The native grade route checks forecasted course tiles after leaving/reentering GPA and after an explicit refresh, then verifies Restore returns the official readout. The display route asserts that evening study has its own location and no competing next-day action. No student data is packaged in the tests.

### 2026-11-22 — open-forecast / populated-leaf
Model: OpenAI Codex. Extended the existing loopback grade detail and native taps to cover an already-scored leaf and check that drafts never trigger a school write. Affected interfaces: test harness only; no student export, school server or real credentials.

### 2026-11-22 — incomplete-publication / future-range-regression
Model: OpenAI Codex. The `--annual` weekly replies end with a dated evening-only performance and then an empty teaching date. The native test checks both dates' daytime lessons, distinct late content and source label, and after cold offline relaunch checks the affected rotation in the next term. No production endpoints, student records or credentials are fixture inputs.

### 2026-11-22 — future-week / offline-next-term
Model: OpenAI Codex. In `--annual`, evening visits follow weekdays rather than the six-Day cycle. After disabling the fixture network, jump past the import window into the following term and assert an actual class on Today and Planner, as well as no further timetable requests. Only the loopback build has the injected clock.


### 2026-11-22 — canonical-bells / named-school-cards / seasonal-pause
Model: OpenAI Codex. The `--annual` loopback roster deliberately mixes shifted split classes, an explicit vacancy and an incorrectly timed pre-lunch course. Check the iPad week/day school cards and time disclosure, including the full fixed lunch range; no real account or timetable is a fixture.


### 2026-11-22 — campus-bells / boarding-display
Model: Codex. The `--annual` scenario alone now supplies an identified split double, one explicit blank and one after-school enrollment. The existing saved-year journey checks day/week cards, local boarding opt-in and unchanged timetable read counts. Other scenarios retain their original fixtures.

### 2026-11-21 — group-forecast / scoped-plan-removal
Model: Codex · Changed: `--native-reads` checks parent, child and empty groups, scoped weight labels and saving/removing a forecast; `--planner-removal` checks both removal scopes and undo, plus ordinary-plan removal. `--reminders` verifies the one removed synthetic request leaves the OS queue while the two other personal requests and class reminders remain. Reason: exercise the actual Release UI with a loopback school and private fixture plans. Interfaces: simulator harness only.

### 2026-11-21 — local-class-alerts / notification-suspension
Model: Codex. Add `--reminders` to the iPad smoke harness: an isolated app and loopback-only, clock-relative synthetic calendar exercise the real system notification queue. The probe belongs only to the temporary simulator target; it sends aggregate QA counts, not identifiers or credentials. Test authorization, timing-only payload, background delivery, offline relaunch, opt-out and logout.

### 2026-11-21 — planner-rotation / native-selector
Model: Codex. Added a separate XCUITest scenario for the existing personal-plan form using the annual fixture; no test-only inputs in the shipping app.

### 2026-11-21 — next-school-day / offline-route
Model: Codex. Extended the loopback annual scenario across a published closure to distinguish a real date jump from a successful tab switch. Clock switches exist only in the disposable simulator copy.

### 2026-11-21 — annual-timetable / cache-first-today
Model: Codex. Added --annual, with a dedicated isolated app identity and local date-only fixture. Verify year import, no requests on week flips, fresh live summaries, failed manual refresh and a cold offline restart.


### 2026-11-21 — offline-policy
Model: Codex · Keywords: settings-privacy / bilingual-terms
Changed: Extend the existing synthetic Settings route test to cover bundled text, nested navigation and switching language. Reason: a normal launch or passing HTML check cannot prove the iPad can show the packaged documents. Interfaces: existing `--settings` test only.

### 2026-11-21 — login-result-handoff
Model: Codex · Keywords: busy-form / first-party-frame / rejected-handoff
Changed: The loopback iPad UI flow checks a slow submit handler, ordinary framed Home and the original refusal after manual handoff. The hosted account-boundary test also checks an unanswered click times out exactly once and a frame on the login form cannot claim a credential.
Reason: The previous synchronous fixture did not exercise these WebKit transitions. Interfaces: existing `--delegated` and `--account-boundary` tests only, with generated data.

### 2026-11-21 — cold-launch
Model: Codex · Keywords: cold-launch / shipping-ui / navigation-retry
Changed: Add synthetic account-boundary, cold-restart and native-navigation checks, including slow identity and owner-isolated semester selection.
Reason: Keep account boundaries explicit and avoid blocking navigation on redundant reads. Affected interfaces: Isolated fixture modes; no school accounts or production targets used.

### 2026-11-21 — Local activity integration
Model: Codex (GPT-6.2-sol) · Keywords: widget-embedding / lesson-activity / native-link  
Changed: add a dedicated QA bundle and Shanghai-date schedule for the system activity path. A separate fixture URL scheme keeps the link in that bundle; nested app and widget identifiers share one test prefix. Reason: exercise actual registration, stop and next-course focus without making a request to a school or exposing an account. Affected interfaces: fixture CLI only.

### 2026-11-21 — Attendance, grade refresh and settings regressions
Model: Codex · Keywords: selected-course / native-reads / settings-disclosure  
Changed: Added school-shaped offline attendance responses, owner/filter/range and failure cases, an actual WebKit summary/detail round trip, plus isolated simulator Settings and native GPA/attendance scenarios. Reason: proving an endpoint was read does not prove the student remained on a native screen. Affected interfaces: local fixture flags and tests only.
Verification: 197 Swift tests (including the loopback demo integration) and 24 JavaScript tests passed. Apple WebKit read an attendance summary, subject list and selected course detail without a grade or credential request. In iPadOS 27 the native GPA was updated by refresh and re-entry, the student opened a listed attendance course without a web sheet, and a denied daily read offered a native retry which then showed a confirmed empty result. The fixture counted only the expected six attendance calls, three GPA snapshots, one Home entry and zero password submissions in that workflow. Settings alone never read GPA or submitted a password. The foreground sign-in regression still required explicit enrollment, successfully handled full fixture expiry and stopped after one rejection. No actual student account or records were used.

### 2026-11-21 — Full expiry, not device renewal
Model: Codex · Keywords: explicit-enrollment / foreground-password-login / fresh-session  
Changed: An isolated iPad fixture can now individually enable the student's opt-in with a randomly generated synthetic password. Its old session and device grant are both revoked; the server accepts a new session only after its ordinary password check. A wrong password records one rejection and no repeat. Reason: prior WebKit renewal coverage could pass without any new password authentication. Affected interfaces: local test harness, not the school API.

Verified: 193 Swift tests, 20 JavaScript tests, the system WebKit smoke check and the iPad Simulator Release build passed. On an iPad Air 13-inch (M4), iPadOS 27, the student enabled the feature through Settings; the fixture server observed two successful password submissions (one on a subsequent visit, one after relaunch), both after full revocation and a deliberate GPA tap. Both displayed the newly changed synthetic grade without a web sheet. A rejected password was submitted only once across repeated visits. Startup did not submit a password. The separate test with enrollment off still performed zero password submissions. A read-only check of the public school login page matched the expected controls; no live account, password submission or school grades were used for verification.
### 2026-11-21 — Confirmed expiry and conditional recovery
Model: Codex · Keywords: foreground-grade-entry / device-renewal / interaction-required  
Changed: Added exact failure classifications, same-student fresh grade assertions, rejection/changed owner and stale reply coverage, and server-side expiry with/without a trusted device. Reason: a passing old-session read is not proof of reauthentication. Affected interfaces: test harnesses only. The synthetic device grant is a test condition, not a claim about the school. The earlier proposal below is historical.

Verified: 189 Swift tests passed with the current loopback Rust demo, 16 JavaScript tests passed, the system WebKit check passed and the production iPad Simulator Release target built. On an iPad Air 13-inch (M4) simulator running iPadOS 27, XCUITest tapped GPA while the first document was deliberately held: waiting, no sign-in action or web view, and the first grade appeared after release without another tap. A second visit after server expiry displayed a changed synthetic GPA for the same student without a web sheet. Revoking device authorization left only the interactive sign-in action, no old grade and no automatic loop on re-entry. The fixture server independently counted one Home navigation per expiry, two grade snapshots in all and zero credential submissions. No live student login or records were used.
### 2026-11-21 — Foreground grade reauthentication: proposed acceptance check
Model: Codex · Keywords: foreground-reauth / confirmed-expiry. Documentation only; no runtime or interface change.

- The ordinary student-reported web flow does not normally require a second step. This is not evidence that the portal supports noninteractive client sign-in. The current app does not read the login form or store the school password.
- The existing `.login` result is too broad to trigger reauthentication: the native reader returns it while loading or off the home page as well. Do not treat navigation, connectivity failures, access denials, account changes or explicit logout as proof of expiry.
- Acceptance for a supported sign-in method: after an opted-in personal device's **school session expires**, opening GPA should perform at most one foreground reauthentication, independently confirm the same student, and display a fresh read of published grades without a web page or separate grade-read prompt. A rejected credential or interactive challenge stops the attempt; logout must never restart it.
- Baseline: 13 local reader tests and the loopback WebKit expiry check passed. They do not exercise reauthentication; no real credentials or academic records were used. Cached scores and a password-filled web page do not meet the acceptance check.

### 2026-11-21 — Task order across pages
Model: Codex · Keywords: published-time / task-page-order  
Changed: The paging fixture checks that the reader preserves source order and never substitutes the deadline when the publication date is missing. Reason: the task grid relies on both facts. Affected interfaces: regression tests only.

### 2026-11-21 — Student task marks
Model: Codex · Keywords: task-list-release / webkit-bool  
Changed: Added synthetic coverage of published zero and letter marks, strict release and mode flags, and non-access to masked values. The WebKit check exercises both task-list scopes using native booleans. Reason: previously a metadata-only fixture passed while every legitimate mark was discarded. Affected interfaces: test payloads only.

### 2026-11-21
Model: Codex · Keywords: schoolis-fixtures / webkit-loopback  
Changed: Added isolated JavaScript transport tests and WebKit smoke harness. Reason: validate browser/session behavior without private records. Affected interfaces: test-only.

### 2026-11-21 — language-switch / verbatim-source
Model: Codex. New mode: `python3 Tests/SchoolPortalSync/ipad-smoke.py <dedicated-iPad-simulator-uuid> --localization`. The Release fixture launches twice with the same synthetic records and opposite language preferences. It checks navigation, filters, named and generated semester labels, the planner editor, reminders, privacy and the embedded widget; the notification probe constructs requests without registering or delivering them. `TSCHEDULE_FIXTURE_RESULTS` optionally preserves the xcresult with screenshots. No real account, school writes or product test entry. The separate `--reminders` suite exercises actual simulated notification delivery. Check string coverage/format signatures with `check-localizations.py --help`.

Simulator evidence (2026-11-21): the same-account English/zh-Hans journey passed on iPadOS 26.4.1 and 27.0. Checks include original mixed-language school fields, an app-generated semester next to an official named archive, both bundled languages in the activity extension, and per-language local notification copy. Separate synthetic delivery runs exercised both reminder types with the app in the background. This is not a physical-device Lock Screen test.

### 2026-11-22 — Codex · assignment-cache / OS notification reconciliation
`python3 -B Tests/SchoolPortalSync/ipad-smoke.py <QA-simulator-UUID> --assignments` drives an isolated Release build in Simplified Chinese; use `--assignments-en` for the same journey in English. The loopback school drops its sockets (not an HTTP empty reply); XCUITest terminates and relaunches the app. A separate test-only observation channel checks actual UNUserNotificationCenter identifiers, trigger times and title privacy; an unresponsive notification daemon is not an empty queue. Covers same-count edits, malformed empty pages, withdrawal, an interrupted account review during an outage, and a second student reusing the same portal task ID and reopening their own list offline. No school writes. Set `TSCHEDULE_FIXTURE_RESULTS` to an existing output directory to retain XCTest results and screenshots.

The semester checks also distinguish the live directory from the offline menu: an archive is not read until selected, it can then be opened and reset offline, and it never becomes the other student's saved archive or steals the current-term reminder.

Simulator evidence (2026-11-22): the complete journey passed in Simplified Chinese on iPadOS 26.4.1 and in English on iPadOS 27.0 (iPad Air 11-inch, M4). These are process-relaunch and system-queue checks against fictional records, not a physical Lock Screen or live-school test.

### 2026-11-22 — material-foreground / file-save
Model: OpenAI Codex. The assignment fixture observes lazy reads while the app shows Settings (with zero automatic file requests), exercises an explicit file download and Files picker, checks material after a cold offline launch, and uses a different owner with the same item ID. All names, responses, bytes and accounts are synthetic. The JS cases cover membership, released documents, drafts, denied reads and cross-account responses independently. The loopback exceptions are injected only into a temporary simulator project, never the production bundle.

Verification: 267 Swift tests with the synthetic local service, 35 JavaScript tests, both school-calendar and assignment XCUITest journeys, and the bilingual release catalog check passed. No real assignment bodies or downloaded student files were needed.

### 2026-11-22 — timetable-display / supplemental-courses
Model: OpenAI Codex. The --timetable-display iPad journey uses an isolated synthetic dated TSSA enrollment. It enables boarding, adds a local course in Planner, checks Today, hides external courses and then TSSA, and verifies the replacement study slot after relaunch. Actual school transport and personal data are not used.
