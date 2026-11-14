STATUS: BLOCKED

# J1–J5 验收记录

## J1 — 缩放控件
- `Floretta/Shared/Shell/EditorStatusBar.swift:11-20`：移除右下角缩放控件，状态栏容器仍保留。
- `Floretta/Shared/Shell/DocumentEditor.swift:1089-1112`：顶部缩放控件保留，identifier 为 `editor.zoom`。
- `FlorettaUITests/ThemeModesScreenshotUITests.swift:168-173`：保留并加强断言，明确检查旧 identifier 不存在、顶部控件可见且可交互。

## J2 — 外观模式标题
- `Floretta/Shared/Shell/AppearanceSettingsPanel.swift:40-50`：保留 Section 标题，隐藏 segmented Picker 的可见重复 label；Picker 仍有可访问性 label。
- 该项目前有两个远端提交：`1247713`（原修改）和 `a82a3c3`（编译修正）。未改写远端历史或 force-push。

## J3 — 返回按钮与文档名
- `Floretta/Shared/Shell/DocumentEditor.swift:90-99, 153-160, 196-226`：iOS 保留标准 toolbar 返回项；macOS 使用原生窗口标题，返回按钮独立。
- 契约测试更新于 `Tests/FlorettaCoreTests/AppleGlassChromeContractTests.swift`、`Tests/FlorettaCoreTests/EditorChromeContractTests.swift`。

## J4 — 侧边栏原生选中态
- `Floretta/Shared/Shell/AppleGlassChrome.swift:191-198`：保留 row inset，背景清空并交由 `.sidebar` 原生 List selection 绘制。
- 调用点：`Floretta/Shared/ContentView.swift:138-149`；同一 inset modifier 也用于 `Floretta/Shared/Outline/OutlineView.swift`、`Floretta/Shared/Shell/LibraryHome.swift`。
- 玻璃与 inset 实现保留。

## J5 — 待用户确认，不改布局
1. `Floretta/Shared/ContentView.swift:138-150, 197-209` 的 `NavigationSplitView`：窗口宽度不足导致列自适应/折叠时，侧栏或 detail 内容可能显得被挤出。
2. `Floretta/Shared/Shell/DocumentEditor.swift:193` 的 inspector 列宽 `min: 280, ideal: 320, max: 440`：窗口较窄且 inspector 展开时，编辑区可能被压缩。
3. `Floretta/Shared/Shell/DocumentEditor.swift:565-566` 的 outline 固定 300 pt 宽：outline 展开且编辑器可用宽度有限时，画布区域可能变窄或被推出视野。

## 验证
- `xcodebuild -scheme Floretta-macOS -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO build` → `** BUILD SUCCEEDED **`
- `xcodebuild -scheme Floretta-iOS -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build` → `** BUILD SUCCEEDED **`
- `swift test --package-path FlorettaCore` → `Executed 380 tests, with 1 test skipped and 0 failures`。
- 修改过的 `ThemeModesScreenshotUITests` 未实跑：相关截图测试依赖外部 screenshot poller 且需 GUI/副屏环境；当前未启动模拟器，也未验证该测试端到端。需在具备 poller 的副屏 GUI 会话单跑后解除 BLOCKED。

## 提交与 PR
- 分项提交已推送：`2100095` (J1)、`1247713` + `a82a3c3` (J2)、`33cacb3` (J3)、`48c75b4` (J4)。
- 已提交 PR #14：https://github.com/Super-Console/Floretta/pull/14（未合并）。
- 资源收尾：未启动模拟器；本任务构建进程已退出；未创建临时 DerivedData 目录。
