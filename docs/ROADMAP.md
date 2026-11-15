# 路线图

这是 Floretta 唯一的进度文档（原 `docs/STATUS.md` 已并入本文后删除）。功能合入后只更新这一份。顶部「本轮」每轮覆盖；下面的矩阵用统一状态词；更早的申报与流水记在文末历史记录里。

## 本轮

- 本轮进度：修复首页 Recents 把当前 UI-test 会话自产文档也过滤的问题。`RecentMapsStore` 注入当前会话根目录，仅放行该根下文档，其他 `FlorettaUITest-*` 残留仍过滤；新增真实用户“未命名”、当前会话可见、其他会话隐藏三条单测。`swift test` 369/1 skipped/0 failures，macOS `FlorettaTests` 460/1 skipped/0 failures，macOS 与 iOS unsigned build 均成功。详见 `DONE-recents-fix.md`。
- 下一步：`fix/recents-uitest-visibility` 已推送并开 PR（不合并）；iOS UI 门禁待 Timmy 在 GUI 会话运行 `./scripts/pre-release.sh` 复验。
- 阻塞：此会话未运行 iOS UI 自动化；复验前不能声称 pre-release 门禁全绿。

状态词只用：✅ 已交付 / 🚧 进行中(PR#) / ❌ 缺失 / ⛔ 不做(原因)。证据列只写已存在的 PR、提交、路径或已核验的时间。不得用 ✅ 掩盖未收口项。

## 待办（未开工）

### TD-001 画布节点文字在预览态不居中（贴在框左上）

- 状态：✅ 已交付（1.0 (21) TestFlight；提交 `8f2b15e`；观感验收由 Timmy 在 TestFlight 上进行）
- 实测证据（2026-11-15 21:06 CST，本机 `fix/glass-title-restore`）：
  - 实现：`FlorettaCore/Layout/EditorLayoutConvergence.swift` 新增 `centeredRows(in:rowHeights:)`（纯几何，块居中、行等距堆叠）；`Floretta/Shared/Canvas/MapExport.swift` 新增 `CenteredNodeTextLayout`（`ThemeFontCascade.platformFont` + `NodeTextTypography.paragraphStyle(lineHeight:)` 组属性，`CTFramesetter` 在容器宽度断行，`CTFrameGetLineOrigins` 排出上→下顺序，逐行 `draw(Text, at: 行中心, anchor: .center)`）。
  - 画布：`InfiniteCanvas.swift` 的 `draw(_ node:...)` 标题与副标题都改为逐行居中，`excludingChildBadge` / 徽章 `badgeTop` / `tagBandHeight` / 缩略图让位 / `clip(to:)` 全部保留；副标题仍用原有的 0.72 墨色，不吃标题的主题字体与粗斜体。
  - 导出：`MapExport.swift` 节点文字同一机制，`insetBy(dx: 8, dy: 4)` 对齐成画布的 `6/4`。
  - 已修的一处实测缺陷：`CTLineGetStringRange` 会把硬换行的 `\n` 带进行字符串，`Text("第一行\n")` 会多出空行、把可见行挤偏（导出实测首行偏 6.25pt），现已剔除行尾换行符。
  - 测试：`Tests/FlorettaCoreTests/LayoutTests.swift` 新增 `testCenteredRowsAreSymmetricAboutTheContainerCentre`（给定 rect 与行高，断言行块相对中心对称）；`FlorettaTests/MapExportTests.swift` 新增两条像素断言：单行「中心」ink 水平偏 0.5pt、垂直偏 1.75pt，「HAMBURG」水平 0.25pt、垂直 0.25pt；两行且末行更短时两行 ink 水平偏 −0.25pt / −0.5pt。口径按**行盒（typographic line box）居中**为准，ink 偏移只用于发现整体跑偏（CJK 的 1.75pt 来自字形升部/降部不对称，编辑态 `NSTextView` 同样按行盒排，未改）。
  - 闸门：`bash scripts/check-compile-and-tests.sh` 全部 PASSED（core-imports / macos-compile / ios-compile / macos-florettatests，EXIT=0，FlorettaTests 477 条 0 failure）；`swift test`（FlorettaCore）通过。
  - 未完成：真机 GUI 截图（编辑前 / 编辑中）尚未入库 `docs/reviews/`，由上级统一启动预览 App 截图后补；编辑态与预览态同一文字的 ≤1pt 对照因此仍待截图核对。
- 现象：同一份文档、同一个节点，**非编辑态**文字贴在节点框的左上角（水平偏左、垂直偏上）；点开编辑后文字才回到框中心。用户判定「不可接受」，要求任何状态下文字都始终位于框的正中。对照截图两张（编辑前 / 编辑中）已由 Timmy 于 2026-11-15 20:45 提供。
- 根因（2026-11-15 用独立渲染实验证实，未靠猜测）：
  1. 预览态走 SwiftUI `Canvas` + `GraphicsContext.draw(Text, in: rect)`，位置在 `Floretta/Shared/Canvas/InfiniteCanvas.swift` 的 `draw(_ node:...)`（标题段约 1836–1920 行）。该 API 按 **leading / top** 排版，`rect` 只是排版容器，文字永远从左上开始。
  2. 文字本身是 `Text(AttributedString(NSAttributedString))`，属性里确实带 `NSMutableParagraphStyle(alignment: .center)`（`Floretta/Shared/Canvas/MapExport.swift` 的 `canvasText` 与 `Floretta/Shared/Ports/ApplePlatformPorts.swift` 的 `NodeTextTypography.paragraphStyle`）。但 **SwiftUI 的 Text 忽略 NSParagraphStyle**：实验里属性带 center 的两行文字仍然贴左，证明这条路径无效。
  3. `Text.multilineTextAlignment(.center)` 在当前 SDK 返回 `some View`，不是 `Text`，无法作为 `GraphicsContext.draw` 的实参（编译报错），因此也不能靠单行改修饰器解决。
  4. 编辑态由 `NSTextView` 渲染（`Floretta/Shared/Keyboard/NodeTextEditor.swift`：218 行 `textContainerInset = (8, 6)`、330–346 行 `lineFragmentPadding = 0` + 段落 `.center`，垂直方向按 `EditorLayoutConvergence` 动态写 inset 去居中）。所以「编辑时才居中」不是巧合，是两套渲染各干各的。
  5. 垂直方向同样错：预览只做了 `rect.insetBy(dx: 6, dy: 4)` 与 `NodeEditChrome.textInset = (6, 4)` 对齐（注释写明目的是「glyphs do not jump」），这只能防止进出编辑时跳字，不产生居中。
- 修复方案（实验已确认可行）：按行绘制并显式居中，不依赖 SwiftUI 的对齐继承。
  1. 断行沿用画布自己那套字体：用 `ThemeFontCascade.platformFont(familyID:nodeDesign:size:)` + `NodeTextTypography.paragraphStyle(lineHeight:)` 构造与 `canvasText` 完全相同的 `NSAttributedString`，再用 `CTFramesetter` 在 `titleRect.width` 约束下取行（`CTFrameGetLines` / `CTFrameGetLineOrigins`），得到每行字符串、行宽、行位置。
  2. 绘制：每行 `context.draw(Text(line), at: CGPoint(x: rect.midX, y: 行中心 Y), anchor: .center)`；整块行高之和在 `titleRect` 内垂直居中。实验中两行（第二行更短）也各自居中，短行不会偏左。
  3. 保留全部现有裁剪与让位逻辑：`excludingChildBadge`、子节点徽章 `badgeTop`、标签带 `tagBandHeight`、缩略图让位、`clip(to:)`。
  4. 明确不动：`titleRect` 的 6/4 内边距、节点尺寸计算、编辑态 `NSTextView` 路径。
- 同批要一起做（Timmy 2026-11-15 明确要求「副标题和导出都做」）：
  1. **副标题**：`node.subtitle` 现在同样走 `draw(in:)`（`InfiniteCanvas.swift` 约 1885–1911 行），标题居中后必然显得歪 → 用同一逐行机制在副标题 rect 内水平居中，垂直分配沿用现有 `subtitleHeight` 逻辑。
  2. **导出**：`MapExport.swift` 节点文字（约 355–382 行）用的是同一个 `draw(in:)`，导出的 PNG/PDF 目前同样偏左上 → 同一机制修正；顺带把导出 `insetBy(dx: 8, dy: 4)` 与画布 `6/4` 的差异对齐，避免导出与屏幕不一致。
  3. 影响面记录：`InfiniteCanvas.swift` 为 macOS / iPad / iPhone 共用，三端会一起变居中；`MapExport` 影响 PNG/PDF 导出与分享扩展。
- 验收标准（全部要有证据，不写「应该好了」）：
  1. 单行「中心」在非编辑态与编辑态，文字块中心相对节点框中心偏差 ≤ 1pt（水平、垂直各测一次）。
  2. 六种情形不回退：单行、多行、末行更短、带副标题、带标签带或附件徽章、窄节点强制折行。
  3. 导出 PNG 与屏幕同一节点的文字位置一致（同一文档对照）。
  4. `bash scripts/check-compile-and-tests.sh` 通过；新增一条纯几何单测：给定 rect 与断行结果，断言行矩形相对 rect 中心对称。
  5. 真机截图入库：编辑前、编辑中各一张，放 `docs/reviews/`，文件名注明日期。

### 参照：XMind 的实现事实（2026-11-15 核实，避免重复调研）

- 用户对标的是新版 XMind（Zen / 2020 起）。该版本**闭源**：2018.01 起由 Electron 整包重写，绘制引擎名 Snowbrush，节点与连线用 **SVG 渲染**。因此其视觉与交互可以按行为重新实现，源码不可复用，也不存在合法的「照抄代码」路径。
- XMind 8（旧版，Java / Eclipse RCP）是真开源（LGPLv3 + EPL，`github.com/xmindapp/xmind`），但 UI 与新版本完全不同，**不可作为视觉参照**，仅可用于理解早期布局思路。
- 文件格式公开：`.xmind` 即 zip；2020+ 内为 `content.json`，XMind 8 为 `content.xml`。官方 `xmindltd/xmind-sdk-js`（npm 包名 `xmind`，MIT，v2.2.33）可程序化读写；`xmindltd/xmind-viewer` 可把 `.xmind` 渲染成 SVG。格式层已有合法路径（本仓 PR #43 已做双向导入导出），UI 层只能重画。
- 因此后续条目一律按「照行为重画」处理，不要指望引入 XMind 前端资产。

### TD-002 画布标签栏（多画布切换 UI）

- 状态：✅ 已交付（1.0 (21) TestFlight；提交 `e44bb5b`）
- 参照：XMind 画布左下角一条胶囊：「结构版 | 画布 2 ▾ | ＋」，`▾` 弹出 重命名 / 拷贝 / 粘贴 / 复制 / 删除 / 新画布 / 画布另存为…（用户 2026-11-15 20:54 截图）。
- 现状证据（2026-11-15 复核，修正下面「没有任何切换栏 UI」一句）：多画布**模型层**在 `FlorettaCore/Model/CanvasSheets.swift`（`canvasCount` / `addCanvas` / `removeCanvas` / `renameCanvas` / `viewport(forCanvas:)`），会话层在 `Floretta/Shared/Shell/DocumentSession.swift` 的 `editingDocument` / `activateCanvas` / `addCanvas` / `removeCanvas`；`EditorToolbarCommandID.newCanvas` 在 `FlorettaCore/Editor/EditorToolbarCatalog.swift`。UI 层**当时确实已有一条横向标签栏**（`DocumentEditor.swift` 旧 `canvasTabBar` + `canvasTab(_:)`，AX 标识 `canvas.tabs` / `canvas.tab.N`，单画布时隐藏，改名靠双击、删除靠右键菜单）——原文「无命中」是因为只 grep 了 `sheetBar|canvasTabs` 两个词，漏掉了 `canvasTabBar`；本次把它整体替换成 XMind 式胶囊。
- 差距（开工时）：缺 `▾` 菜单、删除不可撤销、没有拷贝 / 粘贴 / 复制画布 / 画布另存为。
- 修法：底部左侧玻璃胶囊（`appleGlassChrome(.bottomBarCapsule)`）+ 当前画布名 `▾` 菜单 + `＋`；切换复用现有 `activateCanvas` / 每画布 camera；菜单七项对齐 XMind，无能力的项不出现（单画布不出「删除」，没拷贝过不出「粘贴」）。
- 本轮实现（2026-11-15，分支 `fix/td002`）：
  - 模型：`CanvasSheets.swift` 新增 `canvasSnapshot(at:)`、`insertCanvas(_:at:)`（`removeCanvas(at: 0)` 的逆操作，把当前首画布下推回 `additionalCanvases[0]`）、`duplicateCanvas(at:title:)`、`uniqueCanvasTitle(basedOn:suffix:)`、`MindMapCanvas.copyWithFreshIDs()`（节点 / 概要 / 边界 / 关系线 / 便签 / 专区全部换新 id，跨画布关系线丢弃）；新文件 `FlorettaCore/Model/CanvasSheetHistory.swift` 存删除记录与一条时钟，用来排序「⌘Z 该撤销内容编辑还是删除画布」。
  - 会话：`DocumentSession` 的 `removeCanvas` 记下被删画布（含实时 camera），`undoCanvasRemoval` / `redoCanvasRemoval` / `restoreRemovedCanvas` 复活；`undo()` / `redo()` 先问画布历史；`copyActiveCanvas` / `pasteCanvas` / `duplicateCanvas` 走进程内一格画布剪贴板 `CanvasSheetBoard`；`editActive` 只在内容真的变了才打时钟标记。
  - UI：`DocumentEditor.canvasTabBar` 改成胶囊（当前画布名 + `▾` Menu + `＋`），单画布也显示（XMind 如此，`＋` 才有常驻入口）；菜单项 AX 标识 `canvas.menu` / `canvas.add` / `canvas.menu.rename|copy|paste|duplicate|delete|undoDelete|add|saveAs` / 画布行 `canvas.tab.N`；「画布另存为…」写单独一页 `.floretta`，不改当前文档 URL（`exportKind = "canvas"`）。新增 7 条界面文案进 `FlorettaL10n.english` 与 `Localizable.xcstrings`（两份 key 必须一致）。
  - 测试：`Tests/FlorettaCoreTests/CanvasSheetMenuTests.swift` 12 条（快照 / 首画布插入 / 中段插入 / 末尾插入 / 复制换 id / 跨画布关系线丢弃 / 附件引用保留 / 复制标题编号 / 删除是 ⌘Z 最新步 / undo-redo 栈 / redo 清空与上限 / 删除后带 camera 复活）。
  - 验证（SSH，临时 DerivedData `.build/wt`）：`swift test` 407 tests / 1 skipped / 0 failures（exit 0）；macOS `FlorettaTests` 476 tests / 1 skipped / 0 failures（exit 0）；macOS `Floretta-macOS` ad-hoc 签名构建 BUILD SUCCEEDED；iOS 模拟器目标构建 BUILD SUCCEEDED。
- 难度：低（0.5–1 天）。
- 剩余：PR 与 Censor 审查未做；iPad / iPhone 真机与 UI 自动化未跑（`FlorettaUITests/HomeSmokeTests.swift` 已按新胶囊改写「单画布也显示 / 经 `▾` 菜单切画布」两处断言，需 GUI 会话复验）；胶囊的浅色 / 深色观感未截图。
- 验收：新建 / 切换 / 重命名 / 删除画布后，节点内容与 camera 均正确恢复；删除画布可撤销；macOS 与 iPad 行为一致；胶囊不遮挡画布右下角操作。

### TD-003 右下角状态胶囊与主题统计 popover

- 状态：✅ 已交付（1.0 (21) TestFlight；提交 `5707796`）
- 本轮证据（2026-11-15，`fix/td003`）：提交 `5707796`。`Floretta/Shared/Shell/EditorStatusBar.swift` 的 `EditorStatusStrip` 现在是右下角单块玻璃胶囊（`AppleGlassChrome` 的 `bottomBarCapsule` 角色，无自绘渐变/blur/shadow），从左到右为 主题数 ｜ 实时缩放百分比 ｜ 查看模式 ｜ 大纲 ｜ 全屏。悬停（macOS `.onHover`）与点按（iPad / iPhone 走同一个 `.popover`）弹出 主题 / 字数 / 字符数。统计已从 `•••` 移出：SwiftUI 菜单与 iOS `makeOverflowUIMenu` 两处都删掉了 census 行，三数仍只来自 `TopicTitleCensus`（`statusCensus` 一处读取）。缩放同时从 macOS / iOS 顶栏移除，胶囊成为唯一缩放入口（`EditorToolbarCatalog` 的 `.zoom` 改为 `menuOnly`）。单测：`EditorStatusBarTests` 5/0、`AppleGlassChromeContractTests` 12/0、`EditorChromeContractTests` 7/0；`swift test` 全量 396 通过 / 1 skipped / 0 failures。
- 未收口：悬停→popover 的真机手感、浅色/深色可读性、窄窗口不遮挡画布，均未做视觉验收（本会话不启动 App）。`FlorettaUITests/ThemeModesScreenshotUITests.fitToWindow` 已改为点 `statusBar.zoom`，但本会话未跑 iOS UI 自动化。
- 跨端差异已显式实现：`onHover` 仅在 macOS 生效，iPad / iPhone 用点按打开同一个 popover。XMind 的「卡片视图」在本仓没有对应功能，该槽位驱动既有「查看模式」（地图 / 聚焦），不是死按钮。
- 参照：XMind 右下角胶囊「主题: 5 ｜ 100% ▾ ｜ 卡片视图 / 大纲 / 全屏 / 演说」，hover「主题: 5」弹出「主题 / 字数 / 字符数」三行（用户 2026-11-15 20:54、20:55 截图）。**用户明确只要前三个图标，不做「演说」**。
- 现状证据：`Floretta/Shared/Shell/EditorStatusBar.swift:10-20` 的 `EditorStatusStrip` 现在是个空 `Spacer`，底栏什么都不画；主题 / 字数 / 字符数被塞在 `EditorOverflowCensus`（同文件 26 行起，即 `•••` 菜单内）；缩放百分比是工具栏项 `zoomPercent`。
- 差距：把已有零件搬进胶囊，不新建数据源；统计直接复用 `TopicTitleCensus`（`EditorOverflowCensus` 已在用），禁止第二套计数器。
- 修法：胶囊容器用官方 Liquid Glass（复用 `Floretta/Shared/Shell/AppleGlassChrome.swift` 的 role，不要手写渐变或自定义 blur）；hover popover 在 macOS 用 `.popover`，iPad / iPhone 用长按或点按（跨端差异必须显式处理，不能只做 macOS）。
- 难度：低（0.5–1 天）。
- 验收：三个数字与 `•••` 内完全一致；缩放点按与键盘快捷键状态同步；浅色 / 深色下玻璃可读；窗口变窄时不遮挡画布内容。

### TD-004 右侧样式检查器（XMind 式）

- 状态：✅ 已交付（1.0 (21) TestFlight；提交 `aa89576`）
- 参照：XMind 右侧浮层，tab「样式 / 演说 / 画布」，区块为 形状 / 填充 / 边框 / 宽度（PX·适应）/ 文本（字体、字号、加粗斜体下划线、对齐）/ 结构 / 分支（线条、终点）/ 配色方案 / 背景色 / 全局字体 / 分支线粗细（用户 2026-11-15 20:55–20:57 截图）。**明确不做：演说 tab、彩虹分支。**
- 现状证据（开工前）：`InspectorTab` 已存在（`Floretta/Shared/Shell/DocumentEditor.swift:51` 声明、`:1649` 渲染，AX 标识 `inspector.tabs`）；外观三模式与字体在 `Floretta/Shared/Shell/AppearanceSettingsPanel.swift`。
- 已落地（分支 `fix/td004`，基于 `09f1398`，本地提交未推送）：
  - 分组重排：`FlorettaCore/Shell/InspectorStyle.swift` 的 `InspectorStyleSection` 改为 `形状 / 填充 / 边框 / 宽度 / 文本 / 分支 / 配色方案 / 背景色 / 全局字体 / 连到`，并新增 `isDocumentScope`（分支、配色方案、背景色、全局字体 为文档级，无选中时仍可见）。**没有 `structure` case**：结构下拉属 TD-005，未实现前该行在数据层就不存在（`testStyleGroupsFollowXMindOrderAndSkipStructure` 断言其不存在）。
  - 面板结构：`DocumentEditor.stylePage` 先给文档级分组（`inspectorColorSchemeSection` = 配色方案、`inspectorBranchSection` = 分支 线条/终点），再放 `AppearanceSettingsPanel(fields: .mapScope)`，后者把「底色」与「字体族」提升为独立的 背景色 / 全局字体 两个 `Section`（`Floretta/Shared/Shell/AppearanceSettingsPanel.swift`）；节点级 `StyleInspector` 拆成 形状 / 填充 / 边框 / 宽度 / 文本 / 连到 六段。
  - 新字段与新映射（均有单测）：`MindMapNodeStyle.autoWidth`（`FlorettaCore/Model/MindMapNode.swift`）+ `InspectorWidthMode`（PX·适应）；`MindMapDocument.branchLineStyle` / `branchEndMarker`（`FlorettaCore/Model/MindMapDocument.swift`，`curve`/`none` 不写入 JSON，旧文件字节不变），并在 `FlorettaCore/Model/CanvasSheets.swift` 的 `isolatedCanvas` / `replaceCanvasContent` 里逐画布带过（否则检查器经 `activeCanvasDocument` 写入会丢）。
  - 真正生效：`FlorettaCore/Layout/LayoutEngine.swift:667` 在 `autoWidth == true` 时不再套用 `topicWidth`（适应 = 量文字）；`FlorettaCore/Layout/BranchStyle.swift` 定义 曲线/直线、无/箭头/圆点 与箭头/圆点几何；`Floretta/Shared/Canvas/InfiniteCanvas.swift` 按 `branchLineStyle` 决定直线并画终点，`Floretta/Shared/Canvas/MapExport.swift` 用同一套 token 与几何，PNG/PDF 与屏幕一致。
  - 写法：节点样式走 `InspectorStyle.apply`（新 `.widthMode`），文档级走新增的 `InspectorStyle.applyDocument`（`.branchLine` / `.branchEnd` / `.colorScheme`），配色方案复用 `EditorSession.setBranchTheme`（与「配色」sheet 同一入口、同一 `themeID`）。
  - 移除 `演说` tab：`InspectorTab` 只剩 `样式 / 导图`，空占位页删除（`AppleGlassChromeContractTests` 与 `FlorettaUITests/InspectorTabPinUITests.swift` 同步改动）。
  - 验证：`swift test` 399 tests / 1 skipped / 0 failures；macOS Debug（ad-hoc 身份）`xcodebuild ... Floretta-macOS build` → `** BUILD SUCCEEDED **`。新增单测：`testWidthModeFitDropsTheStoredPixelWidth`（适应 与「无 topicWidth」布局等宽、px 滑块回落）、`testBranchTokensAndColorSchemeWriteThrough`（往返、默认省略、Markdown 拒写）、`testColorSchemeAndBranchChoicesCoverBothCatalogs`、`testBranchEndGeometryMatchesTheRelationshipArrow`、`testStyleGroupsFollowXMindOrderAndSkipStructure`。
- 缺口（本分支未做，不要按 ✅ 读）：
  1. 参考列里的「分支线粗细」未做：`LayoutAppearance.linkStroke` 目前仍由配色方案决定，没有独立滑杆。
  2. 「背景色 / 全局字体」写的是应用外观 profile（`AppSettings.currentProfile`），不是文档内字段；XMind 里背景色是文档级。要改成文档级需要新字段 + 布局/导出 plumbing，属独立一轮。
  3. 「结构」行按 TD-005 预留：`InspectorStyleSection` 无该 case，入口在 TD-005 落地时再加。
  4. 未在 GUI 会话跑 `FlorettaUITests`（SSH 会话无法签名构建 App）：分段控件两段化的 UI 测试改动只做了源码级修订，需在图形会话复验。
- 差距（原始评估，保留以便对照）：字段大多在模型里已有，缺的是按 XMind 分组的重排；形状 / 结构下拉引用 TD-005，未实现前该行不出现。
- 难度：中（2–3 天，不含结构布局）。
- 验收：每个控件改动即时反映到画布与导出；面板可收起且不挤压画布；键盘可达；深色模式对比度合规。

### TD-005 结构布局引擎（9 种图，第一版只做 2 种）

- 状态：✅ 已交付（1.0 (22) TestFlight；逻辑图/组织结构图/时间轴/鱼骨图/树型表格/矩阵图 + 思维导图共 7 种，检查器可选；括号图与树形图按决定作为变体不做）
- 参照：XMind「结构」下拉九项——思维导图 / 逻辑图 / 括号图 / 组织结构图 / 树形图 / 时间轴 / 鱼骨图 / 树型表格 / 矩阵图（用户 2026-11-15 20:56 截图）。
- 现状证据（2026-11-15，分支 `fix/td005`）：`LayoutKind` 已从单 case 扩成 `.bilateral` / `.logicChart` / `.orgChart`（`FlorettaCore/Layout/LayoutEngine.swift`），每个 case 背后是 `StructureLayout` 的一个实现（`BilateralLayout.swift` / `LogicChartLayout.swift` / `OrgChartLayout.swift`）；量尺寸、配色与连线统一收在 `LayoutGeometry.swift`，布局不许另写测量公式；`MindMapDocument.layoutKind` 存结构（`.bilateral` 不写进 JSON，旧文件照旧打开为思维导图），`LayoutEngine.forDocument(_:)` 让画布与导出取同一结构。
- 差距（本项是全批里唯一的工程级投入）：其余 8 种各需一套布局算法 + 连线规则 + 折行 + 导出渲染一致性，`Floretta/Shared/Canvas/InfiniteCanvas.swift` 与 `Floretta/Shared/Canvas/MapExport.swift` 都要跟着支持；同时影响 XMind 导入时 layout 字段的映射。
- 修法：先把 `LayoutKind` 从单 case 扩成可插拔布局（每布局一个实现 + 单元测试 + 视觉回归夹具）；**第一版只做逻辑图与组织结构图**验证架构，验证通过再补齐其余，不要一次上九种。
- 已完成（`fix/td005`，三次提交，每个提交都单独编译过）：
  1. 架构 `38ab284`：`StructureLayout` 协议 + `LayoutGeometry`（尺寸/配色/连线/帧工厂）+ `LayoutKind.makeLayout(geometry:)` 注册表；原双边算法整体搬进 `BilateralLayout`，几何零变化（重构后 `swift test` 395 tests / 1 skipped / 0 failures）。
  2. 逻辑图 `1bd9640`（单侧向右）：父节点垂直居中于子节点栈，每层右移一个 `horizontalGap`，兄弟间距 `siblingGap`，连线由父右边到子左边；拖拽过的根保留落点、子树跟随。
  3. 组织结构图 `3302d0d`（向下展开）：父节点水平居中于子节点行，每层下移一个 `horizontalGap`，兄弟间距 `siblingGap`，连线由父底边到子顶边（新增 `LinkAnchor.down`）。
  4. 单测：`Tests/FlorettaCoreTests/StructureLayoutTests.swift` 共 16 条（两种布局各 8 条）——逐层缩进、兄弟间距、父级居中、连线端点与控制点、折叠隐藏子树、手动根点、互不重叠、文档↔引擎↔编解码往返。
  5. 画布与导出一致：`CanvasPlacement.nodes` 改为 `LayoutEngine.forDocument`，`MapExport` 的 PNG/PDF 与图片槽都复用 `CanvasPlacement.nodes`，因此位置、父子连线、命中测试、选中、拖拽、插入子节点读的是同一批 `NodeFrame`。
  6. 验证（真实输出）：`swift test` → `Executed 411 tests, with 1 test skipped and 0 failures`；macOS Debug ad-hoc `xcodebuild` → `** BUILD SUCCEEDED **`（未跑 iOS 编译脚本）。
- 新增一种布局要改的地方（本次实测清单）：1) `LayoutKind` 加 case；2) `displayNameKey` 加一行；3) `makeLayout` 加一行；4) 新文件实现 `StructureLayout`（只用 `LayoutGeometry` 的 `size` / `frame` / `link`）；5) `StructureLayoutTests` 加该布局的几何测试；6) 连线若不走左右出，只在 `LinkAnchor` 加一个锚点。
- 仍未收口：其余 6 种结构（括号图 / 树形图 / 时间轴 / 鱼骨图 / 树型表格 / 矩阵图）；XMind `structureClass` 映射（`XMindFieldCatalog` 仍是 passthrough「不解释」）；九种结构的入口 UI 属 TD-004；入库截图与视觉回归夹具未做（本任务禁止启动 App 截图）。
- 难度：高（每种 1–3 天，全量约 3–4 周）。
- 验收：切换结构后节点位置、连线、导出 PNG 与屏幕一致；导入的 `.xmind` layout 字段能映射到对应结构；每种布局有独立单测与一张入库截图。

