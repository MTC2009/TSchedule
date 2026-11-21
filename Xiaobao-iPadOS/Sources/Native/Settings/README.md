# Settings

The existing Settings sidebar route opens one native grouped form. No extra sidebar, login implementation, backend, or new data source.

| View | Input → output / ownership |
| --- | --- |
| `SettingsView`, `SettingsForm` | AppModel state → native navigation links and shared form width; keeps grade tools and version in the overview |
| `AppearanceSettingsView` | Existing environment sheet plus an explicit whole-App icon selection via UIKit; default uses the primary adaptive icon |
| `PersonalInfoSettingsView` | Existing campus account and sign-in controls → unchanged account actions; optional nickname is displayed only in this device's Settings |
| `LessonActivitySettingsView` | Local background and optional heading → loaded current lesson in the same native card, or a neutral empty state; new value is copied into the next started activity, not applied to one already running |
| `ReminderSettingsView` | Confirmed timetable registration → opt-in course alerts and lead; optional subtitle → personal-plan and test content only |
| `PrivacyPolicyView` | [Bundled bilingual policy copy](../../../Resources/PolicyCopy.json) → existing native Privacy form and nested Terms page; no WebKit or sign-in dependency. Starts in English for an English preferred language, otherwise simplified Chinese. The language switch is local to this visit. |

- Dependencies: the [local personalization values](../../Core/Personalization/README.md), AppModel, existing `CampusConnectionSettings`, `GradeTrialSettings`, environment sheet, notification service and shared [activity card](../../ActivityWidget/README.md). RootView consumes `SettingsView()`.
- Limits: no school profile edits, remote push, per-notification app icon, background school reads or new account storage. Only the explicit notification test or explicit reminder opt-ins can request notification permission. Actual notification delivery, Lock Screen material and icon presentation are system decisions.
- Tests: `Tests/SchoolPortalSync/ipad-smoke.py --settings <QA-UUID>` checks the shipping account UI with fresh and legacy preferences, preference edits and relaunch, shared preview, nested navigation, disclosure and narrow/large text. `--delegated` checks the moved enrollment route with the isolated loopback fixture.

## Change History

### 2026-11-21 — local-class-alerts / notification-suspension
Model: Codex. Added the saved timetable’s opt-in switch and lead to the existing Reminders form. A denied permission or unavailable timetable is explained in place. No new page, API or school read.

### 2026-11-21 — annual-timetable / cache-first-today
Model: Codex. Added the in-form 更新课表 action, update date, coverage and failure states. UI does not replace a usable saved timetable on a failed refresh. The existing live-activity preview now reads that same day. The sign-out confirmation discloses the local timetable removal; it does not delete personal plans.


### 2026-11-21 — offline policies
Model: Codex · Keywords: offline-policy / terms / shared-copy
Changed: Read both documents from the same versioned resource as the [static review pages](../../../../docs/tschedule-app-store/04-web/README.md); display the revision, draft status and a user-initiated support email link.
Reason: Students should be able to review data practices and terms without a connection or school account. Interfaces: existing Settings → Privacy, one nested Terms link; no acceptance record, network call, account change or new stored preference.
Verification: On the isolated 11-inch iPad simulator, both languages and back navigation worked; Terms remained accessible after school sign-out at accessibility text size. No GPA read or password submission occurred in that flow. The unsigned device Release contained the same policy file as the generated web pages; the widget did not include it.

### 2026-11-21 — login-result-handoff
Model: Codex · Keywords: school-account-status / manual-handoff
Changed: Personal Info shows a sign-in timeout separately from a school rejection and from required interaction. The existing school-page action can show the original school response.
Reason: A delayed response is not a password error. Interfaces: existing account row and action; no new setting or stored preference.

### 2026-11-21 — shipping-account
Model: Codex · Keywords: shipping-account / current-lesson-preview
Changed: Remove fixture account and reminder controls from standard builds; preview only the verified loaded lesson or a neutral empty state. Document foreground device sign-in consent.
Reason: Keep account boundaries explicit and avoid blocking navigation on redundant reads. Affected interfaces: Existing settings routes, no school mutations.

### 2026-11-21 — Native Settings subpages
Model: Codex (GPT-6.2-sol) · Keywords: settings-routes / adaptive-icon / personal-info / privacy  
Changed: Separate Appearance, Personal Info, Live Activity, Reminders and Privacy, retaining existing grade tools and one school action inside account settings. Reason: Make appearance and device controls discoverable without expanding school access. Affected interfaces: local navigation, personalization and native icon assets only.
Verification: The isolated iPadOS 27 simulator passed the five routes, saving and relaunching with preferences, account disclosure, demo reminders and large type; Settings made no grade reads or password submissions. A separate run verified that UIKit selected the dark alternate and restored the adaptive primary, and that the next started system card used the saved custom heading and background. No physical-device notification delivery was tested. [Overview](../../../../docs/verification/student-interface/settings-overview.jpg) · [Activity preview](../../../../docs/verification/student-interface/settings-activity-preview.jpg).
