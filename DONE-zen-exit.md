STATUS: BLOCKED

## 改动
- `Floretta/Shared/Shell/DocumentEditor.swift:172-184`：Zen 激活时显示原生 `.borderedProminent` 退出按钮，identifier 保持 `zen.exit`，点击调用 `session.exitZen()`；未改弱既有测试断言。
- `logs/2026-11/zen-exit.md`：本次变更与验证记录。

## 验证

1. UI 冒烟（按要求执行的命令）：
```text
Test Case '-[FlorettaUITests.A24EditorActionSmokeTests testSmoke12ZenEnterAndExitRestoresToolbar]' passed (21.802 seconds).
Test Suite 'A24EditorActionSmokeTests' passed at 2026-11-14 23:58:20.438.
Test Suite 'FlorettaUITests.xctest' passed at 2026-11-14 23:58:20.441.
Test Suite 'Selected tests' passed at 2026-11-14 23:58:20.442.
** TEST SUCCEEDED **
```

2. `FlorettaTests`：`Floretta-iOS` scheme 不包含该测试 target（xcodebuild 原文：`Tests in the target “FlorettaTests” can’t be run because “FlorettaTests” isn’t a member of the specified test plan or scheme.`）。改用 `Floretta-macOS` scheme 后，构建其 Share 扩展时失败：`errSecInternalComponent` / `Command CodeSign failed with a nonzero exit code`，测试未执行，故无法报告总数或零失败。

3. 双端构建：
```text
iOS: ** BUILD SUCCEEDED **
macOS: /tmp/dd-zen/Build/Products/Debug/FlorettaShare-macOS.appex/Contents/MacOS/FlorettaShare-macOS.debug.dylib: errSecInternalComponent
macOS: ** BUILD FAILED **
```
macOS 构建所需签名受本机钥匙串错误阻塞；未触碰钥匙串。

## 其他
- 未运行 `scripts/pre-release.sh`。
- 未执行 `simctl shutdown all`；测试前后均未留下 booted simulator。
- 视觉未验证，待 CUA。