### TD-006 顶栏铺开与窄窗口收敛

- 状态：✅ 已交付（1.0 (21) TestFlight；提交 `ce69362`）
- 本轮证据（2026-11-15，`fix/td003`）：提交 `ce69362`。macOS 顶栏改为三组 —— `macToolbarItemsPrimary`（撤销 / 重做 / 删除）｜ `macToolbarItemsInsert`（＋ 插入 一个下拉，子节点 / 同级 / 语音输入 / 自由节点 / 便签 / 专区 / 图片 / 附件 / 从文件导入 是菜单行）｜ `macToolbarItemsRelations`（关系线 / 概要 / 边界 / 标签），随后是 `•••` 与检查器胶囊。导入导出、全屏、历史、主题、查找、粘贴、大纲、样式、适应窗口默认不在顶栏（`addable`，仍可从工具栏自定义面板加回）。`•••` 新增 `overflowMenuCommands`：`EditorToolbarCatalog.menu(.more)` 减去 `EditorToolbarLayout` 当前显示在顶栏的命令，因此同一命令不会有两处入口；窄窗口交给系统 toolbar 溢出，没有另写「变窄就换 •••」的判定。目录侧同时把 概要 / 边界 / 关系线的菜单归属从 `insert` 移到 `more`（作为窄栏回退），`.more` 声明移到数组末尾，使 `defaultToolbarItems` 以 `•••` 结尾。单测：`EditorToolbarCatalogTests` 7/0、`EditorChromeContractTests` 7/0（含新增 `testMacTopBarGroupsHighFrequencyCommandsAndOverflowComesLast`）；`swift test` 全量 396 通过 / 1 skipped / 0 failures；macOS 未签名 build `** BUILD SUCCEEDED **`。
- 未收口：窗口收窄到最小宽度时是否裁切、`•••` 是否仍可达，需要真机截图验收（本会话不启动 App）。XMind 顶栏的「备注」在本仓没有对应命令，未做。`•••` 帮助文案仍写「文档统计」，统计实际在胶囊里；改文案要新增本地化 key，本轮未动。
- 参照：XMind 顶栏一排图标（撤销 / 关系线 / 边界 / 概要 / 标签 / 备注 / ＋插入），窗口变窄时由系统溢出（用户 2026-11-15 20:58 截图）。
- 现状证据：`FlorettaCore/Editor/EditorToolbarCatalog.swift` 的 `EditorToolbarCommandID` 已含 40+ 命令（含 link / summary / boundary / region / tagFilter / outline / viewMode / focusMode / immersive / zoom / fit / newCanvas / history），并已有 `EditorCommandPlacement`（principal / primary）与 `EditorCommandVisibility`（visible / menuOnly）分级。差距是**分组策略**，不是造轮子。
- 修法：顶栏分三组——`撤销 / 重做` ｜ `＋ 插入`（子节点 / 同级 / 自由节点 / 便签 / 图片 / 附件 / 录音）｜ `关系线 / 概要 / 边界 / 标签 / 备注`；低频项（导入导出、历史、主题、查找、统计）留 `•••`。溢出交给系统 toolbar，不另写「变窄就换 •••」的判定。
- 难度：低-中（0.5–1 天）。
- 验收：默认宽度下高频项在顶栏且无重复入口；窗口收窄到最小可用宽度时无控件被裁切、`•••` 仍可达；`Tests/FlorettaCoreTests/EditorChromeContractTests.swift` 同步更新。

