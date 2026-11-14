# Canvas text batch — delivery

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

## PR

To be filled after publishing; do not merge this PR.
