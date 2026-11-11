# E4 size gate and A24 smoke follow-up

## Changes

- Added `.github/workflows/size-gate.yml` to build Release iOS and macOS app bundles on a macOS runner and enforce the existing 15/25 MB limits.
- Added `scripts/check-size.sh`; it reads each scheme's `BUILT_PRODUCTS_DIR`, builds the app, strips Mach-O files inside the `.app` (DWARF stays in the sibling `.dSYM`), totals regular files in the `.app`, prints one-decimal MB values (1024²), and fails on over-budget results.
- Added `scripts/check-compile-and-tests.sh` for unsigned macOS / iOS Simulator compiles plus `FlorettaTests`; `scripts/pre-release.sh` now also runs `FlorettaTests`.
- Added A24 UI actions for rows #4–#10 and #12 with stable command identifiers. File operations verify the real system panels/pickers are reached, not that a chosen file was saved/imported/reopened. `#9` is split into PNG / PDF / Markdown cases. Import of `.mm` / `.opml` uses the single「从文件导入」picker.
- Updated `docs/PERF-BUDGET.md` with local run and over-budget guidance.

## Occupancy (before trim)

Hubert / OpenCode Release measurements of the unstripped `.app` payload, same totaling method as `check-size.sh` but without `strip`:

- iOS 20.0 MB (20,975,300 bytes): `Floretta-iOS` 12,105,008 (`__LINKEDIT` 7,405,568), `FlorettaShare-iOS` 4,719,872 (`__LINKEDIT` 2,670,592), `Assets.car` 4,039,928. dSYMs already sat beside the `.app`, but the binaries still carried the symbol table.
- macOS 33.0 MB (34,552,001 bytes): `Floretta-macOS` 12,696,640, Share 4,764,400, Quick Look Thumbnail 6,740,064, Quick Look Preview 6,620,960, `Assets.car` 3,297,368. Same unstripped `__LINKEDIT` pattern; FlorettaCore is statically linked into the app and each appex.

`strip -S` (debug only) was not enough (iOS 18.2 MB, macOS 29.3 MB). Full `strip` of shipped Mach-O files brought both platforms under budget without removing features, screens, formats, or extensions.

## Verification

- `bash scripts/check-floretta-core-imports.sh`: `GUARD=0` at 23:26:08 CST (Asia/Shanghai), 2026-11-11.
- `bash scripts/check-size.sh`: started 23:25:08 CST, finished 23:26:02 CST, exit 0. Log: `/tmp/floretta-release-gate/check-size-2.log`.
  - iOS: 11.1 MB (11,690,963 bytes; limit < 15 MB)
  - macOS: 17.1 MB (17,978,001 bytes; limit < 25 MB)
- `bash scripts/check-compile-and-tests.sh`: started 23:26:08 CST, finished 23:28:01 CST, exit 0. Log: `/tmp/floretta-release-gate/guard.log`.
  - macos-compile exit 0 (`/tmp/floretta-release-gate/macos-compile.log`)
  - ios-compile exit 0 (`/tmp/floretta-release-gate/ios-compile.log`)
  - macos-florettatests exit 0 (`/tmp/floretta-release-gate/macos-florettatests.log`): `Executed 413 tests, with 0 failures`, `TEST SUCCEEDED`.

## Outstanding

- `#7–#10` still do not select a real file and assert saved / imported / exported content; `#4/#5` do not assert canvas node text or count. Those remain deeper acceptance items, not missing path coverage.
