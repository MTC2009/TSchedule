# Xiaobao · Rust backend prototype

给 Xiaobao iPadOS 原型使用的独立 JSON 后端。Rust + Axum 使用单线程异步运行时。设备登录用内嵌 SQLite 持久化，数据库操作在后台执行。接口只表达数据和操作，不限制前端布局。

**尚未连接真实校宝。** 运行服务时，Day 和停课依据已整理的 2026–2027 主校区高中部校历；两套账号的六门课程、成绩、考勤和资料仍是独立演示数据。[学生端页面及接入对照](../docs/portal-backend-inventory.md)列出 14 个已核对页面对应的接口。Rust 只提供 JSON，不渲染校宝网页。

## 启动

安装 Rust stable，然后：

```sh
cd xiaobao-backend
cargo run --release --locked
```

服务默认监听 `http://127.0.0.1:3001`。编译后也可以直接运行 `./target/release/xiaobao-backend`，运行时不需要 Rust 工具链。

浏览器前端联调时指定它的 origin：

```sh
XIAOBAO_WEB_ORIGIN=http://localhost:5173 cargo run --release --locked
```

模拟器可以连接默认的本机地址。实体 iPad 使用证书受信任的 HTTPS 服务地址，可在同一网络的电脑上用 HTTPS 反向代理转发到这个进程。

这是可选择任意演示账号的本地开发服务，不是已接入学校身份认证的公共服务。

## 第一个请求

```sh
curl -s http://127.0.0.1:3001/api/v1/demo/profiles

curl -s http://127.0.0.1:3001/api/v1/demo/sessions \
  -H 'Content-Type: application/json' \
  -d '{"profile":"demo-a"}'
```

把响应中 `data.access_token` 的值用作后续请求的 Bearer token：

```sh
curl -s http://127.0.0.1:3001/api/v1/schedule \
  -H 'Authorization: Bearer YOUR_DEMO_TOKEN'
```

上述请求创建原有的 8 小时内存会话。iPad 选择保持登录后，发送 `{"profile":"demo-a","remember":true}`，获得 15 分钟的访问令牌和此设备专用的续期凭据。服务只保存凭据的 SHA-256 摘要、账号和有效期。数据库默认为 `.xiaobao/sessions.sqlite3`，可通过 `XIAOBAO_SESSION_DB` 指定持久卷上的固定路径。每个身份提供方独立使用数据库。

`POST /api/v1/session/refresh` 接收 `{"refresh_token":"..."}`。成功续期将闲置窗口延长至 30 天，最迟到首次登录后第 90 天。遇到断线可以重试，同一有效期内返回同一访问令牌。注销可使用该设备的访问或续期凭据，在线撤销立即生效。

iPad 从本机资料打开各个页面。课程、课表、校历活动、考勤、任务、考试、测评、资料库与成绩各有独立版本。后台检查先发一次带版本标记的请求，未变时返回 HTTP 304 和空正文。有变化时，一次取回对应模块的完整记录。考勤比率、Day 和成绩试算可离线完成。

课程目录可私有缓存 24 小时，课表、考勤和完整成绩 GET 可缓存 5 分钟。带 `If-None-Match` 校验时先验证会话和数据版本，相同的账号、查询与版本直接返回 `304`。没有可靠版本的数据源默认返回完整响应。模拟数据和学校网页的身份验证独立，真实账号连接仍需学校支持的登录、续期和数据读取方式。

## 已实现的接口

所有业务接口均以 `/api/v1` 开头，学生数据需要有效的访问令牌。创建演示会话与设备续期使用各自的请求体。

| 页面或功能 | 接口 |
| --- | --- |
| 演示账号 | `GET /demo/profiles`、`POST /demo/sessions` |
| 设备续期 | `POST /session/refresh` |
| 账号、注销 | `GET /me`、`DELETE /session` |
| 课程 | `GET /courses` |
| 今日课表、Day 几 | `GET /schedule?date=YYYY-MM-DD` |
| 日程：校历、活动、课程、任务截止时间 | `GET /calendar?from=...&to=...` |
| 全部资料版本及按模块下载 | `GET /offline/versions`、`POST /offline/data` |
| 旧客户端按科目检查成绩 | `POST /grades/sync` |
| 各科成绩、往期学期、公布信息、各次评估权重 | `GET /grades?term=...&class_type=...&q=...` |
| 成绩模拟 | `POST /grades/project-score` |
| 上课／日常／活动考勤及记录 | `GET /attendance?category=classroom` / `daily` / `activity` |
| 任务 / 考试 / 测评 | `GET /work?kind=task` / `exam` / `evaluation` |
| 任务详情、考试分科成绩或测评演示记录 | `GET /work/{id}` |
| 任务及考试得分率统计 | `GET /work-statistics?kind=task` / `exam` |
| 共享 / 个人资料、共享信息、搜索 | `GET /resources?scope=shared` / `personal` |
| 资料详情 | `GET /resources/{id}` |

