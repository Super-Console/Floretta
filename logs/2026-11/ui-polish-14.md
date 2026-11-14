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
- UI changes were committed as `b5eccb1` and pushed only to `origin/feat/ui-polish-14`; delivery records were pushed in a documentation-only follow-up. Draft PR #1 targets `main`, uses the requested title, and is explicitly BLOCKED / do-not-merge. The PR was verified open after the follow-up push; no merge or main push occurred.

## Independent follow-up (2026-11-14)

- Independently checked viewport equality and the relay path: `CanvasViewport` carries SwiftFlow's `x/y/zoom` only; neither `viewSize` nor `contentBounds` participates in equality. `noteViewport` writes the `@ObservationIgnored liveViewport`. The relay predates this branch on `origin/main`. Thus the observed AttributeGraph symbols are not sufficient evidence that the relay write caused the graph loop.
- Opened the actual one-root document “未命名 9.floretta”; its package has one root “中心” and no persisted viewport, so the model falls back to `.standard`. The rendered node remained in the upper-left at 100% zoom. Captured `.dispatch/shots/macos-single-root-center-current.png`.
- Candidate centering fix in `InfiniteCanvas.swift`: yield once on the main actor after canvas appearance, re-check the one-root and standard-viewport conditions, then center. This is intended to let `DocumentEditor`'s camera restore finish first. It has not been app-built or GUI-verified.
- On the pre-change app, node double-click reproduced a 100%-CPU hang with an unresponsive AX window. `/tmp/uipolish-dblclick-followup.sample` again shows repeated SwiftUI/AttributeGraph layout work and `DocumentEditor.body` / `editorEvents`, but no sampled `noteViewport` writer. Root cause remains unproven; no post-change runtime sample exists.
- Verification: `swift test` — 362 passed, 1 skipped, 0 failures; Swift frontend parse, `git diff --check`, and Core import guard passed. No signed build was attempted in this unattended context, per project build constraints.
- This follow-up remains BLOCKED pending a GUI-session build and post-change center / double-click verification. Existing PR #1 only; no merge or main push. The test app PID 23162 was terminated; simulator boot count is 0 and no background `xcodebuild` remains.

## Toolbar hypothesis audit (2026-11-14)

- `EditorToolbarContext` is `Equatable`, with five values derived from document/session state and no clock, random, or layout-dependent data. It is read by pure enablement lookups that return `Bool`, not passed as a SwiftUI modifier value.
- Source inspection of `commandMenuButton`, `commandToolbarButton`, and `commandLabel` found no state mutation during view construction; button closures mutate state only when a person invokes them. `moreMenu` updates an internal title-census memoization cache, but `TopicCensusModel` is an ordinary non-Observable class inside `@State`, so that internal mutation does not publish an Observation change.
- `viewModeCommandMenu` is absent. The macOS view toolbar contains `.fit`; map/focus mode controls are overflow buttons. Remaining toolbar menus (insert/share/zoom/more and nested link/overflow submenus) use pure label builders; their actions run on activation.
- Selection/editing changes can legitimately invalidate toolbar enablement once, but no state write-back loop was found in the inspected toolbar builders. `editorMenuActions` remains a candidate for further testing because its non-Equatable closure-bearing value is regenerated and sent through `.focusedSceneValue` on body reconstruction; causal evidence is missing.
- Count caveat: the earlier local sample reports 607 main-thread sample ticks and the follow-up reports 1,693. Whole-file literal hits are 31 vs 93 for `AGGraphSetOutputValue`; these counts are not time-normalized and should not be presented as a 7× rate change. Future before/after sampling needs matched capture and a fixed aggregation method.
- No toolbar change was made without causal evidence. Preserve the `.sample` files per Timmy's instruction; task remains BLOCKED pending controlled diagnosis and signed GUI validation.

## Runtime growth follow-up (2026-11-14)