### TD-007 检查器开关的玻璃胶囊样式

- 状态：✅ 已交付（1.0 (21) TestFlight；提交 `3bc52dd`）
- 本轮证据（2026-11-15，`fix/td003`）：提交 `3bc52dd`。`DocumentEditor.macInspectorToggle` 是独立 `ToolbarItem(id: "inspector.toggle", placement: .primaryAction)`，画在 `macToolbarItemsView` 末尾（右上角）。玻璃来自既有 `AppleGlassChrome` 的 `toolbarFloatingButton` 角色（`Capsule()` + 系统 glass / 材质回退），未手写渐变、blur 或阴影；标签区 `frame(width: 34, height: 28)` 满足 ≥ 28×28，图标 `sidebar.trailing`，字号与顶栏其它按钮一致（13pt medium）。标题与帮助文本复用 `样式` 目录项，未新增文案。单测：`EditorChromeContractTests.testMacInspectorToggleIsOneGlassCapsule` 通过（该批 7/0）。
- 未收口：浅色 / 深色下的可读性与点按区域只在代码层保证，未做真机截图与 AX 实测（本会话不启动 App）。
- 参照：XMind 右上角「笑脸 + 侧栏开关」的玻璃胶囊（用户 2026-11-15 20:56 截图）。
- 现状证据：检查器开关已存在（AX `inspector.tabs`），只缺样式。
- 修法：复用 `Floretta/Shared/Shell/AppleGlassChrome.swift` 的 toolbar 角色，不手写渐变。
- 难度：低（数小时）。
- 验收：浅色 / 深色下图标清晰可辨；点按区域不小于 28×28；与顶栏其它控件基线对齐。

