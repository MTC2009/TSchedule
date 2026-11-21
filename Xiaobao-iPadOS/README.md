# TSchedule · iPadOS 原生原型

SwiftUI + 系统 Liquid Glass，**0.3 学生端原型**。目标为 **iPadOS 26.0+，Xcode 26+**。工程不依赖第三方库，不需要 XcodeGen 或 CocoaPods。项目中的天气模块不依赖 Rust 演示服务。

## 打开运行

1. 在 Mac 上解压工程，打开 `Xiaobao.xcodeproj`。不要将根目录的 `Package.swift` 当作 App 工程打开；它仅用于核心逻辑测试。
2. 顶部选择 `Xiaobao` Scheme，再选择一个 **iPadOS 26 或更高版本的 iPad 模拟器**。
3. 按 **⌘R**。「今日」按东莞当地时间（Asia/Shanghai）显示正在上课、即将上课或已放学的状态。拖动时间轴才会查看其他时刻；点「回到当前时间」或重新启动即可退出。
4. 在真机运行时，在 Target → Signing & Capabilities 中选择自己的 Team，按需修改 Bundle Identifier，然后选择连接的 iPad 运行。

命令行编译模拟器版本。不需要真机签名证书；模拟器仍需本地 ad-hoc 签名，模拟器钥匙串才能正常工作：

```sh
xcodebuild -project Xiaobao.xcodeproj -scheme Xiaobao \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath ./DerivedData CODE_SIGN_IDENTITY=- \
  CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES build
```

## 天空与天气预览

默认跟随东莞的市级天气，不申请设备定位，不需要校宝登录。点右上角「环境」就能看到来源和有效时刻。点「手动预览」并选中一种天气，即切到手动；重新打开「跟随东莞天气」即可恢复。冷启动使用缓存或更新失败时标为「上次天气」，超过 24 小时不再用它代表当地天气。

手动预览包含 35 种条件，分为晴空与云层、降雨、降雪与结冰、雷暴与强风、雾霾与沙尘。天空由本机 Metal 生成：云量、云体形状与光照逐帧计算，月亮和星空会被三维云层遮挡；没有背景照片、平移贴图或预渲染视频。降水等级改变密度和能见度，区间模式改变强度，阵雨与阵雪有疏密变化。冰雹、雨夹雪、冻雨、台风和扬沙有各自的粒子或风向；雾、霾和沙尘采用不同遮蔽和色调。自动模式仅使用数据源能区分的现象，不从风速或雨量猜测台风、预警等级。

「跟随当前时间」单独控制光照。开启时天空按上海本地日期和时刻改变，季节会推移晨光和黄昏；这不是日出日落预报。关闭后可预览时段或拖动时刻，不会查询另一个时刻的天气。关闭环境动效、开启系统减少动态效果或低电量模式时，显示所选天气的静帧。设置保存在本机；旧「雨」「雪」手动选择分别对应中雨、中雪。

效果代码见 [Atmosphere core](Sources/Core/Atmosphere/README.md) 和 [Atmosphere renderer](Sources/Native/Atmosphere/README.md)。本仓库的 [视觉规则](../UI_DESIGN_SYSTEM.md) 与 [色彩规则](../COLOR_SYSTEM.md) 将天气背景与业务文字、状态、控件分开。

如只想比较同一个时刻的云形，运行 `./scripts/render_sky_probe.sh /tmp/xiaobao-sky-preview`（输出目录必须尚不存在）。这是 Mac 开发机上对同一 Metal 程序的离屏取样，和 iPadOS 界面实拍应分开看。

## 在 App 里读取本人的真实校宝资料

1. 点侧栏「完整校宝」（或「设置 → 个人信息 → 校园资料 → 登录校宝」）。在学校自己的网页完成登录；不需要连接资料服务或选择学生 A/B。
2. 确认进入学校首页后点「完成」。「今日」读取当周实际安排；在「计划」翻周会读取那一周。来源没有提供的轮转 Day、铃声表或课室不编造；失败和没有排课分别显示。
3. 点「GPA」即读取本人当前学期已公布的成绩，不需要另外授权；留在页面上也可以点「刷新 GPA」查看新结果。旧会话失效时先试已有的设备登录；如果校宝仍要求登录，只有主动开启「本机代登录」的学生，才会在自己点 GPA 时由 App 重新登录一次，确认是同一学生后再取新成绩。断网、无权限、启动 App 或后台定时任务不会提交密码。
   点课程才读取其类别、权重和已发布单项成绩。返回「我的任务」可看到任务卡本身已公布的分数；未进入过 GPA 时只读任务和状态，打开任务列表不会请求成绩册。「我的考勤」直接显示校宝的课堂、日常或活动考勤，点一门课才读取该课明细，不打开考勤网页。考试、测评、资料库仍保留手动网页入口。
4. 真实资料本次会话只在内存，离开到后台、明确退出、重新导航或更换账号后会重新确认身份；不会切回演示填空。网页登录由 WebKit 管理，个人计划仍为按账户隔离的本机记录。只想看示例时，可在退出校宝后于「设置 → 个人信息 → 校园资料」明确选择演示。
5. 首次核对：选择同一周比较一节课的日期、起止和地点；同一学期比较一门课的总评、一个已发布项目及其分组权重。不需要回传个人数据。如果某项没有加载，可重试或点「校宝」在原网页核对，勿把网页源码、Cookie 或原始返回提交作问题报告。

模拟器界面（使用本地合成资料）：[原生考勤（更名前的接入验证）](../docs/verification/student-interface/native-school-attendance.jpg) · [账号与设置](../docs/verification/student-interface/native-school-settings.jpg)。

[设备内读取边界及验证](Sources/Native/SchoolPortalSync/README.md) · [数据模型与账号隔离](Sources/Core/SchoolPortalData/README.md)。真实账号内容尚待本人在设备上核对。

## 在这台 iPad 上保持演示资料服务登录

在「设置 → 个人信息 → 校园资料 → 连接演示资料服务」选择资料账户，按需要开启「在此 iPad 保持登录」。模拟器可使用默认的本机地址，真机需要可访问且证书受信任的 HTTPS 地址。钥匙串保存这个设备的续期凭据，App 在凭据有效期内静默续期。登录后，账号设置提供「退出账号」。

侧边栏的「完整校宝」使用学校的网页登录流程。各栏目共用 WebKit 中有效的学校会话，有效期由学校决定。真实模式的原生课表、任务、成绩及考勤由 WebKit 只读接入；接下来的离线缓存与后台检查仅指可选的 Rust 演示服务。

### 离线资料和后台检查

连接后第一次打开校园资料，会下载当前账号可读的课程、轮换课表、校历活动、考勤记录、任务、考试、测评和资料库。每个演示学生有六门课。成绩可在 GPA 页首次点「获取本学期成绩」，以后点「刷新 GPA」，也可在设置里点「检查全部资料（含成绩）」。以后切换页面、日期、筛选或页码，都从本机完整记录读取。在有效设备会话内，重开 App 和断网均可查看已保存的资料。

「资料更新」默认仅手动。学生也可以选择每次打开、每两天打开时，或明确允许约每两天后台检查一次。系统后台模式会向 iPadOS 登记刷新任务，最早执行时间从上次完整检查起算 48 小时。系统根据电量、网络和使用情况分配机会，打开 App 时会补查。后台模式需要持久设备会话。

检查时发送账号版本标记。版本一致时 Rust 服务返回 HTTP 304，正文为零字节。发现变化后，iPad 用一个请求取回所有发生变化的模块，每个模块均为一份完整记录。例如老师更正一条考勤，只传完整考勤。下载或解码失败时可继续读取上次成功保存的记录。旧版本服务可通过原有逐页接口更新。

