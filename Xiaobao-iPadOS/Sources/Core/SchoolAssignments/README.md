# Saved school assignments and deadlines

One device, one verified student, separate semester snapshots. This is local storage for assignment summaries and visible task material, **not** offline authority for a portal request or for GPA. No new backend, credential, API or database. A network outage can show the most recent verified list; account review or an authentication refusal cannot.

- **Inputs / entry:** only the complete school reader result with a verified owner, semester ID and stable task IDs. `SchoolAssignmentStore.accept` reconciles an entire semester by ID, including replacement and withdrawal. Browse other semesters only by explicit selection. No incremental network feed is assumed.
- **Storage:** protected, non-backed-up Application Support files. The random device registration is not a password. A small atomic index carries the last complete check, independent semester filenames and registration-scoped notification preferences. For a changed semester publish new content before replacing its index; unchanged content only updates the check time. On logout/expiry/denial/manual clear, revoke registration before removing owned files. Account review survives process death. The summary type never includes grades or response bodies. Separate detail files contain only visible text and file descriptors; they cannot encode a signed URL, class grade, session, or downloaded file.
- **Outputs:** `snapshot(for:)` returns school-authored titles, dates, course/type and submission state only; the live session can separately render authorized marks. `AssignmentDeadline.make` takes a clock, not a scheduler. After opt-in only the current semester, positive outstanding state and a precise future deadline can produce a one-hour-ahead local notification. A local UUID identifies the same assignment across edits. No school identifier in the OS payload and no title unless explicitly enabled.
- **Consumers:** the portal reads and native app lifecycle, My Tasks, Settings, and the existing shared notification queue. See the root reusable module index for files and parameters.
- **Tests:** `swift test --filter SchoolAssignmentTests`; the native simulator journey and JS paging cases are described in the portal test README.
- **Limits:** an offline copy cannot know about subsequent school changes. School access is foreground-only. A person who can unlock the device may see its previously confirmed assignments. The system may limit pending alerts.

## Change History

### 2026-11-22 — Codex · offline-assignment-snapshot / deadline-reconciliation
Added the protected task-only archive and time projection for offline reading, without expanding portal permissions. Interfaces: accept, snapshot, configure, deadlines, review, verified and forget.

### 2026-11-22 — material-revision / offline-isolation
Model: OpenAI Codex. The independent material type and store load only a current, readable list member (registration + semester + ID + revision). Completed details are atomically written with iOS Complete file protection and excluded from backup. The revision rotates on a changed row or publication flag; withdrawal and revocation remove the copy. The cache has a 32 MiB budget, with oldest entries evicted. Scores, download URLs and file bytes are not cache fields. A fresh online detail supersedes an offline copy. Interfaces: containsTask(term:task:), materialKeys/materialKey, material, saveMaterial, removeMaterial. Tests: SchoolTaskMaterialTests and the isolated two-student iPad fixture.
