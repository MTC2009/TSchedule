# School portal reader

Interactive login remains the official Schoolis page. SchoolPortalReader runs fixed operations in the official HTTPS Home main frame in an isolated WebKit world. Normal reads expose no profile; only an explicit enrollment may obtain the verified student's login name. No existing password-field value or cookie is ever read. [Foreground sign-in](../SchoolPortalLogin/README.md) is a separate opt-in capability, not part of the grade reader. No Rust service is involved.

- `SchoolPortalReader.swift`: native origin and lifecycle checks; load the two signed bundle scripts. `PortalRead.js`: same-origin, no-redirect student reads, current identity checked before and after, bounded task pagination. `PortalProjection.js`: discard profile/credential data and unapproved academic fields inside WebKit. Never change responses or infer hidden marks.
- `SchoolPortalPages.swift`: identity, waiting, recovery and failed reads. `SchoolPortalGradebook.swift`: read the overview on entering GPA and fetch details for a selected course, or sequentially reload only the previously saved forecast courses while that verified term’s GPA view is open. AppModel holds one foreground grade visit outside the account-keyed view. `SchoolPortalEntry.swift` awaits one navigation in the same WKWebView (15 s ceiling). `PortalSession` supplies the fixed Home page only for a persistent store, rejects external top-level navigation, popups and credential challenges during recovery, and never opens a sheet automatically.
- `SchoolPortalAttendancePage.swift`: renders the existing native filters, overview, and course table. Read the selected category and dates on entry; a course tap or page change requests only its detail page. A same-filter refresh keeps its last verified counts visible while pending. A successful empty report is not an error; a denied or incompatible response offers a native retry. No attendance action opens a web sheet or claims a stored password.
- Tests: [reader, WebKit and optional iPad UI checks](../../../Tests/SchoolPortalSync/README.md). Live acceptance: on your own iPad, sign in normally, open GPA, then leave the account intact until its normal server expiry. Return to GPA without opening the website. Check whether fresh results appear or the app instead requests interactive sign-in. Clearing website data or explicitly logging out also removes the recovery opportunity and is not an expiry test. Never submit credentials, grades, bodies, cookies or screenshots.
- Limits: the student portal is not a versioned integration API. An access refusal or incompatible reply is reported, not replaced with demo data. Live academic records require the device owner's comparison. Grade overview and task reads use the current term; the weekly portal reads are limited to initial/manual timetable import, not date navigation; no account write endpoints.

### Overview reads and navigation

