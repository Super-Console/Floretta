# F3：通过五个 Port 路由平台访问

- 日期：2026-11-11
- 分支：`oc/ports-migration`

## 变更

- FileAccess：为目录、路径、临时目录与 iCloud Documents 操作扩展 `FileAccessPort`；`LibraryModel` 的文件访问与枚举通过注入实现。
- Pasteboard：`DocumentEditor` 的文本和图片复制/粘贴改为使用 `PasteboardPort`，AppKit/UIKit 访问留在 Apple adapter。
- DeviceInfo：设置默认视图及本机目录标签改为经 `DeviceInfoPort` 选择。
- Clock：Core 文档、AI 修改、分享提交、缩略图更新时间及应用近期文件/画布时钟改为经 `ClockPort`；固定时钟 Fake 覆盖文档与 AI 时间戳。
- FontMetrics：画布/大纲编辑器的组合输入宽度测量及布局通过 `FontMetricsPort`，Apple 平台 adapter 使用 CoreText。
- 增加各 Port 的 Fake 覆盖和平台访问替身。

## 验证

- `bash scripts/check-floretta-core-imports.sh`：通过（`FlorettaCore boundary ok`）。
- `git diff --check`：通过。
- macOS `xcodebuild build`：成功，`BUILD_EXIT=0`，`error:` 计数为 0。
- iOS `xcodebuild build`：成功，`BUILD_EXIT=0`，`error:` 计数为 0。
- `swift test --scratch-path /tmp/f3-r2-swift-build`：347 tests，0 failures，`TEST_EXIT=0`。
- 模拟器收尾：执行 `xcrun simctl shutdown all`；随后 `booted=0`。

## 性能

- 内存：未做基准测量；本次为平台访问抽象与注入变更，未主动增加缓存或常驻状态。
- 帧率：未做基准测量；渲染流程未作有意变更。
- 包体：未做基准测量；未增加依赖。

## Round 2：补齐 ClockPort 真实应用路径

- `DocumentSession.makeNew()`、模板文档和样式示例创建显式传入 `ports.clock`；两处 `ThumbnailFileCache` 初始化也传入该时钟。`InfiniteCanvas` 不再隐式构造系统时钟。
- 新增 Shell 回归测试：注入固定时钟后通过 `LibraryModel.makeNew()` 检查创建/修改时间，并通过其实际缩略图缓存写入文件后核对修改时间。
- macOS `xcodebuild test`：413 tests，0 failures；iOS Simulator build：成功，`error:` 诊断计数 0；macOS app build：成功（test 编译同时覆盖 UI target）；Core boundary guard 与 `git diff --check` 通过。`swift test`：347 tests，0 failures。
- 审计余项：应用实现中 `SystemClock.now()` 转调 Core 的 `FoundationClock()`；`Date()` 仅在 UI 测试的轮询 deadline 使用。Core 的 `FoundationClock` 是生产系统时钟实现；MindMapDocument、AI/share 操作和缩略图缓存的默认参数保留它，以兼容无需注入的 Core 调用，应用路径现显式传入依赖时钟。
- 验证过程中的首次测试尝试曾在用户 Application Support 下创建 `Floretta/Attachments/Thumbnails/injected-clock`（写入固定测试数据，mtime 为 2023-11-15 06:15:23 +0800）。后续测试已改为 sandbox 路径；该首次生成文件仍在原处，未擅自删除，等待用户决定是否清理。
