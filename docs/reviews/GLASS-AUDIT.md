# Liquid Glass 全界面盘点

审计对象：`feat/liquid-glass-shell`，基线 `origin/main` `a28cde9fc35250457134b85e03db0d89a722e002`。
部署目标已经是 iOS 26 / macOS 26。官方路径在 `AppleGlassChrome.swift`：优先 `GlassEffectContainer` + `glassEffect(.regular, in:)`；macOS 无法走 SwiftUI 时再回退到运行时查找的 `NSGlassEffectView`，最后才是 `NSVisualEffectView`（`.sidebar` / `.underWindowBackground`，`blendingMode: .behindWindow`）。该文件按契约不得写入手绘 `blur`、`ultraThinMaterial`、`regularMaterial` 或黑白洗衬。低于 26 的 iOS 保持不绘制替代模糊。

本表覆盖主界面与编辑器壳层。内容层（画布、最近列表、设置表单正文、缩略图）保持可读，不上玻璃。

| 区域名 | 文件:行号 | 当前实现（改前 → 改后） | 是否符合液态玻璃 | 计划 / 结果 | 用的 API |
| --- | --- | --- | --- | --- | --- |
| iPad 主界面可展开侧边栏（`NavigationSplitView` sidebar） | `ContentView.swift:191-202`，列表本体 `LibraryHome.swift:159-180` | 改前：`HomeSidebar` 仅 `.listStyle(.sidebar)`，列背景未上官方玻璃，展开后看起来是实心栏。改后：列表 `.scrollContentBackground(.hidden)`，列背景走共享 token，detail 使用 `backgroundExtensionEffect()` 把最近列表等内容延伸到侧栏下方供折射。 | 改前不符合；改后符合 | 已改为官方玻璃 | `appleGlassChrome(.sidebarColumn)` → `GlassEffectContainer` + `glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))`；`backgroundExtensionEffect()` |
| macOS 主窗口侧边栏 | `ContentView.swift:134-155` | 改前：`.scrollContentBackground(.hidden)` + `.background(.regularMaterial)`，是系统材质不是 Liquid Glass。改后：同一 `sidebarColumn` token，detail 同样加 `backgroundExtensionEffect()`。 | 改前不符合；改后符合 | 已改为与 iPad 共用的 AppShell token，不另写一套 | 同上 |
| 顶部工具栏（编辑器） | `DocumentEditor.swift:177-266` | iOS 返回键已是 44pt 圆形 + `.appleGlassChrome(.iconButton)`。撤销/重做/删除/插入/分享/缩放/沉浸等走 `.toolbarFloatingButton`；该 role 在 iOS 是 no-op，因为系统 toolbar item 已提供官方玻璃与圆形命中区，再套一层会把返回键 AX 框缩小并挤掉 `editor.more`。macOS 自定义工具栏按钮走同一 modifier 的官方玻璃。工具栏背景保持 `.toolbarBackground(.hidden)`，让系统玻璃按钮浮在画布上。 | 已符合（先前 PR）；本 PR 未改行为 | 保持 | iOS：系统 toolbar glass；macOS / 需要时：`glassEffect(.regular, in: Capsule())`。不使用 `.glassProminent` 以免把普通工具按钮标成强调样式。 |
| 主页顶栏（最近页） | `LibraryHome.swift:28-72`（iOS）、`76+`（macOS） | 系统 `ToolbarItem` / `Menu`。iOS 刻意拆成独立项，避免旧版三图标自定义胶囊。系统导航栏已自动采用 Liquid Glass。 | 已符合 | 保持系统栏，不套第二层玻璃（契约测试 `HomeChromeContractTests` 禁止在这段自定义背景/胶囊） | 系统 NavigationBar / Toolbar Liquid Glass |
| 右侧检查器（样式 / 演说 / 导图） | `DocumentEditor.swift:172-174, 1261-1272, 1333`；表单 `appleGlassInspectorFormPlate()` 约 1405 起 | iOS：整列 `.appleGlassChrome(.inspectorPanel)`，分段控件 `.segmentedContainer`，表单 `scrollContentBackground(.hidden)` 让玻璃透出来，内部 Slider / ColorPicker / Toggle 保持原生。macOS：`inspectorPanel` 在 `AppleGlassChrome` 里仍是 no-op，避免在系统 `.inspector` 列上再叠一块圆角板；macOS 26 的系统 inspector 本身提供 Liquid Glass。 | iOS 已符合；macOS 刻意走系统列，不二次包装 | 保持。未把 macOS `inspectorPanel` 改成再绘一层 | iOS：`glassEffect(.regular, in: RoundedRectangle(16))`；macOS：系统 `inspector` |
| 左侧大纲面板（编辑器内可展开） | `DocumentEditor.swift:522-526, 680-717`；列表 `OutlineView.swift:65-66` | 改前：`.background(.regularMaterial)`。改后：`.appleGlassChrome(.sidebarColumn)`，大纲列表隐藏滚动背景。面板上的展开/关闭按钮本来就是 `.iconButton` 玻璃。 | 改前不符合；改后符合 | 已改 | `appleGlassChrome(.sidebarColumn)` / `.iconButton` |
| 底部 Tab（iOS 主界面） | `ContentView.swift:117-132` | 原生 `TabView` + `.tabViewStyle(.tabBarOnly)`。注释写明不自绘 Tab、不自定义玻璃/模糊/胶囊。系统 Tab 栏在 iOS 26 自动是 Liquid Glass。 | 已符合 | 保持原生 TabView，不自绘 Tab 栏 | 系统 `TabView` Liquid Glass |
| 悬浮工具按钮（画布上的便签色板、专区锁定条等） | `InfiniteCanvas.swift:648, 822`；编辑器画布页签按钮 `DocumentEditor.swift:632` | 已走 `.appleGlassChrome(.bottomBarCapsule)`。 | 已符合（先前 PR） | 保持 | `glassEffect(.regular, in: Capsule())` |
| 画布音频播放条 | `CanvasAudioPlaybackBar.swift:45` | 改前：`.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))`。改后：`.appleGlassChrome(.floatingPanel)`。 | 改前不符合；改后符合 | 已改 | `glassEffect(.regular, in: RoundedRectangle(16))` |
| 底栏状态条与画布页签条 | `DocumentEditor.swift:551-574, 587-609` | 改前：`.background(.bar)`，状态条还叠了一条 `Divider`。改后：`.appleGlassChrome(.floatingPanel)`，去掉硬分割线，改用玻璃边缘。 | 改前是系统 bar 材质，不是 Liquid Glass；改后符合 | 已改 | `appleGlassChrome(.floatingPanel)` |
| 标签筛选条 | `DocumentEditor.swift:643-660` | 已是 `.appleGlassChrome(.bottomBarCapsule)`。 | 已符合 | 保持 | `glassEffect(.regular, in: Capsule())` |
| Markdown 模式横幅与提示条 | `DocumentEditor.swift:719-750` | 改前：`.background(.regularMaterial)`。改后：`.appleGlassChrome(.floatingPanel)`。 | 改前不符合；改后符合 | 已改 | `appleGlassChrome(.floatingPanel)` |
| 菜单 / 上下文菜单 | `DocumentEditor.swift:300`（节点 context menu）、工具栏 `Menu`（约 1003–1138）；macOS `FlorettaApp.swift:86-157` 的 `CommandMenu` | 全部为系统 `Menu` / `CommandMenu` / `contextMenu`。iOS 26 / macOS 26 系统菜单自动采用 Liquid Glass。 | 已符合 | 保持系统菜单，不自绘菜单背景 | 系统 Menu / contextMenu / CommandMenu |
| 沉浸（Zen）模式控件 | `DocumentEditor.swift:147-149, 773-785` | 退出按钮已是 44pt 圆形 + `.appleGlassChrome(.iconButton)`。进入沉浸后工具栏/侧栏/状态栏按 `zenChrome` 隐藏，只留这块玻璃退出键。 | 已符合（先前 PR，含 44pt 命中区修复） | 保持 | `glassEffect(.regular, in: Circle())` |
| 弹窗 / Sheet 背景 | `ContentView.swift:37-67` 恢复与错误 alert；`DocumentEditor.swift:346-478, 612-619` 的 confirmationDialog、alert、About / 快捷键 / 主题 / 预览 / 标签筛选 / 历史 sheet | 全部是系统 `.alert` / `.confirmationDialog` / `.sheet`。系统在 26 上为这些容器提供官方玻璃或标准材质。未把 sheet 里的长文本或表单再套一层玻璃，以免对比度崩塌。 | 系统容器符合；内容层刻意不上玻璃 | 保持系统呈现，不包装内容 | 系统 alert / sheet / confirmationDialog |
| 设置页、最近列表、模板缩略图、画布纸面 | `LibraryHome.swift` 的 `RecentPage` / `SettingsView` / `NewMapPage`；`InfiniteCanvas` 画布纸；`TemplateThumbnail.swift` 节点色块 | 内容层：列表、表单、长文本、画布。缩略图和节点填充是文档内容色，不是壳层。 | 刻意不符合「整页上玻璃」——这是内容层 | 不上玻璃。若将来要让某块内容「看起来有玻璃」，用玻璃容器 + 内层实心内容卡 | 无（保持可读） |
| 共享扩展组成页 | `Share/ShareComposeView.swift` | 独立扩展 UI，inset 列表 + 系统 sheet。不是主应用壳层。 | 本轮不改 | 保持系统表单 | 系统 sheet / list |

