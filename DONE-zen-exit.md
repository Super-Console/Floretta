STATUS: DONE

## 改动
- `Floretta/Shared/Shell/DocumentEditor.swift`：移除 Zen 常驻退出按钮；画布点击后短暂显示 `zen.exit`，使用 `appleGlassChrome(.toolbarFloatingButton)`，2 秒后自动隐藏；退出 Zen 时取消隐藏任务。Esc 与菜单路径保留。
- `Tests/FlorettaCoreTests/AppleGlassChromeContractTests.swift`：断言退出按钮由 Zen 激活和 reveal 状态共同门控，并继续禁止常驻覆盖层。
- `FlorettaUITests/HomeSmokeTests.swift`：覆盖 Zen 工具栏隐藏、点击画布后退出控件出现、退出后工具栏恢复。
- `docs/DECISIONS.md`：追加 D-21 记录该交互决策及理由。
- `logs/2026-11/zen-exit.md`：追加本轮实现与验证结果。

## 验证

1. `swift test --package-path FlorettaCore`
   - `Executed 378 tests, with 1 test skipped and 0 failures (0 unexpected)`。
2. iOS UI 冒烟：
   ```text
   Test Case '-[FlorettaUITests.A24EditorActionSmokeTests testSmoke12ZenEnterAndExitRestoresToolbar]' passed (28.360 seconds).
   Test Suite 'Selected tests' passed ... Executed 1 test, with 0 failures.
   ** TEST SUCCEEDED **
   ```
3. iOS build：`xcodebuild build -scheme Floretta-iOS -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO -derivedDataPath /tmp/dd-zen` → `** BUILD SUCCEEDED **`。
4. 契约反向验证：临时将 `if session.zen.isActive && isExitAffordanceRevealed` 改为无门控的 `if session.zen.isActive`，运行定向测试，预期失败：
   ```text
   AppleGlassChromeContractTests.swift:160: error: ... XCTAssertTrue failed
   Executed 1 test, with 1 failure
   ```
   随后恢复 reveal 门控并重跑同一测试：`Executed 1 test, with 0 failures`。

## 资源收尾
- UI 测试后 `xcrun simctl list devices booted | grep -c Booted` 输出 `0`；未执行 `simctl shutdown all`。测试结束时目标模拟器已不在 booted 列表中。
- 未触碰钥匙串、未改版本号、未合并 PR、未运行 `scripts/pre-release.sh`。
- 本次通过 `xcodebuild` 执行模拟器 UI 自动化；未操作 Simulator.app 窗口或采集 GUI 截图。macOS 上 Simulator.app 窗口未能由 CUA 发现，故不声称副屏视觉验收。
