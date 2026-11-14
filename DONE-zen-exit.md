STATUS: DONE | BLOCKED

## 改动
- `Floretta/Shared/Shell/DocumentEditor.swift:161-172`：Zen 激活时立即挂载官方 `.appleGlassChrome(.toolbarFloatingButton)` 按钮，identifier 保持 `zen.exit`；点击调用 `session.exitZen()`。
- `FlorettaUITests/HomeSmokeTests.swift:467-480`：进入后直接等待按钮，不先点击画布；仍验证退出后工具栏和画布恢复。
- `Tests/FlorettaCoreTests/AppleGlassChromeContractTests.swift:161-170`：契约校验 Zen 激活时按钮可见、使用官方控件。
- `docs/DECISIONS.md:152-156`：修订 D-21，明确退出按钮立即可见。
- `logs/2026-11/zen-exit.md`：追加本轮修改与实测记录。

## 验证

1. 定向 UI 测试：
   ```sh
   CODE_SIGNING_ALLOWED=NO xcodebuild test -project Floretta.xcodeproj -scheme Floretta-iOS \
     -destination 'platform=iOS Simulator,id=F359BDE6-6F6E-4D31-BF18-CBC20C1473A8' \
     -only-testing:FlorettaUITests/A24EditorActionSmokeTests/testSmoke12ZenEnterAndExitRestoresToolbar \
     -derivedDataPath /tmp/dd-zen
   ```
   ```text
   Test Case '-[FlorettaUITests.A24EditorActionSmokeTests testSmoke12ZenEnterAndExitRestoresToolbar]' passed (29.044 seconds).
   Test Suite 'Selected tests' passed at 2026-11-15 03:23:36.197.
   ** TEST SUCCEEDED **
   ```
2. `FlorettaTests`：
   ```sh
   CODE_SIGNING_ALLOWED=NO xcodebuild test -project Floretta.xcodeproj -scheme Floretta-macOS \
     -destination 'platform=macOS' -only-testing:FlorettaTests -derivedDataPath /tmp/dd-zen
   ```
   ```text
   Test Suite 'FlorettaTests.xctest' passed at 2026-11-15 03:25:42.236.
   Executed 470 tests, with 1 test skipped and 0 failures (0 unexpected) in 66.513 (66.638) seconds
   Test Suite 'All tests' passed at 2026-11-15 03:25:42.236.
   ** TEST SUCCEEDED **
   ```
   注：`FlorettaTests` 不属于 `Floretta-iOS` scheme，因此使用包含该 test target 的 `Floretta-macOS` scheme 执行。
3. macOS build：`CODE_SIGNING_ALLOWED=NO xcodebuild build -project Floretta.xcodeproj -scheme Floretta-macOS -destination 'generic/platform=macOS' -derivedDataPath /tmp/dd-zen` → `** BUILD SUCCEEDED **`。
4. iOS build：`CODE_SIGNING_ALLOWED=NO xcodebuild build -project Floretta.xcodeproj -scheme Floretta-iOS -destination 'generic/platform=iOS' -derivedDataPath /tmp/dd-zen` → `** BUILD SUCCEEDED **`。

性能三行：内存未测量；帧率未测量；包体未测量（本次仅修复 Zen 退出控件显隐）。

## 收尾与限制
- **视觉未验证，待 CUA**；未运行完整 `scripts/pre-release.sh`，未改 LocalAsk、钥匙串或版本号。
- `xcodebuild` 已退出。指定模拟器在测试前已 booted；一次被中断的测试使其退出，随后已重新 boot 以恢复原状态。未执行 `simctl shutdown all`，当前保持原先 booted 状态。
- `/tmp/dd-zen` 是本次指定路径的 DerivedData，尚未清理；需用户明确同意后再清理。
- 工作分支为 `fix/zen-exit-immediate`，基于最新 `origin/main`；历史同名任务分支对应已合并 PR #12，因此未改写该分支。