- The saved `DocumentEditor.body` trace reaches 200 evaluations and the historical process was reported near 100% CPU, but it has no triggering-state, collection-size, or observer-count measurements. Longer 25-evaluation intervals do not alone prove accumulation.
- Source checks found no confirmed growth source in the inspected path: `LaidOutFrames` replaces one cached source/frame array; `AttachmentThumbnailMemory.sync` filters non-visible images/durations and tracks in-flight/failed work by hash; `noteViewport` writes `@ObservationIgnored liveViewport`. The update-loop source remains unidentified.
- The 0.5-second periodic `TimelineView` is inside the video-preview sheet, and the trace does not show that sheet was active. Canvas petal timeline activity is also not established. No controlled isolation was made for these or `.focusedSceneValue`.
- The saved trace has no double-tap-end/receive/node-edit event. This continuation did not get a controlled node reproduction, live object-count measurement, matched CPU/AX sample, or new center screenshot. No fix or instrumentation removal is claimed.
- Centering remains blocked: `centerComplete` used `100×100`, followed by `sizeChanged=1400×900`; no final-size transform readback or accepted screenshot exists. Status remains **BLOCKED**, PR #1 remains unmerged, and `main` was not pushed.
- Sent TERM/KILL to diagnostic PID 74143, then TERM to attached debugserver PID 74156; subsequent process readback showed neither. `xcrun simctl shutdown all` returned booted count 0 at that checkpoint. A later read found one booted simulator (`F359BDE6-6F6E-4D31-BF18-CBC20C1473A8`), the destination of an unrelated active LocalAsk `xcodebuild`; left that build and simulator untouched. GUI interaction was limited to the secondary display.

## Runtime growth follow-up (2026-11-14)

- The saved body trace reaches 200 evaluations, with slower later 25-evaluation intervals, but no collection sizes or observer counts were captured. This does not prove per-iteration accumulation.
- Inspected `LaidOutFrames` (single replaceable cache), `AttachmentThumbnailMemory.sync` (filters to visible hashes and deduplicates in-flight/failed hashes), and `noteViewport` (`@ObservationIgnored liveViewport`); no confirmed growth source was found. The 0.5-second periodic timeline is in the video-preview sheet; its participation was not established. No controlled isolation of timeline or `.focusedSceneValue` was run.
- No double-tap markers appear in the trace. The current diagnostic app was at the recent-documents window; no controlled node repro, live object-count readout, or matched CPU/AX sample was produced. No fix or instrumentation removal is claimed.
- Centering remains blocked: center calculation used 100×100 before a later 1400×900 size event. There is no final-size transform readback or accepted screenshot. Keep status BLOCKED; PR #1 only, no merge or `main` push.
- Resource closeout: sent TERM/KILL to diagnostic app PID 74143, then TERM to attached debugserver PID 74156; subsequent process readback showed neither. `xcrun simctl shutdown all` returned booted count 0 at that checkpoint. A later read found one booted simulator (`F359BDE6-6F6E-4D31-BF18-CBC20C1473A8`), the destination of an unrelated active LocalAsk `xcodebuild`; left that build and simulator untouched. GUI operation remained on the secondary display.

## Body-count evidence and focused-scene candidate (2026-11-14)

- Added the user-provided `/tmp/oc-uipolish-emp.log` sequence to DONE as the primary runtime conclusion: bodyCount `25 → 50 → 75 → 100 → 125 → 150 → 175 → 200`, no plateau in the captured run, with the reported process near 100% CPU. The observed elapsed time per 25-body block grew from about 7.5s to 33.2s. This supports sustained non-converging updates and worsening latency; accumulation source remains unlocated.
- The centering trace is documented as zero arithmetic delta only for then-current `100×100` viewSize, followed by final reported `1400×900`; no final-size transform proof or accepted image.
- One source-level candidate (`.focusedSceneValue(\.florettaEditorCommands, editorMenuActions)`) was isolated temporarily. After a neutral empty background preserved the modifier chain, Xcode built and launched the candidate. The app presented a recovery dialog for unsaved “未命名”; only Cancel was selected. No document/editor interaction, node double-tap, or new bodyCount log was obtained. The source edit was restored; this is not a successful bisection.
- GUI constraint incident: test app initially launched at x=1160 (primary), was moved to x=2700 (secondary), then the foreground cancel action returned the window to x=1160. GUI actions stopped immediately; the window was moved back to x=2700 and the Xcode run stopped. This crossed the primary-screen restriction and is disclosed in DONE. No further GUI testing was done.
- LocalAsk's simulator `F359BDE6-6F6E-4D31-BF18-CBC20C1473A8` and LocalAsk process were left untouched. Floretta app exited; its thumbnail helper was sent TERM and was absent in the subsequent process check. Status remains BLOCKED.

## Isolated macOS rerun (2026-11-14)

