STATUS: BLOCKED

# ui-polish-14

## Changes made on `feat/ui-polish-14`

- `InfiniteCanvas.swift`: center a one-root canvas on its measured viewport when the persisted viewport is standard; defer double-tap state changes to the next main-queue turn.
- `DocumentEditor.swift`: remove the bottom view-mode switcher and plus button; put map, focus, and add-canvas commands in the overflow menu; show the glass-backed canvas switcher only when there is more than one canvas; retain the title control in the toolbar.
- `EditorStatusBar.swift` and `FlorettaCore/Layout/EditorStatusBar.swift`: leave only the zoom control in the bottom strip and use the project Apple glass chrome modifier for zoom and canvas tabs.
- `EditorToolbarCatalog.swift`, `HomeSmokeTests.swift`, and affected Core contract tests: update menu availability, identifiers, and placement assertions.

## Incremental test correction

- **Original assertion → replacement:** `status.contains("appleGlassChrome(.toolbarFloatingButton)")` → extract the `EditorStatusControls` section from `EditorStatusBar.swift` and assert it both instantiates `StatusZoomMenu` and applies `.appleGlassChrome(.toolbarFloatingButton)` (also assert the controls accessibility identifier).
- This is not a weakened assertion: the original `status` substring in `DocumentEditor.swift` only instantiates `EditorStatusStrip`; the glass modifier is in the zoom-controls child. The replacement verifies the modifier on the actual child that hosts the zoom menu. Independent source read confirmed `EditorStatusControls.body` wraps `StatusZoomMenu` with the Apple glass modifier (`EditorStatusBar.swift:33–38`), and `StatusZoomMenu` retains `accessibilityIdentifier("statusBar.zoom")` (`:47–60`). The broader `bar` assertions also retain checks for the zoom identifier and glass modifier.

## macOS hang diagnosis

- **Confirmed by the supplied hang report:** all nine main-thread samples are inside an AppKit/SwiftUI layout transaction (`stepTransactionFlush` / `_layoutSubtreeIfNeeded`); project frames include `DocumentEditor.toolbarContext` and the former nested view-mode menu.
- **Original report limit:** the supplied report alone did not establish that a double-click caused the hang or prove a state-write/layout feedback loop. Live evidence below now confirms a node-double-click reproduction, but not the exact mechanism.
- **Live node double-click reproduced the hang on the built test app.** On the secondary display, one foreground pixel double-click on the single root node was followed by an AX state read that stalled for about 12 seconds and returned zero elements. `ps` showed PID 99566 at ~100% CPU. `/tmp/uipolish-dblclick-node.sample` records the main thread in `stepTransactionFlush → NSWindow.layoutIfNeeded → NSView.layoutSubtreeIfNeeded → SwiftUI ViewGraphRootValueUpdater.render → DocumentEditor.body (DocumentEditor.swift:134) → editorPresentations (line 386) → editorToolbar (line 262)`. This is consistent with the supplied layout-transaction hang report and proves the node double-click can trigger the hang in this run; it does **not** isolate the exact state feedback or establish a complete root-cause mechanism.
- **Blank-area comparison:** three foreground pixel double-clicks at a blank canvas location on a separate test process were followed by responsive AX reads. Its main-thread sample `/tmp/uipolish-dblclick-blank.sample` was idle in `mach_msg` / the AppKit event loop, and CPU remained 0%. This does not compensate for the node failure.
- **Centering not accepted:** `.dispatch/shots/macos-canvas-blank-doubleclick.png` shows the single root node at the upper-left, not the visible canvas center. The current iOS capture `.dispatch/shots/floretta-ios.png` is a blank app launch screen, not valid visual acceptance evidence.
- **Conclusion:** the mitigation did not resolve the hang in the tested node-double-click path; the exact cause remains unproven. Centering also failed visual verification. Keep this task BLOCKED; do not describe the hang as fixed or the six-item UI acceptance as complete.

## Verification

- `./scripts/check-floretta-core-imports.sh` — passed: `FlorettaCore` boundary OK.
- `git diff --check` — passed.
- `swiftc -frontend -parse` over the nine changed Swift files — passed (syntax only).
- GUI-session signed build results provided by the user and checked in `/tmp/uipolish-gui-build.log`: macOS `MACOS_BUILD_EXIT=0`, `** BUILD SUCCEEDED **`; iOS `IOS_BUILD_EXIT=0`, `** BUILD SUCCEEDED **`; grep of the log found no `errSecInternalComponent` lines. Earlier unattended-session attempts in this worktree did fail at extension CodeSign; those failures are environment-specific and superseded by the GUI-session build results.
- GUI-session test rerun read from `/tmp/uipolish-gui-tests2.log`: 448 tests, 1 skipped, 0 failures; `** TEST SUCCEEDED **`, `MACOS_TESTS_EXIT=0`, `CORE_GUARD_EXIT=0`. The corrected assertion passed.
- Runtime double-click check: node double-click **failed** by reproducing the layout hang; blank-area double-click **passed** for three foreground attempts. See hang evidence above.

## Screenshots and remaining acceptance

- macOS screenshot exists at `.dispatch/shots/macos-canvas-blank-doubleclick.png`; it records the failed centering result, not acceptance. `.dispatch/shots/floretta-ios.png` is a blank launch screen and is not valid acceptance evidence. Required usable iOS visual evidence remains missing.
- Runtime visual verification found the single root not centered. Removal of the lower-left title, overflow actions, and multi-canvas glass tabs were not verified in representative documents.
- Memory, frame-rate, and package-size impact were not separately remeasured.
- The node-double-click hang and centering failure are known blockers. Any PR must state them; no merge is authorized by this task.

## Delivery

- UI changes committed as `b5eccb1`; delivery notes were committed in a follow-up. Both commits are on `feat/ui-polish-14`, pushed to `origin/feat/ui-polish-14` only.
- Opened draft PR #1: https://github.com/Super-Console/Floretta/pull/1 (`main` base, exact requested title). It is explicitly marked BLOCKED / do not merge and includes the three performance impact lines.
- No merge and no push to `main`.

## Resource closeout

- Ran `xcrun simctl shutdown all`; `xcrun simctl list devices booted | grep -c Booted` returned `0`.
- The test app processes (PIDs 98529 and 99566) are no longer running; no `xcodebuild` process was found. Sampling files and build logs remain under `/tmp`; they were not deleted without cleanup approval.
- GUI操作后来在副屏完成；启动测试 app 时其窗口曾短暂出现在主屏，未在主屏进行交互，随后立即移动到副屏。