### 建议执行顺序（2026-11-15）

TD-003 → TD-002 → TD-007 → TD-006 → TD-004 → TD-005。前四条都是「已有零件 + 入口/样式」，一天内可见；TD-004 需要设计确认；TD-005 单独立项，先做两种验证架构。

### TD-008 Web 端对标（FlorettaWeb 仓库，排在原生 TestFlight 之后）

- 状态：❌ 未开工（Timmy 2026-11-15 决定：排在原生 `1.0 (21)` 上 TestFlight 之后单独一轮）。
- 仓库：独立仓库，与原生不共享代码。Pro 上有本地副本 `/Users/TimmySheep/AWS/floretta/.web/FlorettaWeb`（origin `Super-Console/FlorettaWeb`，tip `ff80e2c`；2026-11-15 已合 PR #13 `feat/web-mac-parity` 并部署）。
- 范围：把本批原生已落地的项在 Web 上等价实现——TD-002 画布标签栏、TD-003 状态胶囊与主题统计、TD-004 检查器分组、TD-006 顶栏分组。TD-001（节点文字居中）先查 Web 画布自己的文本渲染方式再决定是 `text-align` 还是逐行绘制。
- 硬边界：Web 拿不到系统 Liquid Glass，只能用 `backdrop-filter` 近似，不得写成「已实现系统玻璃」；改动前先更新 `docs/WEB-PARITY.md` 的状态词，不用 ✅ 掩盖近似。
- 验收：与原生同场景对照截图；仓库自带 `gate.js` 与既有测试通过。

