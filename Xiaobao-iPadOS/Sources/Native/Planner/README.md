# 原生计划页

`PlannerView()` 是侧栏「计划」的唯一页面，也是按天或按周查看学校安排的入口。本机模式读取内置课表；连接资料服务时读取当前账号现有的课表、校历和课程名。真实校宝模式与「今日」读取同一份按账号保存的学年课表和按日期缓存的事项，翻周不请求网络；不借用演示课表或推算正式铃声时段；所有来源复用此页和[计划核心](../../Core/Planner/README.md)。

| 文件 | 职责 |
| --- | --- |
| `PlannerView.swift` | 日期、浏览时的个人计划可见性、编辑模式、撤销／重做、草稿及唯一的本机写入入口。一次性接收顶栏、日终快捷入口或提醒请求的日期；编辑草稿关闭后才处理日期跳转。 |
| `PlannerSchoolSource.swift` | 从当前资料账户、演示课表或内置高中部校历读取可见日期；不写学校数据。 |
| `PlannerWeekView.swift` | 周日期标题、日期列坐标和日／周共用时间尺；刻度不依赖交互模式。 |
| `PlannerMonthPicker.swift` | 选日期、区分校历事件和明确不上课，显示完整假期起止。 |
| `PlannerTimelineView.swift` | 按同一坐标计算日／周的划选、跨日拖放及边缘滚动；移动已存计划直接保存，划选填入草稿。 |
| `PlannerHoldGesture.swift` | 统一识别长按与移动，结合可见提手坐标区分移动和新建选区。 |
| `PlannerScheduleCanvas.swift` | 学校卡片铺满轨道，起止时间点开才显示；个人计划画在同一天的上层，仅局部气泡接管点击。 |
| `PlannerTimelineDecoration.swift` | 系统色和图标映射；预览、已排计划和标记共用的精确色带与粗端点。 |
| `PlannerTimelineMarks.swift` | 保持已排定的学校短时段和活动时间点的入口。 |
| `PlannerPlanAnnotations.swift` | 绘制避开课名的无底计划标签，以及拥挤时带编号和图标的胶囊；点胶囊查看全部名称与时间。 |
| `PlannerInboxView.swift` | 编辑专用的固定气泡架：待安排、可复用气泡、提醒状态和唯一加号；浏览不挂载也不占位。 |
| `PlannerPlanCard.swift` | 时间轴与待安排共用的个人卡片：抓手、完成、编辑和点选落点。只有抓手接管拖动。此处集中定义计划页的连续圆角。 |
| `PlanEditorView.swift` | 新建和编辑共用：气泡、按星期或轮转 Day 重复、提醒、颜色、图标及时间段划选／微调。草稿只有「保存」才提交；明确确认移除后按所选范围单独提交。 |

输入：当前 `AppModel`、学校日期及账号、缓存或实时读取的学校安排、当天的本机计划。输出：一条可浏览的日程和独立的个人计划写入；学校资料不写回、不改变学校的提交或考勤状态。

本机随堂测验与「我的考试」读取同一条 `StudentServices` 记录。明确绑定的测验代表该节课，只呈现一张可读详情的卡片；不会挤窄相邻课程，也不归入个人计划。普通独立学校记录与正式课表不在此合并。计划时间轴不再显示作业、测评等仅有截止时间的标记，原事项仍在各自页面。

学校课表和个人计划按同一个日期加载，但个人计划不归属任何课程。学校卡片先画满原宽，上层保留全宽色带；重叠处增浓但不超过 28%，单条色带仍为 14%。图标与计划名避开课名和卡片上保留的附属文字。空间不足时保留图标；较密集时多个图标带编号共享一个玻璃胶囊，可在任一模式展开组内标题和时段，点单项进入那一条的表单。减少透明度时保留起止线，并让胶囊使用系统实色，不覆盖课名。

日、周共用的学校卡片平时不重复写起止时间。浏览时，普通课程和有起止时间的学校条目复用原生详情弹窗；已有本机考试详情仍保留。仅一点时刻的事项继续用原生浮层。编辑时学校卡片保持不可打开，划选和落点优先。个人计划的时间和详情不受影响。

