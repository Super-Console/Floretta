# macOS 标题栏标题位置与首页玻璃重影

- 日期：2026-11-14
- 分支：`fix/mac-titlebar`
- 影响：macOS `DocumentEditor` toolbar 与 `ContentView` Home split detail；未修改版本号。
- 改动：标题/返回放入 leading `.navigation` toolbar slot；旧 macOS `leadingDocumentChrome` 入口限制在 iOS；移除 Mac Home detail 的 `.backgroundExtensionEffect()`，保留系统 toolbar glass 与 iOS split 行为。
- 验证：`swift test --filter AppleGlassChromeContractTests`，9 tests passed；`xcodebuild -list -project Floretta.xcodeproj` 成功；标题 placement 和 Mac background extension 的反向验证各自按预期失败。无 GUI/截图/签名构建，视觉需 Timmy 在构建中确认。
- 提交：实现提交 `94a98d6`、`dbd0fb3`；PR #6（OPEN，未合并）。
