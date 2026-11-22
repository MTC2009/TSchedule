# App Privacy 填表前核对

这是基于当前仓库的核对单，**不是预填的 Apple 隐私标签**。Apple 对「收集」有自己的定义，也要考虑 WebView 和集成的第三方行为；不要因为学生资料不经过开发者服务器就直接选择“未收集数据”。

| 数据或场景 | 目前可从工程确认 | 送审前核对 |
| --- | --- | --- |
| 学生门户与真实资料 | 通过官方 WebKit 会话。门户收到用户登录与资料请求；原生读取限当前学生的已授权内容，成绩和考勤用会话内存；已读学期的清单与可见任务详情（含本人提交、已发布点评及文件名）受文件保护、不备份；附件仅点选下载，主动导出的文件由用户管理，登录失效、拒绝访问、退出、换号或手动清除时撤销。可选的截止提醒不含标题，除非学生另行开启；学年课表保存为受系统文件保护、不备份的本机文件，退出或确认换号撤销并清理。不向开发者服务转发。持久 WebKit 可能保留浏览器网站数据。 | 核对最终使用的门户、相关 WebView 流量与服务方实际处理，依 App Privacy 定义填写。不得隐去真实处理。 |
| 保存登录（默认关） | 开启后仅限已核验账号；账号凭据在设备专用、不跨设备同步的 Keychain。仅在授权的前台启动恢复或主动访问 GPA 需要登录时向官方门户验证；用户可移除。 | 用发布构建确认取消、退出、断网、账号切换、未知验证页面的行为；不用真实资料作送审附件。 |
| 本机计划、设置、通知 | 本机存储并安排提醒；不改变学校记录。不见广告或统计 SDK 的接入。 | 最终构建检查所有 SDK/资产；本机功能与设备备份、App Store 下载统计不要混为一项。 |
| 东莞天气 | Open-Meteo 收到固定城市坐标、天气请求和普通连接元数据。不请求设备定位，不附校园身份或成绩。 | 服务方声明免费 API 可能保留技术日志；核实是否需声明相应类型、用途、关联与跟踪。保留署名并核对非商业使用条件。 |
| 发邮件联系支持 | 自愿邮件会给实际发布者发件地址与邮件内容。 | 确认邮箱、保留处理和删除联络方式；要求来信不含凭据、成绩或学生身份截图。不要替实际发布者承诺不存在的清理流程。 |
| 儿童及学生用户 | App 受众与实际学校账号相关。 | 根据真实受众、地区及数据流程核对适用的儿童隐私要求；App Store 年龄分级问卷独立处理。 |

## Required Reason API

[主 App 清单](../../../Xiaobao-iPadOS/Config/PrivacyInfo.xcprivacy)只申报当前 Release 使用的两类 Required Reason API：

| 类别与理由 | 代码依据 |
| --- | --- |
| `NSPrivacyAccessedAPICategoryUserDefaults` · `CA92.1` | [AppModel](../../../Xiaobao-iPadOS/Sources/Native/AppModel.swift)、[天气缓存](../../../Xiaobao-iPadOS/Sources/Core/CityWeather/CityWeatherStore.swift)、[本机课表](../../../Xiaobao-iPadOS/Sources/Core/SchoolTimetable/SchoolTimetableStore.swift)和[本机绑定状态](../../../Xiaobao-iPadOS/Sources/Native/SchoolPortalLogin/SchoolPortalLoginVault.swift)用 App 私有的 `UserDefaults.standard` 保存预设、缓存或状态标记；没有 App Group 或 MDM 的用途。 |
| `NSPrivacyAccessedAPICategoryFileTimestamp` · `C617.1` | [CampusDiskCache](../../../Xiaobao-iPadOS/Sources/Core/CampusPage.swift)读取 App 私有缓存目录中文件的 `contentModificationDateKey` / `contentModificationDate`，以淘汰最旧的页面缓存。文件时间不用于网络请求。 |

复核了主 App 和 `LessonActivityWidget` 的目标成员及 Release 二进制引用。扩展没发现需要申报的 API，不复制主 App 的清单。主 App 不直接调用 Apple 列出的开机时间 API；天气动画的 `CACurrentMediaTime()` 是 QuartzCore 的动画计时接口，不在该表。磁盘空间、活动键盘等未用类别不申报。加入新代码或 SDK 后需重核。

这份清单不替代上面的 App Privacy 问卷，也不声明「未收集数据」。

- [Apple：隐私问卷](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/) · [App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/)
- [Apple：API 类别与获准理由](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype) · [清单打包](https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk)
- [Open-Meteo：条款与隐私](https://open-meteo.com/en/terms)
