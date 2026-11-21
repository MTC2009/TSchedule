# Xiaobao API v1 — frontend contract

This backend supports an independently designed iPad interface. It does not prescribe navigation, card layouts, colors, or screen composition. All sample records are synthetic and scoped to the selected demo student.

Base URL: `http://127.0.0.1:3001/api/v1`.

## Authentication

1. `GET /demo/profiles` lists available demo profiles.
2. `POST /demo/sessions` with `{"profile":"demo-a"}` returns HTTP 201 and `data.access_token`, `data.token_type` (`Bearer`), and `data.expires_at`.
3. Send `Authorization: Bearer <access_token>` for all other business endpoints.
4. `DELETE /session` revokes that token and returns HTTP 204 with no body.

The default demo session lasts eight hours in memory. To remember a device, send `{"profile":"demo-a","remember":true}`. The response also includes `refresh_token` and `refresh_expires_at`. Store the pair and its issuing origin in that device’s secure credential store. The school website uses its own first-party session.

Remembered access tokens last 15 minutes. `POST /session/refresh` accepts a JSON body with the `refresh_token` and returns the same four token/expiry fields. The device secret is stable for this grant. Renewals return the same access token while it is valid, extend the idle deadline by up to 30 days, and enforce a 90-day lifetime from the original login. Coalesce concurrent renewals and retry a failed data request at most once after a 401. A rejected refresh requires a new sign-in. A transport failure permits retry with the saved device secret.

`DELETE /session` accepts the access or refresh token as Bearer for revocation of that device. Data routes only accept access tokens. Persistent grants survive service restarts when the configured SQLite file is retained. Each provider has its own database. Both session modes have independent capacity limits of 128.

## Envelope and errors

All successful business responses except logout use this envelope:

```json
{
  "meta": {
    "source": "demo",
    "availability": "ready",
    "timezone": "Asia/Shanghai",
    "generated_at": "2026-11-18T02:25:00Z"
  },
  "data": {}
}
```

`generated_at` is the response-generation timestamp, **not** a timestamp claiming that school data was synchronized. `source` is `demo` for the current provider and `simulation` for score projections.

`availability`:

- `ready`: matching data is available.
- `empty`: the covered query contains no matching records. A paginated response may also have an empty `items` array when its offset exceeds the matching total.
- `partial`: only part of the requested attendance date range is covered; inspect `data.coverage`.
- `unavailable`: the requested attendance category or period is not covered; `data` is `null`.

Errors use `{"error":{"code":"invalid_request","message":"..."}}`:

| HTTP | Meaning |
| --- | --- |
| 400 | Invalid input, unsupported enum, unknown field, incomplete / invalid date range |
| 401 | Missing, invalid, expired, or revoked bearer token |
| 404 | Unknown route, record, course, or term; also records owned by another account |
| 405 | Unsupported method |
| 413 | JSON body exceeds 8 KiB |
| 415 | JSON endpoint called without the correct content type |
| 429 | Demo session capacity reached |
| 501 | Demo login is disabled by the selected provider |
| 503 | Data source unavailable |
| 500 | Internal error |

Student identity comes from the verified session. Token responses, errors and `/me` carry `Cache-Control: no-store`.

Authenticated data reads from a source with a reliable revision carry a weak ETag, `Vary: Authorization` and `Cache-Control: private, max-age=300`. The directory at `/courses` uses 86,400 seconds. Scope a device cache by login, origin and full query. Fresh hits can be served immediately. For stale rows, show the last check time and send `If-None-Match`. HTTP 304 has an empty body and renews the freshness of the stored representation. HTTP 200 replaces the representation. The backend verifies the session before a 304 and scopes tags to the subject, query, provider revision and relevant school date. A restart invalidates old tags. The provider must retire its revision when data, access rights or availability changes.

Remembered devices retain authorized offline records within their device credential lifetime. Explicit logout, terminal authentication failure and account changes isolate or clear local records. Server-side revocation takes effect on the next authenticated request. A cold device with no saved response shows a retry state.

## Offline synchronization