依赖 `SchoolClock`、`CampusConnection`、`PlanStore`、`GlassCard` 与学校详情；向 `AppModel` 请求调度授权后的个人提醒。`RootView` 是页面消费者。继续用现有 `AppScreen`、程序天气和[设计系统](../../../../UI_DESIGN_SYSTEM.md)，无新主题。计划只在这台 iPad 可用。切日、换账户或取消拖动不会重写计划；仅支持当前页内拖放，不传数据给其他 App。

浏览时可滚动、查看课程、直接打开时间轴已有计划或者用眼睛隐藏计划。打开单项不改变当前模式；保存才提交表单修改。进入编辑会暂时显示计划，完成后回到原浏览状态。撤销／重做和整条底部气泡栏只在编辑时出现，包含「＋」和提醒状态。编辑模式长按非提手处并拖动就划选新时段，长按提手再拖是移动；狭窄标签共用触点，胶囊在编辑时额外保留选择落点和完成快捷操作。表单也可按分钟微调，或选择「在课表上选时段」自动进入编辑模式并保留草稿。选时期间以该日期的操作提示替换气泡栏，只调整该计划当天的时间；划选或取消后返回原表单。普通气泡拖入产生副本，重复气泡和课表上的重复项拖动时更新今后的整组，不覆写过去。撤销／重做仅处理个人修改（包括从浏览表单保存的修改），退出本次页面会话后不保留这段历史。

宽横屏按现有周课表的周日到周六显示；七列共用时钟，不因个人计划或假期改列宽，周末也能放个人计划。竖屏、窄分屏和辅助大字保留单日。浏览和编辑共用同样的整点文字、半点线和时间坐标；选时仍可点击半点线，并由 VoiceOver 读出时刻。月历沿用所供 2026–27 主校区高中部日历，标注节假日、明确停课与其他事件，不导入上一学年的活动日期，不覆盖已有课程。计划提醒在同一次存储成功后重排，不影响学校课前提醒和授权状态。

测试：运行 `swift test --filter Planner` 和原生 Xcode 模拟器构建。除了比较增减个人计划前后的课程矩形，还要验证没有并行课程的学校卡片右缘等于时间轨道右缘，排除固定预留宽度。用跨课的有色计划检查色带经过课程文字；色带内点击仍去课程详情，点气泡去计划详情。走新建、划选、气泡复制、按日隔离、每周和个人提醒流程。横竖屏和大字号下保持时间、抓手和目标可见。资料账户的缓存与隔离沿用 `PlannerTests` 及原联调。

## Change History

### 2026-11-22 — native-period-details / panel-stability
Model: OpenAI Codex. Today 和 Planner 以同一课表条目填充现有详情弹窗；明确标出空缺的教师。真正后台、打开网页核对和换号保持隐私边界；临时系统遮盖不重置已显示的日期列和草稿。仍只有活动页允许编辑和学校读取。

### 2026-11-22 — shared-meal-cards
Model: OpenAI Codex. Breakfast, lunch and dinner reuse the named GlassCard; compact breakfast renders one line at its exact height. Browse time popover and editor gesture behavior are unchanged. Actual locations, when available, remain the card accessibility value.

### 2026-11-22 — incomplete-publication / rotation-source
Model: OpenAI Codex. A sampled date beyond the dated daytime roster now shows the shared timetable's source note in the existing day status or week header. Input: `PlannerSchoolSource.DayInput.usesDaytimeRotation` from the saved school day; no duplicate UI inference, new controls, or browse-time requests. The iPad `--annual` fixture checks both a late-only and an empty date.

### 2026-11-22 — canonical-bells / named-school-cards / seasonal-pause
Model: OpenAI Codex. 日、周的空节直接复用普通学校卡片、主文字色与相同字号；短事项直接显示名称，相邻名称点开查看明细，不再用菱形或裸计数代替。仍以实际时长布局，浏览可点开准确时间，编辑时不抢手势。接口仅限现有 Canvas 和短事项视图；无新控件入口。


