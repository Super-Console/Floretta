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