`GET /offline/versions` requires a valid bearer session. It returns a private envelope containing `data.version` and `data.parts`, a map from readable module names to opaque revisions. The weak ETag belongs to the authenticated subject. Send it in `If-None-Match` on the next check. HTTP 304 has an empty body. Versions are computed when a source publishes data and stay stable over service restarts for unchanged content.

`POST /offline/data` reads all requested modules in one immutable publication. A device compares local revisions with the manifest, then names only the missing or changed modules.

```json
{"version":"<current manifest version>","parts":["attendance"]}
```

The reply echoes the version and includes exactly the requested full records in `data.parts`. HTTP 409 means the snapshot changed between the check and download. Obtain the latest manifest and retry. Apply the response and its revisions atomically. Remove modules omitted from the latest authorized manifest. An unavailable connection preserves the previous successful snapshot.

| Module | Offline contents |
| --- | --- |
| `courses` | IDs, names, rooms and teachers |
| `timetable` | Rotation anchor, cycle length, closures and ordered assigned periods in `days`. Optional `teaching_slots` is indexed in the same order. Optional `school_calendar` gives the dated publication for this account; see Schedule below. Old snapshots can omit both fields. |
| `events` | Published school calendar events |
| `attendance` | Coverage interval, course IDs and individual classroom attendance records |
| `tasks`, `exams`, `evaluations` | Current-term work records, including deadlines and descriptions |
| `resources` | Available library records and the text content supplied by the demo provider |
| `grades` | The full current gradebook, roster and official nullable GPA fields in the grade-sync response shape |

The iPad derives views, attendance rates, timetable dates and score simulations from this snapshot. Historical selections and non-classroom attendance use online GET requests; the existing module keys and offline classroom schema are unchanged. Authentication and data versions are independent. Network errors preserve the device session. A remembered device may opt in to system-scheduled checks, with foreground catch-up when due.

## Profile and courses

`GET /me` returns:

- `profile`: `id`, `name`, `reference_date`, `term`.
- `rotation`: `anchor_date`, `anchor_day`, `cycle_length`, `closures`.

`GET /courses` returns an array of `{id,name,teacher,room}`. `room` is nullable. Join other objects' `course_id` to this array for display labels. Do not parse IDs to derive identity or course names.

## Schedule and calendar

`GET /schedule?date=YYYY-MM-DD`

- Omit `date` to use today's Shanghai date.
- Data: `{date,day,lessons,teaching_slots?,calendar_day?}`. Top-level `day` selects the account's instructional template; `null` means no template applies on that date, not necessarily a confirmed holiday.
- Optional `calendar_day`: `{date,day?,status,notices}`. Its optional `day` is the printed campus rotation and may be present even if the student's division has no class. Status is `teaching`, `no_class`, `weekend` (no regular period in the source; not a closure notice), or `unpublished`. `notices` is a list of calendar text for that scope; it does not create appointments or lessons. Preserve authoritative dated lessons when they conflict with a calendar note.
- Lesson: `{id,course_id,start,end,room}`.
- `start` and `end` are ISO 8601 instants with `+08:00`; `end` is exclusive.
- Lessons are ordered by start time. Use `start <= now < end` for the current lesson and the first future start for the next lesson. An empty list can mean no classes that day.
- `teaching_slots` is optional, not derived from this student's lessons. It contains the school's formal teaching intervals for that day, each `{start,end}` in integer minutes after Shanghai midnight (start inclusive, end exclusive, up to 1440). They must be positive-length and disjoint. Only on a resolved teaching day with a known complete lesson list may the client call a whole slot with **zero overlap** a Free Block. Neither recess nor lunch is a teaching slot. No table, malformed table or unsynchronized lessons means no inferred Free Block. The existing availability flag describes the assigned lessons; the calendar and notification sources still contain only actual lessons.
- The HS preview uses the Main Campus 2026–2027 calendar supplied for review. The assigned courses and bell template **remain synthetic**. With a dated publication, blank/unknown days do not generate regular lessons; an explicit weekend teaching day can. Outside its coverage return `unpublished` and no projected lessons. A source without this publication keeps its existing rotation fallback.
- The bundled campus publishes seven instructional intervals on a full school day. The opening 08:00–09:20 double period is uninterrupted. Assembly (09:30–10:10) and lunch (12:30–13:25) are campus-wide intervals shown by the native client, not teaching slots or lessons returned by the API. Both daily and offline reads preserve the student's six existing assignments. The native app tests its standalone bells and campus-activity projection against both reads.

