# P0: node text input overwritten by AX probe

## Changes

- Removed accessibility-value writes and all AX metadata from macOS and iOS node text editors.
- Replaced the state probe with a separate non-text overlay exposing only an identifier; geometry remains available as the XCUI frame.
- Updated existing chrome tests without weakening frame/fill invariants; added an AppKit text-preservation regression test and read-only corrupted-document scanner.

## Verification

- Confirmed with `NSTextView`: `string` changes from `abc` to `probe` after `setAccessibilityValue("probe")`.
- Reversed the new test to use the unsafe setter: it failed because `string` became the diagnostic identifier; restored safe setter and targeted test passed.
- macOS and iOS `CODE_SIGNING_ALLOWED=NO` builds succeeded; iOS test bundle build-for-testing succeeded.
- macOS unit suite: 461 tests, 1 skipped, 0 failures.
- Read-only scan found 11 matching nodes across 6 document/recovery files. No user document was changed; repair awaits commander decision.
- Runtime editing remains pending independent CUA verification.

## Runtime verification follow-up (2026-11-14)

- Added `FlorettaUITests/NodeTextInputRegressionTests.swift`, registered it in `Floretta.xcodeproj/project.pbxproj`, and captured the result in `docs/reviews/VERIFY-P0.md`.
- iOS XCUITest on `ASC-iPhone16Pro` passed: typed `测试一二三abc`, asserted no `mode=edit`, left/re-entered edit, and verified persistence. Final output: `Executed 1 test, with 0 failures (0 unexpected)`.
- Built the macOS app from this worktree and visually checked the node. AX readback was `中心测试一二三abc`; no edit-chrome marker was visible. Screenshot: `docs/reviews/VERIFY-P0-macos.png`.
- Input-method candidate behavior, multiline input, and longer wrapping remain unverified. The launch-time unsaved-map recovery prompt was canceled, not discarded.