终端按账号保存一个受系统文件保护的离线文件，并排除系统备份。校验成功且资料未变时，只写很小的检查时间记录。普通模式在设备解锁时访问凭据与数据。选择系统后台检查时，专用钥匙串凭据和本机离线文件允许在重启后首次解锁期间继续使用。仅本次登录的学校资料保存在内存。退出会清理本设备的学校资料并尝试撤销设备凭据；个人计划独立保存在本机，退出后不可见，同一资料账户重连后才能读取。

出勤率用保存的逐条考勤计算，「最近七天」按上海日期回溯六天，并显示这段时间内已缓存的起止日期。Day、下一节课、日程和列表分页都在 iPad 上生成。连接模式的 GPA 页优先显示校方公布值，否则只在已公布的课程成绩和校方确认的 GPA 学分、换算规则足够时自动显示加权估算；缺数据时明确提示，不默认等学分。「设置 → 成绩工具」的离线试算仍可调整假设分数与考核占比，不修改学期读数，也不请求下载成绩。

课程详情的折线可以点开、选择起止日期，并点图查看该日实际考核。待评分和仅有字母等级的结果保留在任务明细。考勤直接展示逐科四类次数、出勤率和分段条。两种图表都使用已保存的数据。

## 本机样例功能

- 原生 iPad 分组侧边栏，校园区只有「今日」和「计划」；GPA、任务、其余项目、考勤与设置保持独立。支持横竖屏和分屏。
- 各主页面顶栏统一显示今天的轮转 Day；没有已知 Day 时显示东莞当地日期。点它打开「计划」的今天。课前提醒仍可打开课程详情，日终快捷入口打开「计划」的明天。
- 「今日」只用一张卡显示状态倒计时、地点或提示、小标题和起止时间，不补写课堂备注。班会卡显示两个可能场所「Homeroom/Theater」和「Homeroom / School Assembly」，不猜当天实际地点；午餐是「Canteen / Lunch」，已确认的课间是「Enjoy! / Break」。午餐和课间的倒计时指向下一段实际教学（含班会），没有时显示该时段结束或进入空节。全天明细在「计划」查看。
- 本机课表和已连接账户都用同一条时间轴。拖动或用 VoiceOver 按 5 分钟调整时，课程卡与背景时刻同步，课程卡和轨道不随状态上下移动；回到当前时间不更改外观偏好。天气来源和更新状态在环境面板查看。
- 时间轴的指针平时只是一条窄玻璃线；按住轨道上的任意位置才展开显示时刻，拖动可继续查看。松手后指针收细，所选时刻仍保留在下方。无需瞄准细线。
- 时间轴上的蓝色表示各时段已经过去的部分，课程、班会、午餐和 Free Block 都随当前或所选时间更新。结束后全蓝，往回拖可回退，不写入任务或考勤状态。「今日」和「计划」共用同一组课程与校区活动时段；只有整段未排课的正式节次才是 Free Block。空节卡在教室号的位置显示蓝色「Enjoy!」，下一行是「Free Block」；顶部在开始前倒数到开始，开始后倒数到结束。
- 校区作息（东莞时间）：08:00–09:20 连堂，**09:30–10:10 班会**，10:10–10:50、11:00–11:40、11:50–12:30；**12:30–13:25 午餐**；13:25–14:05、14:15–14:55、15:05–15:45。09:20–09:30 是课间。校区活动不占选课名额；已发布课程优先，未知日、休校日和不覆盖活动的短日不补活动。只有前后时段都已知、且整段落在校区课间内的空档才显示 Break。
- 时间轴只有一条：块宽按时长，块与块之间等距。块内只显示居中的名称；地点仍可在上方卡片和「计划」查看。拖过真正的课间仍能选择课间时间；前后紧接的两项之间不虚构课间。精确时间继续由指针和读数显示。
- Day 与停课取自 2026–2027 主校区高中部（HS）[校历核对稿](../docs/verification/school-calendar-extraction-20261120.json)的运行版，覆盖 2026-08-01 至 2027-07-31。校历的印刷 Day 不等于本人上课；无公布的日期不自动补课。日期以东莞时间显示。本机及演示服务的科目和对应节次仍是已有样例，未从个人校宝账号导入。
- GPA：顶部和课程方块沿用「今日」的玻璃材质，标题在左、学期读数在右，眼睛只隐藏数值。本机模式可切换两个演示学期。点课程卡进入独立详情，只有详情内带子项的评估分组才可展开。关键词和评分状态只筛选课程卡，不改变 GPA；反馈与趋势仍可从详情查看。
- 课程详情把总评小卡和得分率预览并排，下方集中展示任务、权重与成绩；三个区域共用「今日」的玻璃材质，「课程总评」标注在数值下方。用「＋」可以录入临时预估；填了假设权重才参与预估总评，不改变已公布成绩或学期 GPA。待评分、未交、免交不会被当作 0 分。演示学期的 AP 加权选择与单独的试算表单只在「设置 → 成绩工具」。
- 考勤：本机用虚构课程的学期汇总展示状态筛选、逐科明细与日期选择。
- 上课、日常、活动三类考勤入口；演示未覆盖的范围和类型显示“尚未载入”，不会伪造逐次记录或显示假零值。
- 「我的任务」的玻璃卡片用右下角斜绶带表示学校状态，筛选和详情仍分别显示提交与批改。顶部可组合筛学期、课程、类型、模式、截止日期和标题。点任务查看内容、回答、成绩与点评（只显示有来源的资料）。当前学期可离线查看及筛选，往期连接资料服务后按选择读取。演示任务的本地完成不向学校提交。
- 「其余项目」在同一页切换考试、测评、资料库，三栏都用任务页样式的方块、课程筛选和搜索。点开各有自己的详情；保留状态及本机收藏。连接演示服务时按该账户的完整可用缓存筛选；仅有旧式分页时注明只筛本页。没有课程关联的资料进入「未分科」。工具栏的「校宝」按当前栏目打开既有网页入口。
- 「计划」竖屏按天、宽横屏按周，在学校课表上叠放个人色带。浏览不误拖；编辑时可长按划时段、点卡片编辑、长按提手移动。普通常用气泡拖出副本，重复提手改今后每周，可撤销／重做。日期月历标注主校区高中部公布的假期和特殊日；个人提醒仍只在本机。
- 东莞市级天气驱动的天空、季节光线、35 种离线手动预览和春节/中秋/圣诞/元旦氛围。
- 环境面板中的系统 `clear` / `regular` 玻璃材质选择。
- 原生设置持久化，尊重减少动态效果、减少透明度，后台暂停环境动画。
- `WKWebView` 校宝入口。App 内各栏目共享同一 WebKit 存储，持久化方式取决于原生的「在此 iPad 保持登录」选项。
- 各模块共用一个校宝网页会话。任务、动态成绩、日程、考勤和资料使用截图中确认的校宝路径，其余模块使用校宝导航。
- 提供系统通知授权、5 秒测试通知、未来 7 天的演示课前提醒和晨间 Day 提醒；演示课程通知可打开对应课程。

通知默认关闭，只有用户明确开启提醒或检查通知时才请求授权。个人计划通知与课前提醒分别调度；个人计划仍可使用自己的本机提醒，真实校宝课表暂不排课前／晨间提醒。测试通知只确认本机系统通知。通知头部由系统提供 TSchedule 名称和 App 图标。校宝站内信及新成绩推送仍未接入。

正在上课且当日课表已加载时，可在「今日」开启一次[锁屏课表](Sources/Native/LessonActivity/README.md)。首次展示可能需要在锁屏确认 iPadOS 的实时活动权限。左侧只显示距离下课的整分钟数（不足一分钟时显示 1 分钟，实际到点后不显示课程资料），右侧保留靠右的标题和大号下一节课名。长名称在锁屏省略，点回「今日」可看仍由当前账号加载确认的全名。活动不后台登录、不读取成绩，演示课表会标注来源。

## 个人设置