When present, offline `timetable.school_calendar` contains `{campus,academic_year,division,from,through,source_sha256,days}`. The inclusive coverage has a strictly ordered `calendar_day` for each local date, including dates without an applicable teaching template. Its dates supersede rotation arithmetic only for this publication and account. Older clients can still decode the response, but must be updated to apply dated exceptions correctly; the legacy fields alone cannot represent them. Neither endpoint nor account permissions change.

`GET /calendar?from=YYYY-MM-DD&to=YYYY-MM-DD`

- Supply both bounds or neither. Default: current Shanghai Monday through Sunday.
- Inclusive date bounds, at most 42 days.
- Data: `{range,lessons,events,deadlines}`.
- Events: `{id,title,kind,start,end,all_day}`; include overlapping events. Demo events distinguish `school_calendar` from `activity`. Course blocks are in `lessons`; a week or month is a client view of the same route.
- Deadlines use the work record schema below; their scheduled instant is `due_at`.

All accepted dates must be between 2000-01-01 and 2100-12-31.

## Grades

`GET /grades?term=2026-autumn&course_id=<id>&class_type=teaching&q=...`

All filters are optional. `term` defaults to the current term; `available_terms` lists supported IDs with the current term first. The demo includes the preceding term. An unsupported term is a 404. `class_type` matches the supplied type exactly (`teaching` or `administrative` in the demo). `q` searches course names case-insensitively, using the same length limit as `/work`.

Data: `{term,available_terms,published_gpa,courses}`. A course grade is:

```json
{
  "course_id": "demo-a-c0",
  "class_type": "teaching",
  "class_name": "演示教学班 1",
  "published_score": {"type":"numeric","earned":84,"possible":100},
  "published_letter_grade": "B",
  "first_published_at": "2026-08-01T10:00:00+08:00",
  "published_gpa": null,
  "assessments": [
    {
      "id":"demo-a-c0-a3",
      "title":"专题作业（演示）",
      "date":"2026-11-18",
      "status":"pending",
      "score":null,
      "feedback":null,
      "weight":0.6
    }
  ]
}
```

Score types are `{type:"numeric",earned:number,possible:number|null}` and `{type:"letter",value:string}`. A missing score is `null`. Assessment statuses are `graded`, `pending`, `missing`, `excused`. Preserve the source score type and denominator; do not treat every numeric score as a percentage or replace nulls with zeros.

Class metadata, letter label, publication time, and `assessment.weight` are additive fields. A missing optional field is omitted; a supplied weight is a fraction, not a displayed percentage. Demo class labels, scores and weights are synthetic and do not describe a school policy.

`published_gpa` is nullable at both term and course level. The demo supplies no official GPA policy and therefore leaves these values null. Do not average course percentages or infer weighted / unweighted GPA without an explicit school rule.

### Per-course checks for earlier clients

`POST /grades/sync` is an authenticated, read-only operation for the current term. Send `{}` for the initial check. A successful HTTP 200 response contains `data.version`, `term`, nullable `published_gpa`, an ordered `courses` array of `{course_id,name,revision}` and a `changed` array of complete course grade records. Both demo profiles have six courses. Treat the roster returned for the signed-in account as authoritative.

Subsequent requests send the saved book version and the course revisions that the device actually holds. Use `Content-Type: application/json`. The following values illustrate the shape.

```json
{"version":"saved-book-version","known":{"demo-a-c0":"saved-course-revision"}}
```

A matching book version returns HTTP 204 and zero response bytes. A different version returns HTTP 200 with the full ordered roster and details only for the changed courses. A roster-only or term-GPA change can have an empty `changed` array. Drop records outside the new roster. Keep a local row only when its term, course ID and revision match. Validate and commit the entire result before advancing the saved version. The authenticated subject and term participate in the versions. Stable inputs yield stable versions across service restarts. A production adapter can implement `SchoolProvider::grades_if_changed` against a supported upstream change feed.