## 刻意不上（或不二次包装）玻璃的区域

1. **内容层**：画布、最近文档列表、设置与表单正文、NOTICE 文本、模板缩略图。玻璃只用于悬浮/功能壳层。
2. **iOS 系统 Tab 栏与主页顶栏按钮**：已经是系统 Liquid Glass；再包一层会破坏命中区和契约测试。
3. **iOS 编辑器工具栏按钮**（`.toolbarFloatingButton` no-op）：理由同上，先前已踩过返回键 AX 框缩小和 `editor.more` 消失的问题。
4. **macOS 系统 inspector 列**：`inspectorPanel` 保持 no-op，避免两块玻璃叠在一起。
5. **系统 Menu / alert / sheet**：由系统绘制；不把手绘模糊或半透明白块填进内容。

## 共享 token

新 role：

- `sidebarColumn`：iPad 主侧栏、macOS 主侧栏、编辑器大纲列。圆角 24。
- `floatingPanel`：状态条、画布页签条、Markdown 横幅/提示、音频条。圆角 16。

两平台共用 `appleGlassChrome`，不写第二套实现。

## 验收记录（Asia/Shanghai，CST）

### 编译

- iOS：`xcodebuild build -project Floretta.xcodeproj -scheme Floretta-iOS -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" -derivedDataPath /tmp/glass-ios`
  - 窗口：2026-11-12 12:21:04–12:22:02 CST
  - 结果：`** BUILD SUCCEEDED **`，日志中 `error:` 计数 0，exit 0
  - 日志：`/tmp/glass-ios-build.log`
