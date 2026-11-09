# 复用审计（P1-r）

每一节都有结论。版本是 2026-11-09 读到的提交，不是“没查过”。

| 项目 | 版本 | 许可证 | 这次怎么用 |
|---|---|---|---|
| SwiftFlow | tag `v0.3.1`，commit `98ff46633257d188f1819255df8c8453a9b72d8f` | MIT（根 `LICENSE.md`） | SPM 依赖，三个 target 都链 |
| Mindscape | `0.7.0`，commit `258dfe9eac45aba4607afd09309ada88554988b5` | MIT | 不链、不拷文件；组字行为按它的原因对齐 |
| Brainstorm | commit `59c4fe99b110f5dedc955da2bc578bd7a62df749`（2026-07-26） | MIT | 不链、不拷。键盘规则和我们的规格相反 |
| SimpleMindMap | commit `e8e5ef9c41bc13ca7b13084e078123adff002242` | MIT | 不链。JS，只留作以后读 `.xmind` 结构 |
| Freeplane | 仓库根 `license.txt` 为 GPL-2.0 | GPL-2.0 | 不复制代码 |

## 视口 / 变换

**用了 SwiftFlow。** `CanvasViewport` 保存它的 `Viewport`。屏幕点和画布点通过 `SwiftFlowInstance.screenToFlowPosition` / `flowToScreenPosition`。绕指针缩放调用 `SwiftFlowInstance.zoomTo`：这个方法锚在视图中心，所以调用前把视图尺寸设成指针的两倍，让中心落在指针上。适配调用公开函数 `getViewportForBounds`。

**差异：** 适配的最大缩放仍是 1.25，避免一个小节点铺满窗口。SwiftFlow 自己的适配上限更高。滚轮的缩放系数仍是我们的指数，真正改视口的是它的 `zoomTo`。交互缩放范围用它的 0.1…4，不再用我们以前的 0.2 下限。没有换成它的 `SwiftFlow` 视图、手势或小地图。

## 命中测试

**用了 SwiftFlow `getIntersectingNodes`。** 布局框变成它的 `Node`（左上角、宽高），点一下是一个 0.01 的探测节点。后画的框 `zIndex` 更大，重叠时取最大的。只拖根节点仍是我们的过滤。

**差异：** 不用它的框选。思维导图节点不是它的图节点模型，探测只为命中。

## LayoutEngine

**继续自研。** SwiftFlow 的 `computeAutoLayout` 是通用图布局，没有“按子树高度左右分边、父节点在整棵高度里居中”。yFiles 一类是商业授权，也不是这个语义。双侧布局留在 `LayoutEngine`。

## 键盘映射 / 会话

**不用 Brainstorm 的 `BrainstormKeyRouter`。** 读了 `ContentView.swift` 里那个路由（commit `59c4fe9`）。它在编辑中也用 Tab 建子节点，Return 会提交并新建同级。我们的规格是编辑中 Tab / Return 不建节点，Return 只提交，Shift+Return 才换行。直接移植会破坏 `KeyboardCommandMapper`。撤销也是它的 store，和我们的文档快照不是同一套。

**差异：** 我们保留纯函数映射、组字时一律空、命令模式才 ⌘Z。方向键的同侧规则是我们的布局语义，Brainstorm 没有这套双侧分列。

## IME / 编辑器

**对照了 Mindscape，没有拷它的文件。** `MindCanvasView.swift`（0.7.0）用 `NSTextView` 子类重写 `setMarkedText` / `unmarkText`，因为组字不触发 `textDidChange`。它先把编辑框按未折行宽度撑开，再把含组字的字符串写回模型，这样节点变宽、候选框留在节点上。它还警告：每次按键重写 `textStorage` 属性会打断组字。只有 AppKit，没有 iOS。

**我们做了什么：** macOS `EditingTextView` 和 iOS 文本框在同一对回调里把组字标成 `isComposing`，把当前字符串写进节点，并把编辑框最小宽度设成这段文字的单行宽度。候选框仍由系统文本框贴在插入点，不自画。编辑中不重写整段属性。字号用节点字号乘当前缩放。

**差异：** 没有移植它的相机、测量常数（226/192）或 SQLite。`isComposing == true` 时 `KeyboardCommandMapper.map` 仍返回空，组字确认键不会建节点或取消编辑。

## 文档模型 / codec

**自研，三个候选都不能当实现。** SwiftFlow 的 JSON 是图节点和边，没有 `formatVersion`、有序根、折叠和备注。Mindscape 存 SQLite。Brainstorm 的 `.bs` 是另一套 JSON。`.floretta` 的字段以任务书为准，环和错类型仍由 `FlorettaCodec` 报。

## ZIP 容器

**自研。** 上面四个项目都没有我们的 `document.json` + `metadata.json` + `assets/<sha256>` 容器，也没有“旧 JSON 只读、不许覆盖原文件”。SwiftFlow 的序列化是另一份 JSON。Freeplane 的 `.mm` 是 XML，而且 GPL，不能拿它的读写代码。解压限制和 method 8 inflater 是仓库里自己的。

## 自动保存

**自研。** 看过的项目没有一个提供“Application Support 里每 5 秒原子替换、正常退出删除、异常退出用系统 alert 恢复”这一套。路径和恢复语义跟 Floretta 的恢复副本绑在一起，不适合抽它们的存储层。

## 画布装饰（缩放百分比、适配、底栏页）

**不用 SwiftFlow 的 Controls / MiniMap。** 那些控件是它自己的图画布（缩放按钮、小地图、网格），不是思维导图的底栏多页，也不认识我们的 `CanvasChrome`。缩放百分比、Fit、页签状态留在 `InfiniteCanvas`。适配的数学已经走 `getViewportForBounds`。

## `.xmind` / `.mm`（这批不做格式）

**SimpleMindMap：** MIT，JS。字段映射以后做 `.xmind` 导入时再读，这批不搬代码，也不把 JS 打进 App。

**Freeplane：** 根 `license.txt` 是 GPL-2.0。只确认了许可证。没有把 Java 源码拷进仓库，也没有把它的类改写成 Swift。`.mm` 以后若做，只按公开 XML 结构写。
