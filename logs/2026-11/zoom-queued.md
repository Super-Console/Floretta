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
