# Local lesson activity

The existing Today timetable can publish one current-lesson snapshot after a deliberate tap in the foreground. No changes to reminders, school login, background refresh, or push registration.

- Input: `LessonActivityPlan` from the timetable currently rendered, the real clock, the current data source (verified school account or explicitly displayed demo), and the device's optional `LessonActivityAppearance`.
- Output: a local ActivityKit session, or a native status if system settings disallow it. The same control ends it.
- `LessonActivityControl.swift`: shared Today control, based on the live clock rather than the selected time lens.
- `LessonActivityController.swift`: starts with `pushType: nil`, keeps the source and course identity only in app memory, removes orphan activities on launch, and ends on explicit source change, logout, recognized identity loss, or the end of the class. Normal locking doesn't cancel a still-valid opt-in snapshot. The renderer switches to a neutral ended state at `staleDate` even when the app can't execute. A schedule change observed when returning to Today ends an obsolete snapshot instead of fetching in the background.
- `tschedule://lesson-activity`: a fixed route with no arguments. It opens Today and focuses the original next lesson only if it still matches the currently verified timetable. No account or course ID can be sent through the URL.
- Dependencies / consumers: [plan projection](../../Core/LessonActivity/README.md), [system card and payload](../../ActivityWidget/README.md), Today and AppModel. See [testing](../../../Tests/SchoolPortalSync/README.md).

## Change History

### 2026-11-21 — activity-owner
Model: Codex · Keywords: activity-owner / unavailable-service
Changed: An unavailable fixture service no longer selects a local timetable activity.
Reason: Keep account boundaries explicit and avoid blocking navigation on redundant reads. Affected interfaces: Existing activity source reconciliation.

### 2026-11-21 — Apply a local style on start
Model: Codex (GPT-6.2-sol) · Keywords: minute-countdown / activity-style / next-start  
Changed: The user's foreground action supplies the local appearance, and the existing expiry uses the actual end even while the system renders rounded minutes. Reason: Personalize new cards without refreshing the school data or updating a running card on a settings edit. Affected interfaces: internal `start(_:source:appearance:)` only.

### 2026-11-21 — One foreground lesson activity
Model: Codex (GPT-6.2-sol) · Keywords: class-end / next-course / lock-screen  
Changed: add one local start/stop control, bounded snapshot lifetime and a scoped native link. Reason: keep the Lock Screen useful without loading private school data in a widget or in the background. Affected interfaces: internal controller and a fixed navigation URL; no public HTTP API.