### 2026-11-22 — planner-campus-routine / midnight-disclosure
Model: Codex. `PlannerSchoolSource` 把源校历、本机住宿显示选项和已确认学校日程传给日／周共用投影；`PlannerScheduleCanvas` 复用学校卡片和时间弹层，点击就寝的任一日均显示跨日完整时间。初始化滚动不定位到午夜的就寝续段。短于普通卡片的独立作息（如早餐）在既有标记旁显示名称，保留原时长和 44 pt 点击区域。未添加新页面、提醒或联网读取。回归：学年课表 iPad loopback 场景（`--annual`）。

### 2026-11-21 — dated-removal / sheet-confirmation
有提醒的安排在移除或撤销时先对照系统通知队列；不涉及提醒的操作在保存本机记录后即可返回，不等系统通知服务。
Model: Codex · Changed: saved dated plans have a destructive confirmation in their existing editor. Weekday and rotation occurrences offer one date or that date and later. The active series shelf uses its next confirmed date (shown before removal); an undated reusable template is not a dated target. Reason: cancelling a plan should also cancel its upcoming alert, not move it to the inbox. Interfaces: local editor, store, undo/redo and existing notification reconciliation.

### 2026-11-21 — local-class-alerts / notification-suspension
Model: Codex. 个人计划仍需明确设置开始时间和提醒。普通退后台或等待身份不会撤销已登记的通知；退出、手动账号复核或切号会清理。个人副标题不会出现在独立的校宝课前提醒。

### 2026-11-21 — planner-rotation / repeat-picker
Model: Codex. 原每周开关的位置改用「重复」选择，分别显示星期或 Day 1–6。首次选择轮转时可带入所选日期的已确认 Day；休息日不代猜。没有后续校历可先存规则，不生成日期或提醒。由 `PlannerView` 传入当前所有者校历，不新增页面、校宝读取或存储路径。
验证：隔离 iPad 模拟器上，Day 3 计划出现在两个不同星期几的 Day 3，同星期但不同 Day 的日期没有这条计划。随后从原表单改按星期、再关闭重复，课表请求数不变。完整 225 项 Swift 测试（含本机 Rust 联测）和 iPadOS Release 构建通过。覆盖排程输入，未在真机触发系统通知。

### 2026-11-21 — annual-timetable / cache-first-today
Model: Codex. PlannerSchoolSource uses the same on-device year as Today. Changing date or opening the month picker no longer causes portal week reads. Offline timetable access does not grant access to personal plans.


### 2026-11-21 — planner-source
Model: Codex · Keywords: planner-source / fixture-boundary
Changed: Only the explicit internal local source resolves fixture lessons or work details. A missing service credential is not a timetable.
Reason: Keep account boundaries explicit and avoid blocking navigation on redundant reads. Affected interfaces: Existing planner read projection; no plan record changes.


### 2026-11-21 — 校宝本人资料
Model: Codex · Keywords: schoolis-webkit / scoped-student-reads  
Changed: `PlannerSchoolSource` 分开处理门户实际日期和演示轮转，账户或登录代次改变时关闭旧编辑和详情。 Reason: 防止不同账号和课程来源混用。 Affected interfaces: 内部周读取和所有者范围，个人计划格式不变。


### 2026-11-20 — 点开查看学校时段
Model: Codex · Conversation Keywords: planner / school-time-disclosure  
Reason: 时间轴已提供概览，默认卡片优先展示名称，具体分钟按需查看。  
Changed: 共同的日／周学校卡片隐藏起止时间；已有详情照常打开，其余卡片用原生浮层显示时段。保留时间轴、卡片尺寸和个人计划手势。  
Affected interfaces: `PlannerScheduleCanvas` 内部视图，不改模块入口、学校服务、存储或设置。  
Verification: Release 模拟器构建和 168 项 Swift 测试（含本机演示服务联调）通过。两项 iPadOS 27 界面测试确认：竖屏点午餐、空节才显示准确时段，收起浮层不移动卡片；横屏课程详情正常打开，切换编辑不改变选时刻度的位置。

