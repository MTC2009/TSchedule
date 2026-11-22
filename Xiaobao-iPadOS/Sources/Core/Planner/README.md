# Planner core

日常计划的应用内规则，不依赖 SwiftUI、Rust 或校宝网页。

| 文件 | 职责与接口 |
| --- | --- |
| `PersonalPlan.swift` | `PersonalPlan` 是某个学校日期的个人记录。输入为名称与可选 `PlanTime`（上海当地分钟，时间段含开始、不含结束）、`PlanColor`、`PlanIcon`、`PlanReminder`。`placing(at:)` 只改时间。 |
| `PlanBubble.swift` | 常用气泡和重复规则。`PlanRecurrence` 只取一种：星期或轮转 Day。`PlanPlacementItem` 区分副本、单日记录与重复系列，避免仅凭共享 ID 把重复项误认成复制来源。 |
| `PlannerSchoolDay.swift` | `local(on:provider:work:)` 或 `connected(on:schedule:calendar:courseName:)` 输出只读学校条目、轮转日与资料可用性。空节只由已有课表投影确认。仅将显式关联、且时段与科目一致的本机随堂测验按一条记录呈现；其他重叠学校记录仍各自保留。 |
| `PlannerCampusRoutine.swift` | `withCampusRoutine(on:calendar:showsBoardingRoutine:)` 把同一份已确认日程补成「今日」和「计划」的同一份日程。正式教学日可显示未选的 Block 9/10 和晚餐；该节已有课程则只保留实际课程。住宿选择只产生参考条目，不参与个人计划冲突、空节吸附、课程提醒或实时活动。 |
| `TimetablePresentation.swift` | 将学校已排时段、已验证所有者的补充课程和本机显示选择投影到两页。先确定占用再筛选，正式考试事项不属于外考课程；读取与过滤不改原数据。 |
| `PlannerDay.swift` | `init(on:school:plans:)` 生成全天、按时间排序和待安排三组，不投影仅有截止时间的学校事项；`focus(at:)` 找下一项或正在进行的最后一项；`conflicts(with:)` 提示已知时段重叠。 |
| `PlannerTimelineLayout.swift` | `PlannerTimeScale(hourHeight:)` 做分钟与纵向坐标的双向换算；`PlannerTimelineLayout(day:scale:minimumHeight:)` 对学校、个人两层独立分列。`PlannerAnnotationLayout` 输入个人几何、板面和学校文本矩形，只输出标签位置、是否显示名称和组成员，不修改原时间或列宽。 |
| `PlannerPlacement.swift` | `PlannerPlacement(at:moving:in:)` 用落点分钟、原时间（可无）和当天课表返回建议时间及冲突；`init(from:to:in:)` 给划选和两次点选复用，两端单独吸附。 |
| `PlanStore.swift` | `readEditor(for:session:)` 读取当前所有者的计划和撤销状态；`apply(_:for:session:calendar:)` 原子提交写入，`step(_:for:session:)` 撤销／重做。保留旧读写入口及 `readSchedule(for:)`。 |
| `PlanEditHistory.swift` | 当前页面会话的前后状态，最多 32 步。根据当前状态检查可逆性，只在存储写入成功后推进历史。 |
| `PlanReminderPlanner.swift` | 输入当前时刻、一个所有者的记录和可选的已确认校历，输出独立标识、触发时间和触发类型，不申请权限或调度。 |
| `PlannerCalendarMonth.swift` | 只读 HS 日历网格、选日期范围和连贯假期起止，未发布不能当作不上课。 |

依赖现有 `SchoolClock`、`LessonTimeline`、本机课表/学习事项和 `CampusSchedule`/`CampusCalendar`；由[原生计划页](../../Native/Planner/README.md)、本机提醒入口与核心测试使用。

学校资料是输入，不修改；只有个人计划有完成状态。截止点保留在各自的学习事项页面，不进入计划时间轴或「接下来」。仅有 `due_at` 的考试不当作已排定考试；有明确安排的考试、学校活动及全天公告继续显示。全天公告不视为占用时间。未同步的课程或节次不产生空节。

iPad 使用应用容器中独立、原子写入且受系统文件保护的本机文件，目录排除系统备份；既不是可刷新的学校缓存，也不存储任何会话凭据。计划以本机模式或服务来源与资料账户组合隔离，退出后不显示该账号的计划，同一资料账户重连可读回。旧档案读取时不会改写，只有明确写入后才采用含气泡的格式；旧版本不读取新格式。损坏或无法读取的文件不会被新记录覆盖。不提供跨设备同步。

计时：直接拖卡时，新安排拖进已确认空节会预填整节；否则开始时间吸附到五分钟，已有持续时长不变。划选是另一条路径，两端分别吸附到五分钟，支持反向，不能跨日，结束可为 24:00；不会取整节。`nil` 仍是未定时。旧档案没有颜色和图标时直接读作默认，无需迁移；个人计划文件的存储路径和所有者隔离不变。