完整字段和筛选规则见 [API.md](API.md)，可执行请求示例见 [requests.http](requests.http)。健康检查为 `GET /health`。

## 数据约定

- 演示数据以**服务启动时的上海日期**为基准生成。跨天持续联调时可重启刷新基准。
- `schedule.day` 使用演示轮换规则计算，周末和配置的停课日返回 `null`。真实学校的 Day 轮换、调休和学期重置规则需要校宝数据确认。
- 成绩保留数字分、字母等级、未出分等区别；未出分是 `null`，不会变成 0。未经验证的 GPA 保持 `null`。
- 成绩模拟只计算调用方明确给出的百分制权重，不读取、修改官方成绩，也不声称实现 Giaoculator 的 GPA 算法。
- 演示课堂、日常和活动考勤分别覆盖基准日期及之前 29 天，并使用不同的记录。出勤比例为 `present / total`，迟到、早退、缺勤分别计数；这是演示统计口径，后续按学校规则适配。原有离线考勤只含课堂数据。
- 空考勤的比例是 `null`。没有覆盖的数据返回 `unavailable`；仅覆盖部分日期返回 `partial`，不会把未知日期当成缺勤。
- 任务、考试、测评只读；未出分、字母分或无有效满分时不计算得分率。任务列表提供独立的可用学期，往期可用已有 GET 读取；离线载荷仍以当前学期为准。提交正文、点评、发布时间以及附件名称是可选读取资料，不支持提交或下载。
- 资料只有演示文本，任务附件只有显示名称等元数据，不含下载 URL。

## 代码结构

```text
src/main.rs       启动、监听地址、可选 CORS、退出信号
src/lib.rs        路由、共享状态、请求体限制
src/api.rs        通用请求/响应规则、日历、成绩、资料等现有读取
src/work/         任务、考试、测评的筛选、详情和得分率统计
src/attendance/   三类考勤的在线报告和数据覆盖处理
src/auth.rs       会话验证及非持久登录
src/devices.rs    SQLite 设备凭据、续期与撤销
src/cache.rs      私有缓存与条件请求
src/grade_sync.rs 成绩快照、按科目生成版本和变更集
src/offline.rs    账号资料版本索引与完整模块下载
src/domain.rs     数据类型、轮换日、考勤计算
src/provider.rs   数据源接口、账号快照和课表读取
src/provider/     两套合成账号及页面数据生成
tests/api.rs      HTTP 层集成测试，新增页面覆盖见 tests/api/portal_pages.rs
```

每个请求复用 `Arc` 中的数据，没有复制整份学生档案。内存会话和持久设备分别上限 128 个；JSON 请求体上限 8 KiB；列表每页最多 100 条；日历最多查询 42 天，考勤最多 366 天。使用 release 编译的 thin LTO 和符号剥离减小产物。

## 接真实校宝时的边界

`SchoolProvider` 提供账号快照、指定日期范围的课程以及 `grades_if_changed`。演示服务在载入学生数据时计算版本。适配器通过 `offline_catalog` 发布不可变的账号快照。真实数据源可用校方提供的变更标记刷新这些快照，设备校验直接读取已生成的索引。真实接入需要新增经授权的登录流程，验证账号后签发应用会话，再实现数据源读取。仅更换数据源不足以完成真实登录。

下一步需要学校接口的实际请求与脱敏响应格式，尤其是登录 / 续期、学生身份、课表与轮换日、成绩 / GPA、考勤分类、任务和附件。不要把真实密码或 Cookie 写进代码或演示数据。

尚未实现：真实校宝同步、任务提交、考试作答、测评填写、Teams、真实附件下载、文件管理、APNs 推送、天气 / 节日服务、Giaoculator 兼容桥接。iPad 端可先用课表安排本地通知；这不等于后端已经支持推送或后台实时同步。

## 验证

```sh
cargo fmt --all --check
cargo test --locked
cargo clippy --locked --all-targets -- -D warnings
cargo build --release --locked
```

测试覆盖会话有效期、撤销和数量上限、多账号隔离、错误请求、日期范围、轮换日、成绩类型、考勤一致性、筛选 / 分页和模拟成绩不影响原成绩。

原有 Rust 测试覆盖离线模块版本、条件请求、会话续期与跨账号隔离。页面新增测试覆盖考试分科、得分率和缺失分数、考勤覆盖边界、往期成绩、分享归属、可选筛选以及新统计接口的条件请求。

### 本机日程读取优化

