# Recents 当前 UI-test 会话可见性回归修复

- 日期：2026-11-14
- 对象：Floretta Recents 与 macOS/iOS 应用构建
- 根因：路径过滤把当前 UI-test 启动根下的新文档当成旧测试残留；当前测试自产文档同时被 `load()` 过滤和 `remember()` 拒收。
- 变更：UI-test 创建 store 时注入当前根目录；store 对当前根下文档放行，对其他 `FlorettaUITest-*` 根继续过滤。普通用户 store 不注入当前根。
- 回归测试：`testRecentMapsKeepUserDocumentNamedUntitledVisible`、`testRecentMapsKeepCurrentUITestRootVisible`、`testRecentMapsExcludeOtherUITestRoots`。
- 验证：`swift test` 369 tests / 1 skipped / 0 failures；macOS unsigned build 成功；iOS Simulator generic unsigned build 成功（有现存 UIKit/SDK warnings）；macOS `FlorettaTests` 460 tests / 1 skipped / 0 failures。
- iOS UI 门禁未在此运行，待 Timmy 在 GUI 会话执行 `./scripts/pre-release.sh` 复验。
- 分支 `fix/recents-uitest-visibility`，提交 `274d801`；PR #4 已创建，未合并。
- 未启动/关闭模拟器；未触碰 LocalAsk、版本号、钥匙串。