- Reused the already-built candidate with `.focusedSceneValue(\.florettaEditorCommands, editorMenuActions)` removed, launched through `-FlorettaUITest -FlorettaEditChrome` to use the isolated one-node fixture, and placed the test window at secondary-display bounds `(2700,200,1400×900)`.
- Trace: bodyCount reached `2 → 25 → 50 → 75 → 100` without a plateau; CPU readback at 75 was `99.4%` and at 100 `100.0%`. Removing this one candidate did not make the observed loop converge. No matched baseline run exists, so report as one-sided evidence only.
- `sinceNodeDoubleTap=-s` remained unchanged, despite an attempted pixel double-click and node selection. AX later reported `ax_window_unresolved`. Therefore there is no confirmed double-tap-path or AX responsiveness result.
- Final-size centering trace: size changed `960×680 → 1400×900`; center attempt used final `1400×900`, root frame `(64,96,72,40)`, target `(100,116)`, resulting viewport `(scale=1, offsetX=600, offsetY=334)`, mapped point `(700,450)`, delta `(0,0)`. Screenshot from the secondary-display window visually showed the one-node sample centered.
- Sent TERM to only the test app PID `6866`; LocalAsk app and simulator untouched; no simulator shutdown. Sampling/log files retained. Update source attribution, matched baseline, successful repeated double-click AX/CPU test and any fix remain outstanding; status BLOCKED.

## Center-gate and onset-window re-analysis (2026-11-14)

- Full `centerNotScheduled` at uptime `7042.344239`: roots `1`; viewport `(scale=1, offsetX=50, offsetY=50)`; rootFrames contains the single UUID/frame `(-131.5,-62.5,263,125)`. Frames were populated, so “measured but not yet placed” is not supported by this log.
- `CanvasViewportState.standard` is `(scale=1, offsetX=0, offsetY=0)`. The viewport guard—not root count or root-frame availability—failed. The separate `centerComplete` run began with `(1,0,0)` and a present frame. The branches differ by initial viewport state.
- The old `sinceNodeDoubleTap=-s` format was caused by appending `s` even when the value was the `-` sentinel. Updated diagnostic source now records absolute `nodeDoubleTapUptime` and uses `not-recorded` for both time fields until a node hit is logged. Not built or runtime-verified yet; historical traces remain unaltered.
- Between `centerComplete` at `7119.020505` and first sampled `bodyCount=25` at `7181.816817` there is no `EVENT`/state-change line in the trace. The first intervening trigger cannot be recovered from this sparse log; double-tap ordering remains unknown. `.focusedSceneValue`-removed candidate still reached bodyCount 100 / ~100% CPU, as above.
- Status remains BLOCKED; no further isolation/fix or simulator operation performed.

## Instrumentation sanity build/run and center decision (2026-11-14)

- Added temporary `-FlorettaUITest -FlorettaEditChrome` LaunchAction args to `Floretta-macOS.xcscheme`, used Xcode Run on the secondary display, then removed those args. Xcode built and launched PID 34481 with the isolated one-root sample; window bounds were `(2700,200,1400×900)`. No recovery prompt/user document was involved.
- Runtime confirmed `bodyCount=1 nodeDoubleTapUptime=not-recorded sinceNodeDoubleTap=not-recorded`; the old `-s` formatting error is corrected. Two pixel double-click attempts selected the node but yielded no `canvas.doubleTapReceived`/`nodeDoubleTap` record, so absolute uptime after a confirmed node double tap remains unverified. Later bodyCount reached 25/50/75/100 and process CPU was observed at 98.8%; loop persists in this no-doubletap sanity run.
- Xcode Stop ended the own app after direct TERM/KILL did not immediately remove it. Process readback afterward found no Floretta app, Quick Look helper, xcodebuild, or swift-frontend. No simulator shutdown or LocalAsk interaction; evidence files retained.
- Documented center policy options A–D in DONE and made no centering behavior changes. Broad body-state fingerprint was deferred because reading many `@State`/`@Bindable` properties can itself alter SwiftUI observation dependencies; narrow source mutation markers are safer for the next controlled run.
- Task remains BLOCKED; no root source found, no user decision for centering yet, no matched verified double-tap baseline. No merge or push to main.

## User-selected single-root centering policy A (2026-11-14)

- User selected unconditional centering for exactly one root. Updated `InfiniteCanvas.onAppear` to schedule the same deferred center without gating on persisted viewport; after the yield it only cancels if root count is no longer one. No new center-path state write was added. Multi-root documents remain unscheduled, including non-standard viewports.
- Clarified `centerNotScheduled` trace reasons (`roots-count-not-one` / `single-root-frame-unavailable`) and late cancellation (`roots-count-changed`).
- Accepted UX cost recorded in DONE: a manually panned single-root document resets to center on next open. Runtime acceptance remains pending until real non-standard single-/multi-root document tests, final-size transform verification, and the required three screenshots are captured.
- Hang diagnosis remains BLOCKED and independent; no cause/fix or repaired bodyCount comparison is claimed.

## Policy A acceptance and body-trigger probe (2026-11-14)

