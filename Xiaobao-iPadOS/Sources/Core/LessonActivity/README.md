# Lesson activity plan

Projects a single ongoing class from an already loaded `LessonTimeline` and an actual clock instant. This module has no persistence, notification, network, or ActivityKit dependency.

- Input: the resolved day and a real `Date`, not a time-lens selection.
- Output: `LessonActivityPlan` contains the current class interval and the next unambiguous course that day. Gaps, breaks, lunch, optional assembly and vacant slots do not count as courses. Overlapping current courses do not start an activity.
- `focusMinute(in:at:)` verifies the next course still matches the loaded timetable before a native link can select it.
- Consumer: the [native activity controller](../../Native/LessonActivity/README.md). Dependency: the existing `LessonTimeline` and Shanghai school clock.
- Test: from the iPad project, run `swift test --filter LessonActivityPlanTests`.

## Change History
### 2026-11-21 — Local lesson snapshot
Model: Codex (GPT-6.2-sol) · Keywords: class-end / next-course / lock-screen  
Changed: project the active interval and the next loaded class and validate a lens jump. Reason: the lock screen must not invent an end time or a next course. Affected interfaces: internal Swift projection only.
