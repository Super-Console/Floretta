# 路线图

这是 Floretta 唯一的进度文档（原 `docs/STATUS.md` 已并入本文后删除）。功能合入后只更新这一份。顶部「本轮」每轮覆盖；下面的矩阵用统一状态词；更早的申报与流水记在文末历史记录里。

## 本轮

- 本轮进度：PR #119 已开、未合并（基线 `8e50c1212d9f784ec6b38ba434f8c77cb9206cf6`）。双入口共用 `AppSettings`、三模式可切、经典改非衬线可持久化，见 `docs/THEME-MODES.md`。包体 iOS 12.3 MB / macOS 18.4 MB；思源宋体子集 4,876,368 bytes 未打包。画布三张（classic / modern / classic-sans）已用同一份中英日韩+换行文档重拍（22:56:04–22:57:01 CST）。iPad 模拟器没有宋体和 AppleMyungjo，经典中文回退 PingFang，韩文回退 SD Gothic，据实写在 `THEME-MODES.md`，不把 PingFang 写成宋体。E2：同一 XCUITest 启动器+PR #117 探针、500 节点对照：merge-base `8e50c12` 平移/缩放/拖动平均 FPS 59.7 / 57.3 / 59.7（23:16:56 CST）；`fae6453` 曾回归到 1.0 / 0.8 / 0.9。已按 (family, design, size) 缓存 CTFont（不再用 `Font.system(design:)` 当画布路径），修复后 59.3 / 53.7 / 59.7，峰值内存 105.5 MB（23:34:47 CST）。EB Garamond 对照图见 `docs/reviews/theme-modes/latin-eb-garamond.png`（23:33:32 CST）。矩阵里的已知缺口没有抹掉。
- 下一步：等 Censor 审 PR #119，不合并。并行待办仍是 Quick Look 扩展包 ID 发布阻塞、A27 空态与钉住、`-FlorettaEditChrome` 开窗、补 macOS / iPhone 玻璃截图、音视频 / iPad 蓝牙键盘 / 组字保护的真机验收，以及 FlorettaWeb 自 2026-11-11 04:29:43 CST 之后的同步。
- 阻塞：1.0(9) 上传因 Quick Look 扩展包 ID 两段后缀 `quicklook.preview` / `quicklook.thumbnail` 被拒。当时构建是 `CURRENT_PROJECT_VERSION = 9`（`811b2f5`，2026-11-10 21:33:57 CST），ID 为 `net.timhuang.floretta.quicklook.preview` 与 `net.timhuang.floretta.quicklook.thumbnail`。其后 PR #90 → main `9885b13`（2026-11-11 01:47:58 CST）改为 `net.timhuang.floretta.qlpreview` / `net.timhuang.floretta.qlthumbnail`，本分支 `project.pbxproj` 仍是这一对；没有成功重传 App Store Connect 的证据，故不能算已交付。另：A27 空态仍无法读取；`-FlorettaEditChrome` 启动后 AX 只有菜单栏（2026-11-12 19:32:59 CST 复现）。

