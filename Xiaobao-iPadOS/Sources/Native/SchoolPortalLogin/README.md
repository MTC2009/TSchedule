# Foreground school sign-in

Optional, device-only sign-in for **one already verified student**. It is distinct from reusing a valid WebKit session and from the Rust demo refresh token. Disabled by default. A grade read does not enroll the student.

**Enrollment:** in Settings → 个人信息 → 校园资料 the student opens 设置本机代登录 and supplies their password in a native secure field. The [school store](../../Core/SchoolPortalData/README.md) obtains the login name for the verified student, rechecks the owner, and discards the rest of the profile. There is no editable target account or school URL. The form clears on dismissal/background; an account or screen change cancels unfinished enrollment.

**Use:** A grade visit or refresh may recover the existing school session. Fresh enrollment also discloses foreground startup recovery; an older binding remains grade-only until the student enables “打开 App 时恢复登录”. Startup first tries WebKit. Only a confirmed login requirement can use the bound account once; it must verify the same owner before revealing records and does not read grades. Network failure, manual browsing, background and challenges do not initiate password submission. A failed or interrupted submission stays paused; explicit app logout removes the binding. Seeing the login page alone is not a request to forget it.

| File / interface | Inputs → outputs | Consumers |
| --- | --- | --- |
| `SchoolPortalLoginSettings.swift`, `SchoolPortalLoginSettings()` | Verified student, explicit opt-in and native secure input → enable or remove the current binding | `../CampusView.swift` |
| `SchoolPortalLoginVault.swift`, `enable / setRestoresOnLaunch / claim / confirm / disable` | Verified owner and official login name → one Keychain item; claim allowed only for the same owner. Only metadata is read for normal screens. | Settings, `../AppModel.swift` and its logout/lifecycle hooks |
| `SchoolPortalPasswordEntry.swift`, `run(_:allowed:claim:)` | Original WebKit view, foreground guard, scoped credential callback → lands on official Home or returns a typed failure | `../SchoolPortal.swift` for one eligible foreground action |
| `PortalLogin.js` | Fixed isolated-world operations: inspect normal controls, submit once, clear only the inputs this operation populated → status string only | `SchoolPortalPasswordEntry`; Xcode bundles it as a signed resource |

**Protection:** the Keychain service is separate from the demo service. Its item is non-synchronizable and uses [WhenPasscodeSetThisDeviceOnly](https://developer.apple.com/documentation/security/ksecattraccessiblewhenpasscodesetthisdeviceonly). It does not fall back to a weaker protection class. Preferences contain only a random registration ID and an erase-pending flag. Before releasing a password, the vault durably pauses the entry. A matching independent identity check re-arms startup recovery; recovery on a GPA visit also checks for fresh grades. If the app is interrupted, the password is rejected, or the outcome is ambiguous after submission, the student may need to sign in normally and re-enroll. Opt-out, explicit logout in the app, and a confirmed account change revoke the binding. An expired web session alone does not. Deletion targets only this item's service and account; if protected storage was unavailable, cleanup is retried after unlock. No credential or academic record is logged.

**Limits:** the fixed first-party Chinese login UI must have the recognized ordinary username/password controls. Do not chase alternate destinations, suppress verification, or submit to guessed network routes. Unknown controls, CAPTCHA/OTP, popups, HTTP credential challenges or third-party navigation require the student. This is not a live-school sign-in certification, a school integration grant or a school-wide account service.

**Tests:** [integration and on-device steps](../../../Tests/SchoolPortalSync/README.md). Node checks preflight and zero submissions to unrecognized pages. Swift tests fence identities, account changes, failures and explicit visits. The isolated iPad UI test exercises a real simulator Keychain and a synthetic school's actual password check without any live credential.

## Change History

### 2026-11-21 — foreground-restore
Model: Codex · Keywords: foreground-restore / keychain-consent
Changed: New enrollments disclose startup recovery; old bindings can opt in without re-entering the password. A signed-out page does not erase the binding.
Reason: Keep account boundaries explicit and avoid blocking navigation on redundant reads. Affected interfaces: enable(restoresOnLaunch:), setRestoresOnLaunch, claim/confirm and explicit removal.

### 2026-11-21 — Device sign-in disclosure
Model: Codex · Keywords: settings-disclosure / account-status  
Changed: Settings separates school account status from the persistent device sign-in state; one disclosure reveals explicit enrollment or removal. Temporary sessions and signed-out students get no password form. Reason: make an optional device credential understandable without a repeated prompt. Affected interfaces: Settings presentation only; Keychain protection and permitted triggers do not change.
### 2026-11-21 — Explicit per-device enrollment
Model: Codex · Keywords: foreground-password-login / single-student-keychain / full-expiry  
Changed: Added enrollment, device-only storage, durable attempt pause, one foreground official sign-in and removal. Reason: re-entering Home cannot authenticate a student after *all* school session state has been rejected. Affected interfaces: only the native grade visit, enrollment-name read, existing Settings and one bundled resource. No public API, database or deployment change.
