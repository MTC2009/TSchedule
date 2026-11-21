# 支持网页与隐私政策

- [支持页](support/index.html)：仓库已有 TSchedule 双语支持页的送审包副本。原件仍在 `docs/tschedule-support/index.html`；不会自动同步修改。
- [隐私政策](privacy/index.html)：按当前原生 App 行为整理的双语发布草稿，不是已发布政策或已通过审核的承诺。

发布者确认后，替换 HTML 内所有相应字段：

| 标记 | 要填的实际内容 |
| --- | --- |
| `__TSCHEDULE_SUPPORT_EMAIL__` | 真正可公开、可收信的联系邮箱；两页保持一致 |
| `__TSCHEDULE_PUBLISHER__` | 实际负责发布的个人法定姓名或组织名称 |
| `__TSCHEDULE_EFFECTIVE_DATE__` | 实际生效日期 |

随后分别放到网站的 `/tschedule/support/` 和 `/tschedule/privacy/`，或其他稳定路径。公开页面无需登录、无占位符、邮件地址有效后，才把完整 HTTPS 地址填入 App Store Connect。隐私政策的实际网址也应从 App 内易于找到。

支持页和隐私页不接收学生学号、密码、会话或成绩；只提供邮件联系方式。不要把私有文档共享链接当作提交到 Apple 的公共隐私网址。网站托管若启用额外日志或分析，要核对站点的数据说明。
