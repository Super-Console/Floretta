# Canvas text batch — delivery

## CI follow-up — 2026-11-14

- **Root cause:** Canvas rendering applied `.foregroundStyle` and `.multilineTextAlignment` to `Text`. Those modifiers produced `some View`, but `GraphicsContext.draw(_:in:)` requires `Text`; the same type mismatch affected macOS and iOS compilation.
- **Fix:** In `Floretta/Shared/Canvas/InfiniteCanvas.swift`, use the `Text`-preserving `.foregroundColor` modifier for the title and subtitle draws, and remove the incompatible `.multilineTextAlignment` calls. This restores buildability, but canvas alignment rendering still needs a proper `Text`-compatible implementation; this change does not claim that visual behavior was verified.
- **Builds:** The literal requested environment-prefix form (`CODE_SIGNING_ALLOWED=NO xcodebuild ...`) still attempted signing and failed with `errSecInternalComponent`. The local project has signing settings; using the CI-style Xcode build-setting arguments (`CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=''`) correctly disabled signing. macOS build: `** BUILD SUCCEEDED **`, exit 0. iOS build: `** BUILD SUCCEEDED **`, exit 0.
- **Core tests:** `swift test --package-path FlorettaCore` — 378 tests, 1 skipped, 0 failures.
- **App tests:** `xcodebuild test -scheme Floretta-macOS -destination 'platform=macOS' -only-testing:FlorettaTests -derivedDataPath /tmp/dd-canvas-text` with the CI no-signing build settings — **472 tests, 1 skipped, 8 failures**, exit 65. Failures are in `ShellTests.testStringCatalogMatchesTheRuntimeTableAndSkipsDocumentText` and `ShellTests.testViewportSnapAndCommandScrollUseLegalStops`; not resolved in this follow-up. Therefore the requested Xcode test gate is **not passed**.
- **Size:** `./scripts/check-size.sh` completed; macOS payload reported **18.7 MB** against `<25 MB`. No over-budget report was emitted for iOS. No budget threshold changed.
- **Performance:** remains **未测**. No simulator shutdown, keychain operation, merge, or version change was performed.
- **Delivery status:** No commit or push was made because the required app-test gate remains red. The generated DerivedData directories `/tmp/dd-canvas-text` and `/tmp/dd-canvas-text-ios` were left in place; cleanup requires separate approval.

## Commits

Seven commits on `feat/canvas-text`, rebased onto the current `origin/main`:

- `22f875c` per-topic text alignment
- `4e1e71e` optional node subtitles
- `9c78f99` integer-percent canvas zoom
- `db3fe6c` Zen mode chrome and full-screen handling
- `c6608de` inspector tab-host geometry regression contract
- `89b50f3` mixed-script and long-word wrapping coverage
- `66354c8` edit-mode Return/newline behavior and old-file compatibility

## Changes and tests

- Per-node alignment is persisted with centered fallback: `MindMapNodeTests` / `testTextAlignmentDefaultsToCenterForExistingDocumentsAndPersistsPerNode`.
- Optional subtitle persists only when present; empty subtitle retains legacy node height. Markdown export places it under its heading: `testSubtitleDefaultsEmptyAndPersistsOnlyWhenSet`, `testEmptySubtitleKeepsLegacyNodeHeightAndSubtitleAddsMeasuredHeight`, `testMarkdownExportPlacesSubtitleUnderItsHeading`.
- Zoom is clamped/rounded to integer percentages and fit preserves the viewport center: `ShellTests.testZoomStopsAreTheIntegerPercents` and canvas viewport tests.
- Zen hides editor chrome and exits through Escape, macOS `⌘.`/View menu, or blank-canvas double-tap; it has no persistent exit button: `ShellTests.testZenChromeRemovesEveryEditorSurfaceAndBlankCanvasDoubleTapExits`.
- Inspector tab changes preserve stable top-leading toolbar-host geometry: `InspectorStyleTests.testInspectorTabPagesKeepTheToolbarHostAtStableTopLeadingGeometry`.
- Mixed Chinese/English and unbroken words retain characters while wrapping: `CanvasTests.testMixedChineseAndUnbrokenEnglishWrapsWithoutDroppingCharacters`.
- In text-editing mode Return and Shift-Return insert at the caret; command-mode Return continues to create a sibling: `KeyboardTests.testEnterAndShiftEnterInsertNewlinesOnlyInEditMode`, `KeyboardTests.testEnterCreatesSiblingInCommandModeAndNewlineWhileEditing`, `CanvasTests.testEnterAndShiftEnterAreInsertedAtTheCaretByTheTextView`.
- Existing package compatibility: `ContainerTests.testOpensExistingFlorettaFixtureWithDefaultTextFields` opens `docs/reviews/theme-modes/glyph-sample.floretta`; missing alignment defaults to centered and missing subtitle stays empty.
- A legacy glass-chrome contract was updated to agree with the Zen requirement that no persistent exit control is rendered.

## Verification

- `swift test`: **378 tests, 1 skipped, 0 failures** after rebasing onto `origin/main`.
- `xcodebuild -list -project Floretta.xcodeproj`: succeeded; macOS and iOS schemes/targets are present.
- `git diff --check`: clean.
- No signed build, archive, simulator run, or independent GUI/CUA visual review was performed. Dual-platform compilation remains for the authorized graphical/signing environment.

