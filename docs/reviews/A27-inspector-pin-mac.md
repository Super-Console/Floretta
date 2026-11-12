# A27 — macOS Inspector 顶栏固定 AX 证据

## 结论：有选中节点可读，空态仍无法读取

2026-11-12 19:32:26–19:32:27 CST（Asia/Shanghai）在当前源码的已签名 Debug 构建上，先等到首页窗口出现，再用 AX 按下 `home.newMap` 打开编辑器后，检查器「样式」分段控件的 AX 树可读。有选中节点时读到了 `frame.minY`。清空选择（Escape，以及此前的画布点击）会收起 macOS `.inspector(isPresented:)` 列，之后树里既没有 `inspector.tabs` /「样式」，也没有 `inspector.open` / `inspector.empty` /「选择一个主题」，因此**空态仍无法读取**。没有编造空态数字。

本文件前面「当前源码构建无法读取」的结论来自 2026-11-12 01:29 CST 的测量，当时进程要么尚未完成启动（`cannotComplete(-25204)`），要么用 `-FlorettaEditChrome` 在 `App.init()` 里打开了文档，SwiftUI 没有实例化 WindowGroup，AX 只有菜单栏。那次读数不能代表本次修复后的源码。build 8 的历史读数仍只作参考。

## 当前构建（本次测量）

- **构建产物**：`/tmp/floretta-ax-tree/macos-dd-signed/Build/Products/Debug/Floretta-macOS.app`（worktree `.worktrees/ax-tree` 当前源码，Debug，开发者签名 `Apple Development: timmysh34@icloud.com (L6544N692J)`，`TeamIdentifier=JY5U4D6JD3`，bundle `net.timhuang.floretta`）。未改 `project.pbxproj`、未使用 Distribution / Developer ID、未导出钥匙串。
- **启动参数**：`-ApplePersistenceIgnoreState YES -FlorettaUITest -FlorettaOpenInspector -FlorettaLanguage zh-Hans`。没有传 `-FlorettaEditChrome`：该参数即使在延迟打开文档之后，仍会让 WindowGroup 不创建窗口（AX 只有菜单栏）。本次用首页的 `home.newMap` 进入编辑器。测量程序新建进程实例，测完退出，不使用 `/Applications` 里已安装的版本。
- **读取方式**：ApplicationServices 辅助功能，属性名 `AXFrame`（取 `CGRect.minY`，屏幕左上原点）。查找标识 `inspector.tabs`（`AXRadioGroup`），再读其中描述为「样式」的 `AXRadioButton` 子控件的 `AXFrame.minY`。测量进程 `AXIsProcessTrusted=true`。
- **测量时间**：2026-11-12 19:32:26–19:32:27 CST（Asia/Shanghai）。同一构建在 19:12 CST 的另一次读取得到相同的 `minY=94.0`（窗口 x 不同，横坐标不同）。
- **有选中节点**：检查器「样式」分段控件的 AX `frame.minY = 94.0`。完整 `AXFrame = (945.0, 94.0, 50.0, 24.0)`。`inspector.tabs` 本身为 `(…, 93.0, 152.0, 26.0)`。当时已选中中心主题，检查器样式区可见，`inspector.empty` 不存在。
- **未选中空态**：无法读取。按下 Escape 后 `HAS_INSPECTOR_TABS=false`、`HAS_INSPECTOR_STYLE=false`、`HAS_INSPECTOR_OPEN=false`、`HAS_INSPECTOR_EMPTY=false`、没有「选择一个主题」。此前向画布空白处发送鼠标点击时，同样会收起检查器列。没有在检查器已关闭的树上编造 `minY`。

未取用作 A27 验收的全屏截图。状态条验收截图见 `docs/reviews/statusbar-macos-light.png` 与 `docs/reviews/statusbar-macos-dark.png`。

## 历史读数（已安装的 1.0 build 8，不是当前源码）

> 以下数字来自已安装的 `/Applications/Floretta-macOS.app`（版本 `1.0`、build `8`），仅作历史记录，**不能作为本 PR 当前源码的验收证据**。

- **有选中节点**：检查器「样式」分段控件的 AX `frame.minY = 184`（桌面坐标）。
- **未选中空态**：同一分段控件的 AX `frame.minY = 496.5`（桌面坐标）；AX 同时显示「选择一个主题」，确认处于空态。
- 窗口当时通过 `set_window_frame` 设在副屏坐标 `x=2600, y=120, width=1100, height=900`。AX 树未暴露 `inspector.header` 容器，仅暴露其「样式」「演说」「导图」分段子控件。
- **184 ≠ 496.5，因此这组历史实测不支持顶栏固定。**

A27 空态在当前源码上仍未读到，因此顶栏是否固定不能用空态对比验收。检查单上的标记不在本 PR 中改动。
