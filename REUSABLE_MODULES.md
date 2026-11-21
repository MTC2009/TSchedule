# Reusable modules

Paths are relative to `<repo-root>`. The native app and demo backend are separate. School-service HTTP contracts are defined in [API.md](xiaobao-backend/API.md). Only the isolated city reader calls the public weather endpoint; the renderer itself does not network.

## TSchedule campus mark

Category: Frontend UI assets · Status: Active. Path: `<repo-root>/Xiaobao-iPadOS/Resources/Assets.xcassets/`. Entries: adaptive `AppIcon` (1024 px master copies), its explicit alternatives `AppIconLight` / `AppIconDark`, and adaptive `TScheduleMark` (96 px). Defaults: original colors, no template tint; the app and system each resolve their own appearance. [Source and update notes](docs/tschedule-icon/README.md).

### Consumers

| File | Usage | Parameters | Purpose |
| --- | --- | --- | --- |
| `Xiaobao-iPadOS/Sources/Native/XiaobaoApp.swift` | Sidebar title | image = TScheduleMark, 24 pt, effective app color scheme; spoken label = TSchedule; image is decorative | Identify the app without adding a navigation action |
| `Xiaobao-iPadOS/Sources/ActivityWidget/LessonActivityCard.swift` | Lock Screen mark and preview, via `TScheduleMark(size:)` | image = adaptive TScheduleMark; 18 pt in card; decorative | Keep the native preview and Lock Screen rendering consistent |
| `Xiaobao-iPadOS/Sources/ActivityWidget/LessonActivityWidget.swift` | Compact/minimal mark | size = 16 pt; system appearance | Use the same approved mark with no widget-only artwork |
| `Xiaobao-iPadOS/Sources/Native/Settings/AppearanceSettingsView.swift` | App icon choices and miniature mark | size = 28 pt; preview scheme = selected rendition; existing AppIcon when alternate name is nil | Show the approved light and dark choices before a user changes its app-wide icon |
| `Xiaobao-iPadOS/scripts/generate_project.py`, `Xiaobao-iPadOS/Xiaobao.xcodeproj/project.pbxproj` | App icon compiler setting | primary = AppIcon; alternate = AppIconLight / AppIconDark; app target only | Supply iPadOS with all supported app icon choices |
| `Xiaobao-iPadOS/Sources/Native/ReminderService.swift` | Standard local notification (indirect system consumer) | AppIcon = chosen by iPadOS; content supplies no icon or appearance override | Use native notification branding without changing reminder permissions or routing |
| `Xiaobao-iPadOS/scripts/check.sh` | Verify asset manifests | 1024 px and 96 px appearances; each alternate equals its approved master | Detect missing or divergent artwork |
| `Xiaobao-iPadOS/Tests/SchoolPortalSync/SettingsUITests.swift` | Observe native heading | identifier = sidebar-brand; label = TSchedule | Check the actual sidebar on an isolated simulator |

## Native Settings form and routes

Category: Frontend Composite Component · Status: Active. Entry: `SettingsView()` and `SettingsForm(content:)` in `<repo-root>/Xiaobao-iPadOS/Sources/Native/Settings/SettingsView.swift`. Default: native Form, transparent scroll backdrop, centered 840 pt maximum width; content owns its own rows. [Responsibilities and tests](Xiaobao-iPadOS/Sources/Native/Settings/README.md).

### Consumers

| File | Usage | Parameters | Purpose |
| --- | --- | --- | --- |
| `Xiaobao-iPadOS/Sources/Native/XiaobaoApp.swift` | SettingsView | injected AppModel and AppScreen navigation; no special parameters | Keep one sidebar entry |
| `Xiaobao-iPadOS/Sources/Native/Settings/SettingsView.swift` | SettingsForm | content = grouped links, existing grade tools, version | Show all reachable settings without splitting the sidebar |
| `Xiaobao-iPadOS/Sources/Native/Settings/AppearanceSettingsView.swift` | SettingsForm; existing EnvironmentView via AppModel flag | content = environment trigger and UIKit-managed icon choices | Reuse the existing weather and app appearance controls |
| `Xiaobao-iPadOS/Sources/Native/Settings/PersonalInfoSettingsView.swift` | SettingsForm; existing CampusConnectionSettings with no overrides | content = campus account/actions and optional local nickname | Keep school login in one place without editing the school profile |
| `Xiaobao-iPadOS/Sources/Native/Settings/LessonActivitySettingsView.swift` | SettingsForm | content = sample card and display style fields | Preview styles without starting or extending an Activity |
| `Xiaobao-iPadOS/Sources/Native/Settings/ReminderSettingsView.swift` | SettingsForm | content = local subtitle, test and conditionally available demo reminders | Avoid offering school timetable switches that don't work |
| `Xiaobao-iPadOS/Sources/Native/Settings/PrivacyPolicyView.swift` | SettingsForm | content = native readable privacy information | Explain local handling and user choices without a web view |

## Local personalization and activity appearance

Category: Shared Types / Contracts · Status: Active. Entry: `LocalPersonalization`, `LessonActivityAppearance` in `<repo-root>/Xiaobao-iPadOS/Sources/Core/Personalization/LocalPersonalization.swift`. Defaults: optional text absent, system background. Depends only on Foundation. [Limits and encoding](Xiaobao-iPadOS/Sources/Core/Personalization/README.md).

### Consumers

| File | Usage | Parameters | Purpose |
| --- | --- | --- | --- |
| `Xiaobao-iPadOS/Sources/Native/AppModel.swift` | Persist and read choices | independent UserDefaults key; forward only reminder subtitle to current plan scheduling | Do not migrate or overwrite school/session settings |
| `Xiaobao-iPadOS/Sources/Native/Settings/SettingsView.swift`, `PersonalInfoSettingsView.swift` in the same directory | Display and edit nickname | input = locally entered text; blank restores no nickname | Personalize Settings only |
| `Xiaobao-iPadOS/Sources/Native/Settings/ReminderSettingsView.swift` | Edit reminder subtitle | input = explicit save; refresh pending personal requests, no permission on save | Apply choice without reaching school notifications |
| `Xiaobao-iPadOS/Sources/Native/Settings/LessonActivitySettingsView.swift` | Edit activity appearance | background = native picker; heading = draft for preview, saved only on action | Style the next start; no activity or academic changes from preview |
| `Xiaobao-iPadOS/Sources/Native/LessonActivity/LessonActivityControl.swift`, `LessonActivityController.swift` | Copy chosen appearance at start | appearance = persisted local choice only; lifecycle = existing foreground action | Send no nickname, credentials or reminder text to ActivityKit |
| `Xiaobao-iPadOS/Sources/ActivityWidget/LessonActivityAttributes.swift`, `LessonActivityCard.swift`, `LessonActivityWidget.swift` | Decode/render appearance | optional = old states still decode; draw system fallback when absent | Preserve bounded Lock Screen data |
| `Xiaobao-iPadOS/Tests/Core/LocalPersonalizationTests.swift`, `Tests/SchoolPortalSync/SettingsUITests.swift` under the native app | Boundary and relaunch tests | synthetic display values only | Verify persistence, normalization and safe fallback |

## GlassCard

Category: Frontend UI Component · Status: Active  
Path / entry: `<repo-root>/Xiaobao-iPadOS/Sources/Native/GlassComponents.swift`, `GlassCard(padding:shape:content:)`. Content is required; padding defaults to 26 pt and the shape defaults to the existing 30 pt continuous rounded rectangle. The same shape defines the selected glass material and its existing opaque system fallback for Reduce Transparency. See the [design system](UI_DESIGN_SYSTEM.md).

### Consumers

| File | Usage | Parameters | Purpose |
| --- | --- | --- | --- |
| `Xiaobao-iPadOS/Sources/Native/TodayView.swift` | Focus lesson card | padding = default; content = resolved time and school focus | Read the current or next school block |
| `Xiaobao-iPadOS/Sources/Native/GPA/GPAOverviewView.swift` | GPA overview | padding = default; content = stacked heading, right-aligned readout, existing visibility action, term and provenance | Match the Today card without changing GPA behavior |
| `Xiaobao-iPadOS/Sources/Native/GPA/CourseGradeList.swift` | Course tile and filtered empty state | padding = 22; content = linked course name and total or a no-match explanation | Present grades as distinct rounded tiles with the shared material |
| `Xiaobao-iPadOS/Sources/Native/GPA/CourseGradesView.swift` | Published course total, history preview and task table | shape = 16 pt continuous; padding = 16 for the total and preview, 0 for the table (insets owned by `CourseTaskList`); content = published summary, actual history or task table | Apply the same Today material and transparency fallback once per outer panel |
| `Xiaobao-iPadOS/Sources/Native/Tasks/TaskFilterBar.swift` | Toolbar surface | padding = 14; shape = 18 pt continuous; content = task facets, search and reset | Keep controls grouped with the shared material |
| `Xiaobao-iPadOS/Sources/Native/Tasks/TaskCard.swift` | Task tile | padding = 0; shape = 30 pt continuous (also clips status overlay); content = task summary at an 18 pt inset, optional score above secondary metadata, and a flush ribbon | Match the GPA grid without adding another glass layer |
| `Xiaobao-iPadOS/Sources/Native/Tasks/TaskDetailView.swift` | Task metadata, reading and evaluation panels | padding = 20; shape = 16 pt continuous; content = selected task, instruction/answer and grade/feedback | Reuse the course detail's corner treatment without applying material to individual fields |
| `Xiaobao-iPadOS/Sources/Native/CampusView.swift` | Connected timetable and attendance surfaces | course attendance table: padding = 18, shape = 18 pt continuous; labeled rows and fallback disclosure: defaults | Keep read-only school records in native surfaces; exam, evaluation and resource pages use `OtherItemsGrid` |
| `Xiaobao-iPadOS/Sources/Native/SchoolPortalSync/SchoolPortalAttendancePage.swift` | Native school details and paged course records | padding = 18; shape = existing 18 pt rect; content = selected category and page | Keep real and demo school records visually consistent |
| `Xiaobao-iPadOS/Sources/Native/AttendanceView.swift` | Attendance filter frame, summary, course table and coverage | filters: padding = 12, shape = 18 pt continuous; summary and course table: padding = 18, shape = 18 pt continuous; other uses: defaults | Keep the two filter rows in one glass frame; match the data cards' width when stacked and height when side by side |
| `Xiaobao-iPadOS/Sources/Native/StudentServicesView.swift` | Existing school entry detail | padding and shape = defaults; content = Planner's local work detail | Keep the original Planner presentation |
| `Xiaobao-iPadOS/Sources/Native/OtherItems/OtherItemsGrid.swift` | Exam, evaluation and resource tiles | padding = 0; shape = default 30 pt; content = item title and type-specific metadata with an 18 pt inset | Match the existing My Tasks tiles without task-only states |
| `Xiaobao-iPadOS/Sources/Native/OtherItems/OtherItemsFilterBar.swift` | Compact filter controls | padding = 14; shape = 18 pt continuous; content = course, optional status/bookmark, short adjacent search | Keep My Tasks controls without consuming the whole row or adding summary counters |
| `Xiaobao-iPadOS/Sources/Native/OtherItems/OtherItemsDetails.swift` | Schedule, notes, evaluation and reading surfaces | padding = 20 for work, 24 for reading; shape = 16 pt continuous; content = selected record's original fields | Keep three kinds of content readable without a new color system |
| `Xiaobao-iPadOS/Sources/Native/Planner/PlannerView.swift` | School and storage status | padding = 8 for failure, 10 for retry; shape = PlannerCorners.card; content = selected scope state | Show status without a white panel |
| `Xiaobao-iPadOS/Sources/Native/Planner/PlannerTimelineView.swift` | All-day group, drag preview and range control | padding = 10 for notices, 9 for drag preview, 12 for range controls; shape = PlannerCorners.card or PlannerCorners.tray; content = school notices, current drop target or draft range instructions | Keep controls separate from timed card positions |
| `Xiaobao-iPadOS/Sources/Native/Planner/PlannerScheduleCanvas.swift` | Timed school card | padding = 0; shape = PlannerCorners.card; content = measured school label | Reuse material and its opaque fallback without changing school geometry; the personal annotation has no card backing |
| `Xiaobao-iPadOS/Sources/Native/Planner/PlannerInboxView.swift` | Edit-only pinned bubble shelf | padding = 12; shape = PlannerCorners.tray; content = bubble scroller, one add button and optional reminder status | Keep drag sources reachable in Edit without reserving space in Browse |

## TodayRotationHeader

Category: Frontend UI Component · Status: Active  
Path / entry: `<repo-root>/Xiaobao-iPadOS/Sources/Native/StudentComponents.swift`, `TodayRotationHeader(date:day:unpublished:unknownDayTitle:)`. Displays the rotation and school date as one accessible heading. Date and day are required. `unpublished` defaults to false; use true for a resolved publication that has no Day. A neutral unknownDayTitle can be passed for an actual dated source with no validated rotation. Typography and wrapping are otherwise unchanged. See the [native module](Xiaobao-iPadOS/README.md) and [visual rules](UI_DESIGN_SYSTEM.md).

### Consumers

| File | Usage | Parameters | Purpose |
| --- | --- | --- | --- |
| `Xiaobao-iPadOS/Sources/Native/SchoolPortalSync/SchoolPortalPages.swift` | SchoolPortalToday | date = model.now; day = real schedule day if supplied; unknownDayTitle = 今日课表 | An unknown rotation is not a rest day |
| `Xiaobao-iPadOS/Sources/Native/TodayView.swift` | First element of the local Today page | date = model.now; day = model.todayRotationDay; unpublished = publication marks the date unpublished | Share the toolbar's calendar source independently of the time lens |
| `Xiaobao-iPadOS/Sources/Native/CampusView.swift` | First element of connected Today once the schedule has loaded | date = model.now; day = model.todayRotationDay; unpublished = its calendar status | Use the authorized timetable, not a local fallback |

