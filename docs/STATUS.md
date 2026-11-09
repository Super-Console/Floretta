# 状态

## 当前阶段

P0-1 已由总指挥验收（合并 `ef9e4f2`；本机 `xcodebuild` macOS 与 iOS Simulator 均为 BUILD SUCCEEDED，`UIDeviceFamily = [1, 2]`）。

P0-2 已由总指挥验收（11 个测试，TEST SUCCEEDED）。P0-3 不再单开（那些测试已随 P0-2 落地）。

P0-4 已由总指挥验收（20 个测试全绿）。P0 阶段通过。

P1-1 已由总指挥验收（24 个测试全绿）。触控板手势留到 P1-c 再人工验。

P0.5 已由总指挥验收（32 个测试全绿）。DocumentGroup、实验 A/B 没做。

P1-b 双边布局已落盘，等本机 `xcodebuild test`。只有 bilateral，没有其它布局。

Cloud cannot run Xcode; local Mac will pull and xcodebuild; build errors will be pasted back for fixes.

## 下一步

本机 Mac 拉取后运行：

```bash
xcodebuild test -project Floretta.xcodeproj -scheme Floretta-macOS -destination 'platform=macOS'
```

构建或测试错误贴回再改。通过后再放行下一批。

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
