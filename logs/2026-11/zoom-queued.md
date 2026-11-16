# Zoom and editor chrome follow-up

## Starting measurements and explicit blocker

- English `keyDown` → committed text from the prior probe: base p50 was 1.364/1.404/1.379 ms for a/b/c; current p50 was 1.442/1.389/1.425 ms. The useful summary is approximately 1.4 ms on both sides. The full per-character p95 range was 1.993–8.835 ms (base `a` 7.908 ms; current `a` 8.835 ms), so the tail is not being presented as uniformly 1.4 ms.
- Apple Pinyin: **BLOCKED/UNMEASURED** — the harness could not reliably engage IME composition in a non-interactive run. No Pinyin latency is inferred, and no further authorization request is needed for this measurement.
- Historical zoom outlier retained as a failing observation, not a current or reproduced result: current minFPS 2, maxDraw 225.1 ms, longest main-thread frame 567.9 ms (base comparison minFPS 60, maxDraw 9.5 ms). The later six-run replay did not reproduce it: base minFPS 80/80/82 and maxDraw 5.7/5.4/5.1 ms; current minFPS 80/80/80 and maxDraw 5.1/9.6/5.8 ms. There is no fresh GUI trace in this follow-up.

## C — zoomed-out node visibility

- Baseline-failing test: `swift test --filter CanvasZoomOutVisibilityContractTests` failed both cases with six failed assertions against the pre-fix source.
- Root cause: the `.far` detail branch did not draw a node border; for nodes whose fill is hidden this leaves no visible contour. `CanvasTextLOD` also suppressed titles below 5 pt, and the draw path rejected text rectangles at or below 1 pt.
- Change: far nodes now retain a 0.75 pt minimum contour (selection color for selected nodes), text LOD keeps every finite positive point size, and any positive text rectangle may be drawn. Existing viewport/link intersection selection remains unchanged.
- After change: the same filtered command passed 2 tests, 0 failures. This is a source-contract test; actual rendering at 50% zoom was not GUI-verified, so no visual or frame-time claim is made.
- macOS app compile: `xcodebuild` generic universal Debug attempt hit the command timeout; no compiler diagnostic identified. Re-running the same DerivedData path for `platform=macOS,arch=arm64` with signing disabled completed successfully (quiet mode, no output). Existing compiler deprecation/concurrency warnings remain.

## D — zoom draw-selection latency

- Baseline-failing test: before the change, `swift test --filter CanvasZoomSelectionTests` failed all three contract assertions: the draw path made separate `CanvasPlacement.frames` and `nodeIDsWithVisibleLinks` viewport queries and had no combined selector.
- Change: each draw now uses `CanvasViewportDrawSelection.select`, a single linear pass that returns visible frames in document order and independently retains links whose Bézier control-point bounds intersect the viewport. This removes two per-frame SwiftFlow node-array conversions and avoids a second frame filter; the Bézier bounds calculation uses scalar min/max rather than temporary coordinate arrays.
- After change: `swift test --filter CanvasZoomSelectionTests` passed 3 tests, 0 failures, including a link crossing the viewport while its owning node is outside it and invalid-viewport handling.
- macOS compile follow-up: the earlier duplicate `SwiftCompile`/exit-code-0 anomaly did not recur with `xcodebuild -scheme Floretta-macOS -configuration Debug -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO ENABLE_DEBUG_DYLIB=NO -jobs 1 build`; this unsigned arm64 build succeeded. It is compile verification only, not a signed delivery build.
- No actual zoom gesture/frame-time p50/p95 was measured in this non-interactive run. The historical failing values remain the previously recorded `minFPS=2`, `maxDraw=225.1 ms`, `longestMainThreadFrame=567.9 ms`; they were not reproduced in the earlier six-run replay. This change's effect on those timings remains unmeasured.

## E–J follow-up verification (2026-11-17)

- E/F/I/J already had implementations and contract tests in the branch history; no duplicate implementation changes were made. `EditorChromeContractTests` + `InspectorStructureTests` + `MacMenuBarContractTests` + `MacMenuExpansionContractTests` passed 32 tests, 0 failures.
- G (inspector expansion frame rate) and H (window-resize frame rate) remain **UNMEASURED**. The current continuation has no confirmation that the Mac is unlocked; `STEER-OVERNIGHT.md` prohibits CUA until unlock/notification, so no test app was launched or captured. No new p50/p95 or layout-vs-draw attribution is claimed.
- Full `swift test`: 606 tests executed, 1 skipped, 0 failures. Unsigned macOS arm64 `Floretta-macOS` build succeeded; this is not a signed delivery build.
- Two typing-probe app bundles (74 MB each) and the 24 KB `FlorettaUITest-35377F7C-BBF4-4F8F-87F5-02F9F021DC4A` fixture remain present pending cleanup approval; none was removed. No simulator was used and no build/test process remained after verification.