- Created isolated real `.floretta` package fixtures with persisted viewport `(1,50,50)` in the worktree's ignored dispatch area, then copied them into the UI-test app container `import/` so the sandbox could open them. Single-root package had one root with descendants; regression package had two roots. Both ZIP packages were read back and validated.
- Xcode built and ran the modified macOS app on the secondary display. Single-root trace: `roots=1`, persisted `(1,50,50)`, final view `1400×900`, root center mapped to `(700,450)`, camera offsets `(700,450)`, `centerDelta=(0,0)`. Multi-root trace: `roots=2`, `centerNotScheduled reason=roots-count-not-one`, persisted viewport remained `(1,50,50)` at final size, with no center attempt. Screenshots: `.dispatch/shots/center-single-nonstandard-open.png`, `.dispatch/shots/center-single-nonstandard-deselected.png`, `.dispatch/shots/center-multi-nonstandard-preserved.png`; files were opened/read back. The “deselected” capture still has the node outline, so it is not represented as an unselected view.
- A temporary `Self._printChanges()` probe compiled and ran in `DocumentEditor.body`; initial console output listed all state/environment inputs, while a later line showed only `@self changed`. It did not resolve which changing input caused bodyCount growth, and the console output could not be timestamp-correlated with the file-only count trace. The probe and temporary scheme arguments were removed.
- Previous diagnostic reached bodyCount 100 at ~98.8% CPU; this diagnostic reached 25 then 50 and 100% CPU without plateau. Pixel double-click produced no `canvas.doubleTapReceived` or absolute uptime, so no valid confirmed node-doubletap baseline or causal attribution. Hang remains BLOCKED; no match-paired repaired comparison is claimed.
- Xcode Stop ended the Floretta processes started by this task. No simulator actions/shutdown; LocalAsk was not operated. GUI work and captures were on the secondary display. Test fixture copies in the app sandbox and the diagnostic trace were retained, not cleaned. No merge or push to `main`.

## Petal hypothesis and overflow follow-up (2026-11-14)

- Source semantics confirmed: `.animation(minimumInterval: 1/60, paused: !petal.isPlaying)` advances an animation timeline while playback is active. `PetalExpandDirector.layoutExtra(comparedTo:)` returns `max(0, layoutPassCount - layoutPassCountAtStart)` only while playing; `noteLayoutExtra` assigns that integer. `LaidOutFrames.layoutPassCount` increments only on a cache miss. Thus a state write is conditional on the reported extra changing; whether repeated cache misses and state writes feed one another requires runtime values, not source inspection alone.
- Removed the macOS `.insert` toolbar item and added `insertOverflowSubmenu` unconditionally to the macOS `⋯` menu (iOS retains its prior conditional behavior). A new built-app screenshot, `.dispatch/shots/center-single-node-only-nonstandard-overflow-debug-current.png`, shows a centered single node, no bare lower-left text, only the bottom-right glass zoom control, and no separate plus button. The live `editor.more` AX tree contains the `插入` submenu with the insert commands. Screenshot is from the verified worktree app at `/Users/TimmySheep/Library/Developer/Xcode/DerivedData/Floretta-cokhklpxahsqrlgkfoyjrymwcfqu/Build/Products/Debug/Floretta-macOS.app/Contents/MacOS/Floretta-macOS` (PID 65446 at capture time).
- First temporary frame probe was gated on the node-double-tap marker, so this run yielded no `petalFrame` rows. A pixel double-click landed in the single-node fixture but runtime recorded `beginEditing.enter` / `keyboard.apply.beginEdit`, not `canvas.doubleTapGestureEnded` or `nodeDoubleTap`. That document has no expandable descendants, so it cannot validate petal expansion. Body count subsequently reached 50 and CPU readback was 100%; Xcode console contained `onChange(of: Date) action tried to update multiple times per frame.` and repeated `Modifying state during view update` warnings. This reproduces a high-CPU edit-path failure, but does not attribute it to petal playback.
- Updated the temporary frame probe to record up to 240 frames whenever `petal.isPlaying` (including map-open playback), with `extra`, recorded extra, cache pass count, playback state and motion kind. This adjusted probe has syntax-parse and `git diff --check` passes, but has not yet produced runtime frame data. A subsequent launch only reached the recent-documents screen; recovery prompts were canceled without restoring or discarding. The app was quit/stopped; no Floretta, `xcodebuild`, or debugserver process remained at the final check. No simulator was touched; LocalAsk was not operated.
- No petal-loop fix or animation-preserving repaired comparison is established. Double-click AX responsiveness, repeated clicks, CPU recovery, and warning disappearance remain unverified. Keep **BLOCKED**; preserve the new screenshot and diagnostic materials, and do not merge PR #1 or push `main`.

