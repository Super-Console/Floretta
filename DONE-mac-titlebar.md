STATUS: DONE

# macOS 标题栏双问题修复

## 根因与改动

1. **文档标题位置**：旧 `leadingDocumentChrome` 通过通用 toolbar 的 `.cancellationAction` 放回退箭头和标题，macOS 没有显式的左侧标题分区，最终被系统放进右侧工具组。`DocumentEditor.swift:89-110` 新增 `.navigation` 槽位，回退图标和可点击改名标题各自是独立按钮；`DocumentEditor.swift:199-224` 将旧的返回/标题 toolbar 项限定为 iOS；`DocumentEditor.swift:281-289` 将新的 leading 项先于原操作组注册。选择独立返回按钮是因为它保持 macOS 导航控件与文档标题的语义分离，并保留标题单独点击改名；share/zoom/fit/more 继续留在原 toolbar action/customization 组（`DocumentEditor.swift:112-129`）。
2. **玻璃带卡片重影**：macOS `NavigationSplitView` detail 在 `ContentView.swift:150-162` 原先对包含首页最近网格的整个 detail 使用 `.backgroundExtensionEffect()`，将 detail 内容背景延展进窗口 toolbar 背景采样区域；网格列因此可在系统标题栏玻璃中形成与列对齐的模糊影像。移除了 Mac detail 的扩展效果，保留系统标题栏玻璃；没有降低透明度、平移网格或移除玻璃。iOS split detail 的 `.backgroundExtensionEffect()` 保留在 `ContentView.swift:197-209`，其导航栏/`UIVisualEffectView` 路径不同。上述是代码层因果判断；没有实机视觉验证，待 Timmy 确认。

## 逐项排查（代码判断）

- **`.thinMaterial` + `Glass.tint` + `glassBandBottomFade`：不是重影来源**。前两者只为 chrome plate 的传入控件按 shape 绘制，见 `AppleGlassChrome.swift:310-344`；底部 alpha mask 仅施加于声明 `fadesBottomEdge` 的 plate（`AppleGlassChrome.swift:136-145,292-307`），toolbarFloatingButton 明确不淡出。它没有把网格作为背景传入。
- **`NSVisualEffectView.withinWindow`：不是当前配置下的来源**。默认是 `.light`（`AppleGlassChrome.swift:107-111`）；fallback `NSVisualEffectView` 使用 `.behindWindow`（`AppleGlassChrome.swift:448-456`）。`.withinWindow` 只存在显式 `.native` 的 header/HUD 分支（`AppleGlassChrome.swift:386-392,512-520`），不是当前默认路径。若切换 native，withinWindow 会采样同窗内容，仍需在实机核查，但不是此次默认运行路径。
- **safeAreaInset/contentInset：不是**。最近网格只在 `LibraryHome.swift:126-148` 的单一 `ScrollView`/`LazyVGrid` 内；Mac detail 之前的背景延伸来自 `ContentView.swift:150-162` 的 `.backgroundExtensionEffect()`，而非网格 safe-area inset。
- **系统 `.toolbarBackground` 与自绘 material 双层：不是**。编辑器仅在 `DocumentEditor.swift:291-295` 隐藏系统 toolbar background；标题栏没有另加一层自绘 band。保留默认系统玻璃。
- **网格重复实例：不是**。`LibraryHome.swift:126-148` 只有一处 `LazyVGrid`；没有将 grid 作为 chrome/background 子视图。
- **iOS 同现象：代码无法据此断定视觉是否同现**。iOS split 仍保留 background extension（`ContentView.swift:197-209`），但它不使用 macOS 窗口 toolbar / AppKit backdrop；玻璃 backend 分支见 `AppleGlassChrome.swift:79-94,409-421,525-543`。未进行 iOS 视觉检查，不能声称实机上绝无类似现象。

## 结构断言与反向验证

- `testMacDocumentTitleAndBackButtonOccupyLeadingNavigationRegion`（`Tests/FlorettaCoreTests/AppleGlassChromeContractTests.swift:6-30`）：断言标题/返回位于 `.navigation` leading slot、旧 `leadingDocumentChrome` 不再注入 macOS toolbar，且原操作组在后。
- `testMacTitlebarGlassDoesNotExtendTheHomeGridIntoItsBackdrop`（同文件 `:32-60`）：断言 Mac shell 无 background extension、iOS split 保留其路径、网格仅实例化一次且不作为 glass 背景、当前 glass backend/mask/material 分支以及 toolbar background 所有权。
- **正常运行**：`swift test --filter AppleGlassChromeContractTests` — `Executed 9 tests, with 0 failures`（2026-11-14 21:38:37）。
- **反向验证标题分区**：临时把 `placement: .navigation` 改回 `.primaryAction`，运行 `swift test --filter AppleGlassChromeContractTests/testMacDocumentTitleAndBackButtonOccupyLeadingNavigationRegion`，按预期失败：`XCTAssertTrue failed - document title/back must use the leading navigation slot...`。恢复新实现后全组测试通过。
- **反向验证重影因果**：临时把 `.backgroundExtensionEffect()` 加回 macOS detail，运行 `swift test --filter AppleGlassChromeContractTests/testMacTitlebarGlassDoesNotExtendTheHomeGridIntoItsBackdrop`，按预期失败：`XCTAssertFalse failed - Mac must not extend Home detail/grid pixels behind the window titlebar glass`。移除旧效果后全组测试通过。

## 未验证 / 待验收

- **视觉未验证，需 Timmy 在构建里确认**：文档名在红绿灯右侧左区、返回与标题分开、右侧操作分区未移动；首页顶部玻璃带不再出现模糊卡片影像且玻璃仍保留。
- 未运行 GUI、截图、实机 build 或 iOS 视觉测试；未执行签名构建（按任务约束）。`swift test` 的契约测试和 `xcodebuild -list` 通过，不等同于 app build/视觉验收。
- `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` 未修改；未碰 LocalAsk、模拟器 shutdown 或钥匙串。

## 提交

- `94a98d6` — `fix(mac): place document title in leading toolbar region`（含 macOS 旧 toolbar 标题入口隔离）
- 第二个提交包含背景延伸修正、结构断言及本文件。
