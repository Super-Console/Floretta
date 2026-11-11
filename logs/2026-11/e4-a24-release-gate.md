# E4 size gate and A24 smoke follow-up

## Changes

- Added `.github/workflows/size-gate.yml` to build Release iOS and macOS app bundles on a macOS runner and enforce the existing 15/25 MB limits.
- Added `scripts/check-size.sh`; it reads each scheme's `BUILT_PRODUCTS_DIR`, builds the app, totals regular files in the `.app`, prints one-decimal MB values, and fails on over-budget results.
- Added A24 UI actions for rows #4–#10 and #12 with stable command identifiers. File operations currently verify the real system panels/pickers are reached, not that a chosen file was saved/imported/reopened; coverage notes retain that limitation and release-blocking status.
- Updated `docs/PERF-BUDGET.md` with local run and over-budget guidance.

## Verification

- `bash scripts/check-floretta-core-imports.sh`: `GUARD=0`.
- `swift test` (background run): 347 tests passed, 0 failures.
- `xcodebuild build-for-testing` for `Floretta-iOS` produced the arm64 `.xctestrun` and UI test runner; no simulator was started, so the UI cases were compiled but not executed.
- Real Release app bundle measurements: iOS 20.0 MB (limit <15 MB); macOS 33.0 MB (limit <25 MB). The size gate correctly reports both overages and exits non-zero. These are current app-size blockers, not reasons to raise the limits.
- `scripts/check-packaged-app-size.sh --self-test` could not run with the system Bash 3.2 because the pre-existing script uses `shopt -s inherit_errexit` (unsupported by this Bash).
- Simulator baseline and final booted list were empty; no simulator shutdown was issued.

## Outstanding

- Complete end-to-end file selection and content/produced-file assertions for A24 #7–#10; #4/#5 need assertions on actual canvas node content/count. Current UI tests are honest partial path coverage, not full A24 acceptance.
- Bring iOS and macOS Release app bundles below their respective hard budgets before treating the size gate as merge-ready.
