# Zen 退出入口修复

- 修改：`DocumentEditor` 在 `session.zen.isActive` 时显示系统 `.borderedProminent` 按钮，保留 `zen.exit` identifier 并调用 `exitZen()`；未改测试断言。
- 验证：目标 UI 冒烟通过（`TEST SUCCEEDED`）；iOS unsigned build 成功。`FlorettaTests` 与 macOS build 被 macOS Share 扩展签名失败 `errSecInternalComponent` 阻塞，未改钥匙串。UI 视觉待 CUA；未运行完整 pre-release。

## 2026-11-15：Zen 点击画布浮出退出

- 修改：`DocumentEditor` 只在 Zen 且 `isExitAffordanceRevealed` 时显示退出按钮；画布轻点展示并在 2 秒后隐藏，退出 Zen 时取消任务；使用 `appleGlassChrome(.toolbarFloatingButton)`。Esc 与菜单路径未改。
- 测试：契约测试校验状态门控和官方玻璃封装；UI 冒烟测试校验默认工具栏消失、点击画布后退出入口出现、退出后工具栏恢复。
- 决策：追加 D-21，记录默认无 chrome 与可发现退出的平衡，明确不采用常驻按钮的理由。
- 验证：`swift test --package-path FlorettaCore` 378 项、1 项 skip、0 失败；指定 iOS UI 冒烟通过（28.360 秒）；iOS unsigned build `BUILD SUCCEEDED`。
- 反向验证：临时移除 reveal 门控后，`testNamedSurfacesUseTheOfficialChrome` 断言在 `AppleGlassChromeContractTests.swift:160` 失败（1 项测试、1 失败）；恢复门控后同一测试通过（1 项、0 失败）。
- 资源：测试后 booted simulator 数为 0；未执行 `simctl shutdown all`。未操作 Simulator.app 窗口或采集 GUI 截图，因此不宣称完成副屏视觉验收。

## 2026-11-15：Zen 退出入口进入后立即可见

- 基线：最新 `origin/main` 为 `daba736`。先前 `fix/zen-exit` 对应 PR #12 已合并，但其按钮须先点击画布才出现，且 UI 断言随之变弱；本轮在独立分支 `fix/zen-exit-immediate` 修正，没有重写已合并分支。
- 修改：`DocumentEditor` 在 Zen 激活时立即挂载原生玻璃按钮 `zen.exit`，移除点击画布触发展示及 2 秒自动隐藏逻辑；测试改为进入后直接等待按钮并继续验证退出后工具栏恢复；契约与 D-21 同步。
- 定向 UI 冒烟：`testSmoke12ZenEnterAndExitRestoresToolbar` passed（29.044 秒），`TEST SUCCEEDED`。
- `FlorettaTests` 使用 `Floretta-macOS` scheme（iOS scheme 不包含该 target）：470 tests，1 skipped，0 failures，`TEST SUCCEEDED`。运行期间出现 CoreData Contacts/XPC 诊断日志，但测试通过。
- macOS build 和 iOS build 均 `BUILD SUCCEEDED`。
- 中断/路径说明：首次定向执行收到 SIGTERM，未形成有效 xcresult；随后重新执行通过。首次用 `Floretta-iOS` scheme 运行 `FlorettaTests` 被拒（target 不属于该 scheme），改用 `Floretta-macOS` scheme 后通过。
- GUI 视觉未验证，待 CUA；未执行完整 pre-release。测试前目标模拟器已 booted，异常中断后已恢复 booted 原状态，没有关闭其它模拟器或执行 `simctl shutdown all`。
