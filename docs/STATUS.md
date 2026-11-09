# 状态

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
| 2026-11-10 | 1.3 图片插入 | 待 Censor | 文件选择 / 拖放 / 粘贴；等比不裁切；异步解码走 1.2 spill + 磁盘 LRU；PDF/PNG 按页面分辨率导出。打开 RSS：Darwin `task_info`/`phys_footprint`（不跳过），Linux VmRSS。本机 Linux：1GiB 增量 24576 B，10GiB 增量 4096 B（同进程另一次 10GiB 为 1175552 B），都远小于包体。 |
