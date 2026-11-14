STATUS: BLOCKED

七个接入点均已完成；阻塞仅在两端 Xcode 构建收尾签名：扩展的 debug dylib 返回 `errSecInternalComponent`。依仓库约定，无人值守构建无法签名扩展，本轮不触碰钥匙串。另修正前置提交中 `ThemeSettings.swift` 的工程文件引用路径。

## 接入点清单

- 首页/项目管理器与最近列表/网格：`Floretta/Shared/Shell/LibraryHome.swift:17`（最近页）、`:190`（侧栏项目管理）、`:428`（设置页）。
- 设置页及检查器：`Floretta/Shared/Shell/AppearanceSettingsPanel.swift:79`（同一面板用于设置和检查器）。
- 画布节点文字：`Floretta/Shared/Canvas/InfiniteCanvas.swift:2015`（节点文字绘制）；共享 modifier 与字体候选实际可用性检查：`Floretta/Shared/ThemeSettings.swift:22`、`:67`。
- 状态栏：`Floretta/Shared/Shell/EditorStatusBar.swift:24`、`:40`。
- 工具栏文字/编辑器整体：`Floretta/Shared/Shell/DocumentEditor.swift:160`。

共享 modifier 依据已保存界面语言或系统 locale 选 CJK/Latin 候选；每个候选均通过 `NSFont(name:size:)` / `UIFont(name:size:)` 检查后才应用。新增解析测试：中文界面 classic 首选 Songti 系列、modern 首选 PingFang 系列。

## 验证输出

1. `CODE_SIGNING_ALLOWED=NO xcodebuild build -project Floretta.xcodeproj -scheme Floretta-macOS -destination 'platform=macOS' -derivedDataPath /tmp/dd-theme 2>&1 | grep -E 'error:|BUILD (SUCCEEDED|FAILED)'`
   ```text
   /tmp/dd-theme/Build/Products/Debug/FlorettaQuickLookPreview-macOS.appex/Contents/MacOS/FlorettaQuickLookPreview-macOS.debug.dylib: errSecInternalComponent
   ** BUILD FAILED **
   ```
   详细失败：`FlorettaQuickLookPreview-macOS.debug.dylib: errSecInternalComponent`（签名）。
2. `CODE_SIGNING_ALLOWED=NO xcodebuild build -project Floretta.xcodeproj -scheme Floretta-iOS -destination 'generic/platform=iOS' -derivedDataPath /tmp/dd-theme-ios 2>&1 | grep -E 'error:|BUILD (SUCCEEDED|FAILED)'`
   ```text
   /tmp/dd-theme-ios/Build/Products/Debug-iphoneos/FlorettaShare-iOS.appex/FlorettaShare-iOS.debug.dylib: errSecInternalComponent
   ** BUILD FAILED **
   ```
   详细失败：`FlorettaShare-iOS.debug.dylib: errSecInternalComponent`（签名）。
3. `swift test --package-path FlorettaCore`
   ```text
   Executed 386 tests, with 1 test skipped and 0 failures (0 unexpected)
   Test Suite 'All tests' passed
   ```
4. 新增 2 条单测，均通过：`testChineseInterfaceClassicPrefersSongtiFamily`、`testChineseInterfaceModernPrefersPingFangFamily`。

资源收尾：未启动模拟器或后台服务；遵守用户指定保留 `/tmp/dd-theme` 和 `/tmp/dd-theme-ios` 构建产物，未清理。
