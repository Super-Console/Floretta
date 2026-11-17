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

## 2026-11-18 阶段记录：独立标题胶囊与签名构建阻塞

- 当前 `perf/typing-lag` 工作区将 macOS 返回按钮与可重命名标题拆成两个独立 `.navigation` `ToolbarItem`；标题使用 `CappedWidthLayout`、单行中间省略和 `.fixedSize(horizontal: true, vertical: false)`，空标题显示“未命名”。两份源码契约测试已更新。
- 离屏原生 `NSToolbar` 探针（`scripts/measure-title-capsule.sh --toolbar`）记录的原始值，单位 pt；这不是产品 App 截图：

  | 标题 | plate x / w | content x / w | ink x / w | plate↔ink 中心差 | 布局内距 L/R | 内距差 | plate-content 宽差 | 可见墨迹余量 L/R |
  |---|---:|---:|---:|---:|---:|---:|---:|---:|
  | `草稿` | 857 / 26 | 857 / 26 | 858 / 24 | 0 | 0 / 0 | 0 | 0 | 1 / 1 |
  | `项目复盘与结构整理笔记-长期维护版本-第二稿-补充材料-归档副本.floretta` | 654 / 234 | 654 / 234 | 655 / 232 | 0 | 0 / 0 | 0 | 0 | 1 / 1 |
  | 空标题占位 `未命名` | 849 / 39 | 849 / 39 | 850 / 35.5 | 0.75 | 0 / 0 | 0 | 0 | 1 / 2.5 |

- 占位符墨迹左右余量相差 1.5 pt；这是可见字形墨迹的不对称，不是布局 content inset（测得 0 / 0）。窄宽度离屏探针也通过。悬停/按下的真实窗口宽度稳定性尚未实机测量。
- 本轮 `swift test`：609 tests / 1 skipped / 0 failures；`xcodebuild -list -project Floretta.xcodeproj`、macOS Debug `-showBuildSettings`、`git diff --check` 均通过。CUA 权限可用，但 `list_windows({app: "Floretta"})` 返回空，故没有产品窗口截图。
- 构建图确认 `Floretta-macOS` 依赖 Share、Quick Look Thumbnail、Quick Look Preview 三个扩展；此前正常签名构建在 Share 扩展处以 `errSecInternalComponent` 失败（退出码 65）。未关闭代码签名，未启动 DerivedData 中的旧 App，也未进行 GUI 操作。
- 未提交、未推送、未合并、未发布 TestFlight。`$TMPDIR/floretta-title-capsule.*` 仍有 8 个既有探针目录（各约 156 KB），本轮未清理，等待用户确认。
