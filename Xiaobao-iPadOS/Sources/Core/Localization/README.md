# App language

**Boundary.** TSchedule localizes the interface it owns, not the student's records or the Xiaobao website. There is no translation service, language-specific cache, extra account setting or network call.

- **Input → output:** iPadOS's preferred language for this app → bundle language (English or Simplified Chinese) → native labels and VoiceOver copy. Region preferences affect display; the school clock remains in Shanghai.
- **Entry:** `AppLanguage.locale` for explicit display formatters; `AppLanguage.isEnglish` only for selecting the initial bundled policy document. SwiftUI literal labels and Foundation `String(localized:)` resolve in the current target's bundle. Source strings and both translations live in [Localizable.xcstrings](../../../Resources/Localizable.xcstrings); [InfoPlist.xcstrings](../../../Resources/InfoPlist.xcstrings) is the separate system permission table.
- **Consumers:** app scene (locale), timetable date formatter, city weather timestamp, policy reader and Live Activity countdown. Both the app and its embedded extension compile the shared catalog. Notifications use Apple's localized notification strings for app-authored text; personal titles/subtitles stay verbatim. Foreground queue reconciliation also replaces older literal wording when it differs, without translating personal text or changing reminder times.
- **Authoring rule:** localize at the origin of an app-authored sentence. Interpolate school or personal values as arguments. Never look up a run-time course, task, group, room, person, file name or grade in the catalog, even when its spelling matches an interface key. Web routes, stored enum values and request parameters are identifiers, not translations.
- **Testing:** run `python3 Tests/SchoolPortalSync/check-localizations.py` from the iPad project. Use `--app` and `--derived-data` with a Release simulator build made with `SWIFT_EMIT_LOC_STRINGS=YES` to verify packaged tables, format arguments and extracted UI strings. `python3 Tests/SchoolPortalSync/ipad-smoke.py <dedicated-iPad-simulator-uuid> --localization` exercises both languages using one loopback fixture.
- **Limits:** dates, statuses and fallback labels created by the app can change language. A school's own semester name, an official webpage and user-authored plan text do not. Changing the app language is managed by iPadOS, not an in-app switch. The privacy/terms reader also permits choosing a document language independently.

## Change History

### 2026-11-22 — offline-grade-status / timetable-detail-labels
Model: OpenAI Codex. Add bilingual sync time, unavailable-network text, and the native detail labels. Names, notes, and school-provided metadata stay verbatim.

### 2026-11-22 — routine-place / forecast-status
Model: OpenAI Codex. Localized the location labels, forecast and restore language in the existing catalogs; no translation of imported course, room or assessment text. Kept English and Simplified Chinese in the same bundle.

### 2026-11-22 — open-forecast / localized-results
Model: OpenAI Codex. The existing catalog localizes the percent forecast assumptions, group-subtotal label and specific missing-input states. School group titles and submitted scores stay verbatim. Interface: the existing English/Simplified Chinese catalog; no new bundle, setting or translation service.

### 2026-11-22 — incomplete-publication / rotation-source
Model: OpenAI Codex. Added the bilingual source label used by Today and Planner for a partial future date. School-supplied lesson and event names are still verbatim; no interface or bundle changes.

### 2026-11-22 — planner-campus-routine
Model: Codex. Added local boarding labels and the cross-midnight interval disclosure to the existing bilingual catalog; the school's Block 9/10 identifiers and real course names stay unchanged. No new localization interface or resource bundle.

### 2026-11-21 — bilingual interface / verbatim records
Model: Codex · Added bundled English and Simplified Chinese, sharing language resolution with the activity extension. Affected interfaces: app-local presentation only; no new service API, storage or environment configuration.

### 2026-11-22 — timetable-display / supplemental-courses
Model: OpenAI Codex. Added bilingual display-category, course-type, fallback, and help text to the existing catalog. Imported subjects and typed course titles remain verbatim in both languages.
