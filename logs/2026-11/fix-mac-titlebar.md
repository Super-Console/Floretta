# macOS 标题栏标题位置与首页玻璃重影

- 日期：2026-11-14
- 分支：`fix/mac-titlebar`
- 影响：macOS `DocumentEditor` toolbar 与 `ContentView` Home split detail；未修改版本号。
- 改动：标题/返回放入 leading `.navigation` toolbar slot；旧 macOS `leadingDocumentChrome` 入口限制在 iOS；移除 Mac Home detail 的 `.backgroundExtensionEffect()`，保留系统 toolbar glass 与 iOS split 行为。
- 验证：`swift test --filter AppleGlassChromeContractTests`，9 tests passed；`xcodebuild -list -project Floretta.xcodeproj` 成功；标题 placement 和 Mac background extension 的反向验证各自按预期失败。无 GUI/截图/签名构建，视觉需 Timmy 在构建中确认。
- 提交：实现提交 `94a98d6`、`dbd0fb3`；PR #6（OPEN，未合并）。
- 后续修复（2026-11-14）：修复 `testIOSBackButtonIsAStandardToolbarItem` 因旧源码切片终点失效而无法提取 iOS toolbar 的问题；测试继续锁定系统 ToolbarItem、44×44 hit target 及禁止自绘容器等原契约。macOS 文档名通过 `window.title` + `.visible` 放回原生窗口标题位置，返回键保持系统 `.navigation` toolbar item；同步更新标题位置契约与 `DONE-mac-titlebar.md`。
- 验证：`swift test --package-path FlorettaCore` — 371 tests, 1 skipped, 0 failures。视觉未验证，待 CUA；操作路径与期望现象见 DONE。
- 提交：`7e0be3a` 已推送至 `origin/fix/mac-titlebar`；工作树干净，PR #6 分支继续使用。
