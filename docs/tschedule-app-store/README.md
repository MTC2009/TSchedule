# TSchedule / 澜图 · App Store 美区首发资料

整理日期：2026-11-21。**这是送审资料包，不是已签名或已发布的 App。** 首发按仅美国区、免费下载、iPadOS 26+ 准备；是否申请 Unlisted 由发布者决定。不会把 Unlisted 当私密安装或审核豁免。

| 材料 | 去哪里找 | 状态 |
| --- | --- | --- |
| 商店标题、副标题、文案、关键词 | [en-US](01-store-listing/en-US.md) · [zh-Hans](01-store-listing/zh-Hans.md) | 英文 TSchedule、简中澜图；文案是可编辑草稿 |
| 主屏幕图标 | [icons](02-artwork/icons/README.md) | 已从 Xcode 当前资源复制默认浅色与深色两张 |
| iPad 13 英寸截图 | [截图与顺序](02-artwork/ipad-13-inch/README.md) | 5 张，横屏 2752 × 2064；已逐张核对，只用内置样例 |
| 英文审核备注、测试访问、Unlisted 文案 | [审核资料](03-app-review/README.md) | 备注已整理；单独的授权审核账号尚未落实 |
| 隐私政策、使用与服务条款、支持页 | [双语页面及发布说明](04-web/README.md) | 政策也可在 iPad 设置离线阅读；邮箱已填。未上线，发布者与生效日期未定 |
| 正式构建与隐私填表 | [构建步骤](05-build/README.md) · [App Privacy 核对表](05-build/app-privacy.md) | API 隐私清单已在不签名的 Release 归档验证；正式 Bundle ID、签名和商店隐私申报待确认 |

## 送审前只看这四关

1. **账号与标识：** 实际发布者开通会员、确认协议；在首次上传前确定正式 Bundle ID。不要把原型 ID 当成已经定稿。
2. **网页与隐私：** 「设置 → 隐私」已有离线正文；由发布者确认文案，发布无需登录的网页并补上正式 HTTPS 链接。复核正式签名归档内的隐私清单，再按实际行为填 App Privacy。
3. **审核员能测试：** 用获准的独立测试账号；不交真实学生的账号密码。说明真实校务连接。
4. **签名与发布：** 用发布者的 Team 从原工程签名并上传。在 App Store Connect 只选美国区和免费；补齐年龄问卷、版权、截图和审核联系人。想只发链接就选手动发布并单独申请 Unlisted，确认后再发布。

**不要上传本目录里的说明文件、草案或截图测试副本作为构建。** App 从仓库的 `Xiaobao-iPadOS/Xiaobao.xcodeproj` 构建。此包不包含签名证书、私钥、账号、会话、真实成绩或 iPad 数据。

本次原工程的 **iPad 设备 Release 归档（不签名）通过**，主 App 隐私清单已核对。隔离的 13 英寸模拟器内置演示截图测试通过；这两项不验证正式发布者签名、真实校宝会话或 App Store 审核。

## Apple 参考

- [iPad 截图规范](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)
- [填写产品页](https://developer.apple.com/app-store/product-page/)
- [上传构建](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds)
- [设置上架地区](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/manage-availability-for-your-app-on-the-app-store)
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) · [Unlisted 分发](https://developer.apple.com/support/unlisted-app-distribution)
