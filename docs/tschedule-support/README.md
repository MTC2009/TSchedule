# TSchedule 应用支持页

`index.html` 是供个人网站托管的中英双语支持页。不依赖 App 构建、后端、外部资源或表单；邮件链接由访客自己的邮件客户端打开。

## 部署前

1. 页面已填项目的公开维护邮箱；发布者仍需确认能正常收信。改动时同步[送审包副本](../tschedule-app-store/04-web/support/index.html)和[政策联系信息](../tschedule-app-store/04-web/README.md)。
2. 将 HTML 放到现有网站的 `/tschedule/support/` 或自选路径。用未登录的窗口打开最终 HTTPS 地址，确认两种语言的链接和联系邮箱都可用。发布前确认页面所列菜单与送审版一致。
3. 将公开页面的完整 URL 填入 App Store Connect 的「支持网址」。隐私政策是单独的字段，可在同一个网站另设页面。

## 修改记录

- 2026-11-21 · Codex · `policy-contact`：填入公开支持邮箱并核对英文移除绑定路径。仅更新本地支持页及其副本，未发布。

- 2026-11-21 · Codex · `app-store-support`：新增独立支持页，包括中英联系说明和校宝重新登录、移除已保存登录的操作。未更改 App、数据接口或网站部署。
