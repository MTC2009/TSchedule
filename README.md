<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="Xiaobao-iPadOS/Resources/Assets.xcassets/TScheduleMark.imageset/tschedule-mark.png">
    <img src="Xiaobao-iPadOS/Resources/Assets.xcassets/TScheduleMark.imageset/tschedule-mark-light.png" width="64" height="64" alt="TSchedule 校园图标">
  </picture>
</p>

<h1 align="center">TSchedule · 澜图</h1>

<p align="center">
  为清澜山学生设计的 iPad 课表与计划工具。<br>
  <sub>iPadOS 26+ · SwiftUI · Metal · 0.3 开发版</sub>
</p>

<p align="center">
  <a href="#快速开始">快速开始</a> ·
  <a href="docs/tschedule-promo/Meet-TSchedule.mp4">观看 75 秒介绍</a> ·
  <a href="docs/tschedule-app-store/02-artwork/ipad-13-inch/README.md">浏览界面截图</a>
</p>

[![TSchedule 的「今日」界面：iPad 显示正在上的课、教室、距离下课的时间，以及当天的课程时间轴。](docs/tschedule-promo/TSchedule-preview.jpg)](docs/tschedule-promo/Meet-TSchedule.mp4)

## 在 iPad 上

- **[今日](docs/tschedule-app-store/02-artwork/ipad-13-inch/01-today.png)** — 打开就能看到正在上什么课、在哪里上、还有多久下课。沿时间轴拖到下午，可以提前看下一节；天空的光线也跟着所选时刻变化。
- **[计划](docs/tschedule-app-store/02-artwork/ipad-13-inch/02-planner.png)** — 竖屏看一天，宽屏看一周。把自己的安排放在学校课表旁，拖到合适的时段，或设为每周重复。移动个人计划不会改动学校课程。
- **[任务](docs/tschedule-app-store/02-artwork/ipad-13-inch/03-assignments.png)与[成绩](docs/tschedule-app-store/02-artwork/ipad-13-inch/04-gpa.png)** — 用学期下拉切换学校提供的记录，按课程和截止日期找作业，从课程总评点进每项考核。未公布的成绩不算作零分；个人试算也不会改写已公布成绩。
- **[考勤](docs/tschedule-app-store/02-artwork/ipad-13-inch/05-attendance.png)** — 按课堂、日常或活动查看考勤，也可以点进一门课，核对具体记录。

上课时还可以从「今日」开启**锁屏课表**。不用解锁 iPad，就能看见离下课还有几分钟、接下来上哪门课。

<p align="center">
  <img src="docs/verification/student-interface/lesson-activity-minutes.png" width="540" alt="锁屏课表卡片：左侧显示距离下课的分钟数，右侧显示下一节课的名称。">
  <br><sub>iPadOS 实时活动。配图不含真实学生记录。</sub>
</p>

## 快速开始

准备一台装有 **Xcode 26 或更高版本**的 Mac。查看校园资料需要清澜山学生校宝账号，无需另行启动服务器。

1. 下载或克隆**完整仓库**，从仓库根目录打开 App 工程：

   ```sh
   open Xiaobao-iPadOS/Xiaobao.xcodeproj
   ```

2. 在 Xcode 选择 **Xiaobao** Scheme 和一台 **iPadOS 26 或更高版本**的 iPad 模拟器，按 **⌘R** 运行。
3. 点「完整校宝」，在学校页面登录后点「完成」，即可从「今日」查看本周课表。需要在自己的设备上运行时，参见 [iPad 工程说明](Xiaobao-iPadOS/README.md)。

## 数据来源与隐私

课表、任务、考勤、考试、测评和分享的资料目录来自当前登录的校宝账号。进入 GPA 时才读取已公布成绩；历史学期按选择加载。未登录、会话已过期或学校未提供资料时，App 不填充记录；作业提交仍在学校网页完成。

校务资料只在本机当前会话内读取，不经开发者服务器中转。若主动开启锁屏课表，iPadOS 会在锁屏上显示课程摘要。详见[设备内读取说明](Xiaobao-iPadOS/Sources/Native/SchoolPortalSync/README.md)与[可选的本机代登录](Xiaobao-iPadOS/Sources/Native/SchoolPortalLogin/README.md)。

TSchedule 是独立学生项目，并非学校或校宝的官方客户端。界面与读取流程通过隔离测试；学校实际提供的资料以本人账号为准。

## 开发

| 入口 | 内容 |
| --- | --- |
| [iPadOS 客户端](Xiaobao-iPadOS/README.md) | SwiftUI 界面、Metal 天空、核心逻辑与构建指南。 |
| [模块索引](MODULE_INDEX.md) | 按职责查找源码入口与模块文档。 |

许可证：[MIT](LICENSE)。

在仓库根目录运行对应测试：

```sh
swift test --package-path Xiaobao-iPadOS
cargo test --locked --manifest-path xiaobao-backend/Cargo.toml
```

## 联系

维护者邮箱：[steven.xie.28.tsinglan.org@gmail.com](mailto:steven.xie.28.tsinglan.org@gmail.com)。反馈问题时，请附上 iPadOS 版本和复现步骤；请勿发送学校账号密码、Cookie 或含个人成绩的截图。
