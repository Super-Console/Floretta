STATUS: DONE

# Recents UI-test session visibility fix

## 根因

`RecentMapsStore.isUITestArtifact` 将路径中任意 `FlorettaUITest-*` 组件都视为旧测试残留。当前 UI 测试新建的文档也位于当前启动生成的 `FlorettaUITest-<id>` 根下，因此被 `load()` 隐藏、被 `remember()` 拒收，首页 Recents 无可点击行。

## 改法

- `FlorettaApp` 创建 UI-test `RecentMapsStore` 时显式注入本次启动的根目录。
- `RecentMapsStore` 仅豁免位于注入根目录下的测试文档；其他 `FlorettaUITest-*` 路径仍在 `load()` 和 `remember()` 过滤。普通用户 store 不注入该根，真实用户文档不受影响。
- 没有改动 `FlorettaUITests/HomeSmokeTests.swift` 的断言。

## 新增/拆分的 Recents 单测

- `testRecentMapsKeepUserDocumentNamedUntitledVisible`
- `testRecentMapsKeepCurrentUITestRootVisible`
- `testRecentMapsExcludeOtherUITestRoots`

原 Recents 测试 1 条拆成 3 条，测试总数净增 2。

## 验证

- `swift test`：369 tests，1 skipped，0 failures。
- `xcodebuild build -scheme Floretta-macOS ... CODE_SIGNING_ALLOWED=NO`：`BUILD SUCCEEDED`。
- `xcodebuild build -scheme Floretta-iOS ... CODE_SIGNING_ALLOWED=NO`：成功；保留现有 UIKit actor-isolation 等编译 warning。
- `xcodebuild test -scheme Floretta-macOS -only-testing:FlorettaTests ... CODE_SIGNING_ALLOWED=NO`：460 tests，1 skipped，0 failures，`TEST SUCCEEDED`。
- **iOS UI 门禁待我在 GUI 复验**：没有在本任务执行 UI 自动化或 `pre-release.sh`。

## 交付状态

- 分支：`fix/recents-uitest-visibility`
- PR：待创建
- 未合并；未改 LocalAsk、版本号或钥匙串。
