# 正式构建 · 交给发布者签名

## 2026-11-21 工程快照

| 项目 | 当前值 |
| --- | --- |
| 工程 / Scheme | `Xiaobao-iPadOS/Xiaobao.xcodeproj` / `Xiaobao` |
| App 显示名 | TSchedule |
| 设备 / 部署版本 | iPad；iPadOS 26.0 及以上 |
| 原型标识 | `cn.xiaobao.ipados.prototype`，不是已登记的正式 Bundle ID |
| 工程版本 / build | `0.3` / `3`，以上传的正式构建为准 |
| 本机 Xcode | 27.0（27A266a） |
| 当前提交 | 本次未使用发布者签名，未上传，未制作可提交 IPA |

**验证结果：** 原工程 `Xiaobao` Scheme 的 `Release` 设备归档通过（`CODE_SIGNING_ALLOWED=NO`）。从归档读取了原型 ID、0.3 (3)、最低系统版本 26.0 和仅 iPad 的设备族。主包根目录有 `PrivacyInfo.xcprivacy`，通过 `plutil` 并与仓库源文件逐字节一致；锁屏实时活动扩展仍在包内。此前隔离的演示截图测试 1/1 通过。

## 最短路径

1. 由实际发布者进入其 Apple Developer 账户，确认会员状态与协议；注册最终 Bundle ID，用同一个 ID 在 App Store Connect 建 App 记录。首次上传后该记录的 Bundle ID 不能更换。
2. 在 Xcode 的原工程配置该 Team、最终 Bundle ID、版本号；核对默认浅色与深色图标、正式归档中的隐私清单和可打开的隐私政策链接。
3. 选择可归档的 iPadOS 设备目标而不是模拟器，`Product → Archive`；在 Organizer 先 Validate，再由发布者授权 `Distribute App → App Store Connect`。
4. 核对 Archive 与 App Store Connect 的 ID、构建号、图标、隐私表单和地区。首发只选美国，选免费。等审核测试访问确认以后再提审。

**「设置 → 隐私」可离线阅读中英隐私政策、使用与服务条款；这不是对外可访问的隐私网址。** [网页](../04-web/README.md)仍待正式发布。[隐私清单](../../../Xiaobao-iPadOS/Config/PrivacyInfo.xcprivacy)已经加入主 App 的打包资源；[实际 API 用途](app-privacy.md#required-reason-api)和商店隐私问卷分别核对。

### 在本机复核清单打包

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