### 交付方式（2026-11-15 确认）

- 原生三端（macOS / iPad / iPhone）共用同一份 Swift 代码，本批完成后合并为一个集成分支，版本 `1.0 (21)`，Timmy 验收后直接上传 TestFlight。验收由 Timmy 本人做，助手只负责积分构建与上传。
- Pro 的 Xcode 未登录 Apple ID：签名、导出、上传全程走命令行 + ASC API Key，不使用图形界面登录，也不索取账号密码或验证码。若 provisioning 卡住则停下来等 Timmy。
- Web 端（TD-008）不在本次 TestFlight 包内。

### 交付记录：1.0 (21) → TestFlight（2026-11-15）

- 分支：`release/1.0.21`，自 `5f0e82b` 起，合并 `fix/td003`（`0805e69`）、`fix/td005`（`cc59fae`）、`fix/td002`（`aa386e7`）、`fix/td004`（`3a76b20`），构建号 bump 在 `265da7a`。
- 合并冲突仅一处：`FlorettaCore/Layout/LayoutEngine.swift`。td005 把该文件拆成「引擎 + LayoutGeometry + 每种布局一个实现」，td004 仍在旧位置改宽度规则（「适应」忽略存储 px）。处理方式为保留新架构，把该规则迁入 `FlorettaCore/Layout/LayoutGeometry.swift` 的尺寸计算处，不用 `--ours` 整体丢弃。
- 闸门（合并后于集成分支实测）：`swift test` 429/1 skipped/0 failures；`FlorettaTests` 484/1 skipped/0 failures `** TEST SUCCEEDED **`；macOS Debug 与 iOS Debug 编译 exit 0；Release 配置 iOS/macOS 无签名编译 exit 0。
- 归档与上传：iOS `** ARCHIVE SUCCEEDED **` → `Upload succeeded`；macOS 同。App Store Connect 回读（API `v1/builds?filter[preReleaseVersion.platform]`）：iOS build 21 `VALID`（2026-11-15T05:58:31-08:00）、macOS build 21 `VALID`（2026-11-15T06:02:41-08:00），均挂在 App `6832552931` 的 1.0 版本下。
- 签名方式与环境事实：Pro 的 Xcode 未登录 Apple ID；`xcodebuild archive -allowProvisioningUpdates -authenticationKeyPath/KID/Issuer` 可自动取描述文件，但 **codesign 必须在 GUI 登录会话里执行**。SSH 会话直签、`launchctl asuser`、`osascript do shell script` 三种方式均报 `errSecInternalComponent`，因为都跑在 SSH 的安全会话里；最终通过在用户已打开的「终端」窗口执行 `nohup bash <script> &` 完成。钥匙串须由 Timmy 本人 `security unlock-keychain` 解锁，助手不接触密码。
- 未完成（不得写成已交付）：① 真机/桌面视觉验收未做——上传时 Mac 处于锁屏状态，无法截图；② Web 端 TD-008 未开始；③ TD-005 只实现逻辑图与组织结构图，其余 6 种未做（括号图 / 树形图 / 时间轴 / 鱼骨图 / 树型表格 / 矩阵图）；④ 「备注」命令在仓库内不存在，「卡片视图」当前接的是查看模式。