状态词只用：✅ 已交付 / 🚧 进行中(PR#) / ❌ 缺失 / ⛔ 不做(原因)。证据列只写已存在的 PR、提交、路径或已核验的时间。不得用 ✅ 掩盖未收口项。

## 功能矩阵

| 功能 | macOS | iPad | iPhone | Web | 证据 |
| --- | --- | --- | --- | --- | --- |
| 首页与文档库 | ✅ 已交付 | ✅ 已交付 | ✅ 已交付 | ✅ 已交付 | 原生：PR #42 → main `cbd2dba`；`Floretta/Shared/Shell/LibraryHome.swift`。网页：`docs/WEB-PARITY.md`（2026-11-11）写明已同步；FlorettaWeb origin/main `ecdf695`（2026-11-11 04:29:43 CST，PR #11） |
| 界面本地化（zh-Hans / en） | ✅ 已交付 | ✅ 已交付 | ✅ 已交付 | ✅ 已交付 | 原生：PR #46 → main `4848d35`；`Floretta/Shared/Localizable.xcstrings`。网页：FlorettaWeb README 写明中英界面；介绍页与网关按语言分流（PR #8 / #9） |
| 双边画布布局与节点编辑 | ✅ 已交付 | ✅ 已交付 | ✅ 已交付 | ✅ 已交付 | 原生：`FlorettaCore/Layout/LayoutEngine.swift`；`Floretta/Shared/Canvas/InfiniteCanvas.swift`；P1-b / P1-c 验收见下文历史记录。网页：`docs/WEB-PARITY.md` 大纲编辑、画布与检查器已同步 |
| 键盘映射 | ✅ 已交付 | ✅ 已交付 | ✅ 已交付 | ❌ 缺失 | 原生快捷键：`FlorettaCore/Keyboard/KeyboardCommandMapper.swift`；XMind 快捷键 PR #114 → main `8013478`。网页快捷键是否对齐未在 `docs/WEB-PARITY.md` 证实。iPad 蓝牙键盘见下行，不得并入本行的 ✅ |
| iPad 蓝牙键盘 | ⛔ 不做(iPad 项) | ❌ 缺失 | ⛔ 不做(iPad 项) | ⛔ 不做(不适用) | `docs/REVIEW-CHECKLIST-2026-11-12.md` B4（连实体键盘，Space / Enter / Tab）。仅有模拟器/代码路径，未在真机连蓝牙键盘验收 |
| 输入法组字保护 | ❌ 缺失 | ❌ 缺失 | ❌ 缺失 | ❌ 缺失 | 代码有 `isComposing` 守卫（`KeyboardCommandMapper`），不得据此标 ✅。`docs/SMOKE.md` 第 3 条仍为「未通」；`docs/VERIFY.md` 实验 A 未勾；`docs/reviews/A24-smoke-coverage.md` 写明不验证键入或中文组字；`docs/REVIEW-CHECKLIST-2026-11-12.md` B5。仅模拟器/单测，未在真机验收 |
| 大纲视图（同一份文档） | ✅ 已交付 | ✅ 已交付 | ✅ 已交付 | ✅ 已交付 | 原生：`Floretta/Shared/Outline/OutlineView.swift`；P1-d 验收见下文历史记录。网页：`docs/WEB-PARITY.md` 已同步 |
| 导入导出（.floretta / .mm / OPML / Markdown / XMind / TextBundle / PNG / PDF） | ✅ 已交付 | ✅ 已交付 | ✅ 已交付 | 🚧 进行中(无 PR) | 原生：`.mm` `b51b8c5`；OPML/Markdown 合流 `4c51de7`；PNG/PDF `1b277ce`；XMind PR #43 → `4aed816`；TextBundle PR #45 / #103。网页：`docs/WEB-PARITY.md` 写明常见格式已同步，但 PDF 仅为单页 JPEG 图像 PDF，不是打印面板；FlorettaWeb PR #11（`ecdf695`）提供工程 ZIP 导入导出 |
| 附件（模型、图片、任意文件） | ✅ 已交付 | ✅ 已交付 | ✅ 已交付 | 🚧 进行中(无 PR) | 原生：PR #30 → `8f64c32`；PR #34 → `c80d138`；PR #35 → `59aa8a0`。网页：`docs/WEB-PARITY.md` 为「部分」（工程 ZIP 与 `assets/<sha256>`，完整 App 打开兼容性未独立确认） |
| 节点级音视频真机播放 | ❌ 缺失 | ❌ 缺失 | ❌ 缺失 | ❌ 缺失 | 检查单 B5 / B6 仍为 `[~]`（PR #96 单测通过、AVPlayer 已接入；音频帧率/内存与 GUI 验收未测，iOS/macOS 最新完整构建及 GUI 验收未完成）。仅模拟器路径，未在真机验收播放。不得标 ✅ |
| 自由节点与便签 | ✅ 已交付 | ✅ 已交付 | ✅ 已交付 | ❌ 缺失 | 原生：PR #36 → `31a7740`；PR #38 → `dfd7af9`。`docs/WEB-PARITY.md` 未列此项，未核实网页是否已有 |
| 关系线、概要/边界、标签筛选、分支配色 | ✅ 已交付 | ✅ 已交付 | ✅ 已交付 | ❌ 缺失 | 原生：PR #48 → `22a48dd`；PR #51 → `37a97aa`；PR #53 → `fd97255`；PR #55 → `88d50e9`。`docs/WEB-PARITY.md` 未逐项列出，未核实网页是否已有 |
| 版本快照与回滚 | ✅ 已交付 | ✅ 已交付 | ✅ 已交付 | ❌ 缺失 | 原生：PR #40 → `20ffc7b`；PR #64 → `b0fb7fc`。`docs/WEB-PARITY.md` 未列，未核实 |
| 分享扩展与语音输入 | ✅ 已交付 | ✅ 已交付 | ✅ 已交付 | ⛔ 不做(Apple 系统扩展，网页不适用) | PR #57 → `2bf1f4a`；PR #58 → `536f6c8`。`docs/WEB-PARITY.md` 列为不适用 |
| Markdown 一等文档 | ✅ 已交付 | ✅ 已交付 | ✅ 已交付 | ❌ 缺失 | 原生：PR #62 → `5631b42`。FlorettaWeb `09adf46` 将「Markdown as document」标为 planned, not shipped（未把该提交以后的变更再核一次） |
| Finder Quick Look | ❌ 缺失 | ⛔ 不做(macOS Finder 插件) | ⛔ 不做(macOS Finder 插件) | ⛔ 不做(不适用，Apple 平台能力) | 功能实现已合入 PR #67 → `a9ad9b92`，但不能标 ✅：1.0(9) 上传因扩展包 ID 两段后缀 `quicklook.preview` / `quicklook.thumbnail` 被拒（构建 `811b2f5`，2026-11-10 21:33:57 CST）。PR #90 → `9885b13`（2026-11-11 01:47:58 CST）把当前 `project.pbxproj` 改为 `net.timhuang.floretta.qlpreview` / `qlthumbnail`；无成功重传证据，仍是发布阻塞。扩展点标识仍是 `com.apple.quicklook.preview` / `com.apple.quicklook.thumbnail`（系统规定，不是包 ID） |
| 同一文档多窗口 | ✅ 已交付 | ⛔ 不做(该能力按 macOS 交付) | ⛔ 不做(该能力按 macOS 交付) | ⛔ 不做(不适用，浏览器标签语义不同) | PR #66 → `5d6b994`；`docs/FEATURES-CHECKLIST.md` G6。`docs/WEB-PARITY.md` 列为不适用 |
| CLI 与 MCP | ✅ 已交付 | ⛔ 不做(命令行组件) | ⛔ 不做(命令行组件) | ⛔ 不做(网页仓库列为不做) | PR #71 → `dbde570c`。`docs/WEB-PARITY.md` 写明网页不做 MCP / CLI |
| 底栏字数与无底板状态条 | ✅ 已交付 | ✅ 已交付 | ✅ 已交付 | ❌ 缺失 | 实现：PR #75 → `658b0c37`；PR #115 → `e20c28d`。截图：`docs/reviews/statusbar-macos-light.png`、`statusbar-macos-dark.png`（随 PR #118 合入 `8e50c12`，提交 `1df65eb` 2026-11-12 19:40:01 CST；文件存在，不得报缺失）；另有 `statusbar-ipad-light/dark.png`、`statusbar-iphone-light/dark.png`、`statusbar-overflow-menu.png`、`statusbar-settings-about.png`。`docs/WEB-PARITY.md` 未列网页底栏 |
| Liquid Glass 外壳 | ❌ 缺失 | ✅ 已交付 | ❌ 缺失 | ⛔ 不做(无法提供系统液态玻璃，仅能 CSS 等效) | 实现：PR #113 → `70801fa`；审计 `docs/reviews/GLASS-AUDIT.md`。已入树截图只有 iPad 模拟器侧栏四张：`glass-sidebar-expanded/collapsed-light/dark.png`（`GLASS-AUDIT.md` 写明拍自 `ASC-iPadPro13-M5`）。仓库中没有 macOS 或 iPhone 玻璃观感截图；`docs/REVIEW-CHECKLIST-2026-11-12.md` C2 仍记「macOS 端状态栏/玻璃截图」缺玻璃这一半。网页：`docs/WEB-PARITY.md` 为 CSS `backdrop-filter` 等效 |
| 节点折行 | ✅ 已交付 | ✅ 已交付 | ✅ 已交付 | ❌ 缺失 | 原生：PR #116 → `e373a04`；`docs/reviews/LINEBREAK-AUDIT.md`。`docs/WEB-PARITY.md` 未列网页折行验收 |
| 画布平移/拖拽性能 | ✅ 已交付 | ✅ 已交付 | ✅ 已交付 | ❌ 缺失 | 原生：PR #117 → `918e43f`；`docs/reviews/CANVAS-PERF-RESULT.md`。网页性能未在该审计中核实 |
| macOS 辅助功能树 | 🚧 进行中(PR #118 已合入，仍有残留) | ⛔ 不做(#118 修的是 macOS AX 空树) | ⛔ 不做(#118 修的是 macOS AX 空树) | ⛔ 不做(不适用，Apple 辅助功能) | PR #118 → main `8e50c12`（2026-11-12 19:50:18 CST）用延迟打开文档，让首页 WindowGroup 能建窗。残留：`-FlorettaEditChrome` 启动仍不创建窗口，2026-11-12 19:32:59 CST 复现，AX 只有菜单栏。Censor 明确不能算已修好；`8e50c12` 的 deferred-open 不是完全收口。见 `docs/reviews/A27-inspector-pin-mac.md` |
| A27 检查器钉住 | ❌ 缺失 | ⛔ 不做(A27 是 macOS 验收项) | ⛔ 不做(A27 是 macOS 验收项) | ⛔ 不做(不适用) | `docs/reviews/A27-inspector-pin-mac.md`；PR #118。当前构建仅读到选中态：Style MINY=94.0，FRAME=945.0,94.0,50.0,24.0（2026-11-12 19:32:26–19:32:27 CST）。空态仍「无法读取」：Escape 或点击空白画布会收起 inspector 列，树里没有 `inspector.tabs` /「样式」/ `inspector.empty`。钉住/锁定验收未完成，不得标 ✅ |
| 外观三模式（经典 / 现代 / 自定义）与开源字体 | 🚧 进行中(PR #119) | 🚧 进行中(PR #119) | 🚧 进行中(PR #119) | ❌ 缺失 | 骨架 `06afca1`；字体 `b4c3ece`；双入口 `ba98953`；见 PR #119 与 `docs/THEME-MODES.md`。共享状态、立即同步、经典+非衬线持久化、标识前缀已在 `AppearanceSettingsTests` 验证（2026-11-12 21:37:44 CST）。画布重拍与 iPad 字体回退见 `docs/THEME-MODES.md`（22:56:04–22:57:01 CST）。E2 对照见 `docs/THEME-MODES.md`：`8e50c12` 为 59.7 / 57.3 / 59.7 FPS；缓存 CTFont 后本分支 59.3 / 53.7 / 59.7，峰值内存 105.5 MB。FlorettaWeb 自 `ecdf695` 后再无提交，未接入三模式 |
| 网页版应用 | ⛔ 不做(Web 资产，非原生 App) | ⛔ 不做(Web 资产，非原生 App) | ⛔ 不做(Web 资产，非原生 App) | ✅ 已交付 | 官方仓库 Super-Console/FlorettaWeb。origin/main tip `ecdf695`（2026-11-11 04:29:43 CST）合并 PR #11 工程导入导出，此前 PR #10 为主题与图标。线上 `https://apps.timhuang.net/floretta/app/` HTTP 200，`Last-Modified: Tue, 10 Nov 2026 20:29:48 GMT`（2026-11-11 04:29:48 CST），与 tip 时刻一致。此后至本轮记录时未见新提交；未与原生 2026-11-12 的 #113–#118 同步。对照 App 仓 `docs/WEB-PARITY.md`（写明更新日期 2026-11-11） |
| 官网展示页 | ⛔ 不做(Web 资产，非原生 App) | ⛔ 不做(Web 资产，非原生 App) | ⛔ 不做(Web 资产，非原生 App) | ✅ 已交付 | 同一 FlorettaWeb 仓库的语言网关与介绍页（`/floretta/`、`/zh/`、`/en/`；PR #7–#9，主题对齐随 PR #10）。线上 `https://apps.timhuang.net/floretta/` HTTP 200，`Last-Modified` 同上（2026-11-11 04:29:48 CST）。原「产品网站」行并入本行；App 仓 PR #98 只是文档纪律，不是网页实现 |
| Windows / Linux 客户端 | ⛔ 不做(F5 结论为 UI 须重写，尚未开工) | ⛔ 不做(非该端) | ⛔ 不做(非该端) | ⛔ 不做(非该端) | `docs/FEATURES-CHECKLIST.md` F5；`docs/HANDOFF-WINDOWS-ANDROID.md` |

## 历史记录（原 docs/STATUS.md）

## 当前阶段

P0-1 已由总指挥验收（合并 `ef9e4f2`；本机 `xcodebuild` macOS 与 iOS Simulator 均为 BUILD SUCCEEDED，`UIDeviceFamily = [1, 2]`）。

P0-2 已由总指挥验收（11 个测试，TEST SUCCEEDED）。P0-3 不再单开（那些测试已随 P0-2 落地）。

P0-4 已由总指挥验收（20 个测试全绿）。P0 阶段通过。

P1-1 已由总指挥验收（24 个测试全绿）。触控板手势留到 P1-c 再人工验。

P0.5 已由总指挥验收（32 个测试全绿）。DocumentGroup、实验 A/B 没做。

P1-b 已由总指挥验收（46 个测试全绿，含 S 曲线曲率断言）。触控板手势这批仍不验。

P1-c 修复已由总指挥验收（58 个测试全绿，TEST SUCCEEDED）。

P1-r 已由总指挥验收（60 个测试全绿，合并 `538b0d2`）。

P1-d 已由总指挥验收（67 个 macOS 测试全绿；iOS Simulator BUILD SUCCEEDED）。

P2-1 `.mm` 已由总指挥验收（macOS 74/0，iOS EXIT=0，合并 `b51b8c5`）。

P2-2 OPML 与 Markdown 已由总指挥验收（macOS 80/0，含 6 个 OPMLMarkdownTests；iOS EXIT=0，合并 `4c51de7`）。

P2-3 PNG / PDF 已由总指挥验收（macOS 85/0，iOS EXIT=0，合并 `1b277ce`）。

P3 App 图标已落盘：参考图的纸面和水彩原样保留，白边、投影和旧圆角边用内侧纸纹补成满幅正方形。sRGB，无 alpha。深色变体没有另做（见 `docs/app-icon.md`）。这台云机器没有 `sips`，也没有 Xcode，没有跑 `xcodebuild`。

Cloud cannot run Xcode; local Mac will pull and xcodebuild; build errors will be pasted back for fixes.

## 下一步

本机 Mac 拉取后运行：

```bash
xcodebuild test -project Floretta.xcodeproj -scheme Floretta-macOS -destination 'platform=macOS'
echo EXIT_MACOS_TEST=$?
xcodebuild build -project Floretta.xcodeproj -scheme Floretta-iOS -destination 'platform=iOS Simulator,name=iPhone 16'
echo EXIT_IOS_BUILD=$?
```

构建或测试错误贴回再改。通过后再放行下一批。图标还要用 `sips -g pixelWidth -g pixelHeight -g hasAlpha -g space` 对每个尺寸复核，并看四角不是纯白。

## P1-r 申报

按 `docs/REUSE.md` 的 P1-r-1…P1-r-4。结论写在 `docs/REUSE-AUDIT.md`，第三方记录在根目录 `NOTICE`。

- **SwiftFlow** `v0.3.1`（commit `98ff46633257d188f1819255df8c8453a9b72d8f`，根 `LICENSE.md` 是 MIT，版权 A.Aurelions）。三个 target 都链这个 SPM 产品。`CanvasViewport` 用它的 `Viewport`、`SwiftFlowInstance.screenToFlowPosition` / `flowToScreenPosition` / `zoomTo`，以及 `getViewportForBounds`。命中测试用 `getIntersectingNodes`，后画的节点 `zIndex` 更高。`LayoutEngine` 没换。没有改用它的整块 `SwiftFlow` 视图。
- **Mindscape** `0.7.0`（`258dfe9`，MIT）只对照了组字。组字不走 `textDidChange`，所以 macOS / iOS 文本框在 `setMarkedText` / `unmarkText` 时把组字写进节点，编辑框先按文字宽度撑开，候选框仍由系统文本框贴在插入点上。没有拷它的源文件。`isComposing == true` 时映射仍然返回空。
- **Brainstorm**、**SimpleMindMap**、**Freeplane** 的结论在审计里。Freeplane 是 GPL-2.0，没有复制代码。

云上没有解析 Swift 包，也没有跑 `xcodebuild`。

## P1-d 申报

大纲是同一棵树的第二个系统控件视图，不是另一份数据。`docs/REUSE-AUDIT.md` 原先没有大纲专节；对照过的 Mindscape / Brainstorm 都没有可复用的 SwiftUI 大纲，Freeplane 的大纲不能拷。所以视图自研，模型仍是 `MindMapDocument`。

- `List` 的选中绑定就是 `MindMapKeyboardSession.selectedNodeID`，画布画选中框也读这个 id。
- 大纲里改字走 `replaceEditingText`，节点 `text` 立刻变，画布下一帧按新文字排。
- 画布 Tab 新建的子节点在 `children` 里，大纲按 id 列出。
- 同一层用系统 `onMove` 改兄弟顺序。拖到另一行上用系统 `draggable` / `dropDestination` 改父节点，并拒绝拖进自己的子孙。`LayoutEngine` 仍按 `children` 顺序排，算法没改。
- 方向键仍由 `KeyboardCommandMapper` 变成 `moveSelection`。大纲表面按可见行上下走，左右只改选中（父节点 / 第一个已展开的子节点），不搬动节点。
- `isComposing` 时映射仍是空。
- 折叠只改那个节点的 `isCollapsed`。行身份是 UUID，展开时只读取这一层的子 id。

## P1-c 申报

键盘映射是纯函数 `KeyboardCommandMapper.map`。输入是按键、修饰键、模式（command / edit）、`isComposing`。画布和系统文本框都先调它，再改文档。

- **命令模式**：Tab 新建子节点并进入编辑；Enter 在当前节点后面新建同级并进入编辑；Space 进入编辑；方向键移动选中；Backspace、正向 Delete、⌘Backspace 删除选中节点。Mac 大键印的是 delete，全尺寸键盘另有正向 Delete，两种都删节点。
- **编辑模式**：Tab / Space / 方向键 / Delete / ⌘Z 不建节点、不删节点。Enter 提交文字并回到命令模式（不新建同级；再按一次 Enter 才新建）。Shift+Enter 在文字里插入换行。Esc 取消编辑并还原进入编辑时的文字。编辑中的 Tab 由文本框吃掉，避免系统把焦点移走。
- **组字**：`isComposing == true` 时映射一律返回空，Esc、Enter、方向键、Delete、撤销都不触发。组字结束后恢复。
- **方向键**：上下只在同一父节点的兄弟间走。左右优先走本节点该侧的子节点，多个时按垂直距离取最近，再比水平距离。该侧没有子节点、父节点又在这一侧时回到父节点。否则跨分支，仍取该侧最近的节点。
- **撤销**：自管栈，不用系统 UndoManager。覆盖新建、删除、提交后的文字修改、折叠/展开。一次编辑会话算一步；Esc 还原文字但不入栈。⌘Z / ⇧⌘Z 只在命令模式生效，iOS 外接键盘用同一组修饰键。拖拽撤销不在这批。
- 编辑框是系统 `NSTextView` / `UITextView`，不是自绘控件。组字期间不把标记文本写回覆盖。

`Floretta-macOS`、`Floretta-iOS`、`FlorettaTests` 都编译这些文件。`KeyboardTests` 直接测映射、最近节点和撤销，不靠界面事件。云上没有 Xcode，没有跑过 `xcodebuild`。

## P1-b 申报

`LayoutEngine.layout` 只做 bilateral，输出 `[NodeFrame]`（位置、尺寸、S 曲线、层级样式）。画布按这些参数描边填色，不画阴影。

- 一级子节点按两侧子树总高度贪心分边：哪边加上后更矮就放哪边；两边一样高时先放右侧。不是奇偶固定。父节点在整棵子树高度里垂直居中，左右两列也对着这个中心排。再往下继续向外侧长。
- 字号：中心 30pt，一级 20pt，二级 18pt，更深 16pt。宽高来自 Core Text（Helvetica）测量。缓存键是文本 + 字号 + 最大宽度。同一层级用该层最大高度，宽度按文字收缩并封顶。兄弟纵向间距固定（`siblingGap`）。
- 连线从父节点朝向子节点那条边的中点，到子节点朝向父节点那条边的中点。三次贝塞尔，控制点与端点同高，形成 S 形。越深线越细。颜色跟一级分支色走，孙节点继承。调色板是通用色，不是 XMind 图标或品牌色。
- 样式参数：中心白底、黑边、黑字；一级实心分支色、白字；更深浅填色、黑字。`showsShadows` 为 false。
- 交互：`CanvasInteraction` 悬停给出上下左右四个添加方向；选中是蓝色细边加四个缩放手柄。`CanvasCommands.addFloatingTopic` 在空白处双击时加一个带手动坐标的根。添加子主题走 `addChild`。
- 画布参数：`CanvasChrome.isInfinite`、可点的缩放百分比（点一下回到 100%）、Fit、底栏多页 `sheets`（`addSheet` / `selectSheet`，这一批只是页签状态）。
- 折叠节点只留下自己，子树不测量也不输出。`position` 有值的节点按该坐标摆放，它的子孙不再自动排。格式版本仍是 1。
- 1000 个节点的测试只 `print` 耗时，不断言超时。

`Floretta-macOS`、`Floretta-iOS`、`FlorettaTests` 都编译布局源文件。云上没有 Xcode，没有跑过 `xcodebuild`。

## P0.5 申报

`.floretta` 的用户文件分成两种容器，协议是 `DocumentContainer`（`read` / `write`）：

- `LegacyJSONContainer`：现有纯 JSON，**只能读**。`write` 抛 `readOnlyLegacy`。
- `ZipContainer`：`document.json`（现有 `MindMapDocument`）+ `metadata.json`（容器版本、创建/修改时间、应用版本、默认视图 `canvas`）+ `assets/<sha256>.<ext>`。

`FlorettaDocumentFile.read` 看文件头：`PK` 走 ZIP，否则走旧 JSON。读的时候不写盘。`save` 只写 ZIP，并且是临时文件再 `replaceItemAt` / `moveItem`。目标路径如果已是旧 JSON，抛 `refusesToOverwriteLegacy`，原字节不动。另存到新路径才写出 ZIP。

附件 `addAsset` 按 SHA-256 去重，同一份字节只留一条。ZIP 条目按路径名排序后写入，所以顺序稳定。读 ZIP 时限制条目数（512）、解压总大小（32MB）、单附件（16MB）、节点数（100000）。声明的解压大小或实际 inflate 超出都拒绝。坏 ZIP、缺 `document.json` 抛错，不崩溃。

方法 8（raw DEFLATE）用项目内的 inflater 解，因为系统 Compression 框架给的是带 zlib 头的流，不是 ZIP 的 raw deflate，也没有加第三方包。我们自己写的包用存储法（method 0）。

自动保存的 `recovery.floretta` 仍是文档 JSON，不是用户文件，这批没改。没有接 `DocumentGroup`（那是 D-12）。

## P1-1 申报

无限画布用 SwiftUI `Canvas` 画节点、连线和点阵。平移缩放是视口变换（`view = canvas × scale + offset`），思路接近 SwiftFlow 的 viewport，没有抄它的代码，也没有用 Freeplane。

- 触控板 / 滚轮：平移。⌘ + 滚轮：绕指针缩放。macOS 用本地 `scrollWheel` 监听；iOS 用挂在窗口上的 `UIPanGestureRecognizer`（`allowedScrollTypesMask`），手指拖动仍交给 SwiftUI。
- 空白处拖动：平移。只有**根节点**可拖；拖完把 `MindMapPoint` 写进该根的 `position`。
- ⌘0 和工具栏 **Fit**（系统 `Button` / `Label`）把全部节点框进窗口。缩放按钮也是系统按钮。
- 当时子节点没有手动坐标时，先画在父节点右侧，只为看得见。P1-b 已换成双边布局。子节点仍不能拖。
- `position` 是可选字段，格式版本仍是 1。没有坐标时不写入 JSON，旧文件还能读。拖过的根会随自动保存进恢复副本。
- 没有恢复副本时，窗口里放一张「未命名」开场图（一个带子节点的根，一个浮动根），方便直接拖。

两边 target 都编译这些画布源文件。`CanvasTests` 在 `FlorettaTests` 里，scheme 仍是 `Floretta-macOS`。

## P0-4 申报

编辑中每 5 秒写一份临时副本。路径来自 `FileManager` 的 `applicationSupportDirectory`（`Floretta/Autosave/recovery.floretta`），没有写死绝对路径。写入先落到同目录的临时文件，再 `replaceItemAt`（文件已存在）或 `moveItem`（第一次），不把目标文件截断重写。

正常退出（macOS `applicationWillTerminate` / iOS `applicationWillTerminate`）删掉这份副本。切到后台不算退出，副本留着。异常退出不会走到清理，下次启动 `loadRecoveryCopy()` 读到副本后，用系统 `alert` 问 Recover / Discard。副本损坏时返回 `.unreadable` 并弹出失败 alert，不崩溃。

还没有用户文档的「另存为」。自动保存只动 Application Support 里的恢复副本，不覆盖用户的 `.floretta`。空白窗口上还没有编辑器；`noteEdit` 标记脏，5 秒循环和测试都调用同一个 `tick()`。

§1.1：恢复提示是 SwiftUI `alert` 和 `Button`，没有自绘控件。

测试在 `FlorettaTests`，已由 `Floretta-macOS` scheme 跑（沿用 P0-2 的接线）。覆盖：副本写成功且没有留下 `.partial`、正常清理删除副本、模拟异常退出后新的 store 能读回、损坏副本不崩溃。

## P0-2 申报

共享模型（`Floretta-macOS` 与 `Floretta-iOS` 都编译，测试 target 也编译同一份）：

- `Floretta/Shared/Model/MindMapNode.swift`：`id`（UUID）、`text`、`note`、`isCollapsed`、可选 `style`（版本 1 只有 `colorHex`）、有序 `children`
- `Floretta/Shared/Model/MindMapDocument.swift`：`title`、`createdAt`、`modifiedAt`、`formatVersion`（当前为 1）、有序 `roots`（可以多个，也可以为空）
- `Floretta/Shared/Model/FlorettaCodec.swift`：单文件 `.floretta`，JSON、UTF-8、pretty-printed、`sortedKeys` 字母序。时间戳写成 ISO-8601 UTC，精确到秒
- 类型是 `Sendable`、`Codable`、`Equatable`。没有第三方依赖

环与重复 id：内存里的节点是值类型树，JSON 也没有指针，所以文件里表达不出真正的指针环。解码时整棵树收集 id：子节点复用祖先 id 抛 `cyclicID`；其他重复抛 `duplicateID`。坏文件、非 UTF-8、缺字段、错误类型、版本不是 1，都抛 `FlorettaCodecError`，没有 `fatalError`。嵌套超过 512 层编码路径时抛 corrupt，避免恶意文件把栈打爆。

§1.1：没有改窗口，没有自绘控件，没有需要报批的自定义控件。

§1.2：看过 `docs/REFERENCES.md`。Mindscape 用 SQLite，不是单文件。Brainstorm 的 `.bs` 是另一套 JSON，仓库里没有其源码，不复制。SwiftFlow 是自由画布，不是带格式版本的有序大纲。任务书已经规定 `.floretta` 的字段，所以模型是自己写的，没有引入依赖，也没有拷贝 MIT/GPL 代码。

没有注册系统文件类型（`UTType` / `CFBundleDocumentTypes`）。codec 编译不需要它，这一批也没有文档 UI。

`docs/FORMATS.md` 仍写 `.supernode`。任务书写的是 `.floretta`。这一批没有改格式矩阵，避免把未验收的格式写成已支持。

测试：`FlorettaTests`（macOS XCTest，不挂 host app，零第三方）。已放进共享 scheme `Floretta-macOS` 的 Test 动作。`Floretta-iOS` scheme 没有挂这个 bundle，因为 XCTest bundle 是单平台的，iOS 目的地跑不了 macOS 的 `.xctest`。模型源码仍然编进 `Floretta-iOS`。

任务书里 P0-3 的「建树 → 编解码 → 结构与文字一致」和「坏文件 / 环要报错」按总指挥要求写进了 P0-2。P0-3 不再单开。没有另做 1000 节点脚本。

### 已验证

1. `command -v xcodebuild swift swiftc`：都不在 PATH。没有跑 `xcodebuild`，没有伪造测试日志。
2. Python 解析 `project.pbxproj`：61 个对象 ID，均为 24 位十六进制，引用闭合。三个 target：两个 app 的 Compile Sources 都含 `MindMapNode.swift`、`MindMapDocument.swift`、`FlorettaCodec.swift`；`FlorettaTests` 编译这三份再加上 `MindMapDocumentTests.swift`。无 package 引用。引用的源文件都在磁盘上。
3. `plistlib`：`Floretta/iOS/Info.plist` 的 `UIDeviceFamily` 仍是 `[1, 2]`。
4. 两个 scheme 的 XML 可解析。`Floretta-macOS` 的 Testable 指向 `E20000000000000000000001`（`FlorettaTests`）。

### 未验证

Cloud cannot run Xcode; local Mac will pull and xcodebuild; build errors will be pasted back for fixes.

- `xcodebuild test` 没跑。不能说测试通过，也不能说工程能编译
- Swift 6 严格并发下这些文件能否编译。本机没有 `swiftc`，也没有 Apple Foundation / XCTest SDK
- ISO-8601 往返、pretty-print 的冒号空格、`sortedKeys` 的实际字节，都没在 Apple 的 `JSONEncoder` 上见过
- 空 App Icon、签名、部署目标 26.0 这次没有复测

## 记录

| 日期 | 批次 | 结果 | 备注 |
|---|---|---|---|
| 2026-11-09 | 仓库初始化 | 完成 | 骨架、任务书、格式矩阵、参考清单落盘 |
| 2026-11-09 | 环境就绪 | 完成 | Pro 工作副本 + push 凭据实测可推 |
| 2026-11-09 | 任务书合并 | 完成 | 主线任务 + App 图标任务合并进 TASKBOOK-001；产品名定为 Floretta；图标参考图入库 |
| 2026-11-09 | 约束追加 | 完成 | 新增 D-8 原生控件 / D-9 复用开源 / D-10 TestFlight 交付；已写入 TASKBOOK 1.1、1.2、5.1 |
| 2026-11-09 | P0-1 | 总指挥验收通过 | 合并 `ef9e4f2`。本机 xcodebuild macOS 与 iOS Simulator BUILD SUCCEEDED |
| 2026-11-09 | P0-2 | 总指挥测试未过 | `testMissingAndMistypedVersionThrow`：字符串或非整数 `formatVersion` 报成「不是 .floretta JSON」，测试要「Wrong JSON type」 |
| 2026-11-09 | P0-2 修复 | 总指挥验收通过 | 11 个测试 TEST SUCCEEDED。P0-3 跳过 |
| 2026-11-09 | P0-4 | 总指挥验收通过 | 20 个测试全绿。P0 阶段通过 |
| 2026-11-09 | P1-1 | Pro 编译失败 | `CanvasScrollInput.swift` deinit 访问 `monitor: Any?`，Swift 6 报 nonisolated deinit |
| 2026-11-09 | P1-1 修复 | 总指挥验收通过 | 24 个测试全绿。触控板手势留到 P1-c 再人工验 |
| 2026-11-09 | P0.5 | 已提交，云端未测试 | DocumentContainer + 只读旧 JSON + ZipContainer（原子写、稳定顺序、哈希去重、zip bomb 上限）。不覆盖旧 JSON 原文件。云端不能跑 xcodebuild |
| 2026-11-09 | P1-b | 总指挥验收通过 | 46 个测试全绿，含 Δy ≠ 0 时 S 曲线曲率断言 |
| 2026-11-09 | P1-c | 总指挥测试 57 通过、1 失败 | `testLayoutArrowsMoveBetweenParentAndSide`：上下键把对侧、Y 更近的兄弟当成了下一节点 |
| 2026-11-09 | P1-c 修复 | 总指挥验收通过 | 58 个测试全绿，TEST SUCCEEDED |
| 2026-11-09 | P1-r | 总指挥验收通过 | 60 个测试全绿。SwiftFlow 0.3.1。合并 `538b0d2` |
| 2026-11-09 | P1-d | 总指挥验收未过 | macOS 构建 exit 65：`EditMode` 在 macOS 不可用（`OutlineView.swift`） |
| 2026-11-09 | P1-d 修复 | Pro 双端构建 exit 0 | `EditMode` 仅 iOS。`UIKeyboardHIDUsage.keypadEnter` 替换不存在的 `keyboardKeypadEnter`。云端未跑 xcodebuild |
| 2026-11-09 | P1-d | 总指挥验收通过 | 67 个 macOS 测试全绿；iOS Simulator BUILD SUCCEEDED |
| 2026-11-09 | P2-1 | 总指挥验收通过 | macOS 74/0，iOS EXIT=0。合并 `b51b8c5` |
| 2026-11-09 | P2 OPML+MD | 总指挥验收通过 | macOS 80/0，含 6 个 OPMLMarkdownTests。iOS EXIT=0。合并 `4c51de7` |
| 2026-11-09 | P2-3 | 总指挥验收通过 | macOS 85/0，iOS EXIT=0。合并 `1b277ce` |
| 2026-11-09 | P3 | 已提交，云端未测试 | 满幅纸面图标。无 sips、无 xcodebuild。深色变体不另做 |
| 2026-11-10 | 1.1 基础链路 | Censor通过 + Pro 115/0 | 合并 `99b5156` / PR #31。 |
| 2026-11-10 | 1.2 附件数据模型 | Censor通过 + Pro 127/0 | 合并 `8f64c32` / PR #30。流式读写、引用计数、孤儿回收；缩略图 spill→ImageIO→视口。 |
| 2026-11-10 | 1.3 图片插入 | 已合并 | PR #34 → main `c80d138`（tip `57af77a`）。Censor 通过；Pro macOS 138/0、iOS EXIT=0。文件选择 / 拖放 / 粘贴；等比不裁切；异步解码走 1.2 spill + 磁盘 LRU；PDF/PNG 按页面分辨率导出。打开 RSS 可重跑（Darwin phys_footprint / Linux VmRSS + `scripts/measure-open-rss.sh`）。未开 1.4。 |
| 2026-11-10 | 1.4 任意文件附件 | 已合并 | PR #35 → main `59aa8a0`（tip `107c6b1`）。Censor 通过；Pro macOS 151/0、iOS EXIT=0。PSD/PDF/DMG/任意类型；UTType+通用图标；角标；QuickLook 删文件提示；流式+sha256；插入前确认。未开 1.5。 |
| 2026-11-10 | 1.5 自由节点 | 已合并 | PR #36 → main `31a7740`（tip `e328a8a`）。Censor 通过；Pro macOS 163/0、iOS EXIT=0。独立 ID 与持久坐标，不进父子布局；拖动不回弹；关系只存不画；可搜索可计数；`.xmind` 的 detached floating topic。与附件、备注共存。未开 1.6。 |
| 2026-11-10 | 1.6 便签 | 已合并 | PR #38 → main `dfd7af9`（tip `92b6f782`）。Censor 通过；Pro macOS 175/0、iOS EXIT=0。多行便签；≤5 色；不进节点计数、层级、`.xmind`；PNG/PDF 可选含；有限尺寸；与自由节点、附件共存；撤销重做。未开 1.7。 |
| 2026-11-10 | 1.7 版本快照 | 已合并 | PR #40 → main `20ffc7b`（tip `579703b`）。Censor 通过；Pro macOS 186/0、iOS EXIT=0。原子写入（临时文件 + fsync + rename）、打开时按附件点名 sha256 清单、`document.json` 快照（默认 8、硬顶 32）可回滚、半截写入提示恢复上一版。formatVersion 仍为 1。随后 1.0(6) 已上传（iOS `bb67d0bf` / macOS `24561e09`）；未开 4.1。 |
| 2026-11-10 | XMind 双向读写 | 已合并 | PR #43 → main `4aed816`。`.xmind` 的 `content.json` 可导入再导出；未知字段原样写回。字段表 `docs/XMIND-FIELDS.md`。Apple UI 未改。 |
| 2026-11-10 | OPML / FreeMind / Markdown 保真 | 已合并 | PR #44 → main `0c05171`。`.opml` 与 `.mm` 未知字段原样写回；Markdown 字段表把文档投影和纯标题导出分开。字段表 `docs/OPML-FIELDS.md`、`docs/MM-FIELDS.md`、`docs/MARKDOWN-FIELDS.md`。 |
| 2026-11-10 | TextBundle 导出 | 已合并 | PR #45 → main `be9d77a`。仅导出 `.textbundle` 目录和 `.textpack`。`text.md` 走 `FlorettaMarkdownDocumentCodec`，第一张画布树上有字节的附件进 `assets/`。不导入。不改 Apple UI。字段表 `docs/TEXTBUNDLE-FIELDS.md`。云上无 `xcodebuild`。 |
| 2026-11-10 | 首页标题与冒烟测试 | 已合并 | PR #42 → main `cbd2dba`（tip `248f630`）。iPhone 紧凑宽度使用「最近」的 NavigationStack，使「最近」显示；去掉无操作的侧栏「最近」行；加入 FlorettaUITests 冒烟。Pro 双端验收 tip `248f630`：macOS 187/0，iOS 构建与 UITests EXIT=0。 |
| 2026-11-10 | 界面本地化 | 已合并 | PR #46 → main `4848d35`（tip `3e18018`）。`Localizable.xcstrings`（zh-Hans + en）；设置语言切换在下次视图刷新时生效；文档、节点、便签、「未命名」不翻译。Censor 通过；FlorettaCore CI 通过；同一 tip 上 Pro 双端验收：macOS 232/0，iOS 构建与 FlorettaUITests EXIT=0。 |
| 2026-11-10 | ITMS-90737 | 已合并 | PR #49 → main `651ab6f`（tip `201a8af`）。Censor 通过；同一 tip 上 Pro 双端验收：macOS 232/0，iOS 构建 EXIT=0，FlorettaUITests 1/0。构建并归档的 iOS Info.plist 为 `LSSupportsOpeningDocumentsInPlace=true`；未加入 `UISupportsDocumentBrowser`。 |
| 2026-11-10 | 1.0 (8) | 已上传 | bump/upload tip `dbf7688`。归档前该 tip：macOS 232/0，iOS 构建 EXIT=0，FlorettaUITests 1/0。打包门禁通过归档的 `Floretta-iOS.app` Info.plist。TestFlight 均为 VALID，`usesNonExemptEncryption=false`，仅 Timmy 内部测试，Public Beta 未动：iOS `fc580987-11cd-41c9-b379-f53b5ecf161f`，macOS `21f6d373-7854-4def-b1d0-0560eba8e73f`。不回退 1.0 (7)。 |
| 2026-11-10 | Phase 2.1 关系线 | 已合并 | PR #48 → main `22a48dd`（tip `0e82523`）。Censor 通过该 tip；同一 tip 上 Pro 双端验收：macOS 单元测试 241/0（含 `testPNGAndPDFIncludeTheRelationshipLine`），iOS Simulator 构建 EXIT=0，FlorettaUITests 1/0。 |
| 2026-11-10 | Phase 2.2 概要/边界 | 已合并 | PR #51 → main `37a97aa`（tip `571746f`）。Censor 通过该 tip；FlorettaCore CI（guard + Build and test）在该 tip 上通过；同一 tip 上 Pro 双端验收：macOS 单元测试 249/0（含 `SummaryBoundaryTests` 7/0 与 `MapExportTests.testSummariesAndBoundariesEnlargePNGAndPDF`），iOS Simulator 构建 EXIT=0，FlorettaUITests 1/0。 |
| 2026-11-10 | Phase 2.3 标签筛选 | 已合并 | PR #53 → main `fd97255`（tip `942f46b`）。Censor 通过该 tip；FlorettaCore CI（guard + Build and test）在该 tip 上通过；同一 tip 上 Pro 双端验收：macOS 单元测试 258/0（含 `TagFilterTests` 9/0 与 `testFilterOfThousandTopicsStaysUnderATenthOfASecond`），iOS Simulator 构建 EXIT=0，FlorettaUITests 1/0。 |
| 2026-11-10 | Phase 2.4 分支配色 | 已合并 | PR #55 → main `88d50e9`（tip `4b6bc5b`）。Censor 通过该 tip；FlorettaCore CI（guard + Build and test）在该 tip 上通过；同一 tip 上 Pro 双端验收：macOS 单元测试 263/0（含 `testPNGAndPDFKeepBranchThemeColors`、LayoutTests 16/0、TagFilterTests 9/0），iOS Simulator 构建 EXIT=0，FlorettaUITests 1/0。 |
| 2026-11-10 | Phase 3.2 语音输入 | 已合并 | PR #58 → main `536f6c8`（tip `de9c20c`）。Censor 通过该 tip；FlorettaCore CI（guard + Build and test）在该 tip 上通过；同一 tip 上 Pro 双验：macOS 单元测试 276/0（含 `DictationTests` 12/0、`ShellTests` 31/0），iOS Simulator 构建 EXIT=0，FlorettaUITests 1/0。 |
| 2026-11-10 | Phase 3.1 分享扩展 | 已合并 | PR #57 → main `2bf1f4a`（tip `9e4c4f6`）。Censor 通过该 tip；FlorettaCore CI（guard + Build and test）在该 tip 上通过；同一 tip 上 Pro 双验：macOS 单元测试 284/0（含 `ShareIngressTests` 8/0（`testAbsorbKeepsLocalEditsAndPicksUpTheShare` 通过）、`DictationTests` 12/0、`ShellTests` 31/0），iOS Simulator 构建 EXIT=0，FlorettaUITests 1/0。xcresults Asia/Shanghai：macOS `2026.11.10_19-24-57-+0800`，UITests `2026.11.10_19-26-50-+0800`。 |
| 2026-11-10 | Phase 3.3 Markdown 大纲导入 | 已合并 | PR #60 → main `345a515`（tip `4ca7184`）。Censor 通过该 tip；FlorettaCore CI（guard + Build and test）在该 tip 上通过；同一 tip 上 Pro 双验：macOS 单元测试 296/0（含 `ShellTests` 32/0、`DictationTests` 12/0、`ShareIngressTests` 8/0），iOS Simulator 构建 EXIT=0，FlorettaUITests 1/0。xcresults Asia/Shanghai：macOS `2026.11.10_19-45-14-+0800`，UITests `2026.11.10_19-47-11-+0800`。 |
| 2026-11-10 | Markdown 一等文档 UI（D5 / S2） | 已合并 | PR #62 → main `5631b42`（tip `ba0e893`）。Censor 通过该 tip（不沿用 `cf25ac0` / `047e28c`）；FlorettaCore CI（guard + Build and test）在该 tip 上通过；同一 tip 上新鲜 Pro 双验：macOS 单元测试 303/0（含 `MarkdownDocumentUITests` 7/0，其中 `testHeadingExportStaysOffTheDocumentOpenPath` 通过；`ShellTests` 32/0、`DictationTests` 12/0、`ShareIngressTests` 8/0），iOS Simulator 构建 EXIT=0，FlorettaUITests 1/0。xcresults Asia/Shanghai：macOS `2026.11.10_19-52-28-+0800`，UITests `2026.11.10_19-54-24-+0800`。 |
| 2026-11-10 | Phase 4.1 版本快照 UI | 已合并 | PR #64 → main `b0fb7fc`（tip `d681bf3`）。同分支合并当时的 main `80924c1`（parents `2448a4f` + `80924c1`，不是 rebase）。Censor 通过该 tip（不是 `2448a4f`）。软提示不阻断：历史最多加载 32 个快照；回滚确认按钮不是 `role: .destructive`；SMOKE path 26 仍未测。FlorettaCore CI 在该 tip 上通过：Guard「Core import and os guard」成功 12:22:31Z（20:22:31 Asia/Shanghai）；Build and test FlorettaCore 成功 12:24:32Z（20:24:32 Asia/Shanghai）；workflow run `42815174172`。同一 tip 上新鲜 Pro 双验（每次 xcodebuild 前后 HEAD 确认为 `d681bf3`）：macOS 单元测试 313/0（含 `SnapshotHistoryTests` 10/0、`MarkdownDocumentUITests` 7/0、`ShellTests` 32/0、`DictationTests` 12/0、`ShareIngressTests` 8/0），iOS Simulator 构建 EXIT=0，FlorettaUITests 1/0。xcresults Asia/Shanghai：macOS `2026.11.10_20-23-27-+0800`，UITests `2026.11.10_20-25-32-+0800`。 |
| 2026-11-10 | Phase 4.3 同一文档多窗口 | 已合并 | PR #66 → main `5d6b994`（tip `04f65529`）。merge（parents `66aec76` + `04f65529`，不是 squash / rebase）。macOS 上已打开的同一份文档可以再开一个窗口。窗口菜单「新建窗口」（⇧⌘N）、再次打开当前文件、最近文件、文件导入都走 `openAnotherWindow()`。辅助窗口 id 只和 `SameDocumentWindowOpening` 的呈现（`openWindow`）一起记下。各窗口共用一个 `EditorSession`，编辑保持同步。iOS 仍是单窗口。不是 `DocumentGroup` / `NSDocument`。保存仍走现有的包写入 / 快照路径。 |
| 2026-11-10 | Phase 4.2 Quick Look 插件 | 已合并 | PR #67 → main `a9ad9b92`（full `a9ad9b9218905cac4d75f7f3c13de9a82fba1445`），tip `1b900f4`（full `1b900f4ceea078d25be77d8e2ddba8a23cbccecc`）。merge（parents `9043e670ee85c217455849763f7c1aec24a76061` + `1b900f4ceea078d25be77d8e2ddba8a23cbccecc`，不是 squash / rebase），merged_at 2026-11-10T13:26:30Z / 21:26:30 Asia/Shanghai，merged_by TimmySheep。该 tip 本身是把当时的 main（docs PR #68）合并进 Quick Look 分支（parents `d6a36dc1871a65023562e09678ce06780f714681` + `9043e670ee85c217455849763f7c1aec24a76061`，不是 rebase）。Censor 通过该 tip `1b900f4`（不是 `eac4453`、`d6a36dc` 或更早的 SHA）。FlorettaCore CI run `42823200539` 在该 tip 上全绿：Guard「Core import and os guard」成功 13:17:50Z（21:17:50 Asia/Shanghai）；Build and test FlorettaCore 成功 13:19:58Z（21:19:58 Asia/Shanghai）。这一确切 tip 上新鲜 Pro 双验（每次 xcodebuild 前后 HEAD 确认为 `1b900f4`）：macOS 单元测试 321/0（含 `ShellTests` 34/0，其中 `testStringCatalogMatchesTheRuntimeTableAndSkipsDocumentText` 与两个多窗口用例 `testOpeningASecondWindowUsesTheSameDocumentSession` / `testEditInOneWindowIsVisibleInTheOther`；`QuickLookThumbnailTests` 通过；`SnapshotHistoryTests` 10/0；`MarkdownDocumentUITests` 7/0；`DictationTests` 12/0；`ShareIngressTests` 8/0），iOS Simulator 构建 EXIT=0，FlorettaUITests 1/0（`HomeSmokeTests` 的 `testHomeTitleSettingsNewMapAndRows`）。xcresults Asia/Shanghai：macOS `2026.11.10_21-20-23-+0800`，UITests `2026.11.10_21-22-14-+0800`。 |
| 2026-11-10 | 检查单已派项核对 | 见本变更 | 对照 main `3e2dd3b` 把能用现有或新增单测证明的 `[~]` 改为 `[x]`，仓库里没有实现的改为 `[ ]`。当时仍为 `[~]` 的是 A24、B7、C7、E1、F3。当时 E2/E3 未改（PR #71 尚未合并），E4 仍为 `[ ]`。其后 PR #73 合入 main `1c7cc3d7`，E4 在 main 上为 `[~]`（Linux 的 Packaged app size 只证明脚本自测和 Linux 替身低于预算，未证明已签名 .app 低于预算；Core/Size CI 仍不编译 app/appex）。PR #71 现已合并。不宣称那次核对完成了新 Phase。 |
| 2026-11-10 | Phase 5.1 原生 CLI 与 MCP | 已合并 | PR #71 → main `dbde570c`（tip `af2ea145`）。merge（parents `1c7cc3d7` + `af2ea145`，不是 squash / rebase），merged_at 2026-11-10T14:59:28Z（22:59:28 Asia/Shanghai）。树与 tip 相同。Censor 通过该 tip；同一 tip 上 Pro 双验：macOS 332/0，iOS 构建成功，UITests `HomeSmokeTests` 1/0。该 tip 上 Linux CI 265/0。E2 与 E3 为 `[x]`。E4 仍为 `[~]`。 |
| 2026-11-10 | 底栏字数 | 已合并 | PR #75 → main `658b0c37`（tip `c9d6eb28`）。底栏在「主题: N」旁显示「字数: N」。Censor 与独立确认的 CI、Pro 已通过该 tip。 |
| 2026-11-10 | 检查器顶栏位置 | 待验 | 「检查器」和样式/演说/导图分段用 `safeAreaInset` 固定在列顶，高度不随内容伸缩。短页和未选中空态只发生在顶栏下面：表单在那里滚动，占位只在那一块里居中。`InspectorTabPinUITests` 覆盖分页切换，以及有选中与取消选择后顶栏原点 y、尺寸一致（1pt），空态在顶栏之下。本机无 Xcode，未跑 xcodebuild。 |