Earlier clients can continue to use this per-course protocol. The current iPad client fetches the complete grades module through the offline synchronization endpoint when that module changes.

### Optional score simulation

`POST /grades/project-score`

```json
{"current":88,"assessment":95,"weight":0.3}
```

Both scores must be finite percentages from 0 to 100. `weight` is the assessment's fraction of the **final** score from 0 to 1, not a percentage from 0 to 100. `current` represents all other work. The formula is `current * (1 - weight) + assessment * weight`.

Data contains `projected_score` (approximately 90.1 in the example) and `assumption`. It never modifies grades, and it is not an implementation of Giaoculator's unknown GPA policy. Round only for display.

## Attendance

`GET /attendance?from=...&to=...&category=classroom&course_id=<id>`

- All filters are optional. Date bounds must be supplied together, at most 366 inclusive days.
- Default category: `classroom`. Also supports `daily` and `activity`; each has separate records and its own coverage interval. `course_id` applies only to `classroom`. Requests selecting an owned course in another category remain `unavailable`; IDs outside the account are 404.
- Default date range: the selected category's coverage. In the demo each covers the 30 calendar days ending on the profile's reference date, not necessarily 30 days with records.
- Data: `{range,coverage,category,totals,by_course,records}` or `null` if unavailable.
- `totals`: `{present,late,early,absent,total,present_rate}`.
- `by_course`: `[{course_id,summary}]`, with the same summary fields, or `[]` in `daily` and `activity`.
- `classroom` record: `{id,course_id,date,status}`.
- `daily` record: `{id,date,class_name,status,leave_status}`; `leave_status` is nullable and does not replace `status`.
- `activity` record: `{id,activity_name,start,status}`; date filtering uses the Shanghai date of `start`.
- Shared record status: `present`, `late`, `early`, or `absent`.
- `present_rate` is a fraction from 0 to 1, calculated as `present / total`; it is null when total is zero. The four categories are mutually exclusive here. This is the documented prototype definition, pending verification of the school's definition.
- Statistics are recomputed from the returned, filtered records. Unknown dates contribute neither attendance nor absences.
- If the request partly exceeds coverage, display `partial` alongside statistics. Entirely uncovered dates return `unavailable`, not a zero-percent attendance record.

## Tasks, exams and evaluations

`GET /work?kind=task&status=pending&term=2026-autumn&work_type=practice&task_mode=online&course_id=<id>&from=...&to=...&q=...&offset=0&limit=30`

- `kind`: `task`, `exam`, `evaluation`; omit for all.
- `status`: `pending`, `submitted`, `completed`; omit for all. The synthetic evaluation list uses `pending` and `completed` for its two status views.
- `term`: exact term ID. Defaults to the account's current term (`/me.profile.term`); older records without a term are treated as current. Use the task list's `available_terms` to discover task history, without reading grades. A term with no matching records returns an empty list.
- `work_type`: exact source-provided category, distinct from `kind`; the demo includes `practice`, `reading`, `reflection`, `checkpoint`. `task_mode`: exact `task.mode` value (`online` or `offline` in the demo). Newly added exact text filters are trimmed and limited to 200 characters.
- `course_id`: optional account-owned course. An exam matches if the course is its linked course or has an entry in `exam.results`.
- `from` and `to`: optional inclusive Shanghai dates, at most 366 days; supply both or neither. Uses `exam.start` for exams with timing details, `due_at` otherwise.
- `q`: case-insensitive substring search of titles, trimmed, at most 200 Unicode characters.
- `offset`: nonnegative integer, default 0.
- `limit`: 1–100, default 30.
- Data: `{items,total,offset,limit}`. `total` is the filtered count **before** pagination. Items keep the existing `due_at`, then ID order. With `kind=task`, the demo adds `current_term` and `available_terms` to the page; they describe the same account's task catalog independently of active filters and pagination. Older services can omit both fields.
- Work record: `{id,kind,course_id,title,due_at,status,description}` plus optional `term`, `work_type`, `published_at`, and kind-specific `task` or `exam`. `course_id` may be null. `published_at` is the original RFC 3339 publication time when supplied; it is not a deadline or the start of the task window.
- `task`: `{mode,grading_status,score,attachments}` plus optional `opens_at`, `submission` (`{submitted_at,text,attachments}`) and `feedback` (`{text,attachments}`). Submission `status` and `grading_status` are separate; a submitted task can already be graded, and a missing field does not imply pending grading. `score` uses the shared tagged numeric/letter format and may be null. All attachments are display-only `{name,size_bytes}`; there is no URL or remote file access. A missing answer or feedback says nothing about whether the task was submitted.
- `exam`: `{start,end,score,results}`. `score` is the aggregate grade when supplied, not inferred by the HTTP endpoint. Each result is `{course_id,score}`. One exam can have several subject results.
- `GET /work/{id}` returns a single account-owned record, including a historical one; it does not grant access to an exam-taking or file endpoint.

