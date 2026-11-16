# 打字卡顿、Backspace 与缩放卡顿

## 2026-11-16 阶段记录

### 当前进度

- A 探针已加上 `NSTextView.keyDown` 到实际文本提交的计时，以及 `MacEditorContentHost` root 写入、工具栏快照求值和 text view 第一响应者/marked text 计数。**尚未运行 GUI 探针**，英文字符与苹果拼音提交的基线和修复后 p50/p95 均未取得，不能据此认定性能根因或修复有效。
- 静态代码可确认 `MacEditorContentHost.updateNSView` 目前无条件赋值 `host.rootView = hostedContent`，且 `currentMacToolbarSnapshot` 在 `MacEditorContent.body` 中求值；这只证明代码路径存在，不能代替运行时因果测量。
- B 在 `InfiniteCanvas.applyNodeTap` 的 command-mode 选择分支请求 canvas 焦点；补了选中子树 Backspace 删除并由一次 ⌘Z 恢复、以及编辑态/marked composition 不触发节点删除的 Core 测试。
- C 缩放测量与修复尚未开始；按任务顺序需先完成 A、B。

### 验证

- `swift test`：588 项执行，0 失败，1 项跳过；新增两项 Backspace 测试均通过。
- iOS 模拟器目标 `xcodebuild build -scheme Floretta-iOS -destination 'generic/platform=iOS Simulator'`：构建成功；输出含项目既有 Swift concurrency/deprecation warnings。
- macOS `xcodebuild build -scheme Floretta-macOS -configuration Debug -destination 'platform=macOS,arch=arm64'`：Swift 编译阶段到达签名步骤，但 Share 扩展签名以 `errSecInternalComponent` 失败，整体构建未通过。
- `xcodebuild test -scheme Floretta-macOS -destination 'platform=macOS,arch=arm64' -only-testing:FlorettaTests`：同一签名错误导致测试取消，尚无 FlorettaTests 结果。
- 系统可列出有效代码签名身份，但这不证明对应私钥可供 codesign 使用；未尝试禁用签名或改动钥匙串权限。
- 未启动 App/模拟器、未截图、未清理 DerivedData。任务未完成，未提交或推送。

### 阻塞与续做

需要在图形会话恢复 Xcode 对签名私钥的访问后继续。随后先以当前未修复状态取得同探针基线，再修 A 并复测英文字符、苹果拼音、Tab/方向键；完成 B 的指定测试及两端验证后，再测和修复 C 缩放性能，补齐最终实测数据。任务书文件保留为未跟踪文件，不纳入提交。

## 2026-11-17 阶段记录：基线 GUI 尝试受阻

### 已确认

- `/tmp/dd-base/Build/Products/Release/Floretta.app` 与 `/tmp/dd-typing/Build/Products/Release/Floretta.app` 均存在；本轮未重建。
- 通过 `launchctl` 启动基线文本探针（120 个提交样本）。Floretta 窗口位于副屏（屏幕坐标 x=2620），Google Chrome 始终保持前台。
- 基线任务创建了 `/tmp/typing-lag-runners/base/uitest/` 下的临时测试文档；探针 stdout 为空，未生成 `/tmp/floretta-key-latency.json`，因此**没有取得任何延迟样本**。
- 当前输入源只读检查为 Apple Pinyin（`com.apple.inputmethod.SCIM.ITABC`）。后台按键未进入文本编辑器；真实输入测量需要短暂前台键盘输入。当前执行环境不支持交互问询，未尝试前台操作，等待用户在会话中明确授权。
- 曾通过 CUA 窗口状态检查捕获副屏画面（未保存为截图文件）；这与 `BRIEF.md` 的“不截图”约束不一致，需在交付时如实说明。主屏未被操作，前台应用未改变。
- 已通过后台退出命令关闭测试 App；当前 launchd job 为 `not running`，Floretta 窗口列表为空。

### 后续

- 若获准短暂对副屏测试窗口使用前台键盘输入，重新启动基线探针后完成英文与 Pinyin 提交测量，再继续 A/B；否则停止 GUI 采样并保留未测状态。
- 本轮未改动代码，未产生提交。临时 plist、日志与测试 fixture 仍留在 `/tmp/typing-lag-runners/base/`，未清理。

