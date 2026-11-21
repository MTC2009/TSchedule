# School timetable · 本机学年课表

A device-local document for the currently enrolled portal student, independent of login bindings,
personal plans, and the online academic store. No backend, new endpoint or background job.

- **Inputs:** verified owner, foreground read of actual Sunday–Saturday records, and the published Main Campus HS calendar for the academic year. Never use sample courses or infer holidays from weekdays.
- **Output:** dated lessons/events and verified Day 1–6 lineups for Today and Planner. Read the current week first, then at most five nearby teaching weeks; stop when all six are corroborated. Two distinct teaching dates must agree on the whole course/time lineup. Differing rooms are not repeated. Unknown dates are not empty classes. Events are date-only.
- **Class reminders:** `lessonReminders(now:lead:calendar:)` projects only distinct confirmed starts over seven Shanghai dates. Output is the fire time and lead, never a lesson title, room or account ID. The opt-in is bound to the saved document’s random registration; another student does not inherit it.
- **Next school day:** `nextSchoolDay(after:calendar:)` starts strictly after the given Shanghai date. It skips confirmed closures, accepts published weekend teaching or actual dated lessons, and stops at a gap or the end of coverage. A printed Day on a closure is never a rotation. A published teaching date is still returned if its first lesson is unknown; simultaneous starts are retained, not arbitrarily ranked. No read or file write occurs.
- **Files:** `SchoolTimetable.swift` selects sample weeks and projects one common day; `SchoolTimetableStore.swift` stages a replacement, accounts for cancellation and holds one protected non-backed-up document. Only publish after the file write succeeds. A poorer or failed replacement leaves the old timetable available. If the first import loses the network after already verifying dates, only those confirmed dates are saved as partial, with no automatic retry. If the device is offline, Settings can recheck an existing session without submitting a password. A saved year can only be projected using the matching year and calendar revision.
- **Boundaries:** an offline timetable is visible to whoever can unlock this personal iPad. It never authorizes any network request or access to grades or personal plans. If the student separately enabled foreground login restoration, it can restore the live session on launch without blocking Today; the timetable does not trigger that credential use. Opening the manual portal suspends offline display across process death until the same account is verified. Sign-out, local school data removal or account change revokes the archive registration before file cleanup.
- **Consumers:** `Native/SchoolPortalSync/SchoolTimetableAccess.swift`, Today, Planner and the existing Settings action. See the repository reusable module index for the call sites.
- **Tests:** from the iPad directory run `swift test --filter SchoolTimetable`. The simulator uses a loopback fixture, never a real student.

## Verification · 2026-11-21

The annual iPad loopback scenario counted schedule requests: zero on week changes and on an offline cold launch, exactly one refused read on a deliberately failed replacement. The previous class still rendered; clearing the account and relaunching offline did not expose it. Core checks also cover a held response across a student change, the retained partial first import and restoring backup preferences without the document. The device Release built without signing; no school account or production endpoint was used. The full 216-test Swift suite (including these nine tests), 27 JavaScript checks and the Apple WebKit loopback probe passed. Separate iPad simulator regressions verified native GPA/attendance, archive navigation and opt-in startup restoration without a repeated password submission.

## Change History

### 2026-11-21 — local-class-alerts / notification-suspension
Model: Codex. Shared the existing dated/rotation period lookup with class reminders; the store binds consent and lead to a single local registration. No archive format change.

### 2026-11-21 — next-school-day / calendar-gaps
Model: Codex. Added the read-only next-date and earliest-lesson projection to prevent the Today shortcut from jumping to a closed day. No document schema, import or backend change.

### 2026-11-21 — annual-timetable / cache-first-today
Model: Codex. Added the annual on-device timetable and separately scoped refresh; no school/server interface changes.