提醒：按上海时区。普通计划未定时、已完成或已错过提醒时不会排新通知。完成一次只跳过该次提醒。按星期的计划保持原行为（包括假期）；按轮转 Day 的计划按校历教学日逐次登记，不使用每周系统触发器。停课日印有 Day 也不算，已公布的周末补课算，未公布／超出校历范围则不排。未来才改规则时，旧规则在生效日之前的有效提醒用有限的单次请求，生效后不再按旧时间重复；撤销／重做会用恢复后的资料重新对照系统队列。仅未来才生效的无限周规则短接四次；遇到未来已完成或移除的日期，则在既有通知预算内逐次登记其余各周，接近生效日或已完成的那次经过后打开 App，会重新检查是否可恢复系统重复。长期不再打开或系统队列已满时，不保证桥接用完后的提醒。

测试：在原生工程目录运行 `swift test --filter Planner`。覆盖旧档兼容、账号隔离、两层互不干扰、气泡拷贝、星期与轮转规则互换、生效边界和按日完成、提醒跨午夜且不提前。

## Change History

### 2026-11-22 — timetable-detail-projection
Model: OpenAI Codex. Propagate the optional source detail through `PlannerSchoolEntry` and `LessonTimeline`. Date and time come from the aligned displayed interval; no course or reminder data is rewritten. The participant labels are not instructions for an action. Tests: `TimetablePresentationTests`.

### 2026-11-22 — location / compact-meal
Model: OpenAI Codex. Separate routine title and location through `PlannerSchoolEntry` and the display-only reference block. `PlannerTimelineLayout` gives short meal ranges the same school-card renderer without increasing duration or affecting adjacent lanes. Formal school and notification data are unchanged. Tests: TimetablePresentationTests, SchoolTimetableBellTests.

### 2026-11-22 — canonical-bells / named-school-cards / seasonal-pause
Model: OpenAI Codex. 已确认课表与仅已知校园作息分开；原时间完全相同的真实晚间课程优先于住宿占位。短事项使用学校条目的真实名称投影。接口：`connected`、`withCampusRoutine`、`MarkGroup.singleSchoolEntry`；不改变个人计划和存储。


### 2026-11-22 — planner-campus-routine / school-night
Model: Codex. 住宿夜以周日到周四的晚上为起点，要求次日已公布上课；周五只保留前一晚延续的晨间作息。就寝横跨两栏，保留同一身份和完整时段。不从假期或未发布的校历推算。接口：只读 `PlannerSchoolDay` 投影；个人存储与网络不变。测试：`swift test --filter SchoolTimetableBellTests`。

### 2026-11-21 — dated-removal / reminder-exclusions
Reminder contract: `PlanReminderPlanner.inputsChanged(from:to:)` compares timed plans with alerts and their series revisions on both sides of an edit, including undo. An unrelated silent note does not need to wait on the notification center.
Model: Codex · Changed: `PlanStore.apply(.remove(plan,scope),…)` removes an ordinary record, excludes one repeated date, or stops a rule at that date. Checks the owner-scoped saved record, retains earlier revisions and reusable templates, and participates in existing undo/redo. A missing optional exclusion set means no dates were removed in older files. Reason: unscheduling a plan is not removal. Interfaces: local mutation, day projection and reminder candidates; no database migration.

### 2026-11-21 — planner-rotation / dated-reminders
Model: Codex. 在原有计划修订中保存按星期或轮转 Day 的单一规则；读旧的 `week` 记录不改写文件。显示、拖动、完成和提醒均使用同一份已确认校历；编辑、停用和撤销按原生效日隔离历史。对外服务、数据表、依赖和权限不变。

### 2026-11-20 — 计划日程排除截止点
Model: Codex · Conversation Keywords: planner / deadline-only-records / schedule-focus  
Reason: 把截止时间留在学习事项页，避免无持续时段的截止点打断课程和个人计划的阅读。  
Changed: `PlannerDay` 在分组和排序前排除截止类学校条目，保留明确排定的短活动、学校公告和个人时刻。  
Affected interfaces: 内部 `PlannerSchoolEntry.Kind` 增加截止分类；原始学校投影、个人存储和外部接口不变。  
Verification: 新用例先重现截止标记与错误焦点，再验证四类截止点均不再进入时间轴、短学校活动和个人时刻仍保留；158 项 Swift 测试（含本地演示服务联调）通过。

### 2026-11-20 — 个人标签避让与紧凑分组
Model: Codex · Conversation Keywords: planner / label-avoidance / numbered-plan-groups  
Reason: 让学校文字和个人名称同屏可读，且不以省略计划为默认。  
Changed: `PlannerAnnotationLayout` 在学校矩形之外寻找标签位置，空间不足保留图标并按邻近时间分组，任何标签偏移都不改变区间、提醒或学校卡片。  
Affected interfaces: 内部呈现逻辑；`PlanStore` 和学校契约不变。  
Verification: 全套 155 项 Swift 测试通过（含本地 Rust 演示服务联调），新增课名避让、编号组成员与时段、极窄时保留单图标验证。

