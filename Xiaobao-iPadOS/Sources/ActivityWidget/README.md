# LessonActivityWidget

WidgetKit extension embedded in the iPad app. It renders bounded local ActivityKit content; it does not read WebKit, Keychain, networks, files, grades, or a student account.

- Input / shared contract: `LessonActivityAttributes.ContentState` holds the current interval, a bounded display title for the next course, whether the source is a demo, and an optional background/heading. Closing sends an empty state. The payload, style value and card are compiled into both targets.
- Output: the standard Lock Screen card and supported compact, minimal and expanded system presentations. The system supplies clock ticks and the default surface; optional backgrounds use semantic system colors. The shared `TScheduleMark` asset resolves the same two original-color variants as the main app.
- `LessonActivityCard.swift`: whole minutes until class ends, without a wall-clock end time or seconds. The finite left column allows the system text to render; a partial minute shows the next whole minute, and the real end still controls expiration. The right keeps its aligned heading and large name with native tail truncation. Tap returns to the full title when still available. Expired content clears course information.
- `LessonActivityWidget.swift` configures system presentations, background tint, and the fixed return URL; Settings uses the same card with an illustrative fixed reading and no activity registration.
- Entry: `LessonActivityWidget.appex` with an identifier derived from the containing app and the extension plist in `Config/`. Dependencies: ActivityKit, WidgetKit, SwiftUI and the shared brand asset; no app group, push entitlement, or background reader.
- Consumer: [native controller](../Native/LessonActivity/README.md). Test with the main scheme and the isolated iPad fixture; first allow the system activity on the QA Lock Screen. [System-rendered whole-minute card](../../../docs/verification/student-interface/lesson-activity-minutes.png) uses only synthetic content; a simulator rendering does not prove real-device behavior.

## Change History

### 2026-11-21 — legacy-redaction
Model: Codex · Keywords: legacy-redaction / loaded-preview
Changed: Redact previously archived fixture activities on every widget surface; Settings no longer invents a countdown or course.
Reason: Keep account boundaries explicit and avoid blocking navigation on redundant reads. Affected interfaces: Existing ActivityKit payload remains decodable.

### 2026-11-21 — Whole-minute countdown and optional styles
Model: Codex (GPT-6.2-sol) · Keywords: minute-countdown / activity-preview / activity-background  
Changed: Remove the end clock and second counter, and share the card with Settings. Reason: Use the Lock Screen's own clock for the current time and keep the activity focused on what's left. Affected interfaces: optional style in the local snapshot; expiry and return URL unchanged.
Verification: On the iPadOS 27 simulator's system Lock Screen surface the left readout changed from 12 to 11 minutes without re-opening the app. The next title remained available to VoiceOver and the return route focused the full title in Today. Tests used a dated local fixture and no student data.

### 2026-11-21 — Native Lock Screen card
Model: Codex (GPT-6.2-sol) · Keywords: lesson-activity / light-dark-brand / tail-truncation  
Changed: embed a new WidgetKit target with the local lesson card, its content contract and the existing brand asset. Reason: display the two school times/names with native system handling. Affected interfaces: local payload and fixed widget navigation only.

### 2026-11-21 — bilingual UI / verbatim school data
Model: Codex. App-authored Lock Screen headings, countdown units, VoiceOver hints and ended states follow the extension’s bundled language; a supplied next-class name and custom heading remain verbatim. Interface: shared catalog and display locale, no ActivityKit schema change. [Language boundary and regression tests](../Core/Localization/README.md).
