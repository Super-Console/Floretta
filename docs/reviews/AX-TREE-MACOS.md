# macOS AX 树：复现、根因与修复

完整原始日志留在本机 `/tmp/floretta-ax-tree/`（`before-both-channels.log`、`before-editor-editchrome.log`、`editor-after-makenew.log`、`after-editchrome.log`、`final-probe.log`）。下面是两条通道的原始摘录。时间均为 Asia/Shanghai（CST）。

## 根因

不是控件缺少 `accessibilityIdentifier`。首页在启动完成后本来就有完整的 AX 树（`home.newMap` 等）。

真正让「窗口 AX 树为空」的，是在 `App.init()` / `AppLaunch.make()` 里调用 `openEditChromeSample()` 或 `openPerfFixture()`。此时若已经把主编辑器设进库模型，macOS 上的 SwiftUI 不会实例化 `WindowGroup` 的 content 闭包，`NSApp.windows` 保持为 0，AX 只能看到菜单栏。01:29 CST 那次 A27 测量、以及带 `-FlorettaEditChrome` 的启动，都落在这条路径上。启动瞬间（t+0s）还会出现 `cannotComplete(-25204)`、CG 窗口数为 0，那是启动未完成，不是空树。

修复：`make()` 只把待打开文档记在共享的 `LaunchDocumentQueue.pending`（放在 `DocumentSession.swift`，测试目标也能编译到，不引用仅属于 App 目标的 `AppLaunch`），由 `ContentView.onAppear` 调用 `LibraryModel.openPendingLaunchDocumentIfNeeded()` 再打开。设置页「外观」补了官方 `accessibilityIdentifier("settings.appearance")`。

说明：仅把打开推迟之后，启动参数里如果仍带 `-FlorettaEditChrome`，WindowGroup 还是可能不建窗口（2026-11-12 19:32:59 CST 仍复现，AX 只有菜单栏）。普通启动、以及首页里按 `home.newMap`，窗口和标识都正常。`-FlorettaDoesNotExist` 这类其他参数不会触发这个问题。未改启动参数名称，以免破坏现有 UI 测试调用约定。

## 修复前：`-FlorettaEditChrome` 直接打开文档（2026-11-12 18:55 CST）

AXUIElement（`before-editor-editchrome.log` / 同条件复现 `after-editchrome.log`，19:32:59 CST，推迟打开之后若仍传入该参数，结果相同）：

```
LAUNCH_ARGS=["-FlorettaUITest", "-FlorettaEditChrome", "-FlorettaOpenInspector", "-FlorettaLanguage", "zh-Hans", ...]
TIMEOUT waiting for home.newMap
REASON=no-home-or-editor
==== TREE application-fallback ====
AXApplication sub= id= title=Floretta-macOS desc= value=
  AXMenuBar sub= id= title= desc= value= (0.0, 0.0, 2560.0×30.0)
```

没有 `kAXWindowsAttribute` 文档窗口，也就没有检查器或画布。

## 对照：普通启动首页，两条通道都有窗口（2026-11-12 18:51–18:52 CST）

日志：`before-both-channels.log`。t+0s 启动未完成：

```
======== AX SAMPLE t+0s ========
CopyAttributeNames: cannotComplete(-25204) count=0
kAXWindowsAttribute: cannotComplete(-25204) count=0
==== CGWindowList for pid 28246 count=0 ====
```

t+3s 窗口已在：

```
kAXWindowsAttribute: success(0) count=1
  AXTitle: success(0) value=最近
    AXButton sub= id=home.newMap title= desc=新建导图
tree_node_count=33
```

System Events（同一进程，探针 `AXIsProcessTrusted=true`）：

```
SCRIPT: tell application "System Events" to get name of every UI element of process "Floretta"
EXIT=0
STDOUT:
最近, missing value

SCRIPT: tell application "System Events" to tell process "Floretta" to get {name, role, title, description, position, size} of every window
EXIT=0
STDOUT:
最近, AXWindow, 最近, 标准窗口, 2600, 120, 1100, 900
```

`Floretta-macOS` 进程名的同样脚本结果相同。

## 修复后：首页再按「新建导图」（2026-11-12 19:32:26–19:32:27 CST）

日志：`final-probe.log`。构建路径 `/tmp/floretta-ax-tree/macos-dd-signed/Build/Products/Debug/Floretta-macOS.app`。

AX 标识（检查器、工具栏、画布均可读）：

```
HOME_IDS=..., home.recent, home.recent.row, home.newMap, home.templates, folder
EDITOR_IDS=..., canvas.node.chrome, editor.bottomBar, canvas.tab.0, canvas.tab.add, statusBar.zoom, statusBar.views, editor.canvas, inspector.header, inspector.tabs, inspector.style, ..., smoke.undo, smoke.redo, smoke.delete, basicChain.back, document.title, editor.insert, share.menu, smoke.zen.enter, editor.more
```

System Events：

```
SCRIPT: tell application "System Events" to get name of every UI element of process "Floretta"
EXIT=0
STDOUT:
missing value, missing value

SCRIPT: tell application "System Events" to tell process "Floretta" to get {role, name, description} of every UI element of window 1
EXIT=0
STDOUT:
AXGroup, AXToolbar, AXButton, AXButton, AXButton, missing value, missing value, missing value, missing value, missing value, 组, 工具栏, 关闭按钮, 缩放按钮, 最小化按钮
```

A27「样式」选中态：`MINY=94.0`，`FRAME=945.0,94.0,50.0,24.0`。空态无法读取，原因见 `A27-inspector-pin-mac.md`。
