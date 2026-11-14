STATUS: BLOCKED

# P0 node text input / AX diagnostic contamination

Implementation is complete on `fix/p0-textinput`, based on requested `a4b14b4`. Status remains blocked only on independent CUA runtime input verification; this session did not launch the app, use a simulator, or capture screenshots.

## AX mechanism experiment

Command:

```sh
swift -e 'import AppKit; let view = NSTextView(); view.string = "abc"; print("before: \(view.string)"); view.setAccessibilityValue("probe"); print("after: \(view.string)")'
```

Output:

```text
before: abc
after: probe
```

Confirmed: on this host, setting an `NSTextView` AX value overwrites its text storage.

## Changes

- `Floretta/Shared/Keyboard/NodeTextEditor.swift` (macOS layout around lines 552–579; iOS layout around 1009–1036): removed both platform text-view AX value writes, labels, identifiers, and probe publication calls. Neither text view receives AX state or other AX metadata.
- `Floretta/Shared/Canvas/InfiniteCanvas.swift` (node overlay around lines 662–679; probe views around 2029–2122; `NodeEditChrome` around 2130): removed `NodeEditChrome.accessibilityValue` and its parser helpers. A separate, non-text overlay view now exposes only an `accessibilityIdentifier`, encoding `idle|edit` and fill; geometry remains the element's `XCUIElement.frame`. No AX value/label/help carries state.
- `FlorettaTests/CanvasTests.swift` (around lines 352–367): replaced string-encoding assertions with identifier assertions and added a regression test confirming setting the test identifier leaves `NSTextView.string` unchanged.
- `FlorettaUITests/NodeEditChromeUITests.swift` (around lines 23–47): retained fill and frame/position stability assertions, now reading fill/mode from the overlay identifier and geometry from the element frame rather than AX value.
- `scripts/scan-p0-text-corruption.py`: added a read-only scanner for app document containers, Floretta recovery/autosave, iCloud documents if present, and macOS Autosave Information.

The identifier belongs to a separate, non-text overlay. Updating an identifier does not set the text view's value or content. The text editor has no `accessibilityIdentifier`, `accessibilityLabel`, `accessibilityHelp`, or `accessibilityValue` assignment.

## Affected tests and preserved intent

The initial required search found:

- `FlorettaUITests/NodeEditChromeUITests.swift`: idle/edit state and fill used to come from `canvas.node.chrome`'s AX value. Replaced with the overlay's identifier. Width, height, origin, and fill-equality assertions remain, preserving the requirement that edit chrome does not change while editing.
- `FlorettaTests/CanvasTests.swift`: helper serialization/parser assertions on `NodeEditChrome.accessibilityValue` removed; replaced with exact idle/edit identifier checks plus the regression test.

No test was deleted. `FlorettaTests` test source method count increased by one (123 → 124); full run reports 461 total tests, including 1 skipped.

## Regression reverse verification

Temporary reverse edit replaced the safe test operation with the former unsafe setter:

```swift
view.setAccessibilityValue(identifier)
```

Command:

```sh
xcodebuild test -scheme Floretta-macOS -only-testing:FlorettaTests/CanvasTests/testEditingProbeIdentifierLeavesTextViewContentUntouched CODE_SIGNING_ALLOWED=NO
```

Relevant output:

```text
XCTAssertEqual failed: ("canvas.node.chrome.edit.fill-800020") is not equal to ("user text")
... testEditingProbeIdentifierLeavesTextViewContentUntouched failed
** TEST FAILED **
```

The test was then restored to `setAccessibilityIdentifier`; rerunning the same targeted test passed (`** TEST SUCCEEDED **`). The reverse mutation was not retained.

## Read-only contaminated-document scan

Command: `python3 scripts/scan-p0-text-corruption.py`

Result: **11 matching node texts across 10 user document/recovery files**; no documents were modified. The matching files and node counts:

```text
/Users/TimmySheep/Library/Containers/net.timhuang.floretta/Data/Documents/未命名 15.floretta: 1
/Users/TimmySheep/Library/Containers/net.timhuang.floretta/Data/Documents/未命名 14.floretta: 1
/Users/TimmySheep/Library/Containers/net.timhuang.floretta/Data/Documents/未命名 8.floretta: 1
/Users/TimmySheep/Library/Containers/net.timhuang.floretta/Data/Documents/未命名 10.floretta: 1
/Users/TimmySheep/Library/Containers/net.timhuang.floretta/Data/Documents/未命名 16.floretta: 1
/Users/TimmySheep/Library/Containers/net.timhuang.floretta/Data/Documents/未命名 17.floretta: 2
/Users/TimmySheep/Library/Containers/net.timhuang.floretta/Data/Documents/.未命名 16.floretta.snapshots/00000001.json: 1
/Users/TimmySheep/Library/Containers/net.timhuang.floretta/Data/Documents/.未命名 15.floretta.snapshots/00000001.json: 1
/Users/TimmySheep/Library/Containers/net.timhuang.floretta/Data/Documents/.未命名 10.floretta.snapshots/00000001.json: 1
/Users/TimmySheep/Library/Application Support/Floretta/Autosave/recovery.floretta: 1
```

The ten files are six `.floretta` documents, three snapshot JSON files, and the recovery document (11 nodes total). No matches were found in the separate macOS app container or the inspected macOS Autosave Information directory; the expected Floretta iCloud Documents folder was absent. **Repair actions are intentionally not performed; commander decision is required.**

## Verification

- `xcodebuild -scheme Floretta-macOS -configuration Debug -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO build` — `BUILD SUCCEEDED`.
- `xcodebuild -scheme Floretta-iOS -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build` — `BUILD SUCCEEDED`.
- `xcodebuild build-for-testing -scheme Floretta-iOS -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO` — `TEST BUILD SUCCEEDED` (UI test target compiles).
- `xcodebuild test -scheme Floretta-macOS -only-testing:FlorettaTests CODE_SIGNING_ALLOWED=NO` — 461 tests, 1 skipped, 0 failures.
- `git diff --check` — clean.
- Runtime: **运行时输入验证未做，待审查方 CUA 确认**。

## Review notes

- The open pull request's current head is the authoritative delivery commit.
- Pull request: [#8](https://github.com/Super-Console/Floretta/pull/8), open and not merged.
- No version, LocalAsk, keychain, shared checklist, or user document changes.
- No simulator was started by this task. No custom temporary DerivedData folder was created. Build/test processes exited.
- Performance measurements were not taken; runtime memory/frame-rate/package-size values are unmeasured and should be supplied by the PR review gate.