- macOS：`xcodebuild build -project Floretta.xcodeproj -scheme Floretta-macOS -destination 'generic/platform=macOS'`（同样的 CODE_SIGNING_* 关闭），`-derivedDataPath /tmp/glass-macos`
  - 窗口：2026-11-12 12:21:05–12:22:06 CST
  - 结果：`** BUILD SUCCEEDED **`，`error:` 计数 0，exit 0
  - 日志：`/tmp/glass-macos-build.log`

未改签名配置。未改 `docs/FEATURES-CHECKLIST.md`、`docs/STATUS.md`、`docs/SMOKE.md`、`docs/VERIFY.md`。

### 截图

在 iPad 模拟器 `ASC-iPadPro13-M5`（UDID `330B63B2-5EE7-477E-B564-EE7C02161EE5`）上安装并启动当前源码的 `Floretta-iOS`，用 XCUI 截下真实模拟器像素（与 `simctl io screenshot` 等价）。截图能看出侧栏浮层、背景模糊和边缘高光，不是纯色块：

- `docs/reviews/glass-sidebar-expanded-light.png` — 浅色，侧栏展开
- `docs/reviews/glass-sidebar-collapsed-light.png` — 浅色，侧栏收起
- `docs/reviews/glass-sidebar-expanded-dark.png` — 深色，侧栏展开
- `docs/reviews/glass-sidebar-collapsed-dark.png` — 深色，侧栏收起（顺手补拍）
