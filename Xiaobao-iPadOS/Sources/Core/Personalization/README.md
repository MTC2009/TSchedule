# Local personalization

Small device preferences, independent of school profile, credentials, timetable and lesson timing. Pure Swift, with Foundation only.

- Input / entry: `LocalPersonalization` accepts optional display text through `setNickname`, `setReminderSubtitle` and `setLessonActivity`. Whitespace is folded to one line; blank restores the default. Limits: 24 / 40 / 16 characters respectively, with byte bounds for composed glyphs.
- Output: a Codable preference value with a default activity appearance. A missing/unsupported field falls back without discarding valid sibling values. `LessonActivityAppearance` carries only a background choice and optional next-course heading.
- Files and consumers: `LocalPersonalization.swift` defines both values. Native Settings edits them via AppModel, which saves under `tschedule.localPersonalization.v1` rather than touching the existing preference blob. The activity extension decodes just the appearance provided in its snapshot. AppModel forwards only the subtitle to personal reminder scheduling.
- Testing: `swift test --filter LocalPersonalizationTests`; includes restore/reset, unknown and malformed fields, and paste bounds. No sync, account editing or database migration.

## Change History
### 2026-11-21 — Local Settings choices
Model: Codex (GPT-6.2-sol) · Keywords: local-personalization / lock-screen-style / reminder-subtitle  
Changed: Add independent native display preferences and a bounded shared appearance value. Reason: Keep optional display choices out of the established login and academic data contracts. Affected interfaces: local Codable value and activity style snapshot only.
