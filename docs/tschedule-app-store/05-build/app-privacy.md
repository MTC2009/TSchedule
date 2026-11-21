# App Privacy 填表前核对

这是基于当前仓库的核对单，**不是预填的 Apple 隐私标签**。Apple 对「收集」有自己的定义，也要考虑 WebView 和集成的第三方行为；不要因为学生资料不经过开发者服务器就直接选择“未收集数据”。

| 数据或场景 | 目前可从工程确认 | 送审前核对 |
| --- | --- | --- |
| 学生门户与真实资料 | 通过官方 WebKit 会话。门户收到用户登录与资料请求；原生读取限当前学生的已授权内容，真实视图数据用当前会话内存，不向开发者服务转发。持久 WebKit 可能保留浏览器网站数据。 | 核对最终使用的门户、相关 WebView 流量与服务方实际处理，依 App Privacy 定义填写。不得隐去真实处理。 |
| 保存登录（默认关） | 开启后仅限已核验账号；账号凭据在设备专用、不跨设备同步的 Keychain。仅在符合条件的前台 GPA 访问中向官方门户验证；用户可移除。 | 用发布构建确认取消、退出、断网、账号切换、未知验证页面的行为；不用真实资料作送审附件。 |
| 本机计划、设置、通知 | 本机存储并安排提醒；不改变学校记录。不见广告或统计 SDK 的接入。 | 最终构建检查所有 SDK/资产；本机功能与设备备份、App Store 下载统计不要混为一项。 |
| 内置样例与可选演示服务 | 无账号可查看内置虚构资料；手动连接的独立演示服务另有设备续期凭据和离线样例。 | 明确发布版是否保留演示服务连接。如保留，应披露目的、远端地址控制方式和本机缓存。不要当作处理真实校宝资料的服务器。 |
| 东莞天气 | Open-Meteo 收到固定城市坐标、天气请求和普通连接元数据。不请求设备定位，不附校园身份或成绩。 | 服务方声明免费 API 可能保留技术日志；核实是否需声明相应类型、用途、关联与跟踪。保留署名并核对非商业使用条件。 |
| 发邮件联系支持 | 自愿邮件会给实际发布者发件地址与邮件内容。 | 确认邮箱、保留处理和删除联络方式；要求来信不含凭据、成绩或学生身份截图。不要替实际发布者承诺不存在的清理流程。 |
| 儿童及学生用户 | App 受众与实际学校账号相关。 | 根据真实受众、地区及数据流程核对适用的儿童隐私要求；App Store 年龄分级问卷独立处理。 |

## Required Reason API

工程通过 `UserDefaults` 保存 App 私有偏好等数据，候选声明为 `NSPrivacyAccessedAPICategoryUserDefaults / CA92.1`。这是目前源树的初步核对，不是最终全包审计。签名归档前应复核全部链接的框架、实际用途与数据申报；只添加真正使用且理由匹配的项目。

- [Apple：隐私问卷](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/) · [App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/)
- [Apple TN3183：Required Reason API](https://developer.apple.com/documentation/technotes/tn3183-adding-required-reason-api-entries-to-your-privacy-manifest)
- [Open-Meteo：条款与隐私](https://open-meteo.com/en/terms)
