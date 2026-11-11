# Smoke gate and evidence work

## Changes

- Added `scripts/pre-release.sh` to run the FlorettaCore import boundary, Core tests, iOS UI tests, macOS compile, and iOS compile; it boots a selected iPhone simulator by UDID, uses the `Floretta-iOS` test scheme, and shuts simulators down on exit.
- Added a multi-canvas UI test for adding and switching canvas tabs; adjusted the Inspector empty-state UI test's blank-area attempts.
- Added A24 coverage and A27 AX evidence notes; A27 and full A24 coverage remain incomplete as detailed in `docs/reviews/`.

## Verification

- `swift test`: 344 tests passed.
- iOS UI suite: 8 tests passed, 0 failures.
- macOS build and iOS simulator build succeeded.
- Simulator shutdown check returned `booted=0`; no Simulator.app was launched for the UI suite.
- C7 Core test evidence: `CanvasSheetTests`, 7 passed; UI test now also passed in the UI suite.

## Outstanding

- The macOS AX tree exposes the Inspector tab child at `frame.minY=184`, but not the `inspector.header` container. The empty-state reading was not captured because the canvas has no semantic AX hit target and the required pixel hit would need screenshot grounding, which this task excludes.
- The first 13 `docs/SMOKE.md` routes are not all covered by UI tests; see the coverage table. Do not treat this work as full A24 acceptance.
- Five old `a27-*.png` files remain untracked pending required cleanup confirmation.

## PR #107 blocking-review follow-up

- Reworked `scripts/pre-release.sh`: captures booted simulator UDIDs before work, records only successful boots initiated by this run, shuts down those UDIDs individually, verifies owned devices stopped, and reports the baseline count. No `shutdown all` remains.
- Expanded A24 rows #4–#10 and #12 with an individual gap reason and explicit `发布阻断：是`.
- Rebuilt the current `Floretta-macOS` target from this worktree successfully (build 12). A current-source app process started from DerivedData did not expose a CUA-enumerable window, so current-source A27 reread remains blocked.
- AX observation from the installed 1.0 (build 8) app on the secondary display: selected `minY=184`; empty state showed `选择一个主题` and `minY=496.5`. These differ and are explicitly not claimed as current-source acceptance evidence.
- Simulator baseline at follow-up start was empty; no simulator was shut down by this follow-up. Final `booted=0`.
- Full `scripts/pre-release.sh` rerun after fixing empty-array handling under `set -u`: Core suite 344/344 passed, UI suite 8/8 passed, macOS and iOS simulator builds both report `BUILD SUCCEEDED`; the script-owned iPhone UDID was shut down by the exit cleanup, final booted list empty (`booted=0`). No `Simulator.app` process was started.
- Correction to the earlier outstanding note: an empty-state AX reading was later obtained from the installed build 8; the exact value and its non-current-source limitation are recorded above. Current-source build 12 AX window enumeration remains blocked.
- Clarification: the prior baseline bullet describes the period before the full gate rerun; during the later rerun, one script-owned iPhone simulator was started and then shut down.
