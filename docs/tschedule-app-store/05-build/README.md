# 正式构建 · 交给发布者签名

## 2026-11-22 工程快照

| 项目 | 当前值 |
| --- | --- |
| 工程 / Scheme | `Xiaobao-iPadOS/Xiaobao.xcodeproj` / `Xiaobao` |
| App 显示名 | TSchedule |
| 设备 / 部署版本 | iPad；iPadOS 26.0 及以上 |
| 正式 Bundle ID | 主 App `st.mtc.tschedule`；锁屏实时活动 `st.mtc.tschedule.lesson-activity` |
| 签名 Team | 两个目标使用项目级自动签名，从本机的 `Xiaobao-iPadOS/Config/Signing.local.xcconfig` 读取 `DEVELOPMENT_TEAM`；该文件不进版本库 |
| 本机归档版本 / build | `0.3` / `3` |
| 本机 Xcode | 27.0（27A266a） |
| 当前状态 | 本机归档与 App Store 分发签名已核验；Xcode 已交付 `0.3 (3)`，Apple 返回处理中；未送审或发布 |

**验证结果：** `Xiaobao` Scheme 的 `Release` 设备归档通过。主 App 和内嵌锁屏实时活动扩展的 Bundle ID、Team 和签名通过核对，两者都只面向 iPad（最低 26.0）。主 App 根目录的 `PrivacyInfo.xcprivacy` 与源文件逐字节一致。归档可在本机 Xcode Organizer 找到；开发签名使用 Team 的通配描述文件，不能据此判断两个显式 App ID 已注册或分发签名已就绪。

**建档进度：** 已在发布者的 Apple Developer 团队注册主 App 的显式 ID `st.mtc.tschedule`，并在 App Store Connect 创建「澜图 TSchedule」`1.0` 草稿。已保存「手动发布此版本」并重新加载核对。草稿未关联构建，也未送审。[Apple：版本发布选项](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/select-an-app-store-version-release-option/)

**TestFlight 内测：** 已创建「澜图内部测试」组，未启用自动分发。创建后核验为 0 个测试员、0 个构建；未发送邀请、未上传或送审，不影响 App Store 草稿。日后以 `TestFlight Internal Only` 上传的构建只能用于团队内部测试，不能提交给外部测试者或 App Store。[Apple：内部测试](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers/)

**同学试用：** 目标是 TestFlight 外部测试，仅按邮箱邀请，不开公开链接。Xcode 从已核验的归档导出 `0.3 (3)`，主 App 和锁屏扩展均通过 Apple Distribution 签名及精确 Bundle ID 描述文件核对。已用普通上传交付（非 `TestFlight Internal Only`），Apple 返回处理中，回读时 TestFlight 尚未列出构建。没有建外测组、发邀请或提交测试审核；首个外测构建须过测试审核后再发邀请。[Apple：外部测试](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/)

## 最短路径

1. 主 App 记录已建立。准备分发前，由实际发布者核对协议及两个正式 Bundle ID 的显式注册。首次上传后该记录的 Bundle ID 不能更换。
2. 在 Xcode 的原工程核对本机 Team、两个目标的 Bundle ID 和版本号；核对默认浅色与深色图标、正式归档中的隐私清单和可打开的隐私政策链接。
3. 选择可归档的 iPadOS 设备目标而不是模拟器，`Product → Archive`；在 Organizer 先 Validate，再由发布者授权 `Distribute App → App Store Connect`。
4. 核对 Archive 与 App Store Connect 的 ID、构建号、图标、隐私表单和地区。首发只选美国，选免费。等审核测试访问确认以后再提审。

**「设置 → 隐私」可离线阅读中英隐私政策和使用与服务条款。** [公开隐私政策](https://mantatche.com/tschedule/privacy/)与[支持页](https://mantatche.com/tschedule/support/)已上线；当前归档中的离线政策仍是旧稿，之后应更新 App 内资料及公开隐私链接再归档。[隐私清单](../../../Xiaobao-iPadOS/Config/PrivacyInfo.xcprivacy)已经加入主 App 的打包资源；[实际 API 用途](app-privacy.md#required-reason-api)和商店隐私问卷分别核对。

### 不使用签名时在本机单独复核清单

在仓库根目录运行；产物和 DerivedData 放到新的临时目录。不签名，不连接 App Store Connect：

```sh
work="$(mktemp -d)"
xcodebuild -project Xiaobao-iPadOS/Xiaobao.xcodeproj -scheme Xiaobao -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath "$work/DerivedData" \
  -archivePath "$work/TSchedule.xcarchive" -disableAutomaticPackageResolution \
  CODE_SIGNING_ALLOWED=NO archive
manifest="$work/TSchedule.xcarchive/Products/Applications/Xiaobao.app/PrivacyInfo.xcprivacy"
plutil -lint "$manifest"
cmp Xiaobao-iPadOS/Config/PrivacyInfo.xcprivacy "$manifest"
```

技术验证、模拟器测试或 unsigned build 不能替代发布者签名、真机测试或 Apple 审核。不要把截图用的临时演示构建上传。加密出口申报请按最终打包的实际实现完成问卷，不要把“只用了系统接口”当作已填报或免填的证明。

[Apple 最新提交要求](https://developer.apple.com/news/upcoming-requirements/) · [准备分发](https://developer.apple.com/documentation/Xcode/preparing-your-app-for-distribution) · [上传构建](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds)