### 设计规则：Chrome 与内容的字体分工（2026-11-15 拍板）

- 规则（不再讨论，新界面一律遵守）：**内容层可以用衬线（主题字体）；Chrome 层永远用系统无衬线。** 依据是苹果自己的做法——Books / Pages / Notes 正文可衬线，工具栏、按钮、菜单永远是系统 SF；界面件用衬线族在 13pt 上会中西文混排失配，是「字体看着怪」的真实来源。
- Chrome 范围：顶部工具栏标题与控件标签、底栏状态胶囊、画布标签胶囊、侧栏（首页/最近）、设置面板、检查器标签与分组标题、菜单与弹出框里的静态文字、空状态与提示条。
- 内容范围：画布节点文字、Markdown 正文、以及用户输入的正文内容；节点/卡片内标题按内容处理。
- 决定过程：Timmy 2026-11-15 提出过「为了和 App 图标呼应而全界面用衬线」，讨论后判定不划算——图标是 1024px 场景，界面是 13–15pt 场景，用日常可读性换大图里的品牌感属于拿高价值换低价值；品牌感应放在启动页、空状态、「关于」页这类大字号场景。
- 经典模式不因此「退化成只剩米白背景」：仍可用行距/段距、暖墨色、发丝分隔线、小圆角无投影四个杠杆拉开与「现代模式」的差距（见 TD-009）。

### TD-009 落地 Chrome/内容字体分工

- 状态：✅ 已交付（1.0 (22) TestFlight；`280dd2f`，7 处审计、4 个 chrome 文件改系统字体）
- 现状证据：`themeTypography` 全仓仅 7 处调用、5 个文件（`ThemeSettings.swift` 定义处、`AppearanceSettingsPanel.swift`、`DocumentEditor.swift`、`LibraryHome.swift`、`EditorStatusBar.swift`）。
- 修法：新增 chrome 专用系统字体修饰器，替换 chrome 侧调用；内容侧保留 `themeTypography`；加源码级契约测试（chrome 文件不得出现 `themeTypography(`）与 `docs/THEME-MODES.md` 说明。
- 验收：经典模式下工具栏/侧栏/首页/设置/检查器/底栏全部系统无衬线；画布节点与 Markdown 正文仍随主题变化；modern 模式不回退。

### 设计决定：外观模型简化与 App 级界面归位（2026-11-15 商定）

「经典模式 / 现代模式」这个概念**取消**，拆成互不相干的两件事，用户不需要理解任何"模式"。

- **首页背景**：设置里直接写「首页背景：纸质米白 / 纯白」。只影响首页底色。
- **画布内容字体**：并入检查器现有的字体列表（用户自己挑），**默认无衬线**。不再与任何"模式"绑定。
- **Chrome 字体**：永远系统无衬线，不给用户选（由 TD-009 落地）。
- **文档背景**：每份文档自带、用户可改，**优先级最高**。边界：①已存在文档一律不改 ②在文档里改过背景的，文档值覆盖默认值 ③切换首页偏好不影响任何已打开文档 ④导出 PNG/PDF 跟随文档自身背景，与首页偏好无关 ⑤旧三模式设置值需平滑迁移，不留读不懂的残留。
- **新建文档**：继承创建当时的「首页背景」作为默认背景（偏好=初始值，不是全局强制）。

界面归位：

- **macOS**：删除首页侧边栏（其 `HomeSidebarRow` 含 `.newMap / .openFiles / .openICloud / .browseLocal`，是命令不是导航，移到首页工具栏与「文件」菜单）；首页变单栏（＋新建 / 打开▾ / 搜索 / 卡片墙）；设置改为标准 `Settings` scene + `⌘,` 打开**独立窗口**，内部用系统 `TabView`（自动渲染成 Safari 设置那种顶部页签，**不自绘左侧列表**，页签超过 6 个再议）；文档视图里的「展开侧栏」按钮保留。
- **iPad**：与 Mac 一致（单栏 + 工具栏）。
- **iPhone**：设置入口 Timmy 仍在权衡（候选：导航栏齿轮 → push 新页面 / sheet）。

