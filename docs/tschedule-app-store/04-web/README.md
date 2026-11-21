# 隐私政策、使用与服务条款及支持页

[隐私政策](privacy/index.html) · [使用与服务条款](terms/index.html) · [应用支持](support/index.html)

目前是本地审阅材料，不是已上线的网址或校方授权。两份政策都提供简体中文和英文；现有 iPad「设置 → 隐私」显示相同正文，断网也能读。阅读不是同意，不会保存同意记录或改变校宝登录状态。

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

## 对外分发前

1. 由实际发布者核对负责任的主体、日期、来信处理与未成年人安排；向学校/服务商确认接入范围。政策文本不能替代这些决定或依法需要的同意。
2. 确认后更新正文、再生成网页和构建 App。将 `policy.css` 与 `privacy/`、`terms/`、`support/` 放在同一公开目录；无需上传生成脚本。核对实际托管的访问日志和隐私影响。
3. 用未登录的设备检查最终 HTTPS 地址、两种语言、页间导航和邮箱可用性，再填 App Store Connect、添加正式政策网址。另行核对归档的隐私清单和隐私问卷。
4. 讨论未满十四周岁学生的试用时，另核对监护人同意及专门处理规则；目前没有这项同意流程。[《个人信息保护法》第三十一条](https://www.cac.gov.cn/2021-08/20/c_1631050028355286.htm)。第三方服务和分发许可另见 [Apple 审核指南 §5.2.2](https://developer.apple.com/app-store/review/guidelines/#intellectual-property)；服务条款也不代替 [App Store 软件许可](https://developer.apple.com/help/app-store-connect/manage-app-information/provide-a-custom-license-agreement/)。

## 修改记录

- 2026-11-21 · Codex · `offline-policy / shared-copy`：用同一份文案生成隐私与条款静态页，和 iPad 离线阅读保持一致；补齐联系渠道。无服务端接口或发布操作。