### 2026-11-20 — 本机随堂测验复用课程节次
Model: Codex  
Conversation Keywords: demo-work / in-class-exam / false-overlap  
Reason: 本机演示课表和测验各自填时刻，会把测验叠在不相干的课程上。  
Changed: 测验读取同一课表的时间和教室；计划投影用显式匹配的测验代表同一节课。不根据碰巧重叠的时间隐藏课程。  
Affected interfaces: `PlannerSchoolDay.local` 保持入参不变；新增 `SchoolWork` 的内部节次关联。连接资料服务和个人计划不变。  
Verification: 152 项 Swift 测试通过（含本地 Rust 演示服务联调）。回归用例先重现旧时间与分栏问题，再覆盖本机和已公布 HS 校历、节次精确匹配、停课及未关联／失效关联仍保留课程。

### 2026-11-20 — 每周移动、撤销历史、月历投影
Model: Codex  
Conversation Keywords: planner / weekly-series / session-history / cutover-reminders / HS-calendar  
Reason: 拖动重复气泡要移动今后的整组，跨日计划需要可逆写入，学校假期与事件必须分开。  
Changed: 明确拖动来源，复用规则生效记录，新建、移动、编辑、完成均可撤销与重做，提醒按生效区间计算，月历投影合并连贯假期。  
Affected interfaces: 本机 `PlanStore` 扩展编辑与历史入口，沿用现有档案结构；无 HTTP、数据库、环境变量或部署更改。

Verification: 149 项 Swift 测试通过（含本地 Rust 演示服务联调）。新增用例覆盖新建和编辑分别撤销、跨日更新、整组拖动和未来第一条提前、过去记录保留、撤销分支、账号／会话隔离、旧提醒按规则截止与仅跳过已完成的一次，以及跨年假期和活动区分。

### 2026-11-20 — 两层排版、常用气泡和每周规则
Model: Codex  
Conversation Keywords: planner / independent-school-layer / reusable-bubbles / weekly-rules / local-reminders  
Reason: 排个人事项时不挪动学校课表，日常计划不必重新输入。  
Changed: 两层分别排版、气泡和每周规则按所有者存储、生成一次性与系统重复提醒计划。  
Affected interfaces: 计划内部读写接口与向后读取的本机文件格式；未改学校资料、对外接口、数据库或部署。
Verification: 136 项 Swift 测试通过（含本地 Rust 演示服务的只读 HTTP 联调）；新增回归验证个人区间跨接多个学校重叠组时学校矩形保持不变。

### 2026-11-20 — 显式时间段和可选外观
Model: Codex  
Conversation Keywords: planner / exact-boundaries / short-marks / appearance-compatibility  
Reason: 让校方时段的排版不受短记录撑大，同时尊重手画的两个时间边界。  
Changed: 支持双向选时、可选的颜色与图标，以及空节、短事项和计时时段的分层布局。  
Affected interfaces: `PlannerPlacement`、`PlannerTimeScale`、`PlannerTimelineLayout` 和 `PersonalPlan` 的内部接口；原 `PlanStore` 调用不变，本机文件新增两个可选字段。

### 2026-11-20 — 时间表拖放
Model: Codex  
Conversation Keywords: planner / direct-placement / minute-scale  
Reason: 让预览位置和保存分钟一致，且不挤走原有课程。  
Changed: 新增真实分钟标尺、重叠排布和共享的落点换算。  
Affected interfaces: 新增以上内部 Swift 计算接口；`PersonalPlan`、`PlanStore` 和 HTTP 契约不变。

### 2026-11-20
Model: Codex  
Conversation Keywords: planner / school-day-merge / local-plan-storage  
Reason: 让个人安排能与学校时段同屏而不共享写权限。  
Changed: 增加只读学校安排投影、日计划编排和本机记录存储。  
Affected interfaces: 新增以上内部 Swift 接口；无 HTTP、数据库、环境变量或依赖变更。

### 2026-11-21 — bilingual UI / verbatim school data
Model: Codex. The app-generated fallback for a closed day is localized; notices actually supplied by the school calendar are not. No change to plan persistence, recurrence or timetable dates. [Language boundary and regression tests](../Localization/README.md).

### 2026-11-22 — residence-night / overlapping-study
Model: OpenAI Codex. The existing boarding preference uses the same published return-night classifier as the timetable. On a holiday return it includes evening routine and the next morning; a recorded or corroborated lesson occupies the overlapping study/activity slot rather than appearing twice. Weekends and conferences are not inferred to be holidays. No preference, backend or reminder changes. Test: SchoolStudyWeekTests and planner routine tests.

### 2026-11-22 — timetable-display / supplemental-courses
Model: OpenAI Codex. Cause: only Planner used the campus routine. TimetablePresentation(on:school:plans:settings:editingPersonalCourses:) now produces visible school rows, editable supplements, pre-filter placement input and a Today timeline without deriving vacancies again. TSSA can be displayed as ordinary study at exactly its assigned time; hiding a course cannot create a Free Block. PersonalPlan.courseKind is optional in saved files and survives copies, recurrence and history. TimetablePresentationTests cover independent students, returns and categories.
