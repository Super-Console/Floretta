# Canvas text App build follow-up — 2026-11-14

## Changes

- `Floretta/Shared/Canvas/InfiniteCanvas.swift`: Canvas title/subtitle drawing passed a `some View` to an API that accepts `Text`. Replaced `.foregroundStyle` with `.foregroundColor` and removed `.multilineTextAlignment` to preserve the concrete `Text` type.
- Updated `DONE-canvas-text.md` with root cause, change, command results, size check, and incomplete gates.

## Verification

- macOS `xcodebuild build` with CI no-signing build settings: `BUILD SUCCEEDED`, exit 0.
- iOS `xcodebuild build` with CI no-signing build settings: `BUILD SUCCEEDED`, exit 0.
- `swift test --package-path FlorettaCore`: 378 tests, 1 skipped, 0 failures.
- macOS `FlorettaTests`: 472 tests, 1 skipped, 8 failures (string-catalog lookup and viewport snap assertions), exit 65. The required app-test gate is not met.
- `./scripts/check-size.sh`: macOS payload 18.7 MB under the 25 MB budget; no budget changed.
- No commit or push because the app-test gate is still failing. No simulator shutdown or keychain operation. Temporary DerivedData remains at `/tmp/dd-canvas-text` and `/tmp/dd-canvas-text-ios` pending cleanup approval.
- Performance: 未测.

## Failure triage and final verification — 2026-11-14

- Reproduced the 8 assertions: two in the string-catalog test and six in zoom-stop tests. No test count reduction or weakened assertion.
- **A — catalog:** Added `文字对齐` / Text alignment, `靠左` / Left, `居中` / Center, `靠右` / Right, and `副文本` / Subtitle to `Floretta/Shared/Localizable.xcstrings`, each with `extractionState: manual` and translated `zh-Hans`/`en` string units. Kept `sourceLanguage` as `zh-Hans`. Runtime table already held these entries.
- **C — viewport/display zoom regression:** `CanvasViewport.snapToStop` selected arbitrary whole-percent values (e.g. 1.37); changed it to nearest `ZoomStop`. `CanvasChrome.syncZoomPercent` also showed arbitrary integer percentages; changed it to `ZoomStop.displayPercent`.
- `swift test --package-path FlorettaCore`: 378 tests, 1 skipped, 0 failures, exit 0.
- macOS `FlorettaTests`: 472 tests, 1 skipped, 0 failures, `TEST SUCCEEDED`, exit 0.
- macOS `xcodebuild build`: `BUILD SUCCEEDED`, exit 0.
- iOS `xcodebuild build`: `BUILD SUCCEEDED`, exit 0.
- Logs: `/tmp/canvas-text-core-final.log`, `/tmp/canvas-text-xcode-test-final.log`, `/tmp/canvas-text-build-macos.log`, `/tmp/canvas-text-build-ios.log`.
- Performance remains 未测. No simulator shutdown, keychain operation, merge, LocalAsk change, or version change.
- DerivedData at `/tmp/dd-canvas-text` remains; it was created for this run and no cleanup has been performed.
- GUI 操作未进行；无模拟器或后台测试服务启动。
- Committed and pushed to the existing `feat/canvas-text` branch for PR #9 after all required verification passed.
