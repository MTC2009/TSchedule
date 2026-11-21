# Work reads

Serves the authenticated task, exam and evaluation lists and their record details. The HTTP handlers in `mod.rs` share filter validation. `statistics.rs` converts the filtered tasks or exam subject results into ordered, paginated chart/table rows with nullable rates. This module neither writes records nor launches tasks or exams.

- **Input:** An authenticated `CurrentStudent`, query filters or a work record ID. List/statistics use the current term by default; a historical term can be selected explicitly.
- **Output:** The existing API v1 JSON envelope, with a single record or a paginated collection.
- **Interface:** `GET /api/v1/work`, `GET /api/v1/work/{id}`, `GET /api/v1/work-statistics`. See [API.md](../../API.md) for fields, sorting and limits.
- **Dependencies:** Shared HTTP helpers in `api.rs`, `auth::CurrentStudent`, `domain::{Work, WorkKind, WorkStatus, Score, Student}`. It does not call the school or an interface-specific client.
- **Consumers:** `src/lib.rs` registers each handler; task/exam/evaluation clients consume the HTTP contract. `tests/api/portal_pages.rs` tests filtering, data isolation, nullable scores and the per-subject denominator; `tests/device_cache.rs` covers revalidation.
- **Test:** `cargo test --locked --test api portal_pages` and `cargo test --locked --test device_cache statistics_are_cached`.
- **Limits:** Only the two demo accounts exist. Historical task/exam details are online reads. Attachment names do not imply real files. Unknown work term filters produce an empty page; letters and null/invalid denominators produce a null rate.

## Change History

### 2026-11-20

Model: Codex  
Conversation Keywords: tasks-glass-grid / task-term-catalog / read-only-answers  
Changed: Task pages add an authorized term directory. Work can carry optional publication, task opening, answer and feedback fields; attachment pointers remain names only. Normal list order, task paging and exam/statistics semantics are unchanged.  
Reason: Let the frontend select a real task term and render known details without using grade records or issuing a write.  
Affected interfaces: Additive task fields on `GET /work`, `GET /work/{id}` and existing current-term task bundles. No route, storage or credential changes.

### 2026-11-18

Model: gpt-6.2-sol

Conversation Keywords: student-portal-pages / work-list / exam-subject-statistics

Changed: Moved the existing work read handlers here, added term/type/mode/date filters and one shared task/exam statistics handler.

Reason: Keep statistics and work lists aligned without duplicating filters or growing the common HTTP file.

Affected interfaces: `GET /work`, `GET /work/{id}`, `GET /work-statistics`.
