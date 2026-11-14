RESULT: PASS

# P0 Runtime Verification

## Route 1 — iOS XCUITest (primary)

Added the permanent `NodeTextInputRegressionTests.testTypingIntoNodePersistsWithoutLeakingEditChrome` test. It creates a map, double-clicks the center-node accessibility probe, sends `测试一二三abc` with `typeText`, checks that the node value contains the full string and excludes `mode=edit`, exits edit mode, re-enters, and checks persistence and the marker exclusion again.

Command:

```text
xcodebuild test -project Floretta.xcodeproj -scheme Floretta-iOS -destination 'platform=iOS Simulator,id=F359BDE6-6F6E-4D31-BF18-CBC20C1473A8' -only-testing:FlorettaUITests/NodeTextInputRegressionTests CODE_SIGNING_ALLOWED=NO -derivedDataPath /tmp/dd-verify-p0
```

Final `xcodebuild test` output:

```text
Test Case '-[FlorettaUITests.NodeTextInputRegressionTests testTypingIntoNodePersistsWithoutLeakingEditChrome]' passed (24.551 seconds).
 Executed 1 test, with 0 failures (0 unexpected) in 24.551 (24.555) seconds
 Executed 1 test, with 0 failures (0 unexpected) in 24.551 (24.558) seconds
 Executed 1 test, with 0 failures (0 unexpected) in 24.551 (24.559) seconds
** TEST SUCCEEDED **
```

Result: the full string was entered and remained after leaving/re-entering node edit; neither text readback contained `mode=edit`.

## Route 2 — macOS visual check (supporting)

- Screenshot: [`VERIFY-P0-macos.png`](VERIFY-P0-macos.png)
- The node visibly showed `中心测试一二三abc`; `abc` wrapped onto the next line. No `mode=edit;fill=…` text appeared. AX readback was `中心测试一二三abc`.
- The window was positioned at desktop x=2800 for the final typing and screenshot. Closing the launch-time recovery prompt with Cancel caused the window frame to read back on the primary display; it was moved back to x=2800 before continuing. The shell `open` used to launch the requested build product may itself have raised the app, so this report does not claim the main display was never affected.
- The recovery prompt offered to restore an unsaved `未命名` map. Cancel was chosen; it was not discarded.

## Not verified

- Alternate input methods / Chinese IME candidate behavior.
- Multiline input and long-text wrapping beyond the short sample above.

## Resource and scope notes

- The iOS test used one simulator (`ASC-iPhone16Pro`); `xcrun simctl list devices booted` was empty after the run.
- The macOS test app launched from `/tmp/dd-verify-p0` was terminated by its own PID. No product code, keychain, merge, or push was changed.