## 2026-11-17 阶段记录：测试包后台启动路径仍受阻

### 已确认

- 当前分支 HEAD 为 `29df9553`，基线 worktree HEAD 为 `4e2c1bd5`；继续前复核后，两边原有改动仍在，未新增或覆盖源码改动。
- 当前与基线的本地测试包均为 Release，位于 `/private/var/folders/p1/3pqx3j392m381v0g293m9rgc0000gn/T/opencode/floretta-typingzoom-{current,base}-20261117-dd/Build/Products/Release/Floretta.app`；两包的 `CFBundleIdentifier` 都是 `net.timhuang.floretta`。
- CUA 的应用目录将 `net.timhuang.floretta` 解析到 `/Applications/Floretta.app`，而不是这两份临时构建。故没有按 bundle ID 启动，以免把已安装版本误当作测试对象。上次对本地 bundle 路径的 CUA 启动请求被拒绝为 `No installed macOS app found`。
- 已有的 `launchctl` 直启记录仍无 stdout/stderr、无窗口且没有性能 JSON；本次只读复核未发现 Floretta 或 `xcodebuild` 存活进程，CUA 的 Floretta 窗口列表为空。
- 真实 Apple Pinyin 采样仍需前台键盘事件；先前后台输入没有进入文本编辑器。当前会话未取得创建临时测试启动入口或短暂前台输入的授权；交互式授权工具在此非交互运行中被拒绝，故没有执行这些操作。

### 结果与限制

- 没有重跑出可归因的 zoom outlier，也没有取得新的英文或 Apple Pinyin keyDown→提交样本；因此没有修复/回退依据，回归仍未解决，A 部分仍没有真实数字，禁止 commit。
- 本阶段没有改源码、启动测试 App、截屏或清理文件。两份 DerivedData 与 `/tmp/floretta-typingzoom-runners-20261117/` 均保留；没有使用模拟器，也没有遗留运行中的测试进程。

### 续做所需

- 需先获准为两份精确的本地测试包建立临时、可由 CUA 隐藏启动的唯一入口（不得指向 `/Applications/Floretta.app`），再将窗口移到副屏并确认窗口位置后运行 zoom 同探针。
- A 部分还需 Timmy 明确允许仅在副屏对测试窗口短暂发送前台键盘事件，才能取得真实英文与 Apple Pinyin 输入法样本；未获准前不模拟该输入、不报告推测数字。

## 2026-11-17 阶段记录：测试副本准备完成，锁屏阻断测量

### 已完成

- 按本轮授权，将本地 base/current Release app bundle 分别复制到 `~/Applications/Floretta Base Probe.app` 与 `~/Applications/Floretta Current Probe.app`。只修改副本 `Contents/Info.plist` 的 `CFBundleIdentifier`：`net.timhuang.floretta.base-probe`、`net.timhuang.floretta.current-probe`；逐文件清单、文件哈希及 plist 其他键回读验证均与对应源包一致。CUA 的 app 清单将两个 ID 分别解析到这两个准确路径。
- 两份源包和副本的 `codesign --verify --deep --strict` 均报告相同的 `code has no resources but signature indicates they must be present`；源包为 ad-hoc 签名且 `Info.plist=not bound`。该签名校验失败并非副本 bundle ID 修改独有；本记录不据此判断运行失败原因。
- 以副本 ID 启动 base，并传入 `-FlorettaPerfNodes 12`。CUA 窗口清单报告两个窗口位于 x=2848、3095（均满足项目副屏 x≥2560 约定）；启动结果 `self_activation_suppressed=true`。未截屏、未发送任何键盘输入。
- `get_window_state` 返回 `screen_locked`，明确拒绝窗口输入/AX 操作。未尝试唤醒或解锁。未找到本次新生成的 `canvas-perf-12.json`；测试实例 PID 18336 已经 CUA 终止，之后 `ps -p 18336` 无结果。
- 当前选中的输入源只读回读为 ABC；Apple Pinyin（`com.apple.inputmethod.SCIM.ITABC`）列于启用输入源中。锁屏期间未切换输入源，也未发送英文或拼音按键。

