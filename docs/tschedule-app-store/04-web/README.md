# 隐私政策、使用与服务条款及支持页

[隐私政策](privacy/index.html) · [使用与服务条款](terms/index.html) · [应用支持](support/index.html) · [供 IT Center 讨论的一页说明](../../tschedule-it-center-brief.md)

**2026-11-22 已上线：** [隐私政策](https://mantatche.com/tschedule/privacy/) · [应用支持](https://mantatche.com/tschedule/support/)。已从无需登录的 HTTPS 访问核对发布者、生效日期、双语正文、互链、邮箱入口和样式。美国区配置可直接使用页面地址，也可加 `#en` 跳到英文。只发布了这两页，没有公开使用与服务条款。

第一行是仓库中的审阅材料，不是校方授权。两份政策都提供简体中文和英文；iPad「设置 → 隐私」读打包的正文，断网也能读。阅读不是同意，不会保存同意记录或改变校宝登录状态。

## 修改与检查

- **政策唯一正文：** [PolicyCopy.json](../../../Xiaobao-iPadOS/Resources/PolicyCopy.json)。按语言维护标题、导言及各节，维护者邮箱已填。修订日期不等于生效日期。发布者和生效日期未确认时，都保留为 `null`，网页和 App 显示「讨论稿，尚未生效」。
- **输出：** `render_policies.py` 仅读这份 JSON，校验中英文和发布日期，再写入或核对两个 `index.html`。网页只用同目录树内的 [样式](policy.css)，没有远程脚本、分析、表单或登录依赖；iPad 直接读打包正文，无需解析 HTML。
- **支持页：** [原件](../../tschedule-support/index.html)与送审副本保持一致；更新邮箱时也核对两份支持页。邮件需由使用者主动发送，不是 App 自动提交的报告。

在仓库根目录执行（系统 Python 3，无第三方依赖）：

```sh
python3 -B docs/tschedule-app-store/04-web/render_policies.py --write
python3 -B docs/tschedule-app-store/04-web/render_policies.py --check
cmp docs/tschedule-support/index.html docs/tschedule-app-store/04-web/support/index.html
```

## 单独发布网页

向新的空目录输出公开版。发布者标签和生效日期只用于公开网页，且只输出隐私页、支持页和样式；不会导出服务条款或改 App 的发布状态。

```sh
release="$(mktemp -d)"
python3 -B docs/tschedule-app-store/04-web/render_policies.py \
  --export-public "$release/tschedule" --publisher "$publisher" --effective-date "$effective_date"
```

将生成的三个文件放到个人站点 `mantatche.com` 的 `public/tschedule/`，由站点现有构建部署。上线后核对 HTML 标题、两种语言、互链、支持邮箱和样式，不能只检查 HTTP 200（站点会对不存在的路径返回主页）。切勿将归档、App 安装包、内部材料或仓库作为网页内容一并部署。

## 对外分发前

1. 由实际发布者核对负责任的主体、日期、来信处理与未成年人安排；向学校/服务商确认接入范围。政策文本不能替代这些决定或依法需要的同意。
2. 确认后更新 App 内读得到的发布者与生效日期及公开政策链接，再归档。网页和离线稿的正文来源共用，但网页上线不会改变原有归档。核对实际托管的访问日志和隐私影响。
3. 用未登录的设备检查最终 HTTPS 地址、两种语言、页间导航和邮箱可用性，再填 App Store Connect、添加正式政策网址。另行核对归档的隐私清单和隐私问卷。
4. 讨论未满十四周岁学生的试用时，另核对监护人同意及专门处理规则；目前没有这项同意流程。[《个人信息保护法》第三十一条](https://www.cac.gov.cn/2021-08/20/c_1631050028355286.htm)。第三方服务和分发许可另见 [Apple 审核指南 §5.2.2](https://developer.apple.com/app-store/review/guidelines/#intellectual-property)；服务条款也不代替 [App Store 软件许可](https://developer.apple.com/help/app-store-connect/manage-app-information/provide-a-custom-license-agreement/)。

## 修改记录

- 2026-11-21 · Codex · `offline-policy / shared-copy`：用同一份文案生成隐私与条款静态页，和 iPad 离线阅读保持一致；补齐联系渠道。无服务端接口或发布操作。
- 2026-11-22 · Codex · `public-privacy / support-pages`：加公开网页连接信息说明及静态导出；支持页的中英操作路径与当前 App 一致。没有修改 App 登录逻辑、校宝接口或既有归档。

### 2026-11-22 — Codex · offline-assignment-disclosure
本地打包政策与静态讨论稿已更新作业清单保留、清除和可选锁屏标题。此变更没有重新部署已上线的网页；含本功能的版本对外分发前，要从同一份正文重新导出、发布并复核公开隐私页。
- 2026-11-22 · Codex · `assignment-material-cache / files-export`：已同步本机政策正文与仓库内中英文静态草稿，说明前台逐项读取、设备文件保护及手动导出副本。此修改没有更新线上站点；公开分发本版本前须另行同步。
