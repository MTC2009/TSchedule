# 审核资料 · 尚未提交

[英文审核备注](review-notes.en.txt)可以作为 App Store Connect 的 Notes。目前没有隔离测试账号，审核账户栏仍留空；不要提供真实学生账号或密码。若后续取得获准的独立账号，先确认能在审核环境访问合成校务记录，凭据只由发布者填入 App Review Information，不进入仓库、截图或支持网页。

## 可询问 Apple 的替代方式

若因隐私或安全原因无法提供演示账号，[审核指南 §2.1(a)](https://developer.apple.com/app-store/review/guidelines/) 允许在 Apple 事先同意后，用内置、能展示完整功能的演示模式替代。拟议模式从未登录状态明确进入，使用合成数据展示课表、个人计划、作业、GPA 和考勤，不连接真实校宝、不读取本人数据或使用已保存登录；审核备注应据实说明真实版的登录与使用范围。当前 Release 未包含此模式，内部 Debug 测试入口和宣传片不能直接替代。未询问 Apple，未提交审核。

## 如果选择 Unlisted

在版本发布方式选手动。送审备注中说明计划使用 Unlisted，再按 Apple 的单独表单请求链接。可以在 Notes 附上：

> This release is intended for unlisted distribution. The app is an independent iPad companion for a limited school community; live data requires an existing account on the supported student portal. We have initially selected only the United States storefront.

未得到批准前不要点发布来试链接。如果最终选正常美区上架，删除这段 Unlisted 备注。限定链接分发不限制转发，不替代上架审核、地区合规或第三方服务权限。

[审核信息](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/#app-review-information) · [审核指南 2.1(a)、5.2.2](https://developer.apple.com/app-store/review/guidelines/) · [Unlisted](https://developer.apple.com/support/unlisted-app-distribution)
