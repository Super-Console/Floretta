STATUS: BLOCKED

# Batch 6 · toolbar, menus, multi-canvas

基线：`origin/main` / `0fab6a0`。本分支按 B4、B6、D5 保持三个独立 commit；没有改动 `MARKETING_VERSION`、`CURRENT_PROJECT_VERSION`、体积预算或 22 条既有冒烟 identifier。未运行完整 pre-release。

## 改动

- **B4** — `Floretta/Shared/Shell/DocumentEditor.swift:1065-1082`：沿用 `.toolbar(id: "floretta.editor")` 与既有 ToolbarItem identifiers / customization，显式给 toolbar item 设置 accessibility label；`FlorettaCore/Editor/EditorToolbarCatalog.swift:160` 将缩放工具栏面改为 SF Symbol，避免显示百分比文字。`Tests/FlorettaCoreTests/EditorToolbarCatalogTests.swift:171-183` 检查 iconOnly 与 accessibilityLabel。
- **B6** — `Floretta/Shared/Shell/DocumentEditor.swift:337-365, 1117-1141`、`Floretta/Shared/Shell/LibraryHome.swift:66-75, 103-114`、`Floretta/Shared/FlorettaApp.swift:67-260`：菜单行改用原生 `Label`；主题快捷键由 `KeyboardShortcut(entry:)` 绑定，文本上下文菜单及已有编辑/缩放/格式快捷键由 `.keyboardShortcut` 实际注册。`Tests/FlorettaCoreTests/MacMenuShortcutCatalogTests.swift:32-41` 加入菜单语义合同测试。
- **D5** — 多画布模型与 `.floretta` JSON 字段原已存在并保持 formatVersion 1；本批补上删除画布（保留至少一个画布、删除主画布时提升下一张并保留工程名/视口、活动索引夹紧）：`FlorettaCore/Model/CanvasSheets.swift:67-93`；编辑器画布标签原生上下文菜单提供重命名/删除且保留 `canvas.tabs`：`Floretta/Shared/Shell/DocumentEditor.swift:655-715`；Session 操作：`Floretta/Shared/Shell/DocumentSession.swift:609-618`。文案同步进入 `Floretta/Shared/Localizable.xcstrings` 与 `Floretta/Shared/Shell/FlorettaL10n.swift`。

## 验证输出

1. **macOS build：未通过。** 执行 `CODE_SIGNING_ALLOWED=NO xcodebuild build -project Floretta.xcodeproj -scheme Floretta-macOS -destination 'platform=macOS' -derivedDataPath /tmp/dd-batch6`；编译推进到扩展签名阶段，但 `FlorettaShare-macOS` 和 `FlorettaQuickLookThumbnail-macOS` 返回 `errSecInternalComponent`，最终 `** BUILD FAILED **`。按仓库规则未继续尝试绕过钥匙串。
2. **iOS build：未运行。** `xcodebuild -showBuildSettings` 确认 scheme 使用 `iPhoneSimulator27.2.sdk` / `iphoneos iphonesimulator`；因上述非 GUI 签名限制，未启动第二个签名构建。
3. **FlorettaCore tests：通过。** `swift test --package-path FlorettaCore`：`Executed 391 tests, with 1 test skipped and 0 failures (0 unexpected)`。
4. **指定 macOS FlorettaTests：未运行。** `CODE_SIGNING_ALLOWED=NO xcodebuild test -scheme Floretta-macOS -destination 'platform=macOS' -only-testing:FlorettaTests -derivedDataPath /tmp/dd-batch6` 因同一签名阻塞未运行；故该 suite 总数及结果尚不能验收。

新增/相关定向测试真实输出：

- `swift test --package-path FlorettaCore --filter CanvasSheetTests`：`Executed 9 tests, with 0 failures`（含新增多画布删除测试、旧单画布文件读取与多画布序列化）。
- `swift test --package-path FlorettaCore --filter MacMenuShortcutCatalogTests`：`Executed 5 tests, with 0 failures`。
- `swift test --package-path FlorettaCore --filter EditorToolbarCatalogTests`：`Executed 7 tests, with 0 failures`（含 iconOnly + accessibilityLabel 合同测试）。

## 旧文件兼容性

旧版单画布 `.floretta` 仍由 `MindMapDocument` 的可选增量字段默认解码为空；`CanvasSheetTests.testLegacySingleCanvasFileStillLoadsWithoutNewKeys` 验证旧 JSON 读入后 `canvasCount == 1`、活动画布为 0、画布切换条不显示，且重新编码不会写入 `additionalCanvases` / `activeCanvasIndex` 等多画布字段。没有做破坏性迁移。

## 资源与后续

未启动或使用模拟器；`xcrun simctl list devices booted | grep -c Booted` 当前输出 `1`，未关闭未知来源的已启动模拟器。构建使用单一临时目录 `/tmp/dd-batch6`，按清理规则待用户批准后再清理。分支已 push 至 `origin/feat/toolbar-canvas`，draft PR 已创建：[#19](https://github.com/Super-Console/Floretta/pull/19)。macOS GUI 签名构建、iOS build、指定 FlorettaTests 仍待签名阻塞处理后继续；该 PR 不应合并。