「设置」包含[外观、个人信息、实时活动、提醒和隐私](Sources/Native/Settings/README.md)，原有成绩工具仍在设置首页。

- 外观集中天气与全 App 图标。默认跟随系统，也可主动选择浅色或深色校园图标；普通系统通知的头图不能为某一条消息单独指定。
- 昵称仅在这台 iPad 的设置中显示，不影响校宝账号。校园登录和本机代登录仍在「个人信息 → 校园资料」。
- 实时活动的背景和下一节课小标题可用示例预览，保存后在下一次开启时生效。提醒的自定义副标题只用于本机个人计划及手动测试通知。
- 隐私说明可在 App 内阅读。[发布用隐私页面](../docs/tschedule-app-store/04-web/privacy/index.html)仍是草稿，公开网址和联系信息需要在提交前确认。

## 本机样例的数据来源

仅选择本机演示时，首页和课表来自 `DemoSchoolProvider`，成绩来自 `Gradebook.demo`，「其余项目」来自 `StudentServices`。本机随堂测验的起止时间和教室直接取对应课程节次，「计划」与「其余项目 → 考试」读取同一条测验；停课没有对应节次时不生成测验。学生页面显示课程、状态和时间，不为每条内容加开发标签。「设置 → 个人信息 → 校园资料」明确说明记录为虚构，演示资料不混入真实校宝会话。本地完成、GPA 试算和缺失的数据仍在操作处说明。

本机考勤采用合成的课程汇总，仅用于展示界面和缺失数据行为。它没有真实学生记录或逐次考勤日期、节次及原因。“本学期”采用演示区间；“日常”“活动”和其他日期范围均未载入。数据模型用 `nil` 表示逐次数据不可用，用空数组表示已确认没有记录，避免混淆。

本机考勤保留两排筛选玻璃外框。第一排为两组 iPadOS 原生分段控件：三个类型等宽，快捷时段紧接在右侧；圆角、选中效果和交互由系统提供，不另加主题色。第二排仍用系统日期控件，手动改日期后快捷时段回到原生未选中状态。空间不足时按组换行，不压缩文字。汇总和课程明细并排时等高，上下排列时同宽；汇总卡宽度足够时，圆环在左、状态按钮在右，窄到放不下或使用辅助字号才上下排。圆环中心读出勤率，点每段可读对应状态比例；状态按钮仍筛选课程。内置和已连接账号直接显示同一套逐科表，四类次数和出勤率用文字显示，分段条仅表示该课记录的构成；空记录或无效汇总没有分段条。

| 页面 | 原生原型内容 | 真实数据接入状态 |
| --- | --- | --- |
| GPA / 动态成绩 | GPA、课程总评、分类明细、权重与反馈 | 本人会话：公布的课程总评、学期 GPA 和按需课程明细；校宝缺项不作推算 |
| 我的考勤 | 汇总、状态筛选、日期与类型筛选、课程详情 | 演示汇总；真实记录待接入 |
| 我的任务 | 学期与课程等筛选、状态绶带、回答、成绩、点评、本地完成 | 本人会话：本学期任务列表、截止时间和来源状态；正式提交和附件在校宝完成 |
| 其余项目 → 考试 | 时间、考场、范围、详情 | 演示；正式安排在校宝查看 |
| 其余项目 → 测评 | 待办与完成列表、详情 | 演示；问卷填写与提交在校宝完成 |
| 其余项目 → 资料库 | 示例内容预览、搜索、收藏 | 演示；真实文件待接入 |
| 计划（校宝网页版为「我的日程」） | 独立课表层、个人层；常用气泡、每周安排、个人提醒 | 本人会话：按所选周读取课程与校历事件。个人记录与提醒仍只在此设备，不写入学校 |
| 完整校宝 | 原网站登录和导航 | 实际网站入口，登录和流程尚未经真机验证 |

本地完成状态和收藏仅写入本 App 的偏好存储，不修改学校数据。原型中没有作业上传或测评提交接口。