## Edit-path runtime capture (2026-11-14)

- This follow-up used the worktree's DerivedData macOS app and the one-root fixture with descendants. Confirmed trace markers `beginEditing.enter` and `keyboard.apply.beginEdit` for the fixture node.
- During six recorded `mapOpen` petal frames, `extra=0`, `recordedExtra=0`, and `layoutPassCount=1` throughout; all six had `writesExtra=false`. Frames 5 and 6 reported `willSettle=true` and each logged `petal.settle`. This rules against repeated `noteLayoutExtra` / growing cache-pass writes as the observed edit loop's driver in this capture; repeated settle remains a separate observation without established causal effect.
- Following edit entry, body count went `6 → 25` (~2.5 s), `25 → 50` (~7.3 s), and `50 → 75` (~12.0 s). The diagnostic state fingerprint showed keyboard mode/text initialization, followed by `stateChanges=none` for bodies 51–75. CPU was read at 98% (`ps`); Xcode's gauge showed 99%.
- A 5-second process sample (PID 83822) reports main-thread AppKit layout and SwiftUI `ViewGraphRootValueUpdater.render`; within the 1942 main-thread sample ticks, `ViewGraph.updateOutputs` accounted for 1419, `PreferenceTransform` for 889, and `PlatformItemListNamedImageRepresentable` named-image resolution for 867. These are sampled hot paths only, not proof of the initiating invalidation or state writer.
- Captured `petal.settle` stack frames lead through `InfiniteCanvas.canvasTimeline`'s `onChange(of: timeline.date)` callback into `petal.settle()` (current source line 176). Xcode console showed the Date-action and state-during-view-update warnings; no warning stack mapped to a specific edit-path setter. The exact CPU-loop writer remains unknown; no production change/fix is claimed.
- Xcode Stop ended only this task's PID 83822 and `ps` verified it absent. No simulator was used or shut down; LocalAsk remained untouched. GUI work stayed on the secondary display; primary display was not interacted with. Diagnostic trace and sample files remain preserved.
- Status remains **BLOCKED**; temporary source instrumentation remains. Do not merge PR #1 or push `main`.

## Layout-loop code fix without a GUI rerun

- Removed `UIPolishRuntimeTrace` from the editor, canvas, and text field.
- Window title and toolbar display mode are latched once outside `layout()`. The editing field assigns a font only for a new `EditingFontSignature`, and centers once per bounds and string. Toolbar pulldowns are not wrapped in a second glass container.
- No macOS process was launched here. Hang clearance, AX, CPU, and the five previously accepted screenshots were not rechecked. Status stays **BLOCKED**.

## Localization contract and delivery follow-up (2026-11-14)

- Read `ShellTests.testStringCatalogMatchesTheRuntimeTableAndSkipsDocumentText`: it compares the complete `Localizable.xcstrings` key set with `FlorettaL10n.english.keys`, then requires translated `en` and `zh-Hans` units for each key. Verified the seven appearance/mode keys cited by the user were already present in both sets; the actual mismatch was 29 catalog-only entries, all empty extraction stubs. Twenty-eight are real UI/format strings present in app source; one was the invalid empty key.
- Added the 28 keys and English mappings to `FlorettaL10n.english`, populated their String Catalog `extractionState: manual` and translated `en` / `zh-Hans` `stringUnit` structures, and removed only the empty catalog key. `sourceLanguage=zh-Hans` and `version=1.0` were preserved. Independent key-set check is now 415 vs 415 with no differences; all entries have both translated locales. Swift parse and `git diff --check` passed.
- User-provided `/tmp/uipolish-final-build.log` confirms macOS and iOS builds succeeded; its initial macOS test run had 454 tests, one skipped and this localization-contract failure. The local rerun using `/tmp/dd-uipolish-final` completed successfully: 454 tests, 1 skipped, 0 failures; `testStringCatalogMatchesTheRuntimeTableAndSkipsDocumentText` passed and xcodebuild reported `** TEST SUCCEEDED **`. Non-fatal Contacts/CoreData TCC/XPC diagnostics appeared during the test run; they did not cause failures.
- Updated `DONE-ui-polish-14.md` to `STATUS: CODE_FIXED_RUNTIME_PENDING` and split hang / text-centering code status from runtime acceptance. The user reports signed macOS UI automation remains blocked by TCC authorization. No runtime hang clearance or ≤2pt glyph-center result is claimed.
- Verified the temporary `UIPolishRuntimeTrace`, `UIPolishHangProbe.swift`, and `FlorettaMacUITests` target are already absent from the current tip, so no probe cleanup was needed. Final diff review and delivery follow.
