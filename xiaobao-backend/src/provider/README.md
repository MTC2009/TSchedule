# Demo data provider

`../provider.rs` defines `SchoolProvider`, the account-scoped source boundary, and the immutable `DemoProvider` used by the binary. `demo.rs` builds the synthetic student snapshots; it has no network or file access.

- **Input:** A demo reference date and an authenticated subject on reads. The binary also reads the compiled-in HS calendar; it is shared with the iPad bundle as data, not a dependency on the UI.
- **Output:** A normalized student snapshot, per-day lessons, and published offline module versions and data. `demo.rs` also supplies previous-term grades/work, task and exam scores, categories of attendance, library metadata and calendar records.
- **Interface:** `SchoolProvider::{student, lessons, grades_if_changed, offline_catalog, demo_profiles, cache_revision, source}`; `DemoProvider::new(date)` for the legacy fixture, or `DemoProvider::with_hs_calendar(date)` for the bounded publication used by the binary. Consumers outside the Rust crate use the [HTTP contract](../../API.md), not the Rust structs.
- **Dependencies:** `domain.rs`, `grade_sync.rs`, and `offline.rs` for normalized records and immutable releases.
- **Consumers:** The server composition, authentication, read handlers, offline/cache handlers and integration tests, as indexed in [REUSABLE_MODULES.md](../../../REUSABLE_MODULES.md).
- **Test:** `cargo test --locked`. From the workspace, `python3 xiaobao-backend/scripts/build-school-calendar.py` checks the resource against the reviewed calendar; pass `--output` with a new path to review a derivative without replacing the existing file.
- **Limits:** The dated school calendar is transcribed from the supplied Main Campus 2026–2027 image, not a live school feed. Courses, grades, attendance, and identity remain synthetic. The earlier school year is not bundled.

## Change History

### 2026-11-20 — HS dated calendar
Model: GPT-6.2-Sol · Keywords: hs-calendar / timetable-week / dated-school-status  
Changed: The binary uses the shared HS publication for teaching eligibility. The daily response adds optional `calendar_day`; the offline timetable adds optional `school_calendar` and versions the new contents. Legacy fixtures retain their original rotation.  
Reason: Published Day, student attendance eligibility, and no-data dates cannot be represented by a single weekday counter.  
Affected interfaces: Additive timetable fields and the fixture's calendar lesson dates; no auth, database, environment, or deployment changes.

### 2026-11-19 — Campus bell alignment
Model: Codex · Keywords: campus-bells / school-lunch  
Changed: `CAMPUS_TEACHING_SLOTS` supplies both the published school day and the times for the six enrolled demo courses. It contains seven teaching intervals, without lunch; the private cache revision changed to invalidate old timetables.  
Reason: The roster is not a bell table; neither a midday gap nor the middle of a double period is another subject.  
Affected interfaces: Fixture times on the daily/calendar and offline reads, not the response schema or authentication.

### 2026-11-19 — Formal teaching slots
Model: Codex · Keywords: bell-schedule / freeblock  
Changed: The synthetic school publishes its six existing formal intervals per rotation day independently of the student's course roster. Daily lessons and offline periods still use the same assignment times, and the private GET cache revision advanced.  
Reason: A gap in one student's course list does not identify a school teaching slot. A source without a bell schedule can leave the optional table unset.  
Affected interfaces: Additive schedule and offline timetable metadata; no changed course, identifier, session or database. See the [contract](../../API.md#schedule-and-calendar).

### 2026-11-19 — Student-facing fixture copy

Model: Codex · Keywords: student-copy / provider-revision  
Changed: Synthetic student names, work, library, assessments and event labels use student-facing wording. Advanced the provider cache revision so older copies revalidate.  
Reason: Clients can display structured records as authored; they do not need to filter school-supplied text.  
Affected interfaces: Fixture display values and conditional read validators only; account IDs, source marker, response shapes and authorization are unchanged.

### 2026-11-18

Model: gpt-6.2-sol

Conversation Keywords: student-portal-pages / synthetic-student-snapshot

Changed: Separated demo data generation from source dispatch and added page fixtures without importing real records. `SchoolProvider` method signatures are unchanged.

Reason: Keep page data and the provider boundary separately maintainable.

Affected interfaces: Demo data returned by work, grades, calendar, attendance, resources and statistics. Offline dates and module keys retain their original scope; work is current-term only.

### 2026-11-18 — Calendar performance

Model: gpt-6.2-sol

Conversation Keywords: calendar-performance / lesson-id-reuse

Changed: `DemoProvider::lessons` formats the shared date suffix once per teaching day and allocates each lesson ID with its final byte length. `tests/api.rs` checks multiweek output for IDs, account scope, weekdays and chronology.

Reason: Remove repeated formatting and buffer growth without caching or changing course/timetable data.

Affected interfaces: `SchoolProvider::lessons`, `GET /schedule` and `GET /calendar` retain the same signatures, output and order. Offline publication is unchanged.