天气数据来自 [Open-Meteo](https://open-meteo.com/) 的当前模型估算，并非校园气象站实测或官方预警。[城市天气模块](Sources/Core/CityWeather/README.md) 说明刷新、缓存、编码映射及非商业原型的使用边界。节日日期使用系统公历/农历计算；节日装饰不修改学校课表。校历中的休校日需要由真实学校日历提供。

原生试算按假设分数和权重预估，不等同于 [Giaoculator S 的成绩功能](https://github.com/Haoxuan1016/GiaoculatorS#score-calculations-and-predictions)。任务详情只接受校方明确提供给当前学生的预估，不推导未发布分数。当前演示服务并未提供预估或确认的 GPA 规则字段，真实模式另读校宝向本人展示的成绩；本机示例的 GPA 规则不是学校的正式算法。

登录有效期由校宝决定。默认使用系统网页会话，不保存密码。学生首次用学校网页登录后，可在「设置 → 个人信息 → 校园资料 → 本机代登录」单独选择「保存并开启」。密码仅存这台设有锁屏密码的个人 iPad 的系统钥匙串，不同步 iCloud、不经开发者服务器；以后只有主动打开或刷新 GPA 且需要重新登录时才使用。密码错误不连试；需要验证码或额外确认时由本人继续。可在同处移除，退出账号也会撤销。见[前台代登录模块](Sources/Native/SchoolPortalLogin/README.md)。

## 验证情况

用 Swift 优化编译测量 2027 年 3 月 29 日至 5 月 9 日的 42 天离线日程。每个上课日六节，含一个工作日停课。Linux 本机新旧版本各测 27 次，中位耗时从 17.88 ms 降到 1.84 ms，174 节课的标识和起止时间一致。普通资料刷新期间授权读取成绩，两者复用已校验的版本清单。若服务端报告版本冲突，客户端会重新校验。

Linux Swift 6.2 已通过 49 项 XCTest，包括 Swift 客户端与 Rust 服务的真实 HTTP 联调。测试覆盖九类资料的首次和按模块同步、考勤更正及下载中断、离线试算、手动授权、前台检查与 48 小时间隔、旧成绩缓存迁移、缓存先显示、有效期内零请求、304 空正文、断网、合并重复请求、静默续期、注销和切换账号后的延迟回包。设置环境变量 `XIAOBAO_TEST_ORIGIN` 为正在运行的演示服务地址，会一起执行 HTTP 联调测试。

真机签名、校宝网页登入及 iPhone 版不在天气预览包的验证范围内。

在 Mac 上运行完整检查：

```sh
./scripts/check.sh
```

只运行跨平台核心逻辑测试：

```sh
swift test
```

## 代码位置

| 路径 | 内容 |
| --- | --- |
| `Sources/Native/XiaobaoApp.swift` | App 入口、分组侧边栏、页面容器 |
| `Sources/Native/GlassComponents.swift` | `.glassEffect()` 及可访问性回退 |
| `Sources/Native/TodayView.swift` | 今日页、原生玻璃时间透镜 |
| `Sources/Core/TimelineTrackLayout.swift` | 同一组区段驱动块宽、指针位置和拖动选时，可用 SwiftPM 单测 |
| `Sources/Core/TimetableWeek.swift` | 计划周视图与每周重复项共用的周日到周六日期边界；保留旧版周排版的回归测试 |
| `Sources/Native/GPA/` | [GPA 页](Sources/Native/GPA/README.md)、课程任务表、放大趋势和预估编辑 |
| `Sources/Core/GPA/` | [GPA 数据投影与课程预估](Sources/Core/GPA/README.md)，保留公布值、权重范围和缺失状态 |
| `Sources/Native/GradebookView.swift`、`Sources/Native/GradesView.swift` | 本机学期选择；设置中的加权选择与本机／已保存成绩试算 |
| `Sources/Native/AttendanceView.swift`、`Sources/Native/AttendanceRing.swift` | 内置考勤筛选和课程详情；可点选的状态圆环只读当前汇总 |
| `Sources/Native/StudentChartsView.swift`、`Sources/Core/StudentCharts.swift` | 共享逐科考勤表、状态构成和 GPA 趋势；`StudentChartTests` 核对分段、命中、逐科分母和缺失记录 |
| `Sources/Native/StudentServicesView.swift` | 其余项目的分段入口；计划页继续使用原有本机考试详情 |
| `Sources/Native/OtherItems/`、`Sources/Core/OtherItemsCatalog.swift` | [其余项目](Sources/Native/OtherItems/README.md)的方块、课程筛选和三类详情 |
| `Sources/Native/Tasks/`、`Sources/Core/Tasks/` | [我的任务](Sources/Native/Tasks/README.md)的筛选、卡片、详情和只读数据投影 |
| `Sources/Native/Planner/` | [计划页](Sources/Native/Planner/README.md)、时间线与编辑表单 |
| `Sources/Core/Planner/` | [计划规则](Sources/Core/Planner/README.md)、学校时间表投影与受保护本机保存 |
| `Sources/Native/Atmosphere/` | Metal 体积天空、粒子、能见度与渲染生命周期 |
| `Sources/Core/Atmosphere/` | 天气分类、强度和季节光线计算 |
| `Sources/Core/CityWeather/` | 公共城市天气读取、缓存时效、前台刷新和手动优先级 |
| `Sources/Native/SchoolPortal.swift` | WKWebView 与网站会话管理 |
| `Sources/Native/Settings/`、`Sources/Core/Personalization/` | [原生设置](Sources/Native/Settings/README.md)、[本机显示偏好](Sources/Core/Personalization/README.md) |
| `Sources/Native/ReminderService.swift` | 系统通知授权、课程和个人计划的独立调度、课程跳转 |
| `Sources/Core` | 校历、成绩明细、考勤、学习事项、GPA、节日与提醒规划 |
| `Tests/Core` | 业务边界测试 |

新增 Swift 或 Metal 文件后执行 `python3 scripts/generate_project.py`，或者在 Xcode 中将新文件加入 Xiaobao Target。生成器只重建工程文件，不修改业务代码；若已经在 Xcode 中修改了签名 Team，重新生成后需再次选择。

原生玻璃使用 Apple 的公开 API：[Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)、[Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)。参考项目：[GiaoculatorS](https://github.com/Haoxuan1016/GiaoculatorS)。未复制该插件源码，也未宣称已经兼容其全部功能。

## Change History
### 2026-11-21 — 整分钟锁屏课表与个人设置
Model: Codex (GPT-6.2-sol) · Keywords: whole-minute-clock / settings-subpages / local-privacy  
Changed: 锁屏去掉结束钟点和秒数、设置独立归类、新增本机显示偏好和共享实时活动预览；个人计划与本机测试通知可附副标题。Reason: 让倒计时与本机选择容易辨读，不重复系统时钟，也不扩大学校访问。Affected interfaces: 原生表单、可选活动样式、个人提醒文案及两款替代图标；学校会话、后端、数据库、环境变量和部署不变。
Verification: 203 项 Swift 测试（含隔离的 Rust 演示联调）、24 项 JavaScript 测试、WebKit 回归和 Release 编译（模拟器及无签名 iPad）通过。iPadOS 27 模拟器的[系统锁屏卡片](../docs/verification/student-interface/lesson-activity-minutes.png)实际从 12 跳到 11 分钟，可返回当前已验证课表查看全名。[设置首页](../docs/verification/student-interface/settings-overview.jpg)的五个入口、[实时活动预览](../docs/verification/student-interface/settings-activity-preview.jpg)、个性化偏好重启保留和大字体竖屏通过；未读取成绩、未提交密码。未验证真机通知横幅送达。

### 2026-11-21 — 锁屏课表实时活动
Model: Codex (GPT-6.2-sol) · Keywords: class-end / next-course / live-activity  
Changed: 从「今日」前台手动开启，锁屏左侧是下课时间，右侧是下一节课程名；使用已有浅深校园图标。Reason: 不解锁也能确认当前节结束及接下来的课程。Affected interfaces: 一个本地 WidgetKit 扩展、一条无参数的返回路径和本机状态；不加推送、服务器、数据库或环境变量。
Verification: 200 项 Swift 测试（含本地演示服务）与 24 项 JS 测试通过。用 iPadOS 27 和合成课表验证系统卡片的分栏、倒计时、长课名和返回「今日」对准下一节。初次系统只显示空壳；锁屏渲染器可读到内容，但计时文本请求了无界宽度。改用有限计时列后，系统实际绘制两列且无障碍边界恢复正常。[合成课表实拍](../docs/verification/student-interface/lesson-activity-lockscreen.png)。未用真实学生账号或实体 iPad 测试。
### 2026-11-21 — 图标浅深外观与本机通知
Model: Codex (GPT-6.2-sol) · Keywords: paired-campus-art / notification-system-icon  
Changed: 默认系统图标和侧栏使用新浅色图，深色使用原深蓝图；通知检查不再自称校宝。Reason: 系统可以根据外观选择同一品牌，而不是手动设置替代图标。Affected interfaces: 现有资源名的外观变体与两处文案；不增加权限、调度或后端。
Verification: Release 模拟器构建、197 项 Swift 测试与图标资产清单检查通过。在 iPadOS 27 同一运行中的测试界面切换系统外观，浅、深各自显示正确图标；Release 资产目录包含两组外观。iPadOS 27 本机提醒测试没有观察到横幅，iPadOS 26.4 未能启动 UI 测试运行器，实际送达仍需真机对照。
### 2026-11-21 — TSchedule 侧栏与 App 图标
Model: Codex · Keywords: sidebar-brand / campus-app-icon  
Changed: 侧栏顶部显示校园图标和 TSchedule，主屏幕用同一图标和名称；图案见[资源说明](../docs/tschedule-icon/README.md)。Reason: 用产品身份标记导航，而不是用学校数据源的名称。Affected interfaces: 应用显示名及两个资源名；工程、bundle ID、本机登录与数据均不迁移。
### 2026-11-21 — 原生考勤、刷新 GPA、设置归组
Model: Codex · Keywords: native-attendance / grade-refresh / settings-disclosure  
Changed: 校宝模式在 App 内读取所选时段的考勤和课程明细；GPA 进入即读，按钮只刷新。设置先显示账号和本机登录，其次是天气、成绩工具和实际可用的提醒。Reason: 避免重复打开网页或误解为重复授权。Affected interfaces: 设备内只读桥接和原生页面；不改变后端、密码用途、数据库或部署。

### 2026-11-21 · 本机前台代登录
Model: Codex · Keywords: student-opt-in / foreground-password-login  
Changed: 区分保持续期与全失效后的新登录；学生可为已核验的本人账号单独开启仅本机的钥匙串保管，前台在校宝正常登录后再读取新成绩。Reason: 旧会话被撤销时也能尝试正常登录，而不是不断打开首页。Affected interfaces: 真实校宝 GPA、设置、退出和 WebKit 登录模块。演示服务、数据库、HTTP API、环境变量和部署不变。

### 2026-11-21 · 前台成绩读取和会话恢复
Model: Codex · Keywords: foreground-grade-entry / confirmed-expiry  
Changed: 区分加载、拒绝访问与登录过期；真实校宝成绩改为进入 GPA 时读取，明确过期后由原会话尝试一次，不提交密码。恢复后必须是同一人并重新读取成绩。Reason: 校宝资料读取失败不等于需要重新登录。Affected interfaces: 原生会话、GPA 入口和设备内读取结果。无后台任务、服务端、数据库、环境变量或部署改动。见[验证步骤](Tests/SchoolPortalSync/README.md)。

### 2026-11-21 — 侧栏切换保留天空
Model: Codex · Keywords: sidebar-sky / navigation-scope  
Changed: 切换侧栏不重建右侧的天气画布；推入详情会暂停被遮住的主天空，返回时继续。Reason: 旧版每次切栏都要等待一张新画布的首帧。账号、会话或资料权限边界变化时仍重建受保护的导航。Affected interfaces: 原生页面容器和天气背景的可选遮挡状态；不改校宝读取、数据库、环境变量或部署。

### 2026-11-21 — 任务卡已公布成绩
Model: Codex · Keywords: schoolis-task-score / grade-consent  
Changed: 修正真实任务只显示批改状态、不传递已公布成绩的问题。沿用「GPA」授权和现有卡片。Affected interfaces: 仅设备内任务读取参数与数据映射；无新接口、数据库或环境变量变更。

### 2026-11-21 — 校宝本人资料
Model: Codex · Keywords: schoolis-webkit / scoped-student-reads  
Changed: 学校 WebKit 会话接入今日、计划、GPA 和任务，设置区分真实与演示，未接入栏目提供原网页。  
Reason: 真实登录不能套用演示服务凭据，未读到数据也不能回填样例。  
Affected interfaces: 仅原生会话、读操作及页面取数；无新数据库、环境变量、对外 API、依赖或部署。


### 2026-11-20 — 考勤切换改用系统分段控件
Model: Codex · Keywords: attendance / native-segmented-control / no-selection  
Changed: 类型和快捷时段均采用 `UISegmentedControl`，不再自绘底、圆角或选中背景；保留等宽类型、相邻的快捷时段、玻璃外框和第二排系统日期。  
Reason: 让 iPadOS 自己管理分段选择的材质、动效和无障碍表现，并保留自定义日期的未选中状态。  
Affected interfaces: 仅本机考勤筛选；不改数据、筛选规则、服务接口、数据库、依赖、环境变量或部署。  
Verification: 模拟器构建通过，iPadOS 27 横、竖屏的 2 项界面测试通过：核对了系统分段控件、类型等宽、快捷时段紧邻、日期独占第二排，以及切换筛选、手动日期取消选中和恢复预设。[竖屏实拍（局部）](../docs/verification/student-interface/attendance-native-segments.jpg)

### 2026-11-20 — 日程入口与统一 Day
Model: Codex · Keywords: retire-standalone-timetable / today-day-shortcut / planner-date-route  
Changed: 校园区保留「今日」和「计划」。主页面顶栏共用当天轮转日／日期按钮，打开「计划」的今天；日终打开明天，课前提醒仍保留课程详情。独立课表的两套视图退出构建，原文件移入按日归档；「计划」继续使用原日／周画面、课程和校历。  
Reason: 消除两个日程浏览页面和不同外观的日期入口。  
Affected interfaces: 仅原生导航，移除 `AppTab.schedule`，各日期入口使用 `AppModel.openPlanner(on:)`。课表缓存、存储、权限、HTTP、依赖和部署无变化。  
Verification: 原生模拟器构建和 44 项计划／周历核心测试通过。iPadOS 27 横屏界面测试验证各主页面日期一致、旧侧栏入口消失、查看明天与翻周后可点 Day 回到今天；通知仍复用原详情查找，未在真机触发。[点 Day 后的计划实拍](../docs/verification/student-interface/planner-today-day-shortcut.png)

### 2026-11-20 — 考勤类型留白与中性分段控件
Model: Codex · Keywords: attendance / category-spacing / adjacent-periods / neutral-segmented-glass  
Changed: 类型使用等宽的低圆角分段，给每项预留左右空白；快捷时段紧接考勤类型，共用一个无色玻璃底。两组用中性背景和较重字重标记选中项，保留玻璃外框和第二行的原生日期控件。  
Reason: 分清类型选项、缩短两组选择器之间的距离、减少多层玻璃高光；空间不足时不压缩标签。  
Affected interfaces: 仅本机考勤的筛选外观和布局；不改筛选规则、考勤数据、接口、数据库、环境变量或部署。
Verification: 考勤页通过 iPadOS SDK 定向类型检查。全项目类型检查在课表页引用 `AppModel.selectedDate` 处报错；磁盘空间不足，未复跑最终样式的模拟器界面测试。

### 2026-11-20 — 今日时间轴单行名称
Model: Codex · Keywords: today-timeline / centered-course-name  
Changed: 时间轴课程块只显示居中的简短课名，不随可用宽度显示教室。上方课程卡、课表及课程详情仍保留地点。  
Reason: 时间轴适合扫读当天顺序，无需在每块重复地点。  
Affected interfaces: 仅共享「今日」时间轴的显示；时段宽度、进度、拖动、VoiceOver、数据和服务接口均不变。
Verification: iPadOS 模拟器构建通过；11 英寸 iPad Air（iPadOS 27）横屏运行确认课程、班会、午餐与空节均保留单行名称。[时间轴实拍（局部）](../docs/verification/student-interface/today-timeline-titles-only.png)

### 2026-11-20 — 竖屏考勤汇总与两排筛选
Model: Codex · Keywords: portrait-attendance / aligned-card-width / two-row-filters  
Changed: 竖屏等上下排布时，汇总和明细使用同一宽度；汇总内容优先左图右状态。玻璃外框内把类型与快捷时段分在首排的两边，起止日期独占次排；极窄或大字号保留换行。  
Reason: 对齐两张卡的边缘，不让日期加入首排、挤压类型和快捷按钮。  
Affected interfaces: 仅本机考勤布局；不改圆环点选、筛选规则、考勤数据、服务、数据库或部署。
Verification: iPadOS SDK Swift 类型检查与 2 项 iPadOS 27 模拟器测试通过。横屏验证较长日期仍在第二排；竖屏验证卡片对齐、左图右状态、圆环气泡和状态筛选。[竖屏实拍](../docs/verification/student-interface/attendance-portrait-two-rows.jpg)

### 2026-11-20 — 单排玻璃考勤筛选
Model: Codex · Keywords: attendance-filter-row / native-glass / date-compact  
Changed: 保留原生玻璃外框，把类型、时段和起止日期排进一条随可用宽度换行的工具栏，并在外框里为各控件设置独立玻璃，避免跟外框融成一块。  
Reason: 横屏不用用三行容纳一行放得下的筛选；窄窗仍保留完整文字和系统日期选择。  
Affected interfaces: 仅本机考勤的筛选外观和布局，不改筛选规则、考勤数据、接口、数据库或部署。
Verification: Release 模拟器构建、2 项 iPadOS 27 界面测试通过。11 英寸 iPad 横屏展开侧栏时，本学期及两个两位数日期的本周仍为一排；竖屏两日期一起换行。类型、快捷时段和系统日历都已点验。[横屏实拍](../docs/verification/student-interface/attendance-filter-glass-frame.jpg)

### 2026-11-20 — 考勤两卡等高与逐科构成
Model: Codex · Keywords: attendance-aligned-panels / course-composition / direct-table  
Changed: 内置页面的并排汇总和详情按自然高度等高，去掉重复计数、小字说明、课程搜索和对比开关。内置与连接资料共用逐科表，使用较厚、低亮度的四状态堆叠条，课程导航保持原有权限与入口。  
Reason: 一次看清完整课程记录，不必切换对比模式，也不把相对于最大缺勤次数的条长误读为各科比例。  
Affected interfaces: 原生展示及内部逐科汇总投影；未改统计口径、连接范围、HTTP API、数据库、环境变量或部署。
Verification: Release 模拟器构建、159 项 Swift 核心测试（含演示服务 HTTP 联调）与 3 项 iPadOS 27 界面测试通过。横屏全部课程及按状态筛选后，两张卡的上下边都对齐；另验证竖屏辅助字号、课程详情入口及已连接资料的只读表和缓存范围。[横屏实拍](../docs/verification/student-interface/attendance-aligned-course-composition.jpg)

### 2026-11-20 — 考勤汇总卡片比例
Model: Codex · Keywords: attendance-summary-square / status-grid  
Changed: 汇总卡片宽度上限为 408 pt，圆角收小，四个状态在常规宽度与字号下排成两行；窄窗和辅助字号可自然向下展开。  
Reason: 并排时不用细长的卡片，叠放时也不用整行宽度来装一个圆环。  
Affected interfaces: 仅内置考勤汇总的布局，不改圆环点选、筛选、逐科对比、颜色、数据或 API。
Verification: Release 模拟器构建通过；iPadOS 27 模拟器检查横竖屏的卡片比例、点选气泡和状态筛选，以及辅助字号下可滚动访问的单列按钮。[横屏实拍](../docs/verification/student-interface/attendance-square-summary.jpg)

### 2026-11-20 — 其余项目
Model: Codex · Keywords: other-items / segmented-navigation / student-services  
Changed: 用一个「其余项目」侧栏入口和页内分段替代三个入口。列表共用一块玻璃底；本机的标题／科目搜索、考试和测评状态筛选、详情及资料收藏仍可使用。连接演示服务时继续读取各栏目原缓存和分页。  
Reason: 减少三个低频入口对侧栏的占用，不删记录或操作。  
Affected interfaces: 原生 `AppTab.otherItems`、`OtherItemsSection`；「校宝」按钮仍传当前分类原有的门户栏目名。没有新增目录模块、HTTP API、存储键、数据库或环境变量。  
Verification: 158 项 Swift 核心测试通过（含本机 Rust HTTP 联调）。iPadOS 27 模拟器验证本机三栏切换、考试与测评详情、搜索筛选、资料预览与收藏，以及连接演示服务后的栏目和展开内容。对照定稿核对侧栏、分段和列表排版，并复测夜间提示文字和搜索输入：[横屏考试](../docs/verification/student-interface/other-items-exam-landscape.png) · [竖屏资料库](../docs/verification/student-interface/other-items-library-portrait.png)。未在真实学校账号或真机上测试。

### 2026-11-20 — 考勤圆环与对比条
Model: Codex · Keywords: attendance-glass / ring-callout / course-comparison  
Changed: 移除内置考勤页的重复页头，筛选沿用任务页的紧凑尺寸。用同一分段计算来绘制原生玻璃圆环、命中区段和显示占比。内置及连接资料的逐科对比改用只读玻璃质感条。  
Reason: 首屏直接进入可用条件和结果；各状态的比例可当场看，不必筛选课程或换页。  
Affected interfaces: 仅原生考勤展示和内部图表投影。未改任务页、课程详情、统计口径、账户连接、API、数据库、环境变量或部署。  
Verification: iPad 模拟器 Debug/Release 构建与 157 项 Swift 核心测试通过，含本机演示服务 HTTP 联调。在 iPad Air 11 英寸（iPadOS 27 模拟器）复测了四段连续点选、气泡开合不移动焦点、窄栏及横竖切换、原有课程筛选，以及连接演示资料时的对比/明细切换。演示数据实拍：[圆环与窄栏气泡](../docs/verification/student-interface/attendance-ring-callout.jpg) · [连接资料的玻璃对比条](../docs/verification/student-interface/attendance-comparison-glass.jpg)。

### 2026-11-20 — 本机演示测验与课表对齐
Model: Codex · Keywords: demo-work / in-class-exam / timetable-source  
Changed: `AppModel` 和 `StudentServices` 使用同一份本机演示课表。已有测验保留标识与日期，时间及教室从该课程的节次取得；计划页只显示一次同一节的安排。  
Reason: 两套分别写时刻的演示数据会产生虚假撞课。  
Affected interfaces: 本机样例及计划学校记录的投影；不改变正式校历、连接资料账户、HTTP、数据库、环境变量或个人计划。参见[计划核心验证](Sources/Core/Planner/README.md#change-history)。
Verification: 签名模拟器 Release 构建和 152 项 Swift 测试通过（含本地 Rust HTTP）。核对预览包内校历与仓库资源一致，并在 iPadOS 27 横屏「计划」确认 11 月 19 日的原课程恢复完整宽度，随堂测验只出现于对应节次。

### 2026-11-20 — 横屏周课表的清透时间带
Model: Codex · Keywords: week-timetable / campus-activity-bands / column-width  
Changed: 仅更新原生横屏周表的阅读层级、选择指示、表面和时间参考线。同一个布局把已确认的休课日期收窄，并合并相邻日期内容相同的停课通知或时间完全一致的班会和午餐。  
Reason: 减少重复标签和表格线，把空间留给 Day、课名和教室。周末补课、资料缺失、时段冲突和真实时长不受视觉合并影响。  
Affected interfaces: `WeekTimetableLayout(days:)` 仅供原生周表使用；视图入口、日期跳转、课程详情、竖屏、今日、天气以及 Rust API、数据库、环境变量和依赖均不变。
Verification: Release 模拟器构建通过；142 项 Swift 测试通过（含本机 Swift ↔ Rust HTTP）。iPad Air 11 英寸模拟器分别实测本机翻周、连堂比例、合并通知、课程详情和转回竖屏，以及连接资料服务后的同一布局。[白昼](../docs/verification/student-interface/hs-week-bands-daylight.jpg) · [夜间](../docs/verification/student-interface/hs-week-bands-night.jpg) · [连接资料服务](../docs/verification/student-interface/hs-week-bands-connected.jpg)。

### 2026-11-20 — 我的任务
Model: Codex · Keywords: tasks-glass-grid / grading-badge / task-term-history  
Changed: 新增任务页和任务数据投影，支持顶部组合筛选、学期选择、批改角标，以及可点击的任务详情。  
Reason: 提交与批改分别可查，点开单个任务才看回答和点评。  
Affected interfaces: 只调整「我的任务」及已有任务读取响应的可选字段，不加新路由、数据库表、环境变量或依赖。参见 [任务模块和验证](Sources/Native/Tasks/README.md#change-history)。

### 2026-11-20 — 高中部校历与横屏周课表
Model: GPT-6.2-Sol · Keywords: hs-calendar / timetable-week / unchanged-portrait  
Changed: 从一份已复核的 HS 资源读取 Day 和停课。宽横屏使用同一套七列时间格；连接账号只投影所选一周的缓存。竖屏仍使用单日布局，「今日」只换日号的数据来源。  
Reason: 周课表服务计划日期，而不是重复下一项；重复 Day、学期重置与分学部停课需要按日期读取。  
Affected interfaces: 原生内部周表与日期投影；现有 Rust 日课表附带可选 `calendar_day`、离线课表附带可选 `school_calendar`。无新路由、数据库、环境变量、目录或部署。
Verification: 120 项 Swift、36 项 Rust、2 项 iPad 界面测试通过。已实测本机、连接服务、翻周、停课、卡片高度、课程详情及转回竖屏：[本周横屏](../docs/verification/student-interface/hs-week-timetable.jpg) · [连接服务后的下一周](../docs/verification/student-interface/hs-week-connected-next.jpg) · [冬假周](../docs/verification/student-interface/hs-week-winter-break.jpg) · [竖屏](../docs/verification/student-interface/hs-timetable-portrait.jpg)。共享数据副本与已安装模拟器 Release 包逐字节核对。

### 2026-11-20 — 课程成绩详情
Model: Codex · Keywords: course-workspace / history-range / assessment-forecast  
Changed: 总评小卡与实际走势并排，下方集中为一张可展开分组的任务表。走势可放大和选日期，预估任务可临时添加、编辑或移除。  
Reason: 先看结果，再按需查历次表现或做单科试算，不另堆整宽面板。  
Affected interfaces: 原生课程详情和客户端可选成绩字段；学期 GPA、学校网页入口、HTTP、数据库、依赖、环境变量与部署不变。参见 [GPA 模块与验证](Sources/Native/GPA/README.md#change-history)。

### 2026-11-20 — GPA 玻璃首页
Model: Codex · Keywords: gpa-glass / stacked-heading / course-tiles  
Changed: 复用「今日」的卡片材质，GPA 标题和读数分左右，课程总评放入独立的圆角方块。眼睛保留隐藏功能和触控范围。  
Reason: 统一「今日」和 GPA 首页的视觉，同时不改变进详情后的分组行为。  
Affected interfaces: 仅 GPA 首页显示；课程详情、数据接口、存储及环境变量不变。参见 [GPA 模块与模拟器验证](Sources/Native/GPA/README.md#change-history)。

### 2026-11-20 — 计划页直接拖放
Model: Codex · Keywords: planner / direct-placement / inline-capture / glass-timetable  
Changed: 用现有玻璃材质和固定的「待安排」录入区取代白色列表与新增表单。新计划可直接拖入课表；已排计划可改位置或拖回，点选时间轴也能安排。拖过边缘不滚动，停留才自动滚动。  
Reason: 排计划时仍看得到学校时间表，松手前就知道会排到几点。  
Affected interfaces: 仅原生计划页面与内部落点计算。不改「今日」「课表」、存储档案格式、HTTP、数据库、依赖、环境变量或部署。
Verification: 109 项 Swift 测试通过（含 Rust HTTP 联调）。iPad Air 11 英寸（iPadOS 27.0）在独立的本机演示环境验证录入、空节吸附、保留时长、放开到轴外、拖回、点选、横屏边缘滚动和重开后保留；[界面实拍](../docs/verification/student-interface/planner-drag-timetable.png)使用合成事项。独立验证工程的模拟器 Release 构建通过；同一时段主工作区的周课表编辑尚有 Swift 编译错误，不计为整工程通过。

### 2026-11-20 — GPA 与课程详情
Model: Codex · Keywords: gpa-overview / assessment-disclosure / grade-metadata-backfill  
Changed: 统一两种原生成绩入口；显式区分公布 GPA、试算和缺失。课程总评不折叠，课程详情内按来源显示分组、单项权重和反馈。旧离线缓存继续可读，第一次已授权检查补取此前未解码的可选字段。  
Reason: 先读学期结果，再按需看课程及考核构成；不猜学校权重。  
Affected interfaces: 原生 GPA 页面、可选成绩字段的客户端缓存；校宝网页入口、HTTP、数据库、依赖、环境变量和部署不变。
Verification: 109 项 Swift 测试（含 Rust HTTP 联调）和 Xcode 构建通过；iPadOS 27 模拟器完成三项交互验证。参见 [GPA 模块和实拍](Sources/Native/GPA/README.md#change-history)。

### 2026-11-20 — 计划
Model: Codex · Keywords: planner / timetable-merge / local-plan-storage  
Changed: 原「我的日程」改为「计划」，复用原有学校资料，在同一条时间线上添加个人计划；空节预填，未定时间单独显示。  
Reason: 让固定学校安排与个人待办可以一起看，又不混淆学校状态和个人完成。  
Affected interfaces: 原生计划页与本机计划存储；`SchoolWorkDetailView` 可关闭本地完成入口，其他页面使用原默认值。无 HTTP、数据库、环境变量、部署或依赖改动。  
Verification: 98 项 Swift 测试（含 Rust 演示服务 HTTP）和签名后的 Release 模拟器构建通过。iPad Air 11 英寸（iPadOS 27.0）实测空节预填、未定时计划、编辑、勾选与取消、切日、重开，以及演示服务不可用时继续读缓存并保存个人计划；切换两个演示账户并重新登录，计划只回到原账户。[界面实拍](../docs/verification/student-interface/planner-timeline.png)使用独立合成事项。

### 2026-11-20 — 午餐地点英文名称
Model: GPT-6.2-Sol · Keywords: canteen / lunch-card  
Changed: 午餐卡的大标题改为「Canteen」，保留「Lunch」小标题、中文倒计时和原时段。  
Reason: 与其他卡片的地点或大标题统一。  
Affected interfaces: 仅原生文案；排课、服务接口和存储不变。  
Verification: 模拟器 Release 构建通过，iPad 实测午餐显示「Canteen / Lunch」，倒计时和起止时间不变。[实拍](../docs/verification/student-interface/today-card-canteen.jpg)

### 2026-11-20 — 班会、午餐和课间卡片
Model: GPT-6.2-Sol · Keywords: campus-activity-card / recess / instruction-countdown  
Changed: 班会和午餐复用课程卡的四行布局；拖到已确认的课间会切换为 Break。午餐和课间显示距离下一段教学的时间，保留与 Free Block 的区别。  
Reason: 统一卡片信息顺序，同时不把未排课的时间当成实际上课。  
Affected interfaces: 原生内部 `LessonTimeline.recess(at:)`、`nextInstructionStart(from:)`；没有新增模块、轨道块、API、排课记录、环境变量或存储变更。  
Verification: 89 项 Swift 测试（含本机 Rust HTTP）和 3 项 iPad 界面测试通过。横竖屏和连接服务时均验证了课间、班会、午餐和空节交接以及原时间轴位置；长地点缩放时倒计时、小标题和时间仍在同一高度。实拍：[班会](../docs/verification/student-interface/today-card-assembly.jpg) · [午餐](../docs/verification/student-interface/today-card-lunch.jpg) · [课间](../docs/verification/student-interface/today-card-break.jpg)

### 2026-11-20 — 班会名称与空节卡片
Model: Codex · Keywords: assembly-label / free-block-card / countdown  
Changed: 时间轴（包括窄屏）、今日卡片、完整课表和 VoiceOver 统一使用「班会」。空节沿用课程的状态、主标题、副标题和时间四行布局；无课程详情按钮。  
Reason: 去掉同一时段的不同称呼，用明确的倒计时区分即将开始和进行中的空节。  
Affected interfaces: 仅原生显示；时段、进度、服务接口和存储不变。  
Verification: 86 项 Swift 测试（含本机 Rust HTTP）和 3 项 iPad 界面测试通过。本机课表横、竖屏和连接账户都实测了空节前、刚开始、进行中、结束和回拖；卡片行位置不跳动。[开始前](../docs/verification/student-interface/free-block-card-upcoming.jpg) · [进行中](../docs/verification/student-interface/free-block-card-active.jpg)

### 2026-11-20 — 班会/校会、等距分隔与时间进度
Model: Codex · Keywords: assembly / uniform-separators / elapsed-blocks  
Changed: 本机、服务账户及离线课表均按已确认的校区活动投影。将原先只用于课程的蓝色进度移到所有时段共用的绘制路径；轨道使用同一组坐标绘制并接收手势，未加第二把刻度尺。  
Reason: 旧版的午餐和 Freeblock 即使结束也总是灰色，真实课间与紧接课程的布局间距也不同。  
Affected interfaces: 原生内部 `LessonTimeline.Block` 及 `TimelineTrackLayout`，Swift `Agenda.Status` 增加 `assembly`；无 HTTP 契约、数据库、环境变量、通知或个人排课变更。  
Verification: 85 项 Swift 核心测试（含本机 Rust HTTP 联调）、35 项 Rust 测试和 3 项 iPad 模拟器界面测试通过。实际拖动核对班会、午餐、Freeblock、放学和回拖；横竖屏与连接账户截图中，八处分隔均为 6 pt。模拟器截图：[09:50 班会进行中](../docs/verification/student-interface/assembly-in-progress.jpg) · 15:25 午餐已过、空节过半（[竖屏](../docs/verification/student-interface/activities-elapsed.png) / [横屏](../docs/verification/student-interface/activities-elapsed-landscape.png)）。

### 2026-11-19 — 连堂、校区节次与午餐
Model: Codex · Keywords: campus-bells / continuous-period / lunch  
Changed: 本机课表和 Rust 示例的教学时段对齐；「今日」、语音读值及完整课表共用同一午餐区间。午餐不产生课程详情、课程提醒或蓝色课程进度。  
Reason: 课间、午餐和未选课的正式节次有不同含义；不能从个人课程之间的空档推断学校作息。  
Affected interfaces: 原生内部 `LessonTimeline.Block.lunch`；校区用 `includesCampusLunch` 显式启用午餐。HTTP 格式、数据库、环境变量和账号设置不变。  
Verification: 81 项 Swift、35 项 Rust 测试通过，含本机/Rust 当日/离线作息逐段对照。iPadOS 26.4 模拟器分别以本机课表和隔离的服务账户验证连堂中点、上午空档、12:29/12:30、13:24/13:25、尾节与放学，且两种来源的完整课表都显示午餐。实拍：[连堂中点](../docs/verification/student-interface/campus-double-period.jpg) · [午餐卡片](../docs/verification/student-interface/campus-lunch-today.jpg) · [服务账户的完整课表](../docs/verification/student-interface/campus-bells-schedule.jpg)。

### 2026-11-19 — 时间透镜按住展开
Model: Codex · Keywords: press-lens / timeline-contact  
Changed: 分离按压状态与所选时刻；指针只在按住时展开，释放或手势中断时自动收窄。减少动态效果时不做弹性过渡，减弱透明度时使用系统底色。  
Reason: 不使用透镜时，课程名称和进度应当仍然一眼可见。  
Affected interfaces: 仅修改共享「今日」时间轴的显示；触摸范围、VoiceOver、课表数据、Rust 接口和设置均不变。  
Verification: 在 11 英寸 iPad Air 模拟器（iPadOS 26.4）同一点按住不动 5 秒，直接截取[按住时的画面](../docs/verification/student-interface/timeline-lens-held.png)，并与[同一时刻松手后](../docs/verification/student-interface/timeline-lens-rest.png)对照。点按、拖回一节课的中点、松手保留时间及返回当前时间均已验证；轨道边界未变。78 项 Swift 核心测试通过（含隔离的 Rust 接口测试）。

### 2026-11-19 — 课程进度与 Freeblock
Model: Codex · Keywords: elapsed-course / published-freeblock  
Changed: 课程块根据已过时长局部填蓝，名称在色块两侧分别保持对比。首页、完整课表及离线读取共用正式节次投影；Freeblock 不显示虚构的教室、老师或详情。  
Reason: 下一节课程不是正在进行的课程；课间和午休不是未选课的正式节次。  
Affected interfaces: `teaching_slots` 是既有当日和离线课表中的可选数据；没有它就只显示已知课程。不改本地偏好、校历、天气动效、数据库或通知。  
Verification: 78 项 Swift 核心测试（含本机槽位、旧数据和 Rust HTTP），35 项 Rust 测试通过。iPad 模拟器横竖屏实走课前、上课中、课间、放学及往回拖动，并核对实际画面的蓝色覆盖。另以隔离的 Rust 课表核对空节开始和结束边界；未改变内置账户的排课。实拍：[课程已过一半](../docs/verification/student-interface/timeline-course-progress.png) · [正在 Freeblock](../docs/verification/student-interface/freeblock-current.jpg)。

### 2026-11-19 — 今日时间轴与稳定布局
Model: Codex · Keywords: today-timeline / stable-focus-layout  
Changed: 本机和资料服务共用单栏课程卡与时间轴，按当日课表确定范围；移除并排的后续课程清单、未提供的课堂备注、重复的时刻说明和首页天气状态文字。  
Reason: 在课程、课间和放学之间拖动时，内容可以切换，但手指下的轨道不应移动。按当天内容、实际窗口宽度和字号预留空间，避免用固定高度裁切文字。  
Affected interfaces: 只涉及原生应用及内部课表投影。完整课表、东莞天气刷新、Rust API、数据库与环境变量不变。  
Verification: 72 项核心测试（含 Swift ↔ Rust HTTP）通过。iPad Air 11 英寸模拟器上，本机竖屏、横屏大字号及隔离资料账户三项界面回归通过。对照当前时刻、两段不同课程、放学及返回当前时刻，三组内轨道顶边的纵坐标变化均为 0 pt。实拍：[课程中](../docs/verification/student-interface/timeline-stable-class.jpg) · [放学后](../docs/verification/student-interface/timeline-stable-finished.jpg)。

### 2026-11-19 — 今日轮转日
Model: Codex · Keywords: rotation-heading / timetable-shortcut  
Changed: 本机和资料服务的「今日」在课程前用同一标题显示轮转日、日期和星期。时间轴不再重复天数；今日、课表、日程的工具栏保留日历快捷入口。空间不足时日期另起一行，无障碍字号下方的课程卡也依次排列。  
Reason: 一眼认出当天的轮转日，又不会把今天和正在浏览的另一日期混淆。  
Affected interfaces: 只改原生视图；日号取自现有校历或对应账户当日课表，不改轮转算法、服务接口和存储。  
Verification: iPadOS 26.4 模拟器验证本机和隔离 Rust 账户的日号、时间轴拖动、课表跳转及无障碍大字号。OCR 在首页只读到一个 Day 值，辅助功能树中只有一个相应标题。[首页](../docs/verification/student-interface/rotation-day.jpg) · [大字号](../docs/verification/student-interface/rotation-day-accessibility.jpg)。

### 2026-11-19 — 学生界面文案与实时时钟
Model: Codex · Keywords: student-copy / live-school-clock  
Changed: 首页使用校区当前时间，移除固定时刻入口；统一栏目、详情、内置内容与通知文案。时间轴只临时改变首页光照，不改写外观偏好。旧版拖动时间轴遗留的非整分钟背景恢复跟随当前时间；外观设置中选定的整分钟时刻不变。  
Reason: 学生先看到当前课程状态；数据来源集中在既有设置内，保留必要的操作和权限说明。模拟器验证时也修正了事项卡片的命中区域，点卡片中间空白处也能打开详情。  
Affected interfaces: 无网络、数据结构、存储键或通知标识变更。  
Verification: iPad Air 11 英寸模拟器（iPadOS 26.4）实走 10 个栏目、资料与事项详情、拖动时间轴与重启。界面实拍：[当前时刻](../docs/verification/student-interface/today.jpg)、[主动选择其他时刻](../docs/verification/student-interface/selected-time.jpg)。学校账号与真机未用于验收。

### 2026-11-19 · 东莞天气接入
Model: OpenAI Codex · Keywords: fixed-city / sky-source / weather-cache  
Changed: 独立读取东莞天气，沿用所有主要页面的程序天空；在已有环境面板区分自动、缓存、手动和不可用状态，今日页不再把当前天气标为示例。  
Reason: 天气跟随城市，光照跟随时刻，两者可以独立预览。  
Affected interfaces: 新增原生天气模块和一次公开 HTTPS GET；无新的学校 API、数据库、环境变量、权限或第三方包。

### 2026-11-19 · 程序化天空
Model: OpenAI Codex  
Conversation Keywords: iPad Metal / 体积云 / 固定夜间时刻  
Changed: 改为本机逐帧体积渲染；旧天空图片退出资源包；新增可复现的昼夜渲染探针。  
Reason: 云的形状、阴影及遮挡应真正变化，而不只是整图变亮或移动。  
Affected interfaces: 无新增 API、数据库、应用环境变量或业务页面。

### 2026-11-19
Model: OpenAI Codex  
Conversation Keywords: iPad-weather / sky-background / native-import  
Changed: 将原生 iPad 工程纳入工作区，扩展环境面板与共享背景，替换导入工程中基于原截图的本机考勤样例为合成汇总。  
Reason: 可重复构建新的天气背景，同时避免把参考内容带到新的预览产物中。  
Affected interfaces: 环境面板的本机选择与光线预览；旧天气偏好兼容。无 HTTP、数据库或环境变量变更。
