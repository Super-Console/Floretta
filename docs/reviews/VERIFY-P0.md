RESULT: FAIL

# P0 节点文本运行时验证

- **目标版本**：`origin/main` / `8cd2fd6f371b6fe84171d0681d28e2478b89f91e`
- **构建**：`xcodebuild build -project Floretta.xcodeproj -scheme Floretta-macOS -destination 'platform=macOS' -derivedDataPath /tmp/dd-verify-p0 CODE_SIGNING_ALLOWED=NO` — `BUILD SUCCEEDED`
- **实际进程**：PID `73566`，可执行文件 `/private/tmp/dd-verify-p0/Build/Products/Debug/Floretta-macOS.app/Contents/MacOS/Floretta-macOS`（已用 `ps` 核实）。未测试 `/Applications/Floretta-macOS.app` 的旧进程 PID `31179`。
- **启动限制**：CUA `launch_app` 不接受构建产物路径作为 app name（原文：`No installed macOS app found for name '/tmp/dd-verify-p0/Build/Products/Debug/Floretta-macOS.app'.`）。因此用 CUA 在 Finder 中打开了该构建产物；无法向该启动方式传入 `-ApplePersistenceIgnoreState YES`。应用随后出现“要恢复未保存的导图吗？”提示，选择了“取消”，未恢复也未丢弃那份既有地图。

## 五项判定

1. **FAIL / 未能验证** — 截图 `01-launch.png`、`02-edit.png`：画面停留在“最近”主页，没有进入地图画布或节点编辑器；未实际键入目标文本。
2. **FAIL / 未能验证** — 截图 `02-edit.png`：仍为“最近”主页，未进入编辑态，因此没有退出再进入。
3. **FAIL / 未能验证** — 截图 `02-edit.png`：主页没有节点文本视图，无法判断是否出现 `mode=edit;fill=…`。
4. **FAIL / 未能验证** — 截图 `02-edit.png`：显示主页而非编辑画布，无法判断编辑时画布是否空白。
5. **FAIL / 未能验证** — 截图 `02-edit.png`：没有可见节点或节点文字，无法判断文字是否居中。

现有截图：
- `verify-p0-2026-11-14/01-launch.png` — 构建版应用主页（最近地图列表）。
- `verify-p0-2026-11-14/02-edit.png` — 未进入编辑时的应用主页；不是编辑画布截图。
- `verify-p0-2026-11-14/00-finder.png` — Finder 中的构建产物定位过程（辅助证据）。
- `03-typed.png`、`04-after-reexit.png` 未生成：没有发生键入或重新进入编辑，不能伪造阶段截图。

## 键入后文本视图的实际字符串

无。没有进入节点编辑态，也没有找到可读的文本视图；因此没有向不明焦点发送文本。文本视图 AX value：**不存在/不可读取（未能取得 value）**。`type_text` 未对节点编辑器调用，故没有节点键入返回码；不能把这表述成已键入 0 个字符。

## FAIL 原因、错误原文与已排除假设

阻塞发生在主页的“新建导图”操作之前/期间，尚未到达双击节点步骤。窗口 `862` / PID `73566` 的 CUA 读取返回：

> `ax_window_unresolved: window_id 862 exists and is owned by pid 73566, but none of the 0 AXWindow element(s) under that pid reports this CGWindowID. The tree is returned EMPTY on purpose: the accessibility elements reachable under this pid belong to other surfaces (the menu bar, other windows), not to the requested window, so presenting them would misground the next action.`

可见的 CUA 错误还包括：
- 新建导图 AXPress：`AXUIElementPerformAction(AXPress) returned -25204`。
- 像素输入升级：`No screenshot of window 862 in this session: it has not been read yet. Call get_window_state(pid:73566, window_id:862) and take x,y from that window's own screenshot; pixels read off another window's screenshot do not apply to it.`
- 精确 PID 的 CUA 命名查找：`no button "新建导图" in window 862; the window has no readable elements`。
- 以 bundle id 查找会选中旧进程 PID `31179` 的“设置”窗口；该查找失败于元素定位阶段，**没有执行点击**。

已排除：目标构建成功；实际被启动的是 DerivedData 下的可执行文件而不是 `/Applications` 旧版；测试期间没有恢复旧地图，也没有执行丢弃操作。尚不能排除应用本身的节点输入问题，因为运行时验证未到达节点编辑器。

## 未验证的部分

- 中文/英文实际键入与 AX value 原文
- 编辑退出后内容保留
- 调试串是否出现
- 编辑时画布渲染、文字居中
- 多行、中文输入法候选、长文本换行
- `-ApplePersistenceIgnoreState YES` 启动效果（CUA 路径限制）

## 运行资源与 GUI 影响

- GUI 操作已在副屏完成，主屏未被打扰（目标窗口 bounds 的 x 为 `2700`，副屏起点 x≥`2560`）。
- 未启动模拟器；`xcodebuild` 已退出。`/tmp/dd-verify-p0` 按要求保留。
- **测试 App 尚未关闭**：对 PID `73566` 发送 Cmd+Q 两次后，CUA 仍回报进程运行；`kill_app` 返回 `standard mode may terminate only a process proven to have been launched by this Cua runtime`。未用 shell 或其他方式绕过该权限限制。请用户在副屏关闭该测试实例。