### 2026-11-20 — 统一日期跳转
Model: Codex · Conversation Keywords: today-day-shortcut / planner-date-route  
Changed: 接收顶栏的今天、日终的明天及课前提醒的日期；消费跳转后仍可按原方式选择日期。保留原日／周断点，不再依赖独立课表视图。  
Reason: 计划是统一的按日期浏览入口，切日不改变草稿或已存数据。  
Affected interfaces: 内部 `AppModel.openPlanner(on:)` / `takePlannerDateRequest()`；不改计划存储和课表服务。  
Verification: iPadOS 27 横屏从其他主页面进入今日，翻周、打开明日并回到今日通过；44 项计划／周历核心测试通过。

### 2026-11-20 — 不在计划页展示截止点
Model: Codex · Conversation Keywords: planner / deadline-only-records  
Reason: 计划时间轴只保留学校安排和个人计划，不重复展示学习事项截止时间。  
Changed: 日视图和周视图共用的学校日程不再绘制作业、考试或测评的截止标记；已排定的学校安排不变。  
Affected interfaces: 原生视图及网络接口无变更；使用[计划核心](../../Core/Planner/README.md#change-history)过滤后的日程。  
Verification: 日期投影及标记排版回归通过；签名模拟器 Release 构建通过。

### 2026-11-20 — 浏览留空、统一时间尺与表单划选
Model: Codex · Conversation Keywords: planner / edit-only-shelf / consistent-time-ruler / draft-range-entry  
Reason: 浏览不应占用底部空间，两种模式不得显示不同的时间尺，从现有计划表单选时段时应直接切入编辑。  
Changed: 气泡栏整体限编辑模式；时间刻度的绘制与选时触点分离；表单选时显式切换模式，保留草稿并在周视图指明日期。  
Affected interfaces: `PlannerInboxView` 移除内部的 `showsAdd` 参数；`PlannerScheduleCanvas` 明确接收是否允许查看学校详情。无新模块、HTTP、数据库、配置或部署变更。  
Verification: 155 项 Swift 测试（含演示服务联调）、模拟器 Release 构建与两条 iPadOS 27 横屏界面回归通过。固定背景下，整点文字和半点线所在的 228 × 240 区域逐像素一致；普通浏览不挂载底栏，滚动后切换模式也保持时刻位置，编辑的两点选择仍可用。从缩略图进入同一草稿后自动切到编辑，长按拖选成功回填，取消不改已存时段。预览重新安装及启动前后个人计划档案未变。

### 2026-11-20 — 色带交叠加深与单项编辑入口
Model: Codex · Conversation Keywords: planner / overlap-tint / individual-plan-editor  
Reason: 区别计划重叠密度，并让编号胶囊不会挡掉每条记录自己的编辑入口。  
Changed: 保存色带在相交处叠色并限制合成强度；任一模式的组内单项、单独标签和气泡均打开原表单，新建、板面拖动和撤销／重做继续限编辑模式。  
Affected interfaces: `PlannerRangeBand` 和 `PlannerPlanActions` 的内部呈现；无新页面、目录、HTTP、数据库、配置或部署变更。
Verification: 155 项 Swift 测试（含本地演示服务联调）、签名模拟器 Release 和 iPadOS 27 界面测试通过。固定背景下，同色单条／两条／八条的红通道增量分别为 30／45／60，确认逐步加深且接近封顶。浏览时实测组内点选、保存仅修改目标、单独标签与气泡均可点，撤销仅在切入编辑后可用。原预览计划档案更新前后未变。

### 2026-11-20 — 编号玻璃胶囊与浏览控制
Model: Codex · Conversation Keywords: planner / numbered-capsule / browse-visibility / edit-only-controls  
Reason: 保留课名和个人计划的可读性，并让浏览不会误触新建或历史写入。  
Changed: 使用无底个人标签和保留图标的拥挤样式，一个系统玻璃胶囊展开全部分组计划；眼睛只切换浏览层，撤销、重做和「＋」只在编辑中出现。  
Affected interfaces: 新增 `PlannerPlanAnnotations.swift` 和内部布局；复用同一编辑器。无新页面目录、HTTP、数据库、配置或部署。  
Verification: 155 项 Swift 测试（含本机演示服务联调）及签名模拟器 Release 构建通过。iPadOS 27 横屏验收通过：三项计划分组与逐项展开、隐藏前后课程卡片矩形一致、浏览无写入控件、进入编辑后可以新建和选组内记录编辑、退出恢复隐藏状态。核对原预览档案更新前后未变。[收起示例](../../../../docs/verification/student-interface/planner-numbered-capsule.jpg) · [展开示例](../../../../docs/verification/student-interface/planner-numbered-capsule-open.jpg)均为合成事项。

### 2026-11-20 — 计划和考试共享本机节次
Model: Codex · Conversation Keywords: planner / demo-timetable / in-class-assessment  
Reason: 测验样例不应使用另一套时钟，也不应挤占其他课程。  
Changed: 本机投影只呈现一次明确关联的随堂测验与课程节次，不改卡片样式、拖动或课表源数据。  
Affected interfaces: 沿用只读 `SchoolWorkDetailView`，无新入口或个人存储变化。  
Verification: iPadOS 27 模拟器实拍核对横屏周四列：两节原课恢复完整宽度，随堂测验在对应节次仅有一张卡片。

### 2026-11-20 — 编辑模式、每周移动、撤销重做与高中部周／月历
Model: Codex  
Conversation Keywords: planner / edit-hold-gestures / weekly-series-move / undo-redo / HS-month  
Reason: 让点击、选择新时段与移动可明确区分，在横屏按一周安排个人计划并看清学校假期。  
Changed: 浏览／编辑切换、提手和选区互斥、重复符号和整组移动、历史操作、周视图和月历标注。  
Affected interfaces: `PlannerTimelineView`、`PlannerPlanActions`、`PlanStore` 的原生调用；没有新模块目录、网络接口、数据库、配置或部署。

Verification: 149 项 Swift 测试（含本地 Rust 演示服务联调）及签名模拟器 Release 构建通过。iPadOS 27 竖屏实测轻点编辑、从课表或计划名长按划选、提手移动、快速滑动、完成及撤销。横屏实测七列、跨日移动每周计划、查看下一周与撤销／重做。月历实测假期完整起止和高中考试日期的非停课标记。[高中月历实拍](../../../../docs/verification/student-interface/planner-hs-month.png)使用合成事项。提醒重排经核心测试，模拟器系统接受通知设置但拒绝登记请求（`UNErrorDomain` 2003，`Source is not authorized`）；本次未验证实际通知送达。

### 2026-11-20 — 计划浮在学校课表上方
Model: Codex  
Conversation Keywords: planner / full-width-course-track / front-overlay / pass-through-taps  
Reason: 上一版的固定控制栏让课表始终偏窄，背景色块加侧栏不是视觉叠层。  
Changed: 学校卡片恢复全宽；所有个人时间段连同起止线盖在课程之上；重叠色带合成一次，只有小气泡接管点击。  
Affected interfaces: 计划页私有绘制和 `PlannerRangeBand` 的绘制参数；日期、已存计划、提醒及学校读取不变。无新模块、目录、HTTP 或数据库变更。

Verification: iPadOS 27 实测旧版无个人计划时仍预留 158.5 pt，新版无重叠课程的右缘与轨道右缘对齐；划选、保存跨课计划后所有可见课程矩形不变，点色带可打开课程、点个人气泡能编辑、切日不显示该计划。对比截图，范围内课名笔画有上层色带的改色，范围外课名像素没有改色。[叠层实拍](../../../../docs/verification/student-interface/planner-overlay-above-courses.png)使用合成事项。Release 构建通过。全套 Swift 编译被未修改的 `WeekTimetableTests.swift` 表达式拦住；仅在隔离检查中排除此文件，131 项通过，其中 22 项为计划测试。

### 2026-11-20 — 时间轴分层、气泡及提醒
Model: Codex  
Conversation Keywords: planner / school-frame-invariance / bubble-shelf / weekly-notification  
Reason: 个人计划不应挤动学校卡片，常用事项和固定安排需要重复使用。  
Changed: 独立的学校与个人绘制路径；一处加号、可复用气泡、按周规则、本机通知权限及调度。  
Affected interfaces: 计划页内部响应、`PlanStore`、`ReminderService` 生命周期；无新页面或模块目录、HTTP、数据库或环境变量变化。
Verification: 签名 Release 构建通过。iPadOS 27 实测划选、气泡重复投放及次日保留、跨学校事项时卡片矩形不变且课程详情仍可点击、切换七天后的每周安排。接受系统通知权限后，从系统队列读到一条重复提醒；改回「不提醒」后同一队列为空。未等到实际通知弹出，未在实体 iPad 验证。[分层实拍](../../../../docs/verification/student-interface/planner-independent-layers.png)使用合成事项。

### 2026-11-20 — 划选与计划样式
Model: Codex  
Conversation Keywords: planner / draw-range / range-band / plan-appearance  
Reason: 用同一把时间尺比较各天、准确圈选时间，区分个人安排与固定课程。  
Changed: 课表选两个时间边界并回填草稿；编辑中选系统颜色和图标，保存后显示真实起止的色带。空节不占列，短事项用独立标记。  
Affected interfaces: 计划页、内部草稿和绘制。学校详情、HTTP、数据库、环境变量和部署不变。  
Verification: 123 项 Swift 测试（含本地 Rust 演示服务联调）及 iPad 模拟器 Release 构建通过；iPadOS 27 实测双向划选、取消、用两次点选回填、带样式保存、移动和重开，最后对齐时间刻度并复测端点。原预览模拟器的计划文件保持不变。[界面实拍](../../../../docs/verification/student-interface/planner-range-bands.png)使用合成事项。

### 2026-11-20 — 计划页连续圆角
Model: Codex  
Conversation Keywords: planner / continuous-corners / simulator-preview  
Reason: 收小课表卡片和待安排区的圆角，让时段边界更清楚。  
Changed: 课表卡片与落点轮廓用 12 pt，待安排外框用 16 pt，内部条目与输入用 8 pt；玻璃和减少透明度模式共用相同形状。  
Affected interfaces: `GlassCard` 增加可选形状，不改其他页面的默认值；计划的录入、拖放和本机存储规则不变。  
Verification: 实际工作区的 iPadOS 27 模拟器构建通过；14 项 Planner 测试通过。新版已更新到原测试模拟器，未清空已有计划。

### 2026-11-20 — 玻璃课表与直接排程
Model: Codex  
Conversation Keywords: planner / direct-drag / inline-capture / glass-timetable  
Reason: 录入不中断看课表，不要求先在表单逐项选时间。  
Changed: 去掉主流程的白色面板和弹窗表单，使用学校时间轴、固定待安排区和放手前预览；已有编辑和勾选继续可用。  
Affected interfaces: 内部 `PlannerTimelineView`、`PlanEditorView` 调用和新增的计划交互组件；学校只读入口、今日、课表和已保存计划不变。

### 2026-11-20
Model: Codex  
Conversation Keywords: planner / schedule-entry / untimed-plans  
Reason: 复用原日程位置，把下一项、学校安排和个人计划放到同一天。  
Changed: 本机和资料服务共用计划页。已有「今日」「课表」「我的任务」与校宝网页入口保留。  
Affected interfaces: 原生 `AppTab.planner`；`SchoolWorkDetailView` 新增默认不变的 `allowsLocalCompletion` 参数。无学校写入。

### 2026-11-21 — bilingual UI / verbatim school data
Model: Codex. Localize calendar navigation, editing, removal scope, repetition, reminder options, timeline actions and VoiceOver; date displays use the interface language and school time zone. User-authored plan titles remain verbatim. [Language boundary and regression tests](../../Core/Localization/README.md).

### 2026-11-22 — study-time-notice / shared-dates
Model: OpenAI Codex. PlannerSchoolSource passes Day.studyTimePending to the existing portrait day note and landscape week headers. Both layouts keep the published notices and use the same shared schedule as Today. No new timetable query, control or student-specific rule.

### 2026-11-22 — timetable-display / supplemental-courses
Model: OpenAI Codex. TimetablePlanScope identifies the verified owner and session for both pages. The existing editor writes a timed, typed supplement through PlanStore; normal notes are unchanged. Editing can manage hidden personal courses. Hide-plans affects ordinary notes, not enrollments. Touch placement uses unfiltered occupancy; the editor continues warning about official conflicts. Test: --timetable-display.