### 未完成与续做

- 本轮没有获得新的缩放或键盘样本，不能据此报告新的 p50/p95、不能认定缩放根因已定位/修复。现有可引用的失败观测仍是既有记录中的 base-12 minFPS 60 / maxDraw 9.5 ms 与 current-12 minFPS 2 / maxDraw 225.1 ms；本轮没有复现或修复它。
- 两份测试副本暂留在 `~/Applications`，未移入废纸篓，因为本轮测试尚未完成；源 bundle 未修改。无源码改动、无测试运行、无 commit/push/merge。
- 续做前需先由 Timmy 解锁 Mac；之后沿用本轮授权，不需要再次确认范围。GUI/键盘操作仍只在副屏窗口进行；完成后按授权将两份副本移入废纸篓。

## 2026-11-17 阶段记录：zoom 复测通过，current Release 编译阻断

### Zoom 复测

- 回读六份 12 节点 zoom JSON：base 三次 `minFPS=80/80/82`、`maxDrawMs=5.7/5.4/5.1`；current 三次 `minFPS=80/80/80`、`maxDrawMs=5.1/9.6/5.8`。旧 outlier 未复现，结论已追加至 `zoom-regression-finding.md`。没有据此改产品绘制或布局代码。

### 探针与构建

- 检查发现 text probe 若在 IME marked composition 期间遇到 Core Animation `.committed`，会提前结束样本。已把 `KeyLatencyProbe.mark` 改为 text run 只在 `.textSubmitted` 结束；相同改动同时写入 baseline/current worktree。该修正只限测量探针。
- Baseline Release：`xcodebuild build -scheme Floretta-macOS -configuration Release -derivedDataPath /tmp/dd-base CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=`，`BUILD SUCCEEDED`。
- Current Release：相同命令，`/tmp/dd-typing`，`BUILD FAILED`。编译器报告 `DocumentEditor.swift` 多处调用 `session.finishEditingIfNeeded()`（行 1604、1640、1647、1654、1661、2219、2235）不可访问；声明位于 `DocumentSession.swift:884` 且为 `private`。该问题不在本次 probe 改动中，本阶段未改该产品代码。
- `/tmp/dd-base` 可执行文件已更新；`/tmp/dd-typing` 仍是先前 00:02 的旧产物，不能代表当前源码。没有启动任何 app 或发送键盘输入，因此本阶段没有有效英文或 Apple Pinyin 延迟样本，也没有 current 性能数据；没有 commit。

### 续做阻塞

- 需先处理 `DocumentSession.finishEditingIfNeeded` 的跨文件访问编译错误，再重建 current Release。修复前不使用旧 current 二进制冒充当前版本，也不报告 p50/p95。

## 2026-11-17 阶段记录：菜单提交的跨文件访问修复

- `git blame` 确认 `DocumentEditor.swift` 中这些调用由本分支提交 `534bf7f`（`Expand macOS editor menus`）引入；方法声明早于该提交，位于 `DocumentSession.swift:884`，原为 `private`。
- 修复前 Release 编译复现 7 处 `inaccessible due to 'private' protection level`。只将声明改为 `internal`，未改调用、实现、行为或绘图代码。
- 修复后 macOS Release：`xcodebuild -scheme Floretta-macOS -configuration Release -destination 'generic/platform=macOS' ... CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= build`，`BUILD SUCCEEDED`。第一次并行编译尝试出现 SwiftCompile 子命令报 exit code 0 但无输出；使用 `-jobs 1` 对同一 DerivedData 重跑成功。
- 修复后 iOS Release：`xcodebuild -scheme Floretta-iOS -configuration Release -destination 'generic/platform=iOS' ... CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= build`，`BUILD SUCCEEDED`。
- 本段记录尚未完成 typing GUI 采样；base/current 英文与 Apple Pinyin 的 p50/p95 与每键样本数仍待取得。