## TimetableWeek

Category: Frontend Utility · Status: Active  
Path / entry: `<repo-root>/Xiaobao-iPadOS/Sources/Core/TimetableWeek.swift`, `TimetableWeek(containing:)`. Given a date, returns its Shanghai Sunday-first week, including the first date, last date and all seven dates. No defaults, I/O or assumption about school openings. See the [Planner module](Xiaobao-iPadOS/Sources/Native/Planner/README.md). The former standalone view is retired; the old layout projection in this file is retained by existing regression tests only.

### Consumers

| File | Usage | Parameters | Purpose |
| --- | --- | --- | --- |
| `Xiaobao-iPadOS/Sources/Core/SchoolPortalData/SchoolPortalStore.swift`, `SchoolPortalData.swift` (same directory) | Resolve and validate one live week | containing = selected Shanghai date; store keys = start/end | Date-bounded actual data, not a rotation template |
| `Xiaobao-iPadOS/Sources/Native/Planner/PlannerView.swift` | Week window | containing = Planner selected date | Align the seven day columns and date jumps to the same week |
| `Xiaobao-iPadOS/Sources/Core/Planner/PlanBubble.swift` | TimetableWeek boundary | containing = reschedule destination date | Relocate the future series, not a single displayed occurrence |
| `Xiaobao-iPadOS/Tests/Core/WeekTimetableTests.swift`, `Xiaobao-iPadOS/Tests/Core/CampusConnectionTests.swift` | Date/layout and account integration tests | independent overlaps, matching and shortened campus intervals, closure/unknown dates and live loopback or legacy fixtures | Verify week boundaries, real duration, grouping, scoped caches and no-request projection |

## PublishedSchoolCalendar and SchoolCalendarDay