- 状态：❌ 未开工（规格已定稿，按 Timmy 要求讨论阶段暂不派工）。

### 交付记录：1.0 (22) → TestFlight（2026-11-15）

- 分支：`release/1.0.21` 之后的 `main`，末尾提交 `fec49f9`（build 22）。合并顺序：`fix/bottom-bar-alignment` → `feat/chrome-typography` → `feat/layouts-4` → `feat/appearance-simplification` → `feat/structure-picker`。
- 本轮落地：底栏两胶囊同排同高 + macOS 28pt / iOS 44pt 平台拆分 + SF Symbols 统一字重 + 地图/聚焦单键切换；Chrome 永远系统无衬线（7 处审计，4 个界面文件改为 `chromeTypography`）；新增时间轴 / 鱼骨图 / 树型表格 / 矩阵图四种结构（引擎共 7 种）；取消经典/现代模式改为「首页背景：纸质米白 / 纯白」（浅深各一套色值、存语义、新建文档按当前外观解析、旧值迁移）；macOS 与 iPad 删首页侧边栏、首页单栏、设置改为 `Settings` 场景独立窗口（⌘,）；检查器新增「结构」选择器（7 种 + 中英文本地化键）。
- 闸门（`fec49f9` 实测）：`swift test` 493 项 / 1 skipped / 0 failures；`FlorettaTests` 495 项 / 1 skipped / 0 failures `** TEST SUCCEEDED **`；macOS 与 iOS Debug 编译 exit 0。
- 合并时契约测试抓到一处真回归：`LibraryHome.swift` 的 macOS 设置窗口套了 `themeTypography`（设置窗口属 chrome，应为系统字体），修复提交 `caf8dba`。另更新了一条因字体 API 改名而过期的断言（`ThemeTypography.font(mode:)` → `familyID:` 路径），意图未削弱。
- 归档与上传：iOS 与 macOS **并行**归档（72s 双成功，零 `errSecInternalComponent`）、并行上传（156s 双 `Upload succeeded`）。ASC 回读：iOS build 22 `VALID`（2026-11-15T07:17:37-08:00 = 23:17 CST）、macOS build 22 `VALID`（07:18:21-08:00 = 23:18 CST），均挂在 App `6832552931` 的 1.0 下。
- 仍开着的口子（不得写成已交付）：① iPhone 的设置入口 Timmy 仍在权衡，本轮 iPhone 行为逐字未变；② 结构只有 7 种（括号图/树形图按决定作为变体不做，PRO 网格不做）；③ 「备注」命令仓库内不存在；④ Web 端 TD-008 未开始；⑤ 本轮未做真机视觉验收（按 Timmy 要求改为直接在 TestFlight 上看）。

### 交付记录：1.0 (23) → TestFlight（2026-11-16）

- 分支：`main`，末尾提交 `f35017e`。合并顺序：`feat/bottomfix` → `feat/inspectorglass` → `feat/pointer-modes` → `feat/add-handles`，另有 `337486c` 修本地化目录。
- 本轮落地：①浮层玻璃底板按角色区分采样模式（底栏与浮层 `.withinWindow`、侧栏与检查器 `.behindWindow`），底栏压在节点上时可读；②左下画布名居中、超长中间省略、宽度上限 30% 窗口且胶囊贴合内容；③胶囊内间距 8→10、组间 16、图标命中区 28；④工具栏去掉第二层玻璃（`.toolbarFloatingButton` 在 macOS 也改 no-op）；⑤检查器面板玻璃化、行块保持不透明实底；⑥macOS 指针/手掌两种模式（默认指针，空白拖动框选、Shift 追加、Esc 恢复；手掌拖动平移；空格按下即应手、抬起按 300ms 判定短按编辑/长按无事，忽略自动重复）；⑦节点快捷加号可点（外扩 28pt 命中 + 200ms 宽限）、按布局只显示有意义方向、方向写入 `MindMapNode.side` 让双侧布局左/右真实生效。
- 闸门：Core `swift test` 549 项 / 1 skipped / 0 failures；`FlorettaTests` 499 项 / 1 skipped / 0 failures `** TEST SUCCEEDED **`；macOS 与 iOS Debug 编译 exit 0。
- 合并期两次修复：`EditorStatusBar.swift` 冲突按「保留底栏分组 + 指针按钮并入组内」解；本地化目录缺 3 条指针文案，按脚本算出的差集补齐（444 条，JSON 校验通过）。
- 归档上传：双平台并行归档 66s 双成功、并行上传 132s 双 `Upload succeeded`。ASC 回读：iOS build 23 `VALID`（2026-11-15T08:04:37-08:00）、macOS build 23 `VALID`（08:04:53-08:00）。
- 未完成（不得写成已交付）：①本轮未做屏幕级验收（助手截图受上下文限制被吞，只有离屏渲染与契约测试背书），观感由 Timmy 在 TestFlight 确认；②键位响应延迟（Tab/Enter 约 0.2s）仅做了代码层怀疑点分析，未跑 profile；③iPhone 设置入口仍待定；④Web 端 TD-008 未开始；⑤「备注」命令仓库内不存在。

### TD-012 iOS 线上闪退：Release 下类型名解析爆栈（2026-11-16 定位）

- 现象：1.0 (23) 在 iPhone/iPad 上打开文档（新建或打开现有）立即闪退。
- 真实崩溃日志关键行：`EXC_BAD_ACCESS` + `Exception Message: Thread stack size exceeded`，崩溃线程为 `decodeMangledType` 反复递归 → `__swift_instantiateConcreteTypeFromMangledNameV2` → `DocumentEditor.canvasTabBar.getter` ← `bottomBarRow`(694) ← `canvasStack`(676) ← `editorCore`(221)。
- 根因：`DocumentEditor.canvasTabBar` 的 SwiftUI 视图类型链嵌套过深，Swift 运行时解析巨型泛型 mangled name 时自身递归，把主线程栈打爆。**Release 构建的类型名比 Debug 长，所以只在线上触发**——Debug 模拟器跑同一路径不崩，这也解释了为什么本机没发现。
- 修法：把该胶囊拆成独立的小 `View` 结构体（`CanvasSheetCapsule` / `CanvasSheetNameLabel`），把 `.alert` 移到父级，切断类型链；并用 **Release 配置**在 iOS 模拟器跑 UI 测试实测确认「点新建不崩」。
- 教训：凡是把一个巨型视图体内联在 `DocumentEditor` 这种超大 View 里、又叠加大量 modifier 的地方，都可能在 Release 下踩这个坑。验收这类改动必须用 Release 构建，Debug 通过不算数。

### 交付记录：1.0 (24) → TestFlight（2026-11-16）