The visible tab is served first. `SchoolPortalWarmup.swift` prepares authorized overview lists in the foreground, in memory. With cached Today, tasks are checked first, then the attendance summary and eligible GPA overview can complete independently. `SchoolTermMenu.swift` uses the school semester directory for Tasks and GPA. Only a selected archive is read. Exam rows use the student exam list; evaluations use My Assessments; the resource list uses Shared to Me with the current student's own verified school-supplied scope. No archive scan, attachment URLs, file downloads, answers or grade details are prefetched during overview warmup. The same-origin reader uses the list contracts in the [school's student web client](https://cdn.schoolis.cn/sis/release/student/fe_stu/fe_build/scripts/main.dfaa16ecd7c35ba0dbda.js) and [current student list app](https://cdn.schoolis.cn/sis/sisstureact/pre/17175/assets/js/App-4c7fd13d.js). Unrecognized/denied responses are errors, not empty lists.

Hash-only navigation no longer sets a document-loading flag. Full document loads have a 10 s deadline; an identity read has a separate native 8 s deadline and one timetable week has a 16 s native deadline, even if WebKit's JS timers stop. Closing the manual sheet must verify the same student before a short-lived overview can reappear.

## Change History

### 2026-11-22 — cache-first / inactive-school-scheduler
Model: OpenAI Codex. Opening or closing a temporary system panel is not a school-work trigger. Only a real foreground arrival, reachable grade entry/term or manual refresh can start the relevant work; existing authorization and session bounds still apply. The school grade view reads a protected local snapshot before considering WebKit and offers the existing refresh control and sync time. The cached document grants no authority to read a new result.

### 2026-11-22 — verified-forecast-scope / private-model
Model: OpenAI Codex. The Schoolis GPA adapter joins the selected owner/semester’s local what-ifs to the current authorized grades. Grade refresh reuses the read-only detail operation for those courses. The app does not retain school marks on disk, read unpublished results or alter grade responses. The archive check is fenced by the same epoch and opened only in GPA.

### 2026-11-22 — incomplete-publication / today-rotation-source
Model: OpenAI Codex. Today reads `SchoolTimetable.Day.usesDaytimeRotation` to identify a displayed daytime cycle when a sampled future date had incomplete rows. Its source is the same as Planner's, not an extra portal call or a change to the reader.

### 2026-11-22 — canonical-bells / named-school-cards / seasonal-pause
Model: OpenAI Codex. Today can now show confirmed assembly and lunch alongside the existing unconfirmed-roster notice. Unconfirmed enrollments still do not produce lessons or free time. No browser, session or API changes.


### 2026-11-22 — explicit-vacancy / split-opening
Model: Codex. The existing weekly projection distinguishes a timed school row with explicit blank title and no subject from an invalid record. A named lesson without a class identity gets an occurrence-scoped key so the annual importer cannot join two different sections by title. Internal JS→Swift contract only; the endpoint, session checks and returned data scope are unchanged. Run `node --test Xiaobao-iPadOS/Tests/SchoolPortalSync/portal-reader.test.cjs`.

### 2026-11-21 — local-class-alerts / notification-suspension
Model: Codex. After a first import or explicit replacement, reconcile local notifications using the confirmed document. No new reader, network permission or background access.

### 2026-11-21 — next-school-day / offline-navigation
Model: Codex. SchoolPortalToday now passes its visible annual timetable's next confirmed date and today's closure notice to the shared focus card. The end-of-day action uses that date without running the portal reader. No change to sign-in, warm-up or data retention.

### 2026-11-21 — annual-timetable / cache-first-today
Model: Codex. SchoolTimetableAccess bridges the import-only weekly reader; Today uses the saved year before identity resolution. Warmup refreshes live tasks/attendance and a current published GPA on cached Today, never archived terms or grade details.


### 2026-11-21 — overview-prefetch
Model: Codex · Keywords: overview-prefetch / identity-deadline
Changed: Add the shared semester control, three read-only list projections and priority loading; bound identity checks and hash-route handoff.
Reason: Keep account boundaries explicit and avoid blocking navigation on redundant reads. Affected interfaces: Native list/term reads and their SwiftUI consumers; no school writes.

### 2026-11-21 — Native student attendance and explicit GPA refresh
Model: Codex · Keywords: native-attendance / mounted-tab / published-gpa-refresh  
Changed: School attendance now uses a native overview and paged detail rather than a website prompt. GPA refresh is an action, not a grant. The page adapter is bound to the mounted tab so an outgoing tab cannot start the next tab’s read. Reason: keep school navigation and device sign-in separate from student reads. Affected interfaces: two in-process reads and the page adapter; no new password use, application HTTP routes or data stores.
### 2026-11-21 — Verified enrollment name
Model: Codex · Keywords: scoped-login-name / independent-sign-in  
Changed: Added one same-account enrollment-name read from the existing identity response. A credential challenge or external redirect is now an interaction-required result, not an invitation to supply a password. Reason: only the confirmed current student can enroll. Affected interfaces: private reader operation and WebKit delegate boundary.
### 2026-11-21 — Foreground grade entry
Model: Codex · Keywords: confirmed-expiry / single-webkit-entry  
Changed: Only HTTP 401 or school state `999901` from a scoped read indicate unauthenticated; `999902` and HTTP 403 are access denials. The first-party [student client](https://cdn.schoolis.cn/sis/release/student/fe_stu/fe_build/scripts/main.dfaa16ecd7c35ba0dbda.js) labels the two school states differently. A loading frame, opaque redirect, malformed HTML or outage is not a signed-out verdict. A known student's grade visit can re-enter the ordinary Home page once and independently confirm the same identity. This Home-only recovery remains the default for students who did not enroll. The separate [foreground sign-in module](../SchoolPortalLogin/README.md) now covers full expiry for opted-in students. Affected interfaces: typed UI states and one internal navigation completion; no school or Rust route added.
### 2026-11-21 — Published task-card scores
Model: Codex · Keywords: task-list-release / scoped-mark-projection  
Changed: Pass local grade consent into the existing task-list operation. In the linked first-party student card template only standard-mode cards have a score block, and only a numeric release flag of 1 renders the result. Keep numeric zero and source letter grades; do not project hidden, unsupported or exempt results. Reason: the original bridge discarded every task score. Affected interfaces: one internal boolean and an optional task-row score; no new school requests or UI controls.

### 2026-11-21
Model: Codex · Keywords: schoolis-webkit / current-student / real-school-source  
Changed: Added a fixed read-only bridge plus native page wiring. Reason: enable real account reads on-device without mixing sources. Affected interfaces: internal WebKit reader; no public API, environment or database changes.

### Source contract and reproducible checks

The first-party [student Home shell](https://tsinglanstudent.schoolis.cn/Home) references its public [student network client](https://cdn.schoolis.cn/sis/release/student/fe_stu/fe_build/scripts/main.dfaa16ecd7c35ba0dbda.js) and [student display components](https://cdn.schoolis.cn/sis/release/student/fe_stu/fe_build/scripts/common.d71671ae6ee249053f39.js). The active student, dated schedule, current term, grade summary, detail and task-list conventions were checked against these assets. [Giaoculator S](https://github.com/Haoxuan1016/GiaoculatorS) is a reference for the signed-in reading flow, not an imported dependency or display authority. TSchedule does not intercept, change or substitute the site's responses.

The [first-party student attendance page](https://tsinglanstudent.schoolis.cn/newstu/attendance/class) uses separate [classroom](https://cdn.schoolis.cn/sis/sisstureact/pre/17175/assets/js/index-7e95c8e4.js), [daily](https://cdn.schoolis.cn/sis/sisstureact/pre/17175/assets/js/index-2c3c9752.js) and [activity](https://cdn.schoolis.cn/sis/sisstureact/pre/17175/assets/js/index-5deab1bd.js) views. We checked its published client contract, not live student data. The four fixed student reads for the [report](https://cdn.schoolis.cn/sis/sisstureact/pre/17175/assets/js/AttendanceGetAttendanceStatistic-b0d5c7d6.js), [selected course](https://cdn.schoolis.cn/sis/sisstureact/pre/17175/assets/js/colors-82c6ee82.js) and [paged records](https://cdn.schoolis.cn/sis/sisstureact/pre/17175/assets/js/AttendanceGetAttendanceStatisticDetail-5995b5f1.js) are GETs under the existing school attendance path: overview (`GetAttendanceStatistic`), courses (`GetSubjectAttendanceStatistic`), a selected course (`GetSubjectAttendanceDetail`), and daily/activity records (`GetAttendanceStatisticDetail`). No caller-supplied student identity. The overview uses the school’s percentage when present, plus the four published status counts. Details are paged by ten; no staff, contacts, attendance notes or explanation text leave the reader.

The synthetic WebKit check uses the actual system browser engine, an HttpOnly loopback test session and the shipped scripts: `python3 Tests/SchoolPortalSync/webkit-smoke.py` from the iPad project. The school domain is not contacted in this test. A passing test does not verify a particular student's account.

The [vendor's documented third-party student login-code flow](https://doc-cloud-api.xiaobaoonline.com/api/authentication-api.html) uses an application credentialed integration. It is not the student's ordinary website password, is not used here, and does not establish whether this school's web session can renew on a particular iPad. The fixture's independent device grant is not inferred from a successful password login.

Verification on 2026-11-21: the full Swift suite (175 tests), the reader/projection suite (11 tests), and the loopback WebKit check passed. The Release build was installed and launched in an iPad Air simulator. No school account was used; comparing the native timetable and released marks with the signed-in portal is a separate, on-device acceptance step.

Task-card fix, later that day: tests reproduced both the missing field at the JS boundary and its loss on the Swift side before the fix. All 178 Swift tests (including the local Rust integration), 13 JS tests and the WebKit consent/zero-mark check then passed. The existing simulator app was updated in place and relaunched; the installed binary and both reader resources matched the tested build. No live student results were inspected.

### 2026-11-21 — bilingual UI / verbatim school data
Model: Codex. The JS bridge projects source text, stable semester IDs and machine states, not translated prose. Swift supplies generated semester text, status, task/attendance/GPA controls and errors. Web navigation still uses official route keys in both languages. No external endpoint changed. [Language boundary and regression tests](../../Core/Localization/README.md).

### 2026-11-22 — Codex · assignment-contract / offline-scope
Every assignment page now needs a valid, stable total, including a zero response. A separate eligibility flag requires a precise time and an explicitly pending state. There is no modified-since cursor: reconcile the selected term, not just page one. SchoolAssignmentAccess allows an offline task list only on transport failure with an unrevoked local registration; an unverified account review cannot display it. No portal endpoint or authentication change.

### 2026-11-22 — foreground-material-queue / attachment-export
Model: OpenAI Codex. After a complete verified list, SchoolAssignmentAccess fills the selected semester one item at a time while the app is open, not on a repeating timer. It skips recently saved items, shares in-flight reads with a tap and stops on suspension, identity change or connection failure. PortalRead verifies membership in the same verified list and document generation. The student’s ordinary GET /api/LearningTask/GetDetail supplies instructions, an actual online submission and only released teacher feedback. No file fetch happens in the queue. On a file tap the selected descriptor is re-resolved against a fresh visible detail. SchoolTaskDownload uses WebKit for a single transfer to protected temporary storage and the system Files picker for an optional copy. School-host requests keep the existing WebKit session; supported external school storage hosts use an empty nonpersistent store. Redirects, unsafe names, unexpected HTML, unsupported hosts and files above 100 MiB fail closed. A user export is not app cache. Tests: portal-reader.test.cjs and ipad-smoke.py --assignments.

### 2026-11-22 — timetable-display / supplemental-courses
Model: OpenAI Codex. SchoolPortalToday now supplies the original school timeline to TodayTimetableView separately from display filtering. The shared projection includes boarding routines and explicitly entered courses; an offline timetable does not grant access to an unverified owner’s plans. The original enrollment source, not the visible list, still feeds Live Activities. Test: --timetable-display.
