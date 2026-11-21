# 审核资料 · 尚未提交

[英文审核备注](review-notes.en.txt)可以作为 App Store Connect 的 Notes。当前只整理了真实行为和样例操作，**还没解决审核员如何获准测试真实校宝连接**。不要把个人账号填成 demo account。

选好下面一条再提审：

1. **单独的授权测试账号。** 由合适的服务负责人提供可供 Apple 使用、只含虚构记录的测试学生账号；验证审核期间可以登录。凭据只由发布者填入 App Review Information 的登录栏，不进入此包、截图、Git 或支持网页。
2. **事先得到 Apple 同意的完整内置演示。** 如因法律或安全原因无法提供测试账号，先按审核指南 2.1(a) 咨询；明确演示不连接学校，真实功能依赖已有第三方账号。检查最终构建的样例是否足以展现全部相应功能。下面是可用的询问，不是 Apple 已批准的记录：

> TSchedule uses an existing school-issued account for live academic data. We cannot share real student credentials or records with App Review. May we provide a fully featured built-in demonstration with synthetic records in lieu of a separate school demo account? The review notes will describe the live sign-in and read-only integration separately.

## 如果选择 Unlisted

在版本发布方式选手动。送审备注中说明计划使用 Unlisted，再按 Apple 的单独表单请求链接。可以在 Notes 附上：

> This release is intended for unlisted distribution. The app is an independent iPad companion for a limited school community; live data requires an existing account on the supported student portal. We have initially selected only the United States storefront.

未得到批准前不要点发布来试链接。如果最终选正常美区上架，删除这段 Unlisted 备注。限定链接分发不限制转发，不替代上架审核、地区合规或第三方服务权限。

[审核信息](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/#app-review-information) · [审核指南 2.1(a)、5.2.2](https://developer.apple.com/app-store/review/guidelines/) · [Unlisted](https://developer.apple.com/support/unlisted-app-distribution)