Apple M3 Max 本机用相同演示数据对比两个 Release 二进制。每个版本、每条路由测量 6,000 次：42 天日程中位耗时 **154.1 → 135.0 微秒**，P95 **181.5 → 154.2 微秒**；一周日程中位耗时 **81.9 → 76.9 微秒**。只减少了构建课程 ID 时的重复日期格式化和字符串扩容，未增加缓存、改变接口或缩减返回数据。短请求的微小波动不当作收益；数据不代表真实校宝、网络或 iPad 渲染性能。结果与对照信息见 [verification.json](verification.json)。

保留优化前的 Release 二进制后，可在本机复测：

```sh
python3 scripts/bench.py /path/to/old/xiaobao-backend target/release/xiaobao-backend --calendar-42d --runs 8 --samples 750
```

### 历史基准

以下是增加设备登录之前的序列化优化基准。在 Linux x86_64 本机上，两个 release 版本以相反顺序交替运行 6 轮。每轮用同一条 HTTP 长连接交替读取两个学生在基准周的周三课表、整周日历、成绩和 30 天考勤。每个版本每个接口预热后共测量 3,000 次，计时包含客户端完整读取响应。考勤中位耗时从 149.6 降至 72.4 微秒，成绩从 88.1 降至 57.3 微秒。服务完成同一批请求后的 RSS 中位数从 2,670 降至 2,384 KiB。数据源为本地演示账号。其余接口的中位数和 P95 见 [verification.json](verification.json)。

保留两个版本的可执行文件后，可用 Python 3.9 及以上版本在 Linux 上复测。

```sh
python3 scripts/bench.py /path/to/old/xiaobao-backend target/release/xiaobao-backend
```

## Change History

### 2026-11-19 — 校区作息校正
Model: Codex · Keywords: campus-bells / midday-gap  
Changed: 当日课表、日历与离线资料改用同一组校区教学时段，包括早上连堂和午餐后的三节课。保留原有六门课的名称、顺序、教室与 ID，不用虚构科目填满七个时段。  
Reason: 旧示例的整点偏移把一门课排进了午餐。  
Affected interfaces: 原有 GET 的示例时间和缓存修订变化；离线 timetable 内容版本随之更新。无新字段、路由、环境变量或数据库改动。

### 2026-11-19 — 正式节次
Model: Codex · Keywords: teaching-slots / offline-timetable  
Changed: 当日课表和离线轮转表可带正式节次，不把 Freeblock 伪造成课程记录。原有两个账户的课程、上课时间、校历和身份验证不变。  
Reason: 客户端只有知道学校的节次，才能区别空课、午休与普通课间。  
Affected interfaces: [课表与离线契约](API.md#schedule-and-calendar) 中的可选字段 `teaching_slots`；无新路由、环境变量或数据库迁移。

### 2026-11-19 — 内置校园资料文案

Model: Codex · Keywords: student-copy / provider-revision  
Changed: 合成资料改为面向学生的名称、说明与反馈；同步更新条件请求的版本标识，见 [provider](src/provider/README.md)。  
Reason: 避免在原生页面逐条显示开发标记。  
Affected interfaces: 仅内置内容与缓存标识变化；数据来源仍是 `demo`，无路由、授权或数据库变更。

### 2026-11-18

Model: gpt-6.2-sol  
Conversation Keywords: student-portal-pages / rust-read-api / demo-work-statistics

Changed: 导入归档的 Rust 工程；补齐 14 个已核验学生页面的数据接口，增加分科成绩、任务/考试统计、日常/活动考勤、资料分享信息和往期成绩。使用合成数据，保持已有前端协议、数据库、应用配置及依赖版本。

Reason: 让现有前端能为各页面读取对应数据，不把页面渲染或原站会话放进 Rust。

Affected interfaces: `GET /work-statistics`（新增）；`GET /work`、`GET /work/{id}`、`GET /attendance`、`GET /resources`、`GET /resources/{id}`、`GET /grades` 和 `GET /calendar`（增量扩展）；离线模块键及课堂考勤格式不变。

### 2026-11-18 — 日程读取性能

Model: gpt-6.2-sol  
Conversation Keywords: calendar-performance / lesson-id-reuse / local-ab-benchmark

Changed: 演示课程生成按教学日复用日期字符串，每个课程 ID 按所需容量分配。现有基准脚本增加可选的 42 天窗口；集成测试核对跨月日程的 ID、账号归属、周末和顺序。

Reason: CPU 分段测量确认长期日程存在可移除的重复工作；没有为演示服务引入额外缓存或自定义日期序列化。

Affected interfaces: `GET /schedule` 与 `GET /calendar` 只改变内部实现，返回契约、权限和离线数据不变。
