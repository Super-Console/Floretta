# UI polish 14

## Changes

- `InfiniteCanvas` recenters a single root on first appearance only when the stored viewport is standard, using the measured canvas size and root frame. Canvas double-tap handling is deferred to the next main-queue turn before editing or document state is changed.
- `DocumentEditor` removes the left status-bar view-mode controls and unadorned add-canvas button, moves map/focus/add-canvas actions to the overflow menu, shows canvas tabs only for multiple canvases, and applies the project Apple glass chrome modifiers to zoom and canvas tabs.
- Toolbar catalog and UI/Core contract tests were adjusted for the new menu and control placement.

## Verification so far

- `./scripts/check-floretta-core-imports.sh`: passed (`FlorettaCore` boundary OK).
- `git diff --check`: passed.
- macOS build with `CODE_SIGNING_ALLOWED=NO`: failed at the Share and Quick Look extension CodeSign steps with `errSecInternalComponent`; Swift/app build completion is not established.
- iOS generic build ended with the same `errSecInternalComponent` while signing the `FlorettaShare-iOS` extension; full build did not pass.
- `swiftc -frontend -parse` over the nine changed Swift files: passed.
- Required macOS `xcodebuild test ... -only-testing:FlorettaTests` was attempted and failed before tests ran at extension CodeSign (`errSecInternalComponent`, then “Testing cancelled because the build failed”).
- The user then reported one GUI-session test failure: a source-contract assertion searched for the zoom glass modifier in the parent `DocumentEditor` slice, although the modifier lives in the child `EditorStatusControls`. Replaced it with assertions on the actual child implementation: it instantiates `StatusZoomMenu`, applies `.appleGlassChrome(.toolbarFloatingButton)`, and retains its accessibility identifier. This replacement is awaiting the user's test rerun; no pass is claimed.
- The user provided GUI-session build results for both platforms: `MACOS_BUILD_EXIT=0`, `IOS_BUILD_EXIT=0`, both `** BUILD SUCCEEDED **`, log `/tmp/uipolish-gui-build.log`; I independently read the log markers and confirmed it contains no `errSecInternalComponent` line. The user's test report was 448 tests, 1 skipped, 1 failure before this assertion correction.
- `xcrun simctl shutdown all` was run per task instruction; final `xcrun simctl list devices booted | grep -c Booted` output was `0`. No `xcodebuild` process remains.

## Hang diagnosis limits

- The supplied hang report establishes repeated main-thread layout-transaction activity and includes `toolbarContext` / the old nested view-mode menu in the stack. It does not prove a state-write/layout feedback loop or prove that a canvas double tap initiated that loop.
- Deferring the double-tap handler and removing the nested macOS view-mode menu are targeted mitigations. Runtime reproduction, before/after sampling, and repeated no-hang verification remain outstanding.


## Final runtime follow-up (2026-11-14)

- GUI-session build results were read from `/tmp/uipolish-gui-build.log`: `MACOS_BUILD_EXIT=0`, `IOS_BUILD_EXIT=0`, both `** BUILD SUCCEEDED **`, no `errSecInternalComponent` lines.
- GUI test rerun was read from `/tmp/uipolish-gui-tests2.log`: 448 tests, 1 skipped, 0 failures; `MACOS_TESTS_EXIT=0`; Core guard `CORE_GUARD_EXIT=0`.
- Live macOS verification on the secondary display: a foreground pixel double-click on the single root node reproduced a layout hang (PID 99566 at ~100% CPU; AX read stalled about 12 s). `/tmp/uipolish-dblclick-node.sample` shows `stepTransactionFlush → layoutSubtreeIfNeeded → ViewGraphRootValueUpdater.render → DocumentEditor.body → editorPresentations → editorToolbar`. Three foreground double-clicks on a blank canvas area in a separate process returned promptly; `/tmp/uipolish-dblclick-blank.sample` shows the main thread idle in `mach_msg`.
- Visual verification: `.dispatch/shots/macos-canvas-blank-doubleclick.png` shows the root node at the upper-left, so centering is not accepted. `.dispatch/shots/floretta-ios.png` is a blank launch screen and does not satisfy iOS visual acceptance. Other representative UI acceptance points were not verified.
- The hang's exact state-feedback root cause remains unproven; the attempted mitigation did not stop the node-double-click repro. Keep status BLOCKED.
- Test app PIDs 98529 and 99566 were closed; no matching test app or `xcodebuild` process remained. Ran `xcrun simctl shutdown all`; `xcrun simctl list devices booted | grep -c Booted` returned `0`. GUI operations after the initial launch were on the secondary display. The launch briefly placed the app on the primary display before it was immediately moved; no primary-screen interaction followed that launch.
- Committed as `b5eccb1` and pushed only to `origin/feat/ui-polish-14`. Opened draft PR #1 to `main` with the requested title and explicit BLOCKED / do-not-merge status. PR head was verified as `b5eccb1f0af837203a32128d71db7d50c41406ca`; no merge or main push occurred.
