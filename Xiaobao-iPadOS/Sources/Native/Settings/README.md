# Settings

The existing Settings sidebar route opens one native grouped form. No extra sidebar, login implementation, backend, or new data source.

| View | Input → output / ownership |
| --- | --- |
| `SettingsView`, `SettingsForm` | AppModel state → native navigation links and shared form width; keeps grade tools and version in the overview |
| `AppearanceSettingsView` | Existing environment sheet plus an explicit whole-App icon selection via UIKit; default uses the primary adaptive icon |
| `PersonalInfoSettingsView` | Existing campus account and sign-in controls → unchanged account actions; optional nickname is displayed only in this device's Settings |
| `LessonActivitySettingsView` | Local background and optional heading → sample of the same native card; new value is copied into the next started activity, not applied to one already running |
| `ReminderSettingsView` | Existing demo timetable switches, optional subtitle and explicit notification check → device personal-plan and test request content |
| `PrivacyPolicyView` | Native explanation of the current data paths, disclosure on the Lock Screen and user controls; not a hosted App Store privacy URL |

- Dependencies: the [local personalization values](../../Core/Personalization/README.md), AppModel, existing `CampusConnectionSettings`, `GradeTrialSettings`, environment sheet, notification service and shared [activity card](../../ActivityWidget/README.md). RootView consumes `SettingsView()`.
- Limits: no school profile edits, school notifications, per-notification app icon, background school reads or new account storage. Only the explicit notification test or pre-existing enable actions can request notification permission. Actual notification delivery, Lock Screen material and icon presentation are system decisions.
- Tests: `Tests/SchoolPortalSync/ipad-smoke.py --settings <QA-UUID>` checks both account modes, preference edits and relaunch, shared preview, nested navigation, disclosure and narrow/large text. `--delegated` checks the moved enrollment route with the isolated loopback fixture.

## Change History
### 2026-11-21 — Native Settings subpages
Model: Codex (GPT-6.2-sol) · Keywords: settings-routes / adaptive-icon / personal-info / privacy  
Changed: Separate Appearance, Personal Info, Live Activity, Reminders and Privacy, retaining existing grade tools and one school action inside account settings. Reason: Make appearance and device controls discoverable without expanding school access. Affected interfaces: local navigation, personalization and native icon assets only.
Verification: The isolated iPadOS 27 simulator passed the five routes, saving and relaunching with preferences, account disclosure, demo reminders and large type; Settings made no grade reads or password submissions. A separate run verified that UIKit selected the dark alternate and restored the adaptive primary, and that the next started system card used the saved custom heading and background. No physical-device notification delivery was tested. [Overview](../../../../docs/verification/student-interface/settings-overview.jpg) · [Activity preview](../../../../docs/verification/student-interface/settings-activity-preview.jpg).