- 分支 `main`，末尾 `1eff516`。合并顺序：`feat/ios-settings-sheet` → `fix/ios-launch-crash` → `feat/sidebar-glass` → `feat/key-latency`。
- 本版内容：
  1. **修 iPhone/iPad 线上闪退（TD-012）**：把 `DocumentEditor.canvasTabBar` 拆成 `CanvasSheetCapsule` / `CanvasSheetNameLabel` 两个独立小 View，`.alert` 移到父级；`canvasTabBar` 相关 mangled 类型名从 1313 字符降到 125 字符，父链不再内嵌菜单子树。Release 构建 + Release UI 测试（含新增的重命名弹窗测试）全部跑完，无 crash/stack/EXC_BAD_ACCESS。**注意**：同测试在未修复版本上于模拟器也通过，说明模拟器复现不了真机栈溢出——真机结论仍需本次 TestFlight 验证。
  2. **iOS 设置入口改造**：移除底部「设置」Tab，首页右上角圆形齿轮（`home.settings`）→ `.sheet`（medium/large detents + 拖拽指示器），卡内无大标题。macOS Settings 窗口未动。
  3. **侧边栏/面板玻璃**：引入单一规则 `sampleSource`——**底板采样它真正遮住的那一层**。编辑器大纲栏与 iOS 检查器改为 `windowContent`（画布），macOS 检查器保持交给系统 `.inspector` 玻璃（no-op），底栏/浮层早已是 `windowContent`。审计表见提交报告。
  4. **键位延迟**：先测后改。测量结论（Release，12 节点）：Tab p50 207.7ms、Enter 200.9ms；对照「只按方向键、不改文档」也有 172–183ms → 存在约 170ms 地板。已优化 `NodeTextEditor` 的 AppKit chrome 重复写入（13 次/按键 → 2 次），但**总延迟未下降**（Tab 210.4ms、Enter 216.3ms，在噪声内）。采样显示主线程停在 `NSHostingView.layout → ViewGraph.updateOutputs → ToolbarBridge.updateStorage`，下一步须用 Instruments Time Profiler 在 GUI 会话取 Timeline。**本项不得记为已修复。**
- 闸门（`1eff516` 实测）：`swift test` 555 项 / 1 skipped / 0 failures；`FlorettaTests` 505 项 / 1 skipped / 0 failures `** TEST SUCCEEDED **`；macOS 与 iOS Debug 编译 exit 0。
- 归档上传：双平台并行归档 72s（零 `errSecInternalComponent`）、并行上传 114s 双 `Upload succeeded`。ASC 回读：iOS build 24 `VALID`（2026-11-15T09:39:33-08:00）、macOS build 24 `VALID`（09:39:46-08:00）。
- 工作区清理（Timmy 2026-11-16 授权，全部移至废纸篓可恢复）：18 个已合并工作树 → `~/.Trash/floretta-worktrees-20261116-014059/`；UI 测试残留的测试文档与快照（未命名 10–19 及 `.snapshots`）+ `ui-polish-14-ui-test` 缓存 → `~/.Trash/floretta-cleanup-*`。保留 `floretta`、`floretta-wt/integration` 与 6 个历史 `.worktrees/*`。
- 仍未完成：① 键位延迟未解决（见上）；② 观感一律由 Timmy 在 TestFlight 验收，助手不做截图/CUA 验收；③ 「备注」命令仓库内不存在；④ Web 端 TD-008 未开始；⑤ iPhone 设置入口已按新形态重做，但真机体验待验。

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
| macOS 辅助功能树 | 🚧 进行中(PR #121；正常启动已可读，`-FlorettaEditChrome` 仍空) | ⛔ 不做(#118 修的是 macOS AX 空树) | ⛔ 不做(#118 修的是 macOS AX 空树) | ⛔ 不做(不适用，Apple 辅助功能) | PR #118 → main `8e50c12`（2026-11-12 19:50:18 CST）延迟打开文档，让首页 WindowGroup 能建窗。2026-11-13 在 `24aa462` 上复测：正常启动的签名与未签名 Debug 都有窗口和 `home.newMap` / `inspector.tabs`。残留：`-FlorettaEditChrome` 仍不创建窗口，03:41:54–03:42:06 CST 复现，AX 只有菜单栏，不得称已完全收口。见 `docs/reviews/AX-TREE-MACOS.md` |
| A27 检查器钉住 | 🚧 进行中(PR #121) | ⛔ 不做(A27 是 macOS 验收项) | ⛔ 不做(A27 是 macOS 验收项) | ⛔ 不做(不适用) | `docs/reviews/A27-inspector-pin-mac.md`；`scripts/assert-macos-a27-inspector-pin.sh`。当前源码签名 Debug（03:48:30–03:48:36 CST）：选中态与空态 Style `MINY=94.0`，`FRAME=945.0,94.0,50.0,24.0`，顶栏同为 `94.0`，空态有 `inspector.empty` /「选择一个主题」。`24aa462` 原树上 Escape / 点击画布会崩溃，不是单纯收起列；已去掉 `containerRelativeFrame`。检查单未改。在 PR #121 合并前不得标 ✅ |
| 外观三模式（经典 / 现代 / 自定义）与开源字体 | 🚧 进行中(PR #119) | 🚧 进行中(PR #119) | 🚧 进行中(PR #119) | ❌ 缺失 | 骨架 `06afca1`；字体 `b4c3ece`；双入口 `ba98953`；见 PR #119 与 `docs/THEME-MODES.md`。共享状态、立即同步、经典+非衬线持久化、标识前缀已在 `AppearanceSettingsTests` 验证（2026-11-12 21:37:44 CST）。画布重拍与 iPad 字体回退见 `docs/THEME-MODES.md`（22:56:04–22:57:01 CST）。E2 对照见 `docs/THEME-MODES.md`：`8e50c12` 原测 59.7 / 57.3 / 59.7，同参数重测 59.3 / 55.5 / 59.7；上轮 `9a92549` 为 59.7 / 55.3 / 59.7，峰值 92.8 MB；干净 tip `aef98b0`（产品代码 `44723d0`）重测为 58.7 / 57.7 / 59，缩放 57.7 / 50，峰值内存 93 MB，不得写成已证实的缓存收益，也不得写成 57–60，也不得再用 `ebe0874` 的 57.2 / 50 或 65.2 MB。70% 裁切根因是 Helvetica / 系统 UI 测宽对 cascade 绘制，不是 log 桶字号差；残留路径见 `THEME-MODES.md`，不是本轮硬阻断。`44723d0` 按绘制同一套 `cachedCTFont` 测宽后，干净树捏合 100/85/70/55% 中心节点「字形样本」完整。FlorettaWeb 自 `ecdf695` 后再无提交，未接入三模式 |
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
| 2026-11-13 | C1 / A27 检查器 AX | 进行中 | 在 main `24aa462` 上判定：正常启动的签名与未签名 macOS Debug AX 树都不空；空树只复现于 `-FlorettaEditChrome`。`24aa462` 上 Escape / 点击画布会触发 Auto Layout 崩溃（`_postWindowNeedsUpdateConstraints`），根因是检查器 `containerRelativeFrame`。去掉后空态可读，选中/空态 Style `MINY=94.0`（03:48:30–03:48:36 CST）。自动化断言 `scripts/assert-macos-a27-inspector-pin.sh`。检查单未改。|
