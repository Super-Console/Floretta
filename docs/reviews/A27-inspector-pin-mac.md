# A27 — macOS Inspector 顶栏固定 AX 证据

## 结论：选中态与空态都可以读到，minY 一致

2026-11-13 03:48:30–03:48:36 CST（Asia/Shanghai）在当前源码的已签名 Debug 构建上，先等到首页窗口出现，再按 `home.newMap` 打开编辑器。检查器「样式」分段控件在有选中节点和清空选择后都可读，`AXFrame.minY` 相同。自动化断言见 `scripts/assert-macos-a27-inspector-pin.sh`。

本文件前面「空态仍无法读取」「Escape 或点击画布会收起 inspector 列」的结论，来自 2026-11-12 19:32 CST（PR #118）以及更早 01:29 CST 的测量。2026-11-13 在 main `24aa462` 上复测时发现：那种「窗口突然读不到」其实是进程在 Auto Layout 更新周期里崩溃（`EXC_BREAKPOINT` / `NSWindow._postWindowNeedsUpdateConstraints`），不是检查器被正常收起。根因是 `inspectorBody` 上的 `.containerRelativeFrame(.vertical) { length, _ in length }` 在列高或页面高度变化时回写约束。去掉该修饰后，空态可以读，检查器列仍在。

## 当前构建（本次测量）

- **构建产物**：`/tmp/floretta-inspector-ax/macos-dd-signed/Build/Products/Debug/Floretta-macOS.app`（worktree `.worktrees/inspector-ax`，当时 HEAD `24aa462` 加本次 inspector 布局修复；Debug，开发者签名 `Apple Development: timmysh34@icloud.com (L6544N692J)`，`TeamIdentifier=JY5U4D6JD3`，bundle `net.timhuang.floretta`，版本 1.0(13)）。未改 `project.pbxproj` 的签名项、未使用 Distribution / Developer ID、未导出钥匙串。
- **启动参数**：`-ApplePersistenceIgnoreState YES -FlorettaUITest -FlorettaOpenInspector -FlorettaLanguage zh-Hans`。没有传 `-FlorettaEditChrome`：该参数启动后 WindowGroup 仍不建窗口，AX 只有菜单栏。本次用首页的 `home.newMap` 进入编辑器。测量程序新建进程实例，测完退出，不使用 `/Applications` 里已安装的版本。
- **读取方式**：ApplicationServices 辅助功能，属性名 `AXFrame`（取 `CGRect.minY`，屏幕左上原点）。查找标识 `inspector.tabs`（`AXRadioGroup`），再读其中描述为「样式」的 `AXRadioButton` 子控件的 `AXFrame.minY`。测量进程 `AXIsProcessTrusted=true`。清空选择：在 `editor.canvas` 框的 (20%, 40%) 处点击（Escape 不会取消中心主题的选中，`handleEscape()` 只处理禅模式）。
- **测量时间**：2026-11-13 03:48:30–03:48:36 CST（Asia/Shanghai）。日志 `/tmp/floretta-inspector-ax/empty-probe-after-fix.log`。
- **有选中节点**：检查器「样式」分段控件的 AX `frame.minY = 94.0`。完整 `AXFrame = (945.0, 94.0, 50.0, 24.0)`。`inspector.header` 为 `(945.0, 94.0, 150.0, 24.0)`。当时已选中中心主题，`inspector.style` 在树上，`inspector.empty` 不存在。
- **未选中空态**：同一分段控件的 AX `frame.minY = 94.0`。完整 `AXFrame = (945.0, 94.0, 50.0, 24.0)`。`inspector.header` 仍为 `(945.0, 94.0, 150.0, 24.0)`。`HAS_INSPECTOR_EMPTY=true`，AX 同时显示「选择一个主题」。窗口仍在（`WINDOW_COUNT=1`），没有新的崩溃报告。
- **94.0 = 94.0**，选中态与空态的「样式」分段和顶栏 `minY`、尺寸都一致，支持顶栏固定。

修复前（同一签名构建、去掉 `containerRelativeFrame` 之前）Escape 或点击画布会在 0.2 秒内变成 `WINDOW_COUNT=0`，随后进程退出。崩溃报告：`/tmp/floretta-inspector-ax/crashes/Floretta-macOS-2026-11-13-034129.ips`、`034343.ips`、`034417.ips`（另一次复现 `034704.ips`）。

`-FlorettaEditChrome` 启动路径仍然没有文档窗口，见 `docs/reviews/AX-TREE-MACOS.md`。本项验收不走那条参数。

检查单上的标记不在本 PR 中改动。

## 历史读数（已安装的 1.0 build 8，不是当前源码）

> 以下数字来自已安装的 `/Applications/Floretta-macOS.app`（版本 `1.0`、build `8`），仅作历史记录，**不能作为本 PR 当前源码的验收证据**。

- **有选中节点**：检查器「样式」分段控件的 AX `frame.minY = 184`（桌面坐标）。
- **未选中空态**：同一分段控件的 AX `frame.minY = 496.5`（桌面坐标）；AX 同时显示「选择一个主题」，确认处于空态。
- 窗口当时通过 `set_window_frame` 设在副屏坐标 `x=2600, y=120, width=1100, height=900`。AX 树未暴露 `inspector.header` 容器，仅暴露其「样式」「演说」「导图」分段子控件。
- **184 ≠ 496.5，因此这组历史实测不支持顶栏固定。**
