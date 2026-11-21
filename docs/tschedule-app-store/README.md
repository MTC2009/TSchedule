# TSchedule / 澜图 · App Store 美区首发资料

整理日期：2026-11-21。**这是送审资料包，不是已签名或已发布的 App。** 首发按仅美国区、免费下载、iPadOS 26+ 准备；是否申请 Unlisted 由发布者决定。不会把 Unlisted 当私密安装或审核豁免。

| 材料 | 去哪里找 | 状态 |
| --- | --- | --- |
| 商店标题、副标题、文案、关键词 | [en-US](01-store-listing/en-US.md) · [zh-Hans](01-store-listing/zh-Hans.md) | 英文 TSchedule、简中澜图；文案是可编辑草稿 |
| 主屏幕图标 | [icons](02-artwork/icons/README.md) | 已从 Xcode 当前资源复制默认浅色与深色两张 |
| iPad 13 英寸截图 | [截图与顺序](02-artwork/ipad-13-inch/README.md) | 5 张，横屏 2752 × 2064；已逐张核对，只用内置样例 |
| 英文审核备注、测试访问、Unlisted 文案 | [审核资料](03-app-review/README.md) | 备注已整理；真实测试账号或 Apple 对演示送审的同意还没落实 |
| 支持与隐私网页 | [发布说明](04-web/README.md) | 本地 HTML，未发布；需填真实发布者、公开邮箱和日期 |
| 正式构建与隐私填表 | [构建步骤](05-build/README.md) · [App Privacy 核对表](05-build/app-privacy.md) | 正式 Bundle ID、签名和最终隐私申报待确认 |

## 送审前只看这四关

1. **账号与标识：** 实际发布者开通会员、确认协议；在首次上传前确定正式 Bundle ID。不要把原型 ID 当成已经定稿。
2. **网页与隐私：** 发布支持页和隐私政策，未登录也能打开；让正式 App 内能点到隐私政策。核对并打包所需隐私清单，再按实际行为填 App Privacy。
3. **审核员能测试：** 用获准的独立测试账号，或者按 Apple 指南事先获准使用充分的内置演示；不交真实学生的账号密码。说明真实校务连接，不把演示当真实联通。
4. **签名与发布：** 用发布者的 Team 从原工程签名并上传。在 App Store Connect 只选美国区和免费；补齐年龄问卷、版权、截图和审核联系人。想只发链接就选手动发布并单独申请 Unlisted，确认后再发布。

**不要上传本目录里的说明文件、草案或截图测试副本作为构建。** App 从仓库的 `Xiaobao-iPadOS/Xiaobao.xcodeproj` 构建。此包不包含签名证书、私钥、账号、会话、真实成绩或 iPad 数据。

本次原工程的 **iPad 设备 Release 编译（不签名）通过**。隔离的 13 英寸模拟器内置演示截图测试通过；未验证正式发布者签名、真实校宝会话或 App Store 审核。

## Apple 参考

- [iPad 截图规范](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)
- [填写产品页](https://developer.apple.com/app-store/product-page/)
- [上传构建](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds)
- [设置上架地区](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/manage-availability-for-your-app-on-the-app-store)
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) · [Unlisted 分发](https://developer.apple.com/support/unlisted-app-distribution)
