# TSchedule / 澜图 · App Store 美区首发资料

整理日期：2026-11-21，构建验证更新于 2026-11-22。**这是送审资料包，不含 App 构建产物。** 首发按仅美国区、免费下载、iPadOS 26+ 准备；是否申请 Unlisted 由发布者决定。不会把 Unlisted 当私密安装或审核豁免。

| 材料 | 去哪里找 | 状态 |
| --- | --- | --- |
| 商店标题、副标题、文案、关键词 | [en-US](01-store-listing/en-US.md) · [zh-Hans](01-store-listing/zh-Hans.md) | 主语言为英语（美国），已用「澜图 TSchedule」建档；其他文案尚未提交 |
| 主屏幕图标 | [icons](02-artwork/icons/README.md) | 已从 Xcode 当前资源复制默认浅色与深色两张 |
| iPad 13 英寸截图 | [截图与顺序](02-artwork/ipad-13-inch/README.md) | 5 张，横屏 2752 × 2064；已逐张核对，只用内置样例 |
| 英文审核备注、测试访问、Unlisted 文案 | [审核资料](03-app-review/README.md) | 备注已整理；没有可在校外使用的虚构数据测试账号，暂不处理审核访问 |
| 隐私政策、使用与服务条款、支持页 | [双语页面及发布说明](04-web/README.md) · [IT Center 讨论材料](../tschedule-it-center-brief.md) | 隐私与支持网址已上线并保存到商店草稿；条款未公开，已有 iPad 归档内的政策仍为离线旧稿 |
| TestFlight | [构建与分发记录](05-build/README.md) | 「澜图内部测试」组仍为空；已普通上传 `0.3 (3)`，Apple 处理中，未邀请测试员或送审 |
| 正式构建与隐私填表 | [构建步骤](05-build/README.md) · [App Privacy 核对表](05-build/app-privacy.md) | 正式 Bundle ID 已确定；本机开发签名与隐私清单已验证；App Store 分发签名和商店隐私申报尚未完成 |

## 送审前只看这四关

1. **账号与标识：** 发布者团队已用主 App ID `st.mtc.tschedule` 在 App Store Connect 建立「澜图 TSchedule」草稿。未上传构建或送审。锁屏扩展的显式 ID 留到分发准备，不用原型 ID。
2. **网页与隐私：** 无需登录的[隐私政策](https://mantatche.com/tschedule/privacy/)与[支持页](https://mantatche.com/tschedule/support/)已上线。后续更新 App 内政策与公开链接，复核签名归档内的隐私清单，再按实际行为填 App Privacy。
3. **审核员能测试：** 用获准的独立测试账号；不交真实学生的账号密码。说明真实校务连接。
4. **签名与发布：** App Store Connect 草稿已核验为仅美国区、`$0.00`，状态仍为「准备提交」，未关联构建或填写审核账号。后续用发布者的 Team 从原工程签名并上传；补齐年龄问卷、版权、截图和审核联系人。想只发链接就选手动发布并单独申请 Unlisted，确认后再发布。

**不要上传本目录里的说明文件、草案或截图测试副本作为构建。** App 从仓库的 `Xiaobao-iPadOS/Xiaobao.xcodeproj` 构建。此包不包含签名证书、私钥、账号、会话、真实成绩或 iPad 数据。

原工程的 **iPad 设备 Release 归档已使用发布者 Team 的 Apple Development 签名**，主 App 隐私清单已核对，本次未上传。此前隔离的 13 英寸模拟器内置演示截图测试也已通过；这些检查不验证真机运行、真实校宝会话或 App Store 审核。

## Apple 参考

- [iPad 截图规范](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)
- [填写产品页](https://developer.apple.com/app-store/product-page/)
- [上传构建](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds)
- [设置上架地区](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/manage-availability-for-your-app-on-the-app-store)
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) · [Unlisted 分发](https://developer.apple.com/support/unlisted-app-distribution)