## CUA reproduction paths

For visual review in a GUI session, open the app and a disposable test map; do not overwrite the compatibility fixture.

1. **Alignment:** select a node → Style inspector → Text → choose leading/center/trailing; verify multiline text alignment.
2. **Subtitle:** select a node → Style inspector → Subtitle; enter multiple lines and confirm it appears beneath the title. Clear it and confirm the old title-only geometry.
3. **Integer zoom:** use the canvas zoom control and trackpad/pointer zoom; verify the displayed zoom remains whole percentages and Fit retains the canvas center.
4. **Zen:** View → Enter Zen (or the app's Zen command); verify editor chrome is hidden, then exit with Escape / `⌘.` / View menu. Also verify a blank-canvas double-tap exits.
5. **Inspector geometry:** alternate Style, Presentation, and Map inspector tabs; verify the inspector header and window toolbar host do not jump vertically.
6. **Wrapping:** enter a mixed Chinese/English title containing a long unbroken English token; confirm every character remains visible and wraps within the node.
7. **Return behavior:** edit a node, place the caret mid-text, press Return and Shift-Return; confirm newline insertion at the caret. Exit editing and press Return; confirm sibling creation.

**视觉未验证，待审查方 CUA 确认** — the paths above are reproducible review steps, not claims that visual review was executed.

## Final test-failure triage and verification — 2026-11-14

The earlier “8 failures, unresolved” entry above describes the initial state only. The failures were 8 assertions across 2 test methods (not 8 distinct test methods); no test was removed and no expectation was weakened.

### All 8 initial failures

| # | Test / assertion as emitted | Class / cause / fix / result |
|---|---|---|
| 1 | `ShellTests.testStringCatalogMatchesTheRuntimeTableAndSkipsDocumentText`, `ShellTests.swift:1070`: `XCTAssertEqual failed` comparing `Set(strings.keys)` with `Set(FlorettaL10n.english.keys)` | **A** — five UI strings (`文字对齐`, `靠左`, `居中`, `靠右`, `副文本`) existed in the runtime table but not `Localizable.xcstrings`. Added all five as manual entries with `sourceLanguage: zh-Hans` preserved and translated `zh-Hans`/`en` string units. Test passes. |
| 2 | Same test, `ShellTests.swift:1072`: `XCTUnwrap failed: expected non-nil value of type "Dictionary<String, Any>"` | **A** — catalog entry lookup failed because the new runtime keys had no catalog entries. Added complete catalog structures; test passes. |
| 3 | `ShellTests.testSnapAndDisplayPercentAlwaysLandOnALegalStop`, `ShellTests.swift:96`: `XCTAssertEqual failed: ("137") is not equal to ("125")` | **C** — `CanvasChrome.syncZoomPercent` rounded to arbitrary integer percentages. It now uses `ZoomStop.displayPercent`; test passes. |
| 4 | Same test, `ShellTests.swift:97`: `XCTAssertNotEqual failed: ("137") is equal to ("137")` | **C** — same root cause and implementation fix; test passes. |
| 5 | Same test, `ShellTests.swift:98`: `XCTAssertTrue failed` | **C** — displayed percentage was not a legal zoom stop; same fix; test passes. |
| 6 | `ShellTests.testViewportSnapAndCommandScrollUseLegalStops`, `ShellTests.swift:105`: `XCTAssertEqualWithAccuracy failed: ("1.37") is not equal to ("1.25") +/- ("0.0001")` | **C** — gesture snap rounded to an integer percentage instead of a legal stop. `CanvasViewport.snapToStop` now selects `ZoomStop.nearest`; test passes. |
| 7 | Same test, `ShellTests.swift:106`: `XCTAssertTrue failed` | **C** — same non-legal 1.37 scale; same implementation fix; test passes. |
| 8 | Same test, `ShellTests.swift:115`: `XCTAssertTrue failed` | **C** — Command-scroll zoom also failed to land on a legal stop; snap fix covers this path; test passes. |

### Final verification outputs

- `swift test --package-path FlorettaCore`: **378 tests, 1 skipped, 0 failures**; exit **0**.
- `CODE_SIGNING_ALLOWED=NO xcodebuild test ... -only-testing:FlorettaTests` using Xcode build-setting arguments `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=''`: **472 tests, 1 skipped, 0 failures**, `** TEST SUCCEEDED **`; exit **0**. Test count unchanged.
- macOS `xcodebuild build` (`Floretta-macOS`, `platform=macOS`, same no-signing build settings): `** BUILD SUCCEEDED **`; exit **0**.
- iOS `xcodebuild build` (`Floretta-iOS`, `generic/platform=iOS`, same no-signing build settings): `** BUILD SUCCEEDED **`; exit **0**.
- The originally specified environment-prefix command was also tried literally; it produced no matching `: error: -[` test assertions and exited **1** because signing was not disabled by that syntax. The successful runs above use Xcode build-setting arguments and preserve the complete logs under `/tmp/canvas-text-*.log`.
- Performance: **未测**. No merge, LocalAsk change, version change, keychain operation, or simulator shutdown.
- Committed and pushed to the existing `feat/canvas-text` branch for PR #9 after all required verification passed.

## PR

To be filled after publishing; do not merge this PR.
