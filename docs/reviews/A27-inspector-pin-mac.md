# A27 — macOS Inspector 顶栏固定 AX 证据

## 结论：当前源码构建无法读取 AX `frame.minY`

2026-11-12 01:29:16–01:29:47 CST（Asia/Shanghai）用当前分支源码构建并启动了 `Floretta-macOS`，进程出现了可查询的 AX 窗口，但窗口的 AX 树为空（无 `AXRole` / `AXIdentifier` / `AXTitle`），找不到检查器顶栏「样式 / 演说 / 导图」分段控件，因此**无法读取**有选中节点与空态两套 `frame.minY`。本文件保留 build 8 的旧读数，仅作历史参考，不能作为当前源码的验收证据。

## 当前构建（本次测量）

- **构建产物**：`/tmp/floretta-a24-27/macos-dd-signed/Build/Products/Debug/Floretta-macOS.app`（当前 worktree 源码，Debug，开发者签名 `TeamIdentifier=JY5U4D6JD3`，bundle `net.timhuang.floretta`）。同一源码另一次 `CODE_SIGNING_ALLOWED=NO` 的 ad-hoc 构建（`/tmp/floretta-a24-27/macos-dd/Build/Products/Debug/Floretta-macOS.app`）结果相同。
- **启动参数**：`-FlorettaUITest -FlorettaOpenInspector -FlorettaLanguage zh-Hans`，由测量程序新建进程实例，测完退出，不使用 `/Applications` 里已安装的版本。
- **读取方式**：ApplicationServices 辅助功能，属性名为 `AXFrame`（取 `CGRect.minY`）。查找标识 `inspector.tabs`，或标题同时包含「样式」「演说」「导图」的分段控件，再读其中「样式」子控件的 `AXFrame.minY`。
- **测量时间**：2026-11-12 01:29:16–01:29:47 CST（Asia/Shanghai）。
- **结果**：无法读取。启动后约 20 秒内能拿到 AX 窗口，但随后等待编辑器和分段控件均超时；树转储仅有一个无角色、无标题的节点。测量进程 `AXIsProcessTrusted=true`。
- **有选中节点**：无法读取。
- **未选中空态**：无法读取。

未保存或提交证据截图；未取全屏截图。

## 历史读数（已安装的 1.0 build 8，不是当前源码）

> 以下数字来自已安装的 `/Applications/Floretta-macOS.app`（版本 `1.0`、build `8`），仅作历史记录，**不能作为本 PR 当前源码的验收证据**。

- **有选中节点**：检查器「样式」分段控件的 AX `frame.minY = 184`（桌面坐标）。
- **未选中空态**：同一分段控件的 AX `frame.minY = 496.5`（桌面坐标）；AX 同时显示「选择一个主题」，确认处于空态。
- 窗口当时通过 `set_window_frame` 设在副屏坐标 `x=2600, y=120, width=1100, height=900`。AX 树未暴露 `inspector.header` 容器，仅暴露其「样式」「演说」「导图」分段子控件。
- **184 ≠ 496.5，因此这组历史实测不支持顶栏固定。**

A27 对当前分支仍未验收。检查单上的 `[~]` 不在本 PR 中改动。
