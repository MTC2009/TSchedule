# Attendance reads

Builds the authenticated attendance report for the requested category. `mod.rs` dispatches to the existing classroom calculation or tallies independent daily/activity records. The selected source coverage controls the difference between zero recorded events and unavailable dates.

- **Input:** An authenticated `CurrentStudent`, optional pair of Shanghai dates, category, and classroom course filter.
- **Output:** Category coverage, raw records and computed counts in the common JSON envelope, or `unavailable` with null data. The classroom schema is unchanged.
- **Interface:** `GET /api/v1/attendance`; default `category=classroom`, with `daily` and `activity` also available. See [API.md](../../API.md).
- **Dependencies:** Shared HTTP helpers in `api.rs`, `auth::CurrentStudent`, and attendance types/tallying in `domain.rs`.
- **Consumers:** `src/lib.rs` registers `read`. `tests/api.rs` covers original classroom behavior; `tests/api/portal_pages.rs` covers distinct categories and range boundaries.
- **Test:** `cargo test --locked --test api attendance_` and `cargo test --locked --test device_cache offline_manifest`.
- **Limits:** Daily and activity records are online only in this release. Coverage and leave labels come from demo data and do not reflect a verified school attendance policy.

## Change History

### 2026-11-18

Model: gpt-6.2-sol

Conversation Keywords: student-portal-pages / daily-activity-attendance

Changed: Preserved the classroom handler contract and added daily/activity record schemas and coverage handling.

Reason: Match the three attendance pages without treating the non-classroom categories as course records.

Affected interfaces: `GET /attendance` (additive); offline `attendance` remains classroom-only.