Category: Shared Types / Contract · Status: Active  
Paths / entry: `<repo-root>/xiaobao-backend/src/provider/academic-calendar-hs-2026-2027.json`, Rust `src/domain.rs`, Swift `Xiaobao-iPadOS/Sources/Core/PublishedSchoolCalendar.swift`. A dated, complete coverage uses the printed Day separately from teaching status. Missing publication is a legacy fallback; date outside a present publication is unpublished. No dependency on account identity or UI. See the [provider module](xiaobao-backend/src/provider/README.md) and [HTTP contract](xiaobao-backend/API.md#schedule-and-calendar).

### Consumers

| File | Usage | Parameters | Purpose |
| --- | --- | --- | --- |
| `xiaobao-backend/scripts/build-school-calendar.py` | Reads reviewed current-year data, produces the bundled resource or checks it | campus = Main Campus; division = HS; source = reviewed date records and notes | Keep runtime data traceable and exclude older year/other divisions |
| `xiaobao-backend/src/provider.rs`, `xiaobao-backend/src/main.rs` | Decodes and validates the shared asset, installs it on the HS preview | publication = bundled HS; reference date = Shanghai today | Set teaching eligibility without changing synthetic course assignments |
| `xiaobao-backend/src/api.rs`, `xiaobao-backend/src/offline.rs` | Writes `calendar_day` or `school_calendar` | date = requested date; publication = active subject's source | Carry the same statuses on daily and offline reads |
| `Xiaobao-iPadOS/scripts/generate_project.py`, `Xiaobao-iPadOS/Sources/Core/SchoolDay.swift` | Bundles and loads one shared file for `DemoSchoolProvider.local` | publication = bundledHS; legacy fallback only if not available | Keep the standalone timetable and in-class exam fixtures on the same rotation |
| `Xiaobao-iPadOS/Sources/Core/SchoolDay.swift`, `Xiaobao-iPadOS/Sources/Core/CampusOffline.swift`, `Xiaobao-iPadOS/Sources/Core/CampusPage.swift` | Resolve dates, decode and project account data | decoded publication optional; cycle length = existing provider/template; requested local date | Do not insert routine course blocks on closures or unpublished dates |
| `Xiaobao-iPadOS/Sources/Native/AppModel.swift`, `TodayView.swift`, `CampusView.swift` (same directory) | Read printed Day and status | today's school date; local publication or authorized schedule; no demo fallback for a connected account | Keep the shared toolbar and Today's heading on the same Day source without mislabeling a missing record |
| `Xiaobao-iPadOS/Sources/Native/Planner/PlannerSchoolSource.swift`, `Xiaobao-iPadOS/Sources/Core/Planner/PlannerCalendarMonth.swift` | Read HS dates for headings and month notices | publication = bundled main HS; connected day status = authorized daily metadata when available; month cells = Shanghai date | Preserve real courses and distinguish holidays from events or unpublished dates |
| `Xiaobao-iPadOS/Tests/Core/WeekTimetableTests.swift`, `Xiaobao-iPadOS/Tests/Core/CampusConnectionTests.swift`, `xiaobao-backend/tests/device_cache.rs` | Compare source, snapshots and dated HTTP responses | test calendar, real bundled dates and isolated synthetic subjects | Verify authorization, term resets, closures, coverage and compatibility |

## TodayTimetableView

Category: Frontend Composite Component · Status: Active  
Path / entry: `<repo-root>/Xiaobao-iPadOS/Sources/Native/TodayView.swift`, `TodayTimetableView(timeline:openLesson:)`. Courses, campus activities, Free Blocks and confirmed Breaks share the four-line focus card above one interactive timeline. Input: the resolved school day, or nil if unavailable. A confirmed recess swaps the card without inserting a tile. Every block shows only its elapsed portion at the selected instant. The optional course-detail action defaults to nil; only an actual course can invoke it. A drag changes the temporary selection in `AppModel`, not school data. See the [native module](Xiaobao-iPadOS/README.md).
The strip shows a single centered name per tile; locations remain on the focus card. The marker is narrow by default. Holding anywhere on the track enlarges it; releasing retains the minute without keeping the marker enlarged. Local and connected Today share this behavior without extra parameters.

### Consumers

| File | Usage | Parameters | Purpose |
| --- | --- | --- | --- |
| `Xiaobao-iPadOS/Sources/Native/SchoolPortalSync/SchoolPortalPages.swift` | Render a successfully fetched school day | timeline = live schedule + week roster; openLesson = default nil | Show real dated lessons without demo or inferred bell blocks |
| `Xiaobao-iPadOS/Sources/Native/TodayView.swift` | Local Today | timeline = provider lessons on model.now; openLesson = select that local lesson by ID | Show the school day and open a real local detail |
| `Xiaobao-iPadOS/Sources/Native/CampusView.swift` | Connected Today | timeline = selected account's schedule with names resolved from its courses; openLesson = default | Use only this account's periods and rooms |

## Lesson activity plan and native presentation

Category: Frontend Utilities / System UI · Status: Implemented. Paths: `<repo-root>/Xiaobao-iPadOS/Sources/Core/LessonActivity/`, `Sources/Native/LessonActivity/` and `Sources/ActivityWidget/`. Entries: `LessonActivityPlan(timeline:at:)`, `LessonActivityController`, `LessonActivityControl(timeline:)` and the shared `LessonActivityAttributes.ContentState`. Dependencies: the current loaded timetable, ActivityKit, the system clock, WidgetKit and the campus mark. Defaults: not running, one opt-in foreground activity, no data refresh, local push type nil, closed state with no course values. [Scope and test](Xiaobao-iPadOS/Sources/Native/LessonActivity/README.md).

### Consumers

| File | Usage | Parameters | Purpose |
| --- | --- | --- | --- |
| `Xiaobao-iPadOS/Sources/Native/TodayView.swift` | LessonActivityControl | timeline = same resolved day already rendered by Today | Place the action once without duplicating separate school data paths |
| `Xiaobao-iPadOS/Sources/Native/LessonActivity/LessonActivityControl.swift` | Plan and controller | instant = real clock; source = verifying data scope; appearance = saved activity style; focus = original next lesson if still present | Do not start from a time-lens preview |
| `Xiaobao-iPadOS/Sources/Native/LessonActivity/LessonActivityController.swift` | ActivityKit and shared ContentState | staleDate = end of active class; pushType = nil; title = bounded; dismissal = immediate; scope/IDs = app memory only | Minimize disclosure and end on logout, source change or stale time |
| `Xiaobao-iPadOS/Sources/Native/AppModel.swift`, `Xiaobao-iPadOS/Sources/Native/XiaobaoApp.swift` | Own the controller, revoke scope and handle the fixed course link | source = verified school or separate demo; no URL arguments or arbitrary data | Reuse the current timetable and never open a stale user's records |
| `Xiaobao-iPadOS/Sources/ActivityWidget/LessonActivityWidget.swift` | Read shared ContentState and render LessonActivityCard | end, style and next title = local snapshot; isStale = system; clock = widget clock | Whole-minute readout with no seconds; clear course names when expired |
| `Xiaobao-iPadOS/Sources/Native/Settings/LessonActivitySettingsView.swift` | Reuse LessonActivityCard | state = synthetic interval/title with draft style; previewDate = fixed sample anchor | The preview never starts or reads an actual activity |
| `Xiaobao-iPadOS/Tests/Core/LessonActivityPlanTests.swift`, `Xiaobao-iPadOS/Tests/SchoolPortalSync/LessonActivityUITests.swift` | Core plan and foreground ActivityKit action | synthetic day and loopback portal only | Exercise time boundaries, next-title selection and actual local start/stop |

## Planner date routing

Category: Frontend Utility · Status: Active  
Path / entry: `Xiaobao-iPadOS/Sources/Native/AppModel.swift`, `openPlanner(on:)` and `takePlannerDateRequest()`. A required date is normalized to the Shanghai school day and queued for one consumption by Planner. The default visit via the sidebar opens today. The route is not saved or sent to the service. `todayRotationDay` reads the resolved local or authorized schedule and returns nil when there is no known Day; the toolbar then uses the calendar date. See the [Planner module](Xiaobao-iPadOS/Sources/Native/Planner/README.md).

### Consumers

| File | Usage | Parameters | Purpose |
| --- | --- | --- | --- |
| `Xiaobao-iPadOS/Sources/Native/XiaobaoApp.swift` | Shared toolbar date shortcut | date = model.now; rotation = model.todayRotationDay | Open Planner at today from any main page, including Planner itself |
| `Xiaobao-iPadOS/Sources/Native/TodayView.swift` | End-of-day shortcut | date = tomorrow in the school calendar | Open the next day's Planner without changing Today |
| `Xiaobao-iPadOS/Sources/Native/AppModel.swift` | Course-notification route | date = reminder date; lesson = existing local detail lookup | Land on the matching day and retain authorized lesson details |
| `Xiaobao-iPadOS/Sources/Native/Planner/PlannerView.swift` | Consume the date request | pending date = app navigation; consume once after any draft closes | Reuse Planner date selection without rebuilding its editor or history |

## LessonTimeline

Category: Frontend Utility · Status: Active  
Path / entry: `<repo-root>/Xiaobao-iPadOS/Sources/Core/SchoolDay.swift`, internal `LessonTimeline(on:periods:teachingSlots:includesCampusActivities:)`. Defaults: nil bell table, no assumed activities or recesses. Produces ordered lessons, confirmed Free Blocks and optionally assembly and lunch where the known day spans them, plus clock bounds and the first unended block. `recess(at:)` exposes a bounded campus recess without adding a block; `nextInstructionStart(from:)` includes lessons and assembly, but not vacant time. Published lessons take precedence over activities. `Block.elapsedFraction(at:)` applies to every kind independently of focus. Invalid lessons are unavailable; invalid bells cannot hide actual lessons or create vacancies. Depends on Foundation and SchoolClock, not network or storage. See the [native module](Xiaobao-iPadOS/README.md).

Bundled policy in this file: `CampusBells.teachingSlots` supplies `DemoSchoolProvider`'s standalone lessons and bells, **not** account enrollments; `CampusBells.Activity.minutes` defines campus assembly and lunch for the native timeline and `Agenda` status. The intervals do not create course records. `TeachingSlotTests.swift` and `CampusConnectionTests.swift` cover this policy for both local days and Rust-published schedules.

### Consumers

| File | Usage | Parameters | Purpose |
| --- | --- | --- | --- |
| `Xiaobao-iPadOS/Sources/Core/SchoolDay.swift` | DemoSchoolProvider.timeline(on:lessons:) | date and assignment list = caller; teachingSlots = CampusBells on a teaching day; includesCampusActivities = resolved school day | Provide the same local day to both screens |
| `Xiaobao-iPadOS/Sources/Native/TodayView.swift` | Shared focus card, elapsed fraction and recess readout | blocks and recesses = resolved local/connected day; instant = model.timetableInstant; earliest resumption = lunch or recess end | Show elapsed time and an accurate countdown without conflating lessons, vacancies and breaks |
| `Xiaobao-iPadOS/Sources/Core/LessonActivity/LessonActivityPlan.swift` | Project lesson activity | periods = dated lesson blocks only; instant = real clock; exclude ambiguity | Show the real end time and original next named class |
| `Xiaobao-iPadOS/Sources/Core/TimelineTrackLayout.swift` | Layout input | ordered block IDs, actual start/end minutes and clock bounds = resolved timeline | Map display and interaction to the same times |
| `Xiaobao-iPadOS/Sources/Native/CampusView.swift` | Connected Today | blocks = active account's projection, courseName = name | Expose that day's confirmed slots without manufacturing lesson records |
| `Xiaobao-iPadOS/Sources/Core/CampusPage.swift` | CampusSchedule.timeline(courseName:) | date, periods, names, rooms and optional bells = source; includesCampusActivities = rotation day exists | Project an account-scoped timetable without substituting sample lessons |
| `Xiaobao-iPadOS/Sources/Core/Planner/PlannerSchoolDay.swift` | Planner derives school-only rows from the existing timeline in both modes | local timeline = selected date from DemoSchoolProvider; in-class demo exams match only the explicit lesson ID, course and exact interval; connected timeline = same-date CampusSchedule | Share confirmed slots, assembly and lunch without changing the Today strip or hiding independent school records |
| `Xiaobao-iPadOS/Tests/Core/SchoolDayTests.swift`, `Xiaobao-iPadOS/Tests/Core/TeachingSlotTests.swift`, `Xiaobao-iPadOS/Tests/Core/CampusConnectionTests.swift`, `Xiaobao-iPadOS/Tests/Core/TimelineTrackLayoutTests.swift` | Projection, progress and boundaries | isolated schedules or test-service records; activities = default or opt-in | Check half-open intervals, re-scrubbing, conflicts, missing data, layout and offline parity |

## StudentServices

Category: Frontend demo data · Status: Active  
Path / entry: `<repo-root>/Xiaobao-iPadOS/Sources/Core/StudentServices.swift`, `StudentServices.work`, `work(on:)` and `resources`. The work snapshot uses `DemoSchoolProvider.local`, also used by the app timetable. Fixture dates and course IDs identify existing lessons, not separate clocks. `makeWork(using:)` permits a supplied demo provider; without an assigned lesson, an in-class exam is omitted. No service requests, account writes or personal data. See the [native app](Xiaobao-iPadOS/README.md#change-history).

### Consumers

| File | Usage | Parameters | Purpose |
| --- | --- | --- | --- |
| `Xiaobao-iPadOS/Sources/Native/StudentServicesView.swift` | Local lists inside 其余项目 | work = selected exam/evaluation kind; resources = filtered by search and local favorites | Display the canonical exam time and room beside its detail |
| `Xiaobao-iPadOS/Sources/Native/Planner/PlannerSchoolSource.swift` | Pass date-scoped local school work to the projection | date = school date of the lane; provider = `AppModel.provider` (same local fixture) | Represent a scheduled in-class exam once without changing the timetable |
| `Xiaobao-iPadOS/Sources/Native/Planner/PlannerScheduleCanvas.swift` | Resolve a read-only local work detail | work = matching kind and ID | Open the same exam detail that My Exams uses |
| `Xiaobao-iPadOS/Sources/Core/Tasks/DemoTasks.swift` | Extend local assignments with task metadata | work = task kind only | Preserve unrelated deadlines and task IDs |
| `Xiaobao-iPadOS/Tests/Core/PlannerTests.swift` | Verify exam slots and holiday behavior | provider = local, explicitly published HS or synthetic closure | Lock schedule consistency without hardcoded times |

## PlanStore

Category: Frontend Infrastructure · Status: Active  
Path / entry: `<repo-root>/Xiaobao-iPadOS/Sources/Core/Planner/PlanStore.swift`, `PlanStore(file:)`. `readEditor`, `apply` and `step` take an explicit owner and page session; no history is persisted. `readSchedule` supplies one owner's notification input. The prior day-only read/write entry points remain compatible. Depends on `PersonalPlan` and `PlanBubble` validation, `PlanEditHistory` and Foundation file protection. See the [planner core](Xiaobao-iPadOS/Sources/Core/Planner/README.md).

### Consumers

| File | Usage | Parameters | Purpose |
| --- | --- | --- | --- |
| `Xiaobao-iPadOS/Sources/Native/AppModel.swift` | Install the sole store and read the active notification schedule | file = app Application Support / `XiaobaoPlanner-v1/plans.plist`; owner = active, unlocked scope | Isolate user-authored plans from the school cache; never notify a different account's plans |
| `Xiaobao-iPadOS/Sources/Native/Planner/PlannerView.swift` | Project visible days and save, place, complete or step history | owner = captured scope; session = page lifetime UUID; command = validated draft, dated placement with explicit source, completion or history direction | Write one personal change without changing school data |
| `Xiaobao-iPadOS/Tests/Core/PlannerTests.swift` | Reopen and mutate test stores | file = isolated temporary URL; owner/plan = independent fixtures | Verify legacy/new appearance, persisted completion, date and account boundaries, and non-destructive failures |
| `Xiaobao-iPadOS/Tests/Core/PlannerRoutineTests.swift` | Reopen, copy and revise a weekly rule | file = isolated temporary URL; dates and owners = independent fixtures | Verify rule history, per-day completion, independent copies and account isolation |
| `Xiaobao-iPadOS/Tests/Core/PlannerEditingTests.swift` | Move plans and repeat series; undo/redo and wait for cutovers | file = isolated temporary URL; dates, clock and session = independent fixtures | Verify atomic history and no old-time reminders |

## PlanBubble

Category: Frontend schema and utility · Status: Active  
Path / entry: `<repo-root>/Xiaobao-iPadOS/Sources/Core/Planner/PlanBubble.swift`, `PlanBubble(prototype:reusable:)`, `occurrence(on:)`, `copy(on:at:)`, `revise(weekday:effectiveDay:)` and `reschedule(to:at:now:)`. A template never writes a dated record by itself. The owner store validates changes, projects occurrences and preserves earlier revisions. A nil weekday retires repetition. See the [Planner core](Xiaobao-iPadOS/Sources/Core/Planner/README.md).

### Consumers

| File | Usage | Parameters | Purpose |
| --- | --- | --- | --- |
| `Xiaobao-iPadOS/Sources/Core/Planner/PlanStore.swift` | Own, project, copy or move a series | prototype and repeat settings = validated edit; destination day/time and clock = committed placement; source = explicit type | Distinguish relocating a series from creating an independent copy |
| `Xiaobao-iPadOS/Sources/Core/Planner/PlanReminderPlanner.swift` | Read all applicable recurrence revisions | bubble = active owner snapshot; next fire = school clock; old reminders stop at next effective date | Register correct reminders without creating dated plans |
| `Xiaobao-iPadOS/Sources/Native/Planner/PlannerView.swift` | Route selected cards and track templates | ID = snapshot membership; edit start = effective school date | Distinguish an occurrence from an ordinary editable plan |
| `Xiaobao-iPadOS/Sources/Native/Planner/PlannerTimelineView.swift` | Display the shelf in Edit and resolve placement position | bubbles = visible owner templates; drop = shared board coordinate | Pass the date and range with the source type unchanged |
| `Xiaobao-iPadOS/Sources/Native/Planner/PlannerInboxView.swift` | Present bubbles in Edit | prototype and role = each visible template | Render ordinary and recurring bubbles without a second add control |
| `Xiaobao-iPadOS/Sources/Native/Planner/PlanEditorView.swift` | Seed a draft | bubble = explicit template or nil; time follows the selected date | Show the stored weekday and independent reusable option |
| `Xiaobao-iPadOS/Tests/Core/PlannerRoutineTests.swift` | Verify date projection and reminders | prototype and dates = synthetic fixtures | Cover retirement, future starts and midnight lead |

## PlanPlacementItem

Category: Frontend data contract · Status: Active  
Path / entry: `<repo-root>/Xiaobao-iPadOS/Sources/Core/Planner/PlanBubble.swift`, `PlanPlacementItem(plan:source:)`. The record and its source are required; no UUID-only classification or inferred default. It carries no view state and is not serialized. Depends on `PersonalPlan`. See the [Planner core](Xiaobao-iPadOS/Sources/Core/Planner/README.md).

### Consumers

| File | Usage | Parameters | Purpose |
| --- | --- | --- | --- |
| `Xiaobao-iPadOS/Sources/Native/Planner/PlannerPlanCard.swift`, `PlannerPlanAnnotations.swift` | Construct move/edit source | source = shelf kind or membership of the dated weekly projection; record = shown UI data | Keep template and occurrence distinct even when IDs match, including inside numbered groups |
| `Xiaobao-iPadOS/Sources/Native/Planner/PlannerHoldGesture.swift`, `PlannerTimelineView.swift`, `PlannerInboxView.swift` | Carry handle identity through point routing or tap placement | item = handle frame/selected element; drop date = column geometry | Avoid repeating or copying a plan when drawing a new range |
| `Xiaobao-iPadOS/Sources/Native/Planner/PlannerView.swift`, `Xiaobao-iPadOS/Sources/Core/Planner/PlanStore.swift` | Route actual plan edit and atomic placement | source = original item; date/time = exact resolved target | Change only the intended personal record or series |
| `Xiaobao-iPadOS/Tests/Core/PlannerEditingTests.swift` | Exercise placement source contract | sources and dated plans = isolated fixtures | Verify exact cross-day outcome and stable series identity |

## PlannerCalendarMonth

Category: Frontend utility · Status: Active  
Path / entry: `<repo-root>/Xiaobao-iPadOS/Sources/Core/Planner/PlannerCalendarMonth.swift`, `PlannerCalendarMonth(containing:publication:)`. Projects a Monday-first month, known HS dates and complete ranges for contiguous known notices. An absent or out-of-scope publication does not invent closures. Depends on `SchoolClock` and `PublishedSchoolCalendar`. See the [Planner core](Xiaobao-iPadOS/Sources/Core/Planner/README.md).

### Consumers

| File | Usage | Parameters | Purpose |
| --- | --- | --- | --- |
| `Xiaobao-iPadOS/Sources/Native/Planner/PlannerMonthPicker.swift` | Read grid and notices | containing = visible month; publication = Main Campus HS; selected date = Planner binding | Distinguish published holidays and events in a compact date chooser |
| `Xiaobao-iPadOS/Sources/Native/Planner/PlannerView.swift` | Read existing date bounds | day = current column/drop/move target | Keep daily and weekly controls in the accepted date interval |
| `Xiaobao-iPadOS/Tests/Core/PlannerEditingTests.swift` | Project a viable calendar fixture | publication = synthetic days covering a month and year transition | Verify contiguous closure and no fictional stops |

## PlanReminderPlanner

Category: Frontend Utility · Status: Active  
Path / entry: `<repo-root>/Xiaobao-iPadOS/Sources/Core/Planner/PlanReminderPlanner.swift`, `make(now:schedule:)`. Takes one owner snapshot and an explicit clock. Returns candidates ordered by next fire, with stable logical IDs under `identifierPrefix`; it neither authorizes nor touches the system queue. Depends on Foundation, the Shanghai school clock and the plan snapshot. See the [Planner core](Xiaobao-iPadOS/Sources/Core/Planner/README.md).

### Consumers

| File | Usage | Parameters | Purpose |
| --- | --- | --- | --- |
| `Xiaobao-iPadOS/Sources/Native/AppModel.swift` | Plan reminder reconciliation | now = current Date; schedule = active owner's on-device snapshot | Keep reminder generation outside SwiftUI |
| `Xiaobao-iPadOS/Sources/Native/ReminderService.swift` | Filter the system queue by prefix | candidate namespace = identifierPrefix; actual triggers come from AppModel | Reconcile without touching lesson reminders |
| `Xiaobao-iPadOS/Tests/Core/PlannerRoutineTests.swift`, `Xiaobao-iPadOS/Tests/Core/PlannerEditingTests.swift` | Exercise one-shot, recurring and delayed cutovers | now and schedule = independent clock fixtures | Verify non-early firing, midnight handling and removal of obsolete times |

## ReminderService

Category: Frontend Infrastructure · Status: Active  
Path / entry: `<repo-root>/Xiaobao-iPadOS/Sources/Native/ReminderService.swift`, `ReminderService()`. Owns one notification delegate. The existing timetable scheduler has a separate request namespace from `syncPlanReminders(_:subtitle:)` and `clearPlanReminders()`. An explicit plan edit may call `requestPlanPermission()` before reconciling; the OS prompt does not hold the personal queue. Personal scheduling uses remaining capacity and does not expose account IDs. A nil subtitle preserves the native blank content; pending personal notifications are reconciled against both the existing signature and actual subtitle. See the [native app](Xiaobao-iPadOS/README.md).

### Consumers

| File | Usage | Parameters | Purpose |
| --- | --- | --- | --- |
| `Xiaobao-iPadOS/Sources/Native/AppModel.swift` | Own and coordinate the native service | timetable provider and preferences = existing demo schedule; reminder candidates = active owner; subtitle = local preference; authorization = explicit plan edit with a future candidate | Lifecycle refresh and account-safe reconciliation |
| `Xiaobao-iPadOS/Sources/Native/Settings/ReminderSettingsView.swift` | Existing timetable reminder permission and status; explicit notification check | request options = system alert, sound and badge; test timing = five seconds; test subtitle = saved local choice | Retain timetable controls, test only on an explicit action |
| `Xiaobao-iPadOS/Sources/Native/XiaobaoApp.swift` | Observe lesson notification route | route = existing school detail payload | Preserve lesson navigation and refresh on account changes |
| `Xiaobao-iPadOS/Sources/Native/Planner/PlannerView.swift` | Supply personal scheduling warnings to the Edit shelf | status = read-only planStatus | Distinguish a valid saved plan from a notification that was not registered |

## PlannerPlanCard

Category: Frontend UI Component · Status: Active  
Path / entry: `<repo-root>/Xiaobao-iPadOS/Sources/Native/Planner/PlannerPlanCard.swift`, `PlannerPlanCard(plan:timeLabel:actions:density:conflictsWithSchool:weekly:shelfKind:)` and the shared `PlannerPlanGlyph(plan:weekly:font:)`. Plan, nullable time label and actions are required for the card. Density defaults to standard, overlap and weekly to false, shelfKind to nil. The glyph uses the chosen icon, repeat glyph or a bookmark; its font defaults to the caption. Browse removes drag targets; Edit publishes the handle frame and explicit source for the shared hold recognizer. Narrow annotations keep the same editor and completion actions. The caller paints scheduled bands. See the [Planner page](Xiaobao-iPadOS/Sources/Native/Planner/README.md).

### Consumers

| File | Usage | Parameters | Purpose |
| --- | --- | --- | --- |
| `Xiaobao-iPadOS/Sources/Native/Planner/PlannerInboxView.swift` | Pending and reusable bubbles in Edit | plan = pending record or prototype; timeLabel = nil; actions = PlannerTimelineView callbacks; shelfKind = pending, reusable or weekly by record; remaining = defaults | A non-weekly reusable bubble copies; weekly shelf handle relocates the future series |
| `Xiaobao-iPadOS/Sources/Native/Planner/PlannerPlanAnnotations.swift` | Single plan label and numbered group tokens and details | plan/timeLabel = projected record; actions = PlannerTimelineView callbacks, with `canOpenEditor` independent of Edit-only quick actions; density = measured safe space or icon-only; conflictsWithSchool = known overlap; weekly = occurrence membership; glyph font = caption2 for tokens, default in list | Keep individual plans legible and directly editable in both modes without taking a school lane |

## PlannerRangeBand

Category: Frontend UI Component · Status: Active  
Path / entry: `<repo-root>/Xiaobao-iPadOS/Sources/Native/Planner/PlannerTimelineDecoration.swift`, `PlannerRangeBand(color:paint:isPoint:)`. Optional plan color is required; paint defaults to `.marker`, isPoint defaults to false. The caller positions it at actual boundaries with 1.5 pt outside each end for the capped rule. `.overlayFill` uses per-band alpha relative to `savedOverlapOpacityLimit`; the caller composites those fills before applying that cap. `.endpoints` stays independent. The region never receives taps. Depends on SwiftUI, `PlanColor` and the Planner's corner tokens. See [color semantics](COLOR_SYSTEM.md).

### Consumers

| File | Usage | Parameters | Purpose |
| --- | --- | --- | --- |
| `Xiaobao-iPadOS/Sources/Native/Planner/PlannerScheduleCanvas.swift` | Full-width saved ranges and live drawing/drop preview | color = stored or draft; paint = `.overlayFill` and `.endpoints` for saved geometry, `.preview` while interacting; isPoint = no end; group opacity = `savedOverlapOpacityLimit` on saved fills only | Increase overlap tint while leaving isolated bands unchanged, without taking space or intercepting taps |
| `Xiaobao-iPadOS/Sources/Native/Planner/PlannerTimelineMarks.swift` | Short or point markers for scheduled school entries | color = nil; paint = default; isPoint = zero duration | Preserve exact times near the school ruler; due-only records stay off the board, and personal markers use the shared overlay |

## PlannerTimeScale

Category: Frontend Utility · Status: Active  
Path / entry: `<repo-root>/Xiaobao-iPadOS/Sources/Core/Planner/PlannerTimelineLayout.swift`, `PlannerTimeScale(hourHeight:)`. Explicit points per hour; maps between actual Shanghai school minutes and canvas positions, without compressed gutters. Invalid positions outside the day return nil; only range selection opts into the exact day-end boundary with `minute(at:includingDayEnd:)`. See the [Planner core](Xiaobao-iPadOS/Sources/Core/Planner/README.md).

### Consumers

| File | Usage | Parameters | Purpose |
| --- | --- | --- | --- |
| `Xiaobao-iPadOS/Sources/Native/Planner/PlannerTimelineView.swift` | Scroll starting point, range and drop lookup | hourHeight = Dynamic Type scale; position = pointer relative to the measured canvas; includingDayEnd = true for range only | Define the exact time used in the preview and save |
| `Xiaobao-iPadOS/Sources/Native/Planner/PlannerWeekView.swift` | One time ruler for the day and the week | scale = PlannerTimelineView scale; mode = browse/range/placement changes hit targets, not labels | Keep the same ruler across columns and modes |
| `Xiaobao-iPadOS/Sources/Native/Planner/PlannerScheduleCanvas.swift` | Grid, tap targets and preview markings | scale = timeline's explicit scale; minutes = actual day minutes; includingDayEnd = true for range taps | Keep drawing and input aligned |
| `Xiaobao-iPadOS/Sources/Core/Planner/PlannerTimelineLayout.swift` | Timed card geometry | scale = caller; date = projected school day | Retain real starts for overlapping records |
| `Xiaobao-iPadOS/Tests/Core/PlannerPlacementTests.swift` | Layout and inverse coordinate fixtures | hourHeight = independent display scales; includingDayEnd = both default and true | Check real-time mapping, touching boundaries, and overlap lanes |

## OtherItemsGrid

Category: Frontend Composite Component · Status: Active  
Path / entry: `Xiaobao-iPadOS/Sources/Native/OtherItems/OtherItemsGrid.swift`, `OtherItemsGrid(section:records:filters:showsLocalBookmarks:isPartialPage:campusPage:)`. The section, projected records and filter binding are required. Local bookmarks and partial-page warning default to false; the source page defaults to nil. Renders adaptive tiles and opens category-specific scoped details. See the [native module](Xiaobao-iPadOS/Sources/Native/OtherItems/README.md).

### Consumers

| File | Usage | Parameters | Purpose |
| --- | --- | --- | --- |
| `Xiaobao-iPadOS/Sources/Native/StudentServicesView.swift` | Local exam, evaluation and resource grid | section = selection; records = sorted local projections; filters = state; showsLocalBookmarks = resources only; remaining parameters = defaults | Keep one tile layout and local actions |
| `Xiaobao-iPadOS/Sources/Native/CampusView.swift` | Connected work/resource grid | section = connected tab; records = authorized snapshot or one legacy page; filters = state; isPartialPage = paging coverage; campusPage = selected collection/page; bookmarks = default | Reuse the layout with explicit data scope and existing refresh |

## OtherItemsCatalog and filters

Category: Frontend Utilities · Status: Active  
Path / entry: `Xiaobao-iPadOS/Sources/Core/OtherItemsCatalog.swift`, `OtherItem` projection, `OtherItemsCatalog.courses(in:)` and `OtherItemsFilters.results(in:at:bookmarks:)`. Start at all courses, all statuses, an empty search and no bookmark restriction. Inputs have explicit course associations; output keeps source ordering and each item identity. No I/O or school writes. See the [native module](Xiaobao-iPadOS/Sources/Native/OtherItems/README.md).

### Consumers

| File | Usage | Parameters | Purpose |
| --- | --- | --- | --- |
| `Xiaobao-iPadOS/Sources/Native/StudentServicesView.swift` | Sort/project local items | source = local records; type = selected section; clock = current school time | Keep existing demo content and order |
| `Xiaobao-iPadOS/Sources/Native/CampusView.swift` | Connected projections | source = active authorized collection; names = course roster; kind = selected work section | Match only real course IDs, including cross-course exams |
| `Xiaobao-iPadOS/Sources/Native/OtherItems/OtherItemsGrid.swift` | Compute facets and matching records | records = caller input; filters = supplied binding; clock and bookmarks = current AppModel | Compose course, status, text and local bookmarks without duplicate tiles |
| `Xiaobao-iPadOS/Sources/Native/OtherItems/OtherItemsFilterBar.swift` | Manage picker and search selections | options = available course associations; filters = binding | Keep controls separate from matching rules |
| `Xiaobao-iPadOS/Sources/Native/OtherItems/OtherItemsDetails.swift` | Read original fields and status | item = selected matched record; clock and local bookmarks = current AppModel | Open the correct item without a second network read |
| `Xiaobao-iPadOS/Tests/Core/OtherItemsCatalogTests.swift`, `Xiaobao-iPadOS/Tests/Core/CampusOfflineTests.swift` | Synthetic projection and cache checks | inputs = supplied local records, work JSON and full authorized snapshots | Cover missing courses, distinct sources and records beyond the first legacy slice |

## Cached Other Items collection

Category: Frontend read boundary · Status: Active  
Path / entry: `Xiaobao-iPadOS/Sources/Core/CampusConnection.swift`, `cachedOtherItems(for:)`. Requires a work page for exams or evaluations, or a resource page. Returns the full active authorized module, if present; no I/O, no grade load, no legacy-page fallback.

### Consumers

| File | Usage | Parameters | Purpose |
| --- | --- | --- | --- |
| `Xiaobao-iPadOS/Sources/Native/CampusView.swift` | Supply data for the selected grid | page = current connected page; fallback = its existing snapshot | Filter all authorized cached items; label partial legacy coverage |
| `Xiaobao-iPadOS/Sources/Native/OtherItems/OtherItemsDetails.swift` | Validate still-available connected detail | page = sourcePage; also checks captured account scope and page snapshot | Hide a pushed record when the source is no longer accessible |
| `Xiaobao-iPadOS/Tests/Core/CampusOfflineTests.swift` | Read and permission regression | page = exams and mismatched grades; source = isolated authorized synthetic snapshot | Ensure a 30-item slice does not hide the final course and revoked rows are removed |

## SchoolWorkDetailView

Category: Frontend Composite Component · Status: Active  
Path / entry: `<repo-root>/Xiaobao-iPadOS/Sources/Native/StudentServicesView.swift`, `SchoolWorkDetailView(item:allowsLocalCompletion:)`. `item` is required; `allowsLocalCompletion` defaults to true and applies only to eligible local demo tasks. Depends on the existing native work model, detail surface and local completion state. No school write is supported. See the [native app](Xiaobao-iPadOS/README.md) and [planner page](Xiaobao-iPadOS/Sources/Native/Planner/README.md).

### Consumers

| File | Usage | Parameters | Purpose |
| --- | --- | --- | --- |
| `Xiaobao-iPadOS/Sources/Native/Planner/PlannerScheduleCanvas.swift` | School entry drill-down in local mode | item = matching demo record by kind and ID; allowsLocalCompletion = false | Keep school schedule entries read-only in Planner |

## StudentEmptyState

Category: Frontend UI Component · Status: Active  
Path / entry: `<repo-root>/Xiaobao-iPadOS/Sources/Native/StudentComponents.swift`, `StudentEmptyState(title:detail:symbol:)`. The description and title are required; symbol defaults to `tray`. Wraps the native content-unavailable presentation. See the [design system](UI_DESIGN_SYSTEM.md).

### Consumers

| File | Usage | Parameters | Purpose |
| --- | --- | --- | --- |
| `Xiaobao-iPadOS/Sources/Native/SchoolPortalSync/SchoolPortalPages.swift`, `SchoolPortalGradebook.swift` (same directory) | Confirmed empty day / unavailable detail | title/detail = state-specific; symbol = default | Keep successful empties distinct from errors |
| `Xiaobao-iPadOS/Sources/Native/AttendanceView.swift` | Attendance report, status filter and class details | title/detail = call-site availability or filter explanation; symbol = `calendar.badge.exclamationmark` for date coverage, `list.bullet.clipboard` for summary-only, default for an empty status filter | Distinguish missing coverage and no filter matches |
| `Xiaobao-iPadOS/Sources/Native/GPA/CourseGradeList.swift` | Filtered course list | title/detail = no matches; symbol = default | Explain an empty search or grading-status result |
| `Xiaobao-iPadOS/Sources/Native/GPA/GPAOverviewView.swift` | Course destination fallback | title/detail = course no longer available; symbol = default | Avoid showing stale grades |
| `Xiaobao-iPadOS/Sources/Native/SchoolPortalSync/SchoolPortalAttendancePage.swift` | Empty school attendance or no listed course | title/detail = scoped result; symbol = default | Never substitute demo or render a failed read as empty |
| `Xiaobao-iPadOS/Sources/Native/GPA/CampusGradebookView.swift` | Authorized gradebook without courses | title/detail = confirmed empty term; symbol = default | Distinguish an empty gradebook from one not downloaded |
| `Xiaobao-iPadOS/Sources/Native/Tasks/TasksView.swift` | Tasks with no matching rows or known permissions | title/detail = selected-term empty, filtered empty or unavailable; symbol = `checklist` | Keep missing data distinct from a filter excluding items |
| `Xiaobao-iPadOS/Sources/Native/GPA/CourseHistorySheet.swift` | Course history without eligible data | title/detail = no dated, graded numeric records; symbol = `chart.xyaxis.line` | Avoid a fabricated timeline or selectable dates |
| `Xiaobao-iPadOS/Sources/Native/OtherItems/OtherItemsGrid.swift` | Empty result grid | title/detail = known empty or no filter matches; symbol = selected section | Distinguish no available items from an active filter |
| `Xiaobao-iPadOS/Sources/Native/OtherItems/OtherItemsDetails.swift` | Connected item no longer available | title/detail = read-only source unavailable; symbol = default | Do not display an item after its connected source is lost |

## StudentDetailSurface

Category: Frontend Composite Component · Status: Active  
Path / entry: `Xiaobao-iPadOS/Sources/Native/StudentComponents.swift`, `StudentDetailSurface(content:)`. Required view content, no other parameters. Provides the existing weather backdrop, maximum reading width and inline navigation title for student details. See [native app](Xiaobao-iPadOS/README.md).

### Consumers

| File | Usage | Parameters | Purpose |
| --- | --- | --- | --- |
| `Xiaobao-iPadOS/Sources/Native/AttendanceView.swift` | Course attendance details | content = selected attendance record and coverage | Reuse the student detail layout |
| `Xiaobao-iPadOS/Sources/Native/StudentServicesView.swift` | Existing school work detail | content = domain details selected from Planner | Keep the old detail of a timeline entry intact |
| `Xiaobao-iPadOS/Sources/Native/OtherItems/OtherItemsDetails.swift` | Exam, evaluation and resource details | content = selected item with category-specific layout or unavailable fallback | Share the native reading background and width without merging the contents |
| `Xiaobao-iPadOS/Sources/Native/GPA/GPAOverviewView.swift` | Missing destination | content = course no longer available | Keep a useful back route without stale content |
| `Xiaobao-iPadOS/Sources/Native/GPA/CourseGradesView.swift` | Course detail destination | content = total, chart preview and task table | Reuse the sky and reading width from existing details |
| `Xiaobao-iPadOS/Sources/Native/GPA/CourseTaskList.swift` | Feedback destination | content = selected source assessment's result and feedback | Keep feedback on the same native detail surface |
| `Xiaobao-iPadOS/Sources/Native/Tasks/TaskDetailView.swift` | Clicked task | content = task metadata, material, answer and feedback | Keep the existing native student detail container |

## GPAOverviewView

Category: Frontend Composite Component · Status: Active  
Path / entry: `Xiaobao-iPadOS/Sources/Native/GPA/GPAOverviewView.swift`, `GPAOverviewView(isCurrentTerm:summary:unavailableMessage:courses:courseDestination:termLabel:gradeStatus:)`. Inputs: term heading, nullable GPA with provenance, missing-data explanation, course rows and builders for term content and grade availability/refresh only. Starts with visible GPA and no course filter; does not fetch or host trial forms. Depends on SwiftUI and the [GPA projection](Xiaobao-iPadOS/Sources/Core/GPA/README.md). See the [GPA page](Xiaobao-iPadOS/Sources/Native/GPA/README.md).

### Consumers

| File | Usage | Parameters | Purpose |
| --- | --- | --- | --- |
| `Xiaobao-iPadOS/Sources/Native/SchoolPortalSync/SchoolPortalGradebook.swift` | Real term overview | summary = portal GPA; courses = projected current roster; courseDestination = on-demand SchoolPortalCoursePage; term/status slots = real source and freshness | Reuse the GPA screen without eager detail reads |
| `Xiaobao-iPadOS/Sources/Native/GradebookView.swift` | Local GPA page | isCurrentTerm = selected term equals current local term; summary/courses = active local gradebook term; unavailableMessage = no valid term estimate; termLabel = term picker; gradeStatus = empty | Expose local histories without estimating from individual assessments |
| `Xiaobao-iPadOS/Sources/Native/GPA/CampusGradebookView.swift` | Connected GPA page | isCurrentTerm = true; summary = published or automatic GPA from the authorized cache; courses = saved gradebook; unavailableMessage = missing inputs or cache/access state; termLabel = current connected term; gradeStatus = empty gradebook explanation, permitted sync action and check status | Show known grades or explicit missing inputs without bypassing permissions |

## GPA presentation

Category: Frontend Utility / Presentation Contract · Status: Active  
Path / entry: `Xiaobao-iPadOS/Sources/Core/GPA/GradePresentation.swift` and `CampusGPA.swift`. `CampusGrades.gpaReadout`, `CourseGradeDetail` and `courseGradeDetails` expose provenance, course totals, publication fields and assessments. Connected GPA prioritizes the published value; any estimate requires the authorized GPA credits and published points or a confirmed conversion rule. No default scale or weight is applied to connected grades. Depends on typed caches, grade normalization, dated chart points and the separate built-in grade calculator. See the [projection contract](Xiaobao-iPadOS/Sources/Core/GPA/README.md).

### Consumers

| File | Usage | Parameters | Purpose |
| --- | --- | --- | --- |
| `Xiaobao-iPadOS/Sources/Core/SchoolPortalData/SchoolPortalData.swift` | CourseGradeDetail, GradeMark and AssessmentWeight | grade = current published total; publishedRows = source categories; scope = course/group | Real records retain missing values and source weight scopes |
| `Xiaobao-iPadOS/Sources/Native/GradebookView.swift` | Local summary and course projection | termID = selected local term; weighted = saved AP preference; report = each selected term course | Supply local source and assessment categories |
| `Xiaobao-iPadOS/Sources/Native/GPA/CampusGradebookView.swift` | Connected summary and course projection | source = current account's saved grades, GPA credits and scale, and roster | Present school-supplied values, a labeled estimate, or missing inputs |
| `Xiaobao-iPadOS/Sources/Native/GPA/GPAOverviewView.swift` | Readout, matching and course routing | query/status = view state; course ID = selected row | Keep filters independent from GPA |
| `Xiaobao-iPadOS/Sources/Native/GPA/CourseGradeList.swift` | Read course totals | courses = list filtered by overview; course identity = term and course | Display all matching courses as navigable tiles |
| `Xiaobao-iPadOS/Sources/Native/GPA/CourseGradesView.swift` | Published course summary and history | course = selected route; history points, course total and permitted categories = selected course | Keep published metadata and chart independent of forecasts |
| `Xiaobao-iPadOS/Sources/Native/GPA/CourseTaskList.swift` | Task rows, weights and feedback | rows = selected course's projected groups or flat assessments; school metadata comes from the selected item | Preserve source weight and assessment scope |
| `Xiaobao-iPadOS/Sources/Core/Tasks/TaskPresentation.swift` | Normalize separate published scores and released previews using `GradeMark(score:)` | score = conditional source mark, or explicitly released valid numeric estimate for pending publication; letter = default | Share formatting without calculating unpublished marks |
| `Xiaobao-iPadOS/Sources/Native/Tasks/TaskCard.swift` | `GradeMark.displayText` | mark = published task result only | Never show the released preview on a card |
| `Xiaobao-iPadOS/Sources/Native/Tasks/TaskDetailView.swift` | `GradeMark.displayText` | mark = published result, otherwise authorized task estimate with separate label | Keep the preview visibly distinct from the published score |
| `Xiaobao-iPadOS/Tests/Core/GradePresentationTests.swift` | Local and connected projections | term, category, course, score, weight and publication fields = independent synthetic fixtures | Verify correct ordering, scope, provenance and missing data |
| `Xiaobao-iPadOS/Tests/Core/CampusConnectionTests.swift`, `Xiaobao-iPadOS/Tests/Core/CampusOfflineTests.swift` | Optional metadata in saved projections | grades = authorized legacy sync or offline bundle; synthetic service data | Verify older caches stay usable and only authorized reads refresh them |

## AssessmentHistoryChart

Category: Frontend Composite Component · Status: Active  
Path / entry: `Xiaobao-iPadOS/Sources/Native/StudentChartsView.swift`, `AssessmentHistoryChart(points:presentation:range:)`. Required dated, normalized points in chronological order; presentation defaults to `.detail`, optional inclusive range defaults to nil (plotted dates). Uses Swift Charts and the school date formatter; detail presents axes, a selection and missing-data states. See the [GPA page](Xiaobao-iPadOS/Sources/Native/GPA/README.md).

### Consumers

| File | Usage | Parameters | Purpose |
| --- | --- | --- | --- |
| `Xiaobao-iPadOS/Sources/Native/GPA/CourseGradesView.swift` | Tappable history preview | points = selected course's actual history; presentation = preview; range = default | Keep the preview beside the grade; the enclosing button owns interaction |
| `Xiaobao-iPadOS/Sources/Native/GPA/CourseHistorySheet.swift` | Enlarged dated chart | points = actual history filtered to selected days; presentation = default; range = selected school dates | Read the selected date range without reinterpreting or fetching grades |

## AttendanceCourseTable

Category: Frontend Composite Component · Status: Active  
Path / entry: `Xiaobao-iPadOS/Sources/Native/StudentChartsView.swift`, `AttendanceCourseTable(rows:destination:)`. Rows are required and preserve caller order. Without a destination, rows are read-only. The table renders labeled counts and the supplied rate, adapting to actual width and text size. An `AttendanceComposition` segments each row by its own total; its bar is decorative and has no separate hit target. See the [native app](Xiaobao-iPadOS/README.md#代码位置).

### Consumers

#### Xiaobao-iPadOS/Sources/Native/SchoolPortalSync/SchoolPortalAttendancePage.swift

Usage: `AttendanceCourseTable(rows:destination:)`. Rows = listed subjects in the verified date range, narrowed by the selected status; destination = native detail for that listed subject. No website navigation.

#### Xiaobao-iPadOS/Sources/Native/AttendanceView.swift

Usage:  
`AttendanceCourseTable`

Parameters:
- rows = dynamic: courses in report order after the active status filter, projected with all four counts
- destination = local: selected course with its active report and initial status

Purpose:  
Read all four counts at once and keep the existing course detail navigation.

#### Xiaobao-iPadOS/Sources/Native/CampusView.swift

Usage:  
`AttendanceCourseTable`

Parameters:
- rows = dynamic: active report's per-course counts and published rates, with names from the current course directory
- destination = default (none)

Purpose:  
Reuse the direct table while preserving cache coverage and read-only data.

## Attendance filters, overview and ring

Category: Frontend Composite Components · Status: Active. Paths / entries: `<repo-root>/Xiaobao-iPadOS/Sources/Native/AttendanceView.swift` (`AttendanceFilterBar`, `AttendanceOverviewPanel`); `AttendanceRing.swift` in the same directory. Dependencies: existing attendance counts/categories/status, date range, system date pickers and glass presentation. The caller owns selections and the source of the percentage. The panel stacks unless space and text size permit columns; `fillsRow` defaults to false. No network requests are implemented here. See the [native app](Xiaobao-iPadOS/README.md).

### Consumers

| File | Usage | Parameters | Purpose |
| --- | --- | --- | --- |
| `Xiaobao-iPadOS/Sources/Native/AttendanceView.swift` (demo page) | Filter bar and overview | category/period/date/status = local filter state; totals/rate = filtered demo report and its counts-derived rate; width/fillsRow = available pane | Shared native appearance, independent demo data |
| `Xiaobao-iPadOS/Sources/Native/SchoolPortalSync/SchoolPortalAttendancePage.swift` | Filter bar and overview | category/period/range/page/status = native view state; totals = school counts; rate = published school percentage or nil; width/fillsRow = available pane | Display only the current student’s selected report |
| `Xiaobao-iPadOS/Sources/Native/AttendanceView.swift` (overview panel) | `AttendanceRing(counts:rate:)` | counts and optional rate = panel input | Segment geometry uses the counts; the central and spoken percentage use the supplied rate |

## AttendanceCourseRow and AttendanceComposition

Category: Frontend Presentation Contracts · Status: Active  
Path / entry: `Xiaobao-iPadOS/Sources/Core/StudentCharts.swift`. `AttendanceCourseRow(course:)` projects a local summary; `AttendanceCourseRow(id:name:summary:)` validates connected counts against their reported total and preserves the published rate when present. `AttendanceComposition(counts:)` projects positive-count segments in status order. Zero totals have no segments. Dependencies: `AttendanceCounts`, `AttendanceCourseSummary`, and `CampusCounts`.

### Consumers

| File | Usage | Parameters | Purpose |
| --- | --- | --- | --- |
| `Xiaobao-iPadOS/Sources/Core/SchoolPortalData/SchoolPortalAttendance.swift` | `AttendanceCourseRow(course:)` | course = validated counts and subject name from the scoped school report | Per-course rate uses the four counts as on the student course list |
| `Xiaobao-iPadOS/Sources/Native/AttendanceView.swift` | `AttendanceCourseRow(course:)` | course = filtered local summary | Pass all four native counts to the common table |
| `Xiaobao-iPadOS/Sources/Native/CampusView.swift` | `AttendanceCourseRow(id:name:summary:)` | id and summary = active report; name = roster lookup | Keep invalid and missing data distinct from zero |
| `Xiaobao-iPadOS/Sources/Native/StudentChartsView.swift` | `AttendanceCourseRow`, `AttendanceComposition(counts:)` | counts = current course's positive-total counts | Use exactly the same status order and denominator as the ring projection |
| `Xiaobao-iPadOS/Sources/Core/StudentCharts.swift` | `AttendanceRingLayout` uses `AttendanceComposition(counts:)` | counts = report aggregate | Add polar hit testing without recalculating segment ranges |
| `Xiaobao-iPadOS/Tests/Core/StudentChartTests.swift` | Row projection, composition and ring layout | inputs = independent synthetic counts and invalid totals | Verify per-course denominators, unknowns, zero segments and ring boundaries |

## CourseForecast

Category: Frontend Utility / Presentation Contract · Status: Active  
Path / entry: `Xiaobao-iPadOS/Sources/Core/GPA/CourseForecast.swift`, `AssessmentForecast` and `CourseForecast.calculate(current:estimates:)`. The assessment needs a percent mark; name, category and course weight default to nil. The initializer validates values and creates an ID if omitted. The calculator takes an optional normalized published total and draft assessments, and returns a hypothetical percentage or a reason it is unavailable. Depends only on Foundation and the existing grade validation errors. See the [GPA core](Xiaobao-iPadOS/Sources/Core/GPA/README.md).

### Consumers

| File | Usage | Parameters | Purpose |
| --- | --- | --- | --- |
| `Xiaobao-iPadOS/Sources/Native/GPA/CourseGradesView.swift` | Calculate for the current detail | current = projected published percentage; estimates = page-local drafts | Keep school and semester data unchanged |
| `Xiaobao-iPadOS/Sources/Native/GPA/CourseForecastSheet.swift` | Create or edit a hypothetical assessment | id = existing draft or generated ID; name/category/mark/courseWeight = form state | Validate the student's explicit assumptions |
| `Xiaobao-iPadOS/Sources/Native/GPA/CourseTaskList.swift` | Render drafts and their separate result | estimates/forecast = current course detail state | Explain why a forecast is or is not available |
| `Xiaobao-iPadOS/Tests/Core/CourseForecastTests.swift` | Validate inputs and arithmetic | current and estimates = independent synthetic fixtures | Check zero vs. missing, valid shares and excess allocations |

## Task projection and catalog

Category: Frontend Utilities / Presentation Contract · Status: Active  
Path / entry: `Xiaobao-iPadOS/Sources/Core/Tasks/`, `TaskRecord` (including `cardStage(at:)`), `TaskFilters`, `TaskTermDirectory`, `TaskReadRequest` and `TaskCatalog.load(term:read:)`. No filters by default; nil term means current. The reader is supplied explicitly and pages are validated before a result is returned. Depends on Foundation and the existing task/roster contract. See the [module](Xiaobao-iPadOS/Sources/Core/Tasks/README.md).

### Consumers

| File | Usage | Parameters | Purpose |
| --- | --- | --- | --- |
| `Xiaobao-iPadOS/Sources/Core/SchoolPortalData/SchoolPortalData.swift` | TaskRecord(campus:roster:) | row = verified current-term task; score = optional student-list release after consent; roster = explicit subject relation | Render real task cards without reading grade detail or allowing submission |
| `Xiaobao-iPadOS/Sources/Core/CampusConnection.swift` | Authorized task query and current metadata marker | request = selected term/page; scope = authorized account; route is encoded by the task request | Share auth and preserve offline byte compatibility |
| `Xiaobao-iPadOS/Sources/Native/Tasks/TasksView.swift` | Scope, term catalog, projection, and result sorting; supplies `TaskRecord.cardStage(at:)` to each tile | source = portal/cache/demo/selected term; preservingUndatedSourceOrder = model.school.selected; reader uses the captured scope; filters = view state; stage clock = model.now | Show the newest published assignments in one complete term; do not infer submission from a local flag |
| `Xiaobao-iPadOS/Sources/Native/Tasks/TaskFilterBar.swift` | Options and editable filters | tasks = unfiltered selected term; filters = view binding; range uses school dates | Keep options available while other facets are selected |
| `Xiaobao-iPadOS/Sources/Native/Tasks/TaskCard.swift` | Task summary, score and stage glyph | task/stage = supplied projections; showsLocalCompletion = supplied presentation flag | Keep source rules separate from styling |
| `Xiaobao-iPadOS/Sources/Native/Tasks/TaskDetailView.swift` | Detail presentation | task = one normalized record including separate `mark` and `estimatedMark`; local completion from existing AppModel | Keep publication, authorized preview and local completion distinct |
| `Xiaobao-iPadOS/Tests/Core/TaskPresentationTests.swift`, `Xiaobao-iPadOS/Tests/Core/TaskCatalogTests.swift`, `Xiaobao-iPadOS/Tests/Core/CampusConnectionTests.swift`, `Xiaobao-iPadOS/Tests/Core/CampusOfflineTests.swift` | Projection, history and older-cache tests | fixtures and authorized loopback reads | Confirm no grade requests, no partial pages and no ambiguous grades |
| `Xiaobao-iPadOS/Tests/Core/SchoolPortalTests.swift` | TaskFilters.results / TaskRecord.mark | term = synthetic portal rows; preservingUndatedSourceOrder = true for portal, default for comparison | Verify release projection and filtered newest-first / undated ordering |

## Task filter and status labels

Category: Frontend UI Components · Status: Active  
Paths / entry: `Xiaobao-iPadOS/Sources/Native/Tasks/TaskFilterBar.swift` (`TaskFilterLabel(title:value:symbol:)`, symbol defaults to selector chevrons) and `Xiaobao-iPadOS/Sources/Native/Tasks/TaskCard.swift` (`TaskGradingBadge(state:)`, `TaskSubmissionLabel(state:)`, no status default). Depend on SwiftUI and the task projection. The text labels retain distinct submission and grading semantics in detail, apart from the source-stage ribbon on cards. See the [native task module](Xiaobao-iPadOS/Sources/Native/Tasks/README.md).

### Consumers

| File | Usage | Parameters | Purpose |
| --- | --- | --- | --- |
| `Xiaobao-iPadOS/Sources/Native/Tasks/TaskFilterBar.swift` | TaskFilterLabel for typed facets, states and deadline | title = facet; value = binding or all; symbol = calendar for dates, default otherwise | Show the effective restrictor and tap target |
| `Xiaobao-iPadOS/Sources/Native/Tasks/TasksView.swift` | TaskFilterLabel for academic term | title = term; value = selected/source term; symbol = default | Match the adjacent filters |
| `Xiaobao-iPadOS/Sources/Native/OtherItems/OtherItemsFilterBar.swift` | TaskFilterLabel for course and status | title = current facet; value = current course/status or all; symbol = default | Match My Tasks controls without importing its submission or grading rules |
| `Xiaobao-iPadOS/Sources/Native/Tasks/TaskDetailView.swift` | TaskGradingBadge and TaskSubmissionLabel | grading = supplied grading state; submission = source state projected against deadline/local completion | Keep the two meanings separate in detail |
| `Xiaobao-iPadOS/Sources/Native/Tasks/TaskCard.swift` | TaskSubmissionLabel | state = localCompletion, only when the device has that flag | Distinguish the device-only flag from the school stage |

## TimelineTrackLayout

Category: Frontend Utility · Status: Active  
Path / entry: `<repo-root>/Xiaobao-iPadOS/Sources/Core/TimelineTrackLayout.swift`, `TimelineTrackLayout(timeline:bounds:width:)`. Inputs: a resolved timeline, its clock bounds and the available width in points. Output: proportional tile spans and a bidirectional mapping between position and school minute. Adjacent blocks have a uniform six-point gutter, reduced uniformly if space is exceptionally tight. A real recess occupies that gutter; a shared boundary introduces no extra time. Overlapping source lessons retain a common linear clock. Depends on Foundation and LessonTimeline only. See the [native module](Xiaobao-iPadOS/README.md).

### Consumers

| File | Usage | Parameters | Purpose |
| --- | --- | --- | --- |
| `Xiaobao-iPadOS/Sources/Native/TodayView.swift` | TimeLensView draws tiles and positions the marker; gestures query minutes | timeline and bounds = resolved day; width = measured width minus both insets | Keep rendered progress and a finger's position on the same timeline |
| `Xiaobao-iPadOS/Tests/Core/TimelineTrackLayoutTests.swift` | Map and invert positions | synthetic blocks/bounds and varied track widths | Cover duration ratios, uniform separation, real recesses, touching and overlapping periods |

## TeachingSlot

Category: Shared Type / Contract · Status: Active  
Path / entry: `<repo-root>/xiaobao-backend/src/domain.rs` and `<repo-root>/Xiaobao-iPadOS/Sources/Core/SchoolDay.swift`; `TeachingSlot {start,end}` carries school-local minutes, not a course ID. No default slot table. Source and defaults are described by the [HTTP contract](xiaobao-backend/API.md#schedule-and-calendar); native code depends on Foundation, Rust on Serde.

### Consumers

| File | Usage | Parameters | Purpose |
| --- | --- | --- | --- |
| `xiaobao-backend/src/provider.rs`, `xiaobao-backend/src/provider/demo.rs` | Build fixture bell times and course intervals | slots = CAMPUS_TEACHING_SLOTS; roster and rotation = account fixture | Publish bell times independently of assignment count |
| `xiaobao-backend/src/domain.rs`, `xiaobao-backend/src/api.rs` | Student.slots_for_day, Schedule | day = authorized student's rotation for requested date | Return optional daily bell metadata |
| `xiaobao-backend/src/offline.rs` | Timetable.teaching_slots | table = authorized source snapshot | Publish optional day-indexed bells in the existing timetable module |
| `Xiaobao-iPadOS/Sources/Core/CampusOffline.swift`, `Xiaobao-iPadOS/Sources/Core/CampusPage.swift` | Decode direct or persisted timings | date/day = requested account's school calendar; missing table = nil | Read older payloads and forward only applicable slots |
| `Xiaobao-iPadOS/Sources/Core/SchoolDay.swift` | Local source and LessonTimeline | intervals = provider's published bells | Distinguish a wholly empty teaching slot from unscheduled time |
| `Xiaobao-iPadOS/Tests/Core/TeachingSlotTests.swift`, `Xiaobao-iPadOS/Tests/Core/CampusConnectionTests.swift`, `xiaobao-backend/tests/device_cache.rs` | Contract tests | independent test schedules and campus fixtures | Verify standalone/daily/offline parity and fallback |

## City weather

Category: Frontend Utilities / native service boundary · Status: Active  
Path, purpose and interface: [CityWeather](Xiaobao-iPadOS/Sources/Core/CityWeather/README.md). `CityWeatherStore` supplies a current, cached, preview, loading or unavailable display; `OpenMeteoClient.read(_:)` reads the model-valid time and condition. Defaults: fixed campus city, standard preferences, real clock and automatic mode; the asynchronous reader is injected. Depends on Foundation, Observation and Atmosphere core, not account state or Rust.

### Consumers

| File | Usage | Parameters | Purpose |
| --- | --- | --- | --- |
| `Xiaobao-iPadOS/Sources/Native/AppModel.swift` | Own one store and public client; `display`, `setFollowsCity` | reader = client.read; city/defaults/clock = defaults; display time = model.now; preview = stored manual choice | Share one resolved sky; never overwrite the manual choice with a report |
| `Xiaobao-iPadOS/Sources/Native/XiaobaoApp.swift` | `setForeground` | active = app scene phase is active | Cancel when inactive, resume only when due |
| `Xiaobao-iPadOS/Sources/Native/EnvironmentView.swift` | `followsCity`, `setFollowsCity`, city name and display cases | enabled = toggle value; selected preview = row callback to AppModel; timestamp = sample validity in school time zone | Expose source, cache status and local override |
| `Xiaobao-iPadOS/Sources/Native/Atmosphere/AtmosphereView.swift` | `CityWeatherDisplay.weather` via AppModel | source = model.weatherDisplay; no direct fetch | Draw the effective condition behind all shared screens |
| `Xiaobao-iPadOS/Tests/Core/CityWeatherTests.swift` | client contract, WMO mapping and store | city/clock/reader/preferences = isolated test inputs | Check modes, races, freshness, offline recovery and request contents |

## Atmosphere core

Category: Frontend Utilities · Status: Active  
Purpose / entry: selected weather, normalized illustration values and seasonal light, in [Atmosphere Core](Xiaobao-iPadOS/Sources/Core/Atmosphere/README.md).  
Interface / default: `Weather`, `WeatherCategory.conditions`, `SkyTime(minute:on:)`, `SkyPalette.at(time:style:)` and `Festival.automatic(on:)`. Omitting date gives the canonical light cycle; omitting elapsed time returns the still weather frame.  
Dependencies: `SchoolClock`, Foundation.

### Consumers

| File | Usage | Parameters | Purpose |
| --- | --- | --- | --- |
| `Xiaobao-iPadOS/Sources/Native/AppModel.swift` | `Weather`, `SkyTime`, `Festival` | weather = city display or saved manual preference; minute = live Shanghai time or preview; date = model's current date | Persist manual selection and supply display state |
| `Xiaobao-iPadOS/Sources/Native/EnvironmentView.swift` | `WeatherCategory.conditions`, `SkyTime.previewMinute`, `Festival.allCases` | manual weather = optional selection + model.previewWeather; festival = preference binding; phase = selected shortcut | Populate pickers and preview times |
| `Xiaobao-iPadOS/Sources/Core/CityWeather/CityWeather.swift`, `CityWeatherStore.swift` (same directory) | `Weather` | condition = documented code or caller's preview; unavailable art = cloudy | Return an existing illustration without adding an invented city condition |
| `Xiaobao-iPadOS/Tests/Core/CityWeatherTests.swift` | `Weather` | synthetic samples, expectations and manual conditions | Check the reader-to-sky boundary |
| `Xiaobao-iPadOS/Sources/Native/Atmosphere/AtmosphereView.swift` | `Weather.style`, `SkyPalette.at` | time and weather = AppModel; still frame = default | Render the backdrop and shared contrast |
| `Xiaobao-iPadOS/Sources/Native/Atmosphere/SkyBackdrop.swift` | `SkyPalette` | palette = caller's sky lighting | Procedural gradient fallback before GPU output |
| `Xiaobao-iPadOS/Sources/Native/Atmosphere/SkySurface.swift` | `SkyPlaybackClock` | running = visibility and motion policy; instant = monotonic uptime | Advance or freeze the cloud clock |
| `Xiaobao-iPadOS/Sources/Native/Atmosphere/VolumetricSkyState.swift` | `SkyTime`, `WeatherStyle`, `SkyPalette`, `Festival` | civil sky time, elapsed motion time, selected weather and festival | Supply lighting and cloud controls separately |
| `Xiaobao-iPadOS/Sources/Native/Atmosphere/SkyDetails.swift` | `Festival` | festival = date or manual | Draw optional seasonal decorations only |
| `Xiaobao-iPadOS/Sources/Native/Atmosphere/WeatherOverlay.swift` | `WeatherStyle.frame(at:)` | elapsed = view's timeline or nil for still | Draw moving and static visibility and precipitation |
| `Xiaobao-iPadOS/Sources/Native/Atmosphere/AtmosphereColors.swift` | `SkyColor`, `WeatherMood` | semantic backgrounds and daylight only | Blend weather art tokens |
| `Xiaobao-iPadOS/Sources/Native/GlassComponents.swift` | `SkyColor.color` | source = core RGB value | Bridge core colors to SwiftUI |
| `Xiaobao-iPadOS/Sources/Native/Atmosphere/SkyParticles.swift` | `WeatherFrame` | frame = current strength; motion = stable midpoint | Draw bounded, smoothly moving precipitation or dust |
| `Xiaobao-iPadOS/Tests/Core/EnvironmentTests.swift`, `Xiaobao-iPadOS/Tests/Core/WeatherTests.swift`, `Xiaobao-iPadOS/Tests/Core/SkyPlaybackClockTests.swift` | core APIs | synthetic dates, clocks and effect parameters | Check data, season and motion boundaries |
| `Xiaobao-iPadOS/Tests/AtmospherePreview/RenderSky.swift` | `SkyTime`, `Weather.style` | preset visual clock and explicit elapsed time | Compare generated images independent of the UI |

## AtmosphereView

Category: Frontend Composite Component · Status: Active  
Purpose / entry: shared decorative sky behind native panes, in [Atmosphere Renderer](Xiaobao-iPadOS/Sources/Native/Atmosphere/README.md).  
Interface / default: `AtmosphereView(inEnvironmentPanel: false, isCovered: false)`; weather and sky time are read from the AppModel environment, reduced-motion and appearance from SwiftUI.  
Dependencies: Atmosphere core, SwiftUI, MetalKit and the local Metal shader.

### Consumers

| File | Usage | Parameters | Purpose |
| --- | --- | --- | --- |
| `Xiaobao-iPadOS/Sources/Native/XiaobaoApp.swift` | `RootView` detail-column backdrop | isCovered = state:coveredScope matches current navigation scope; ignore safe area; inEnvironmentPanel = default | Keep the main sky during sidebar switches and pause its clock under a pushed detail |
| `Xiaobao-iPadOS/Sources/Native/StudentComponents.swift` | `StudentDetailSurface` background | all defaults; ignore safe area | Continue backdrop behind details |
| `Xiaobao-iPadOS/Sources/Native/EnvironmentView.swift` | environment sheet backdrop | inEnvironmentPanel = true; ignore safe area | Preview the current scene while the underlying page is covered |

## VolumetricSky

Category: Frontend Composite Component (internal rendering pipeline) · Status: Active  
Purpose / entry: [Atmosphere renderer](Xiaobao-iPadOS/Sources/Native/Atmosphere/README.md); `VolumetricSky.init(device:library:)` builds GPU field caches, and `encode(_:in:to:)` submits only sky rendering.  
Interface / default: shader receives caller-supplied `SkyUniforms`, command buffer and color pass; the MTKView supplies resolution and budget. No assets, time defaults, or networking inside the encoder.  
Dependencies: Metal, `Shaders/VolumetricSky.metal`, two generated 3D scalar/noise volumes.

### Consumers

| File | Usage | Parameters | Purpose |
| --- | --- | --- | --- |
| `Xiaobao-iPadOS/Sources/Native/Atmosphere/SkySurface.swift` | Create, then encode | device = system GPU; library = Xcode default; pass = current drawable; uniforms = selected condition and playback clock | Present the iPad background |
| `Xiaobao-iPadOS/Tests/AtmospherePreview/RenderSky.swift` | Create, then encode | device = host GPU; library = probe build; pass = readable texture; uniforms = fixed visual tests | Validate the same rendering pipeline offscreen |

## AppState and app

Category: Backend Infrastructure · Status: Active  
Purpose / entry: Compose the Axum server (`xiaobao-backend/src/lib.rs`: `AppState`, `app`).  
Interface / default: `app(state)` registers the API; `AppState::new(provider)` uses in-memory devices, `with_session_db(provider,path)` persists device grants.  
Dependencies / documentation: `SchoolProvider`, `Devices`, auth/HTTP read modules; [backend README](xiaobao-backend/README.md).

### Consumers

| File | Usage | Parameters | Purpose |
| --- | --- | --- | --- |
| `xiaobao-backend/src/main.rs` | `app`, `AppState::with_session_db` | provider = `DemoProvider::with_hs_calendar(school_today())`; path = existing session DB configuration | Start the demo binary with the confirmed HS calendar |
| `xiaobao-backend/tests/api.rs` | `app`, `AppState::new` | provider = fixed-date demo | Exercise HTTP contract without a server process |
| `xiaobao-backend/tests/device_cache.rs` | `app`, `AppState::{new,with_session_db}` | provider = fixed-date demo or local stub; path = optional per-test file | Test versioning, persistence and isolation |

## Auth extractors and device grants

Category: Backend Infrastructure · Status: Active  
Purpose / entry: `xiaobao-backend/src/auth.rs` and `xiaobao-backend/src/devices.rs`: validate demo sessions (`Session`, `CurrentStudent`) and manage per-device grants (`Devices`).  
Interface / default: Axum request extractors; `Devices::{memory,open,issue,refresh,revoke,subject}`. Bearer credentials are resolved only in this boundary.  
Dependencies / documentation: `AppState`, provider lookup and existing SQLite; [authentication contract](xiaobao-backend/API.md#authentication).

### Consumers

| File | Usage | Parameters | Purpose |
| --- | --- | --- | --- |
| `xiaobao-backend/src/lib.rs` | `Sessions::new`, `Devices::{memory,open}` | lifetime = 8 hours for memory session; capacity = 128; persistent path = caller-provided | Initialize session state |
| `xiaobao-backend/src/auth.rs` | `Devices::subject` | credential = current authorized request | Resolve a remembered device subject |
| `xiaobao-backend/src/api.rs` | `Session`, `CurrentStudent`, session/device operations | session input = request; profile = validated demo selection | Sign in/out and restrict reads |
| `xiaobao-backend/src/work/mod.rs` | `CurrentStudent` | default request extraction | Restrict work reads/statistics to the session account |
| `xiaobao-backend/src/attendance/mod.rs` | `CurrentStudent` | default request extraction | Restrict attendance reads to the session account |
| `xiaobao-backend/src/cache.rs` | `Session` | default request extraction | Authenticate before an ETag response |
| `xiaobao-backend/src/offline.rs` | `Session` | default request extraction | Scope the offline manifest and downloads |

## Common HTTP helpers

Category: Backend Services · Status: Active  
Purpose / entry: `xiaobao-backend/src/api.rs`: `ApiError`, `reply`, `availability`, `check_course`, `optional_date_range`, `exact_filter`, `search`, `page`.  
Interface / default: Same errors, required date pair, 200-character text filters, paginated slice (offset 0 / limit 30, maximum 100) and JSON envelope.  
Dependencies / documentation: Axum, serde and normalized domain dates; [API.md](xiaobao-backend/API.md#envelope-and-errors).

### Consumers

| File | Usage | Parameters | Purpose |
| --- | --- | --- | --- |
| `xiaobao-backend/src/api.rs` | Common validations/envelopes for existing handlers | range max = 42 for calendar, 366 for resource dates; page offsets/limits = request or defaults; class type/sharer/text = query | Keep the standard contract for grades, resources, profile and calendar |
| `xiaobao-backend/src/work/mod.rs` | `check_course`, `optional_date_range`, `exact_filter`, `search`, `page`, `reply`, `ApiError` | course = `course_id`; term/type/mode/text = query; max = 366; offset/limit = query or defaults | Share list/detail/statistics behavior |
| `xiaobao-backend/src/attendance/mod.rs` | `check_course`, `optional_date_range`, `availability`, `reply`, `ApiError` | range max = 366; course = `course_id`; availability = coverage and rows | Build the same envelope for three categories |
| `xiaobao-backend/src/offline.rs` | `ApiError`, `reply` | source = provider; availability = ready for successful data | Report versions and requested parts |
| `xiaobao-backend/src/auth.rs` | `ApiError` | status/message = session or provider outcome | Return common authentication failures |
| `xiaobao-backend/src/devices.rs` | `ApiError` | status/message = device grant outcome | Return common grant failures |
| `xiaobao-backend/src/lib.rs` | `ApiError` | status = 404/405 through route fallbacks | Keep HTTP errors in JSON |

## SchoolProvider, DemoProvider and demo_slots

Category: Backend Services · Status: Active (demo)  
Purpose / entry: `xiaobao-backend/src/provider.rs` and `xiaobao-backend/src/provider/demo.rs`. Provide authorized data snapshots and a common rotation slot generator.  
Interface / default: `SchoolProvider` source boundary, `DemoProvider::new(reference_date)`, `demo_slots(courses,day)`. Default provider revision is absent unless supported; the current binary uses demo.  
Dependencies / documentation: Domain types, grade and offline snapshots; [provider README](xiaobao-backend/src/provider/README.md).

### Consumers

| File | Usage | Parameters | Purpose |
| --- | --- | --- | --- |
| `xiaobao-backend/src/main.rs` | `DemoProvider::new` | reference date = Shanghai today | Start with only synthetic data |
| `xiaobao-backend/src/lib.rs` | `SchoolProvider`, `source` | provider = caller-supplied; subject scoped by session | Compose and namespace the app |
| `xiaobao-backend/src/auth.rs` | `student` | subject = verified session subject | Load a single account snapshot |
| `xiaobao-backend/src/api.rs` | `demo_profiles`, `lessons`, `grades_if_changed`, `source` | subject = verified session; range = school dates; version = optional request cursor | Supply existing projections and session profiles |
| `xiaobao-backend/src/work/mod.rs` | `source` | default provider id | Describe work read provenance |
| `xiaobao-backend/src/attendance/mod.rs` | `source` | default provider id | Describe attendance read provenance |
| `xiaobao-backend/src/cache.rs` | `cache_revision` | subject = verified session | Validate whether a response may be reused |
| `xiaobao-backend/src/provider.rs` | `demo::make_student`, `demo_slots` | variant = account fixture; course roster + rotation day | Build accounts and schedule lessons |
| `xiaobao-backend/src/offline.rs` | `offline_catalog`, `demo_slots`, `source` | subject = verified session; slots = roster and each rotation day | Keep offline release data consistent |
| `xiaobao-backend/src/grade_sync.rs` | `DemoProvider`, `student` in tests | reference date + same term next day | Check stable revisions |
| `xiaobao-backend/tests/api.rs` | `DemoProvider::new` | fixed date | Exercise demo requests |
| `xiaobao-backend/tests/device_cache.rs` | `DemoProvider`, `SchoolProvider` | fixed date or wrapped local stubs | Exercise cached and alternate publications |

## Domain records, dates and attendance calculation

Category: Shared Types / Contracts · Status: Active  
Purpose / entry: `xiaobao-backend/src/domain.rs` (`Student`, work/library/grade/attendance/calendar models, `DateRange`, `school_offset`, `AttendanceSummary`).  
Interface / default: API field types, optional metadata, and read helpers (Shanghai UTC+8; default category classroom).  
Dependencies / documentation: chrono/serde; [data contracts](xiaobao-backend/API.md).

### Consumers

| File | Usage | Parameters | Purpose |
| --- | --- | --- | --- |
| `xiaobao-backend/src/main.rs` | `school_today` | default system clock | Seed demo time |
| `xiaobao-backend/src/provider.rs` | `Profile`, `Student`, `Lesson`, `DateRange` | subject/range = method inputs | Publish authorized data and lessons |
| `xiaobao-backend/src/provider/demo.rs` | Construct synthetic domain records | reference date, roster, profile and demo variant | Supply testable page data |
| `xiaobao-backend/src/api.rs` | Use `Student` fields, `DateRange`, grades and resources | request filters and account snapshot | Read lesson, grade and library data |
| `xiaobao-backend/src/auth.rs` | `Student` | account matched to session | Serve a trusted snapshot to handlers |
| `xiaobao-backend/src/work/mod.rs` | `Work`, `Student`, `WorkKind`, `WorkStatus`, `school_offset` | term/kind/status/course + dates = query | Select work by account/historical term |
| `xiaobao-backend/src/work/statistics.rs` | `Work`, `WorkKind`, `Score` | records = filtered current account, course = query | Compute nullable rates without converting letter scores |
| `xiaobao-backend/src/attendance/mod.rs` | `DateRange`, `AttendanceCategory`, `AttendanceSeries`, `AttendanceStatus`, `AttendanceSummary` | dates/category/course = query; counts = selected category records | Build attendance reports |
| `xiaobao-backend/src/offline.rs` | Serialize work/grade/timetable/attendance/resource data by part | data = authorized current-term publication | Preserve existing offline interface |
| `xiaobao-backend/src/cache.rs` | `school_today` | default system clock for `/schedule`, `/calendar` | Scope time-sensitive cache entries |
| `xiaobao-backend/src/grade_sync.rs` | `CourseGrade`, `Course`, `Gradebook` | selected publication and roster | Version grade content |
| `xiaobao-backend/tests/device_cache.rs` | `DateRange`, `Lesson`, `Profile`, `Student` | fixed-date fixture or stubs | Implement provider test doubles safely |

## Grade versions and offline releases

Category: Backend Services · Status: Active  
Purpose / entry: `xiaobao-backend/src/grade_sync.rs` (`GradeSnapshot`, `GradeCursor`) and `xiaobao-backend/src/offline.rs` (`OfflineCatalog`, `Part`).  
Interface / default: Current-term release version and per-course or per-module changes. No new mandatory offline parts.  
Dependencies / documentation: Domain serialization and SHA-256; [offline contract](xiaobao-backend/API.md#offline-synchronization), [grade cursor](xiaobao-backend/API.md#per-course-checks-for-earlier-clients).

### Consumers

| File | Usage | Parameters | Purpose |
| --- | --- | --- | --- |
| `xiaobao-backend/src/domain.rs` | `GradeSnapshot` | normalized account snapshot | Store current grade version and records |
| `xiaobao-backend/src/provider.rs` | `OfflineCatalog::demo`, `GradeSnapshot::version` | student = authorized fixture | Prepare releases and detect changes |
| `xiaobao-backend/src/provider/demo.rs` | `GradeSnapshot::new` | subject, current book and course roster | Publish current-term grades |
| `xiaobao-backend/src/api.rs` | `GradeCursor`, `GradeSnapshot::book/changes` | cursor = body or selected account grades | Current grade read and backward-compatible sync |
| `xiaobao-backend/src/offline.rs` | `GradeSnapshot::changes` | cursor = default/full current term | Serialize grades for old clients |
| `xiaobao-backend/src/lib.rs` | `offline::{versions,download}` | default v1 routing/state | Expose offline APIs |
| `xiaobao-backend/tests/device_cache.rs` | `OfflineCatalog::new`, `Part` | local fixture parts | Verify part-specific invalidation |

`cache::conditional` has one registration in `xiaobao-backend/src/lib.rs` (private cache settings from `AppState`); the handlers consume it through the registered Axum read router rather than direct calls. HTTP-level behavior is covered by `xiaobao-backend/tests/api.rs` and `xiaobao-backend/tests/device_cache.rs`.


## School portal data and scoped store

Category: Frontend data contract · Status: Active  
Relative path: `Xiaobao-iPadOS/Sources/Core/SchoolPortalData/` · Repository path: `<repo-root>/Xiaobao-iPadOS/Sources/Core/SchoolPortalData/`. Entry: `SchoolPortalStore.openGrades(boundOwner:signIn:reopen:)`, `SchoolPortalPage.issue(at:foreground:loading:)`, `SchoolPortalRead`, `SchoolPortalWeek`, `SchoolPortalGrades`, `SchoolPortalTasks`, `SchoolPortalAttendanceQuery`, `SchoolPortalAttendance`, `loadAttendance(_:force:)`, `loadAttendanceSubject(_:page:force:)`. Dependencies: existing Campus types, timetable/week, task and grade projections. Defaults: no owner, no records, no grade fetch; a reader is required. [Interface, limits and tests](Xiaobao-iPadOS/Sources/Core/SchoolPortalData/README.md).

### Consumers

| File | Usage | Parameters | Purpose |
| --- | --- | --- | --- |
| `Xiaobao-iPadOS/Sources/Native/AppModel.swift` | Construct/select store, queue one foreground grade visit, verify identity | selected = device preference; reader = SchoolPortalReader; reopen = PortalSession.reopenForGrades; signIn = opted-in explicit grade action only; expected owner = verified matching device binding | Choose the real source without creating a Rust account |
| `Xiaobao-iPadOS/Sources/Native/SchoolPortal.swift` | Begin navigation, classify document and verify | current main-frame URL/loading; invalidate on reset/termination | Fence replies across website navigation |
| `Xiaobao-iPadOS/Sources/Native/XiaobaoApp.swift` | Route and suspend school pages / consume foreground grade intent | tab, scenePhase, sheet visibility, pending reads, epoch and verified owner | Never route unavailable private records to demo |
| `Xiaobao-iPadOS/Sources/Native/SchoolPortalSync/SchoolPortalReader.swift` | Implement fixed SchoolPortalRead operations; gate on SchoolPortalPage | request = typed operation; includeScores = task read’s session scope; expected = current opaque owner; foreground/loading/URL = WebKit | Same-origin transport |
| `Xiaobao-iPadOS/Sources/Native/SchoolPortalSync/SchoolPortalPages.swift` | Select authentic waiting, recovery, interaction, failure and connected states; loadWeek | retry = current identity or grade request; date = current day; force = user refresh | Today and real-source destinations |
| `Xiaobao-iPadOS/Sources/Native/SchoolPortalSync/SchoolPortalAttendancePage.swift` | loadAttendance / loadAttendanceSubject | category/status/date/page = active filters; course = selected listed subject; force = explicit refresh or retry | Display and invalidate only a verified student’s active report |
| `Xiaobao-iPadOS/Sources/Native/SchoolPortalSync/SchoolPortalGradebook.swift` | Observe pending/grades and loadDetail; refresh through AppModel | initial read = foreground GPA visit; refresh = student action; detail = listed course; key = current term | Real grade screen and on-demand course detail |
| `Xiaobao-iPadOS/Sources/Native/Planner/PlannerSchoolSource.swift`, `PlannerView.swift`, `PlannerScheduleCanvas.swift` (same directory) | week(on:), loadWeek, epoch and source flags | date = selected week; force = user retry; owner = account namespace | Bounded school track without demo notices or detail links |
| `Xiaobao-iPadOS/Sources/Native/Tasks/TasksView.swift` | loadTasks, taskRead, current term, projected records | force = user refresh; load identity includes state:allowsTaskScores; no history fallback | Refresh the existing cards after a grade visit without requesting course details |
| `Xiaobao-iPadOS/Sources/Native/CampusView.swift`, `Settings/ReminderSettingsView.swift`, `GradesView.swift`, `StudentServicesView.swift` (under Native) | Settings, trial inputs, reminder and web-only routing | selected / owner / grades = actual store state; trial = memory only | Keep demo data out of account-dependent settings and sections |
| `Xiaobao-iPadOS/Tests/Core/SchoolPortalTests.swift`, `Xiaobao-iPadOS/Tests/Core/SchoolPortalAccessTests.swift` | Verify store, document classification, expiry, owner and cancellation fencing | synthetic readers, fixed URLs and scoped test identities | Offline regression checks |
| `Xiaobao-iPadOS/Sources/Native/SchoolPortalSync/SchoolPortalEntry.swift` | Return typed navigation issues | busy = notReady; timeout = network; terminal issue = delegate input | The store handles a failed entry without guessing its cause |
| `Xiaobao-iPadOS/Sources/Native/SchoolPortalLogin/SchoolPortalLoginSettings.swift` | enrollmentName(for:), owner and epoch | expected = student already verified on the official page; when = explicit enrollment | Bind only that account, never an arbitrary login name |
| `Xiaobao-iPadOS/Sources/Native/SchoolPortalLogin/SchoolPortalPasswordEntry.swift`, `SchoolPortalLoginVault.swift` (same directory) | Official URL classifier and typed sign-in failures | main frame, actual navigation; claim = bound owner | Fail closed on unknown pages, changed owner and challenges |
| `Xiaobao-iPadOS/Tests/SchoolPortalSync/WebKitSmoke.swift` | Instantiate the store and call openGrades with a WebKit navigation | selected = true; reader = loopback WKWebView; reopen = SchoolPortalEntry; classifier = same path on the fixed Home origin | Assert actual fresh grades, scope reset and interactive stop |
| `Xiaobao-iPadOS/Tests/AtmospherePreview/SidebarSkySmoke.swift` | Select / invalidate the synthetic school scope while on Settings | selected = test true/false; reason = default; no school network read | Assert the navigation no longer shows the previous destination |

## School portal WebKit reader and native adapters

Category: Frontend infrastructure / composite views · Status: Active  
Relative path: `Xiaobao-iPadOS/Sources/Native/SchoolPortalSync/` · Repository path: `<repo-root>/Xiaobao-iPadOS/Sources/Native/SchoolPortalSync/`. Entry: `SchoolPortalReader.read(_:expected:)`, `SchoolPortalEntry.reopen(_:home:)`, `SchoolPortalPages(tab:)`, `SchoolPortalAttendancePage`, `SchoolPortalWebSection(section:)`, `SchoolPortalGradebook`, `SchoolPortalCoursePage(id:)`, `SchoolPortalRetry(issue:retry:)`. Dependencies: WebKit, fixed bundled reader/projection scripts, scoped store, existing Today/Planner/Tasks/GPA presentation. Defaults: fixed official Home frame; no credentials exposed, no network target supplied by callers, no writes. [Module contract](Xiaobao-iPadOS/Sources/Native/SchoolPortalSync/README.md).

### Consumers

| File | Usage | Parameters | Purpose |
| --- | --- | --- | --- |
| `Xiaobao-iPadOS/Sources/Native/AppModel.swift` | Construct reader, classify Home and provide recovery callback | session = existing PortalSession; salt = installation namespace; expected = active owner; reopen = fixed official Home | Wire the real account |
| `Xiaobao-iPadOS/Sources/Native/SchoolPortal.swift` | Validate Home; own, finish or cancel SchoolPortalEntry | URL = fixed official Home; WebKit = same device store; navigation = concrete returned handle | Only one navigation, no login sheet or shared credentials |
| `Xiaobao-iPadOS/Sources/Native/XiaobaoApp.swift` | SchoolPortalPages(tab:) | tab = mounted navigation scope’s tab; environment = AppModel | Route non-Settings tabs for real mode |
| `Xiaobao-iPadOS/Sources/Native/StudentServicesView.swift` | SchoolPortalWebSection | section = selected existing tab’s portalSection | Keep three official web destinations |
| `Xiaobao-iPadOS/Sources/Native/SchoolPortalSync/SchoolPortalPages.swift` | SchoolPortalGradebook, SchoolPortalAttendancePage and SchoolPortalRetry | destination = mounted tab; issue = identity or week error; retry = same read or grade visit | Reuse account-aware state handling |
| `Xiaobao-iPadOS/Sources/Native/SchoolPortalSync/SchoolPortalAttendancePage.swift` | SchoolPortalRetry / school attendance store | issue = active report or detail error; retry = same scoped read | Keep failure and retry native |
| `Xiaobao-iPadOS/Sources/Native/SchoolPortalSync/SchoolPortalGradebook.swift` | SchoolPortalCoursePage and SchoolPortalRetry | id = selected listed course; issue = scoped detail read; retry = same course | Lazy authorized detail |
| `Xiaobao-iPadOS/scripts/generate_project.py`, `Xiaobao-iPadOS/Tests/SchoolPortalSync/portal-reader.test.cjs`, `WebKitSmoke.swift` (same test directory) | Bundle/exercise both JS files; WebKitSmoke runs the shipping store and SchoolPortalEntry | resource names fixed; smoke Home = loopback; entries = actual WKNavigation; expectations = same-owner fresh read or stop | Verify the read and recovery chain without a school account |
| `Xiaobao-iPadOS/Tests/SchoolPortalSync/ipad-smoke.py`, `GradeEntryUITests.swift` (same directory) | Ship-equivalent navigation, reader and grade page in an isolated UI fixture | ephemeral localhost origin only in test copy; distinct bundle ID; input = actual sidebar taps and refresh | Cover delayed GPA reads, trusted-device renewal, the native attendance report/detail and interaction-required stop |

## Foreground school sign-in

Category: native frontend infrastructure / settings · Status: implemented (live-school sign-in unverified). Path: `<repo-root>/Xiaobao-iPadOS/Sources/Native/SchoolPortalLogin/`. [Contract, files, protection and tests](Xiaobao-iPadOS/Sources/Native/SchoolPortalLogin/README.md).

### SchoolPortalLoginVault / SchoolPortalLoginSecret — Consumers

Entry: `SchoolPortalLoginVault.swift`. A single private Security.framework Keychain item. Defaults: disabled, standard app preferences for an opaque registration ID only, device-only protection, no synchronization. A claim persists a pause before releasing a secret.

| File | Usage and parameters |
| --- | --- |
| `Xiaobao-iPadOS/Sources/Native/AppModel.swift` | Construct with defaults; claim(for:) = verified expected owner on an explicit active grade visit; confirm = matching claim after fresh grades; disable = source/logout/account boundary |
| `Xiaobao-iPadOS/Sources/Native/XiaobaoApp.swift` | Refresh metadata on active scene; never request a password on resume |
| `Xiaobao-iPadOS/Sources/Native/SchoolPortalLogin/SchoolPortalLoginSettings.swift` | Enable(owner:name:password:) from current verified owner, scoped enrollment reply and explicit secure field; remove only on user's action |
| `Xiaobao-iPadOS/Sources/Native/SchoolPortalSync/SchoolPortalPages.swift` | Read binding availability/paused state for native fallback only |
| `Xiaobao-iPadOS/Sources/Native/SchoolPortal.swift`, `SchoolPortalLogin/SchoolPortalPasswordEntry.swift` (under the same Native directory) | Accept ephemeral typed secret via a claim callback, never a URL, arbitrary username, logging input or cookie |

### SchoolPortalPasswordEntry / PortalLogin — Consumers

Entry: `SchoolPortalPasswordEntry.swift`, bundled `PortalLogin.js`. Defaults: shipped bundle, fixed student login origin, school-owned login button, at most one submission and a finite deadline. Input = WebKit view + current foreground guard + scoped claim callback. Output = completed navigation or sanitized error; not proof of identity.

| File | Usage and parameters |
| --- | --- |
| `Xiaobao-iPadOS/Sources/Native/SchoolPortal.swift` | Own/cancel the transaction; view = existing persistent school WebKit; gate and claim = current grade visit |
| `Xiaobao-iPadOS/scripts/generate_project.py`, `Xiaobao-iPadOS/Tests/SchoolPortalSync/portal-login.test.cjs`, `ipad-smoke.py` and `GradeEntryUITests.swift` (same test directory) | Bundle fixed script; synthetic DOM states for refusal cases; isolated loopback substitution for UI/Keychain/password checks |

### SchoolPortalLoginSettings — Consumers

Entry: `SchoolPortalLoginSettings.swift`. Collapsed native enrollment/removal disclosure with a non-secret status; no parameters; depends on the current AppModel, school store and vault.
- `Xiaobao-iPadOS/Sources/Native/CampusView.swift`: all defaults; single disclosure below school account status. No credential entry on the grade or attendance pages.
- `Xiaobao-iPadOS/Tests/SchoolPortalSync/SettingsUITests.swift` and `GradeEntryUITests.swift`: verify disclosure and access via the native form; generated local test credential only for the explicit enrollment scenario.
