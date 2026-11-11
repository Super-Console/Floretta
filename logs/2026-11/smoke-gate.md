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
