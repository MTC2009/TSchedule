# 其余项目

- **用途与边界：** 一个侧栏入口，页内切换考试、测评和资料库。共用任务页样式的网格与课程筛选；详情分别以考场与时间、测评要求、资料正文为重点。不提交测评、获取成绩、下载文件或修改学校数据。
- **输入：** 本机的 `StudentServices` 示例，或已授权的 `CampusConnection` 考试、测评、资料库与课程名单。已取得完整模块缓存时在全组筛选；旧服务若只给分页，则提示按当前页筛选并保留分页。未同步或无权限不会混入本机数据。
- **入口与输出：** `OtherItemsView()` 负责分段；`OtherItemsGrid(section:records:filters:showsLocalBookmarks:isPartialPage:campusPage:)` 接受当前栏目、记录与页面筛选状态，默认全部课程。整张卡进入对应详情；返回仍保留筛选。只有本机资料沿用已有收藏。
- **主要文件：** `OtherItemsGrid.swift` 是网格与方块；`OtherItemsFilterBar.swift` 复用任务页的菜单标签；`OtherItemsDetails.swift` 按类别展示原内容；`Sources/Core/OtherItemsCatalog.swift` 投影来源并组合筛选。
- **依赖与消费者：** `StudentServicesView.swift` 与 `CampusView.swift` 使用网格。详情依赖 `StudentDetailSurface`、`GlassCard` 和现有校宝入口。原「计划」仍调用其原有考试详情。
- **限制：** 连接版资料没有课程关联，显示为「未分科」。课程 ID 已知而课程名称暂未载入时，不标为「未分科」。跨科考试只出现一次，可按已知的多科关联筛选。旧缓存可能缺少考试起止时间或资料分享时间，只有来源可确认时才展示。
- **测试：** 在 iPad 工程运行 `swift test`，覆盖课程关系、跨科条目、无课程、状态／搜索／收藏组合，以及完整缓存和权限撤销。模拟器验证两种数据来源的三类详情、返回筛选、收藏和横竖屏。

## Change History

### 2026-11-21 — 校宝本人资料
Model: Codex · Keywords: schoolis-webkit / scoped-student-reads  
Changed: actual school mode keeps the three-way selector and opens the selected school webpage without showing local examples. Reason: these three real collections are not imported. Affected interfaces: existing OtherItemsView and portal route mapping; no new API.


### 2026-11-20 — 方块文字与留白
Model: Codex · Keywords: other-items-tile-typography / dynamic-type  
Changed: 放大三类方块的标题、科目、时间与其他字段；用卡片的高度拉开标题区和信息区。考试地点与状态能同排时分列；窄时换行，不缩字。  
Reason: 保持方块比例和原有内容，同时让扫读更容易。  
Affected interfaces: 无。筛选、资料来源、详情、收藏与服务接口保持原样。

Verification: 原生模拟器构建通过；11 英寸 iPad Air（iPadOS 27）两项本机界面测试通过，覆盖横竖屏方块、考试字段、课程与状态筛选、三类详情和收藏，以及辅助字号（中）的单列显示和考试详情入口。最大辅助字号的自动化未定位侧栏入口，未覆盖方块；未上真机。[竖屏考试方块（局部）](../../../../docs/verification/student-interface/other-items-roomier-exam-tiles.png)。

### 2026-11-20 — 方块与课程筛选
Model: Codex · Keywords: other-items-grid / course-facet / category-detail  
Changed: 用共用方块和课程筛选替换三个栏目的长列表；方块随列宽保持接近任务页的比例。移除结果统计行，缩短搜索并与下拉框对齐。新详情各自突出考试时间与考场、测评状态与说明、资料正文。  
Reason: 与「我的任务」的查找方式一致，不把三种记录的状态或内容混成作业。  
Affected interfaces: 新增原生网格、纯筛选投影与完整授权缓存的只读读取；Swift 解码既有可选考试时间／科目关联和资料分享时间。无新增 HTTP API、依赖、数据库、环境变量或部署。

Verification: 164 项 Swift 核心测试通过（含本机 Rust HTTP 联调和跨页缓存测试），iPad 模拟器构建通过。两项 iPadOS 27 界面测试覆盖本机和连接演示服务的三种详情、课程／状态筛选、返回保留筛选、本机收藏，以及横竖屏搜索与「全部」同排、横屏方块比例与无统计行。实拍：[竖屏方块](../../../../docs/verification/student-interface/other-items-compact-exams-portrait.png) · [横屏方块](../../../../docs/verification/student-interface/other-items-compact-exams-landscape.png) · [考试详情](../../../../docs/verification/student-interface/other-items-tile-exam-detail.png) · [测评详情](../../../../docs/verification/student-interface/other-items-tile-evaluation-detail.png) · [资料预览](../../../../docs/verification/student-interface/other-items-tile-resource-detail.png)。未在真实学校账号或真机上测试。