The prototype supports reading only. It does not submit tasks, launch exams, synchronize Teams, or assert that a student's task is overdue merely from its status. Compare `due_at` to current time and status in the UI where needed.

### Task and exam statistics

`GET /work-statistics?kind=task` or `GET /work-statistics?kind=exam&term=2026-spring`

`kind` is required and must be `task` or `exam`. Uses the same filters and pagination as `/work`. An exam produces one row per subject result (and none if it has no results); a task produces one row even when its score is missing. When a course is selected, exam statistics include **only** that subject's rows.

Data: `{items,total,offset,limit}` with rows `{work_id,kind,term,work_type,course_id,title,at,score,score_rate}`. `at` is the task deadline or exam start used for charting. Rows are ordered by `at`, `work_id`, `course_id`. `score_rate` is `earned / possible` when both numbers are valid and the denominator is positive; otherwise `null`. A genuine numeric zero with a valid denominator stays zero. Render as a percentage in the client; don't substitute 0 for a missing or letter score. This route uses the same authentication and private conditional cache as other collection reads.

## Resources

`GET /resources?scope=shared&kind=document&shared_by_id=<id>&from=...&to=...&q=...&offset=0&limit=30`

- `scope`: `shared`, `personal`; omit for both.
- `kind`: `document`, `image`, `video`, `audio`; omit for all.
- `q` searches the title; `content_q` optionally searches plain text. Both use the same search limits as `/work`. Items are sorted by ID.
- `shared_by_id` selects an exact `shared_by.id`. `from` / `to` follow the work date rules and filter by `shared_at`. These filters exclude records without matching share metadata, including personal-only items.
- Data: `{items,total,offset,limit}`.
- Resource: `{id,title,scope,kind,content}`, optional `size_bytes` and, when known, `shared_by: {id,name}` and `shared_at`. Demo sizes count bytes in the plain-text fixture. Current fixtures are text documents; other supported filters return an empty result.
- `GET /resources/{id}` returns the same resource schema for one account-owned resource.

`content` is demonstration text, not a trusted HTML document or a real remote file. There are no upload, download, or share endpoints yet.

## Frontend integration boundaries

- A web prototype needs `XIAOBAO_WEB_ORIGIN` set to its exact origin. CORS allows GET, POST and DELETE with Authorization, Content-Type and If-None-Match, and exposes ETag and Cache-Control. Native URLSession clients do not require CORS.
- Home, timetable, grade, attendance, work and resource layouts are entirely up to the frontend designer.
- Weather / holidays and visual scene animation have no backend provider yet. Time-based scene selection can use the client's clock in the specified school timezone.
- Class and Day reminders can be prototyped as local iPadOS notifications after permission is granted. This service does not currently register devices or deliver APNs notifications.
- Giaoculator compatibility requires the actual plugin data contract and grading rules. No API in this prototype claims that compatibility is already implemented.
- Before production data is connected, add verified Schoolis authentication, school-supported upstream session renewal, actual upstream schemas, timeouts, and sync freshness. Demo selectors must not become a real-login shortcut.
