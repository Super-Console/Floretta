STATUS: BLOCKED

# PR #15 rebase onto `origin/main`

## Rebase and conflict resolution

- Rebased `feat/theme-fonts` onto `origin/main` (`ab9969d`); resulting branch tip: `d6fb139`.
- Pushed only `feat/theme-fonts` with `--force-with-lease` (`a7936f2` → `d6fb139`); PR #15 remains the existing PR. No push to `main`.
- Content conflict: `Floretta/Shared/Shell/EditorStatusBar.swift`.
- `DocumentEditor.swift` auto-merged; retained `.themeTypography(language: settings.language)` on the editor presentation root.
- In `EditorStatusBar.swift`, kept the status strip and its `.themeTypography(language: language)` modifier. Dropped the incoming theme commit's `EditorStatusControls` / `StatusZoomMenu`: J removed the bottom status-bar zoom control, so retaining it would violate the single top-toolbar zoom requirement.
- J's `DocumentEditor.swift` structure is retained: return button and document title are separate toolbar items; zoom remains in the top toolbar, with no bottom status-bar zoom control. J's `AppearanceSettingsPanel.swift` retains the single visible “外观模式” section heading (`.labelsHidden()` hides the picker's duplicate label); `LibraryHome.swift` retains the native `.listStyle(.sidebar)` selection row without restoring custom row chrome.
- Theme typography remains connected to the editor, status strip, and other theme integration points. `ThemeMode`/`ThemeTypography` logic and resolver tests remain unchanged.

## Verification (actual output)

1. `swift test --package-path FlorettaCore`
   ```text
   Executed 388 tests, with 1 test skipped and 0 failures (0 unexpected)
   Test Suite 'All tests' passed
   ```
   Baseline was 386; total increased to 388.

2. macOS build, requested command/filter:
   ```text
   ** BUILD FAILED **
   ```
   Diagnostic rerun:
   ```text
   /tmp/dd-theme-rb/Build/Products/Debug/FlorettaQuickLookThumbnail-macOS.appex/Contents/MacOS/FlorettaQuickLookThumbnail-macOS.debug.dylib: errSecInternalComponent
   Command CodeSign failed with a nonzero exit code
   ** BUILD FAILED **
   ```

3. iOS build, requested command/filter:
   ```text
   ** BUILD FAILED **
   ```
   Diagnostic rerun:
   ```text
   /tmp/dd-theme-rb/Build/Products/Debug-iphoneos/FlorettaShare-iOS.appex/FlorettaShare-iOS.debug.dylib: errSecInternalComponent
   Command CodeSign failed with a nonzero exit code
   ** BUILD FAILED **
   ```

4. macOS `FlorettaTests`, requested `Executed|error:` filter produced no matching output (pipeline exit 1). Diagnostic rerun:
   ```text
   /tmp/dd-theme-rb/Build/Products/Debug/FlorettaQuickLookThumbnail-macOS.appex/Contents/MacOS/FlorettaQuickLookThumbnail-macOS.debug.dylib: errSecInternalComponent
   Command CodeSign failed with a nonzero exit code
   Testing cancelled because the build failed.
   ** TEST FAILED **
   ```
   Tests did not start; no test failure count is available. Per instruction, no keychain changes were made.

`git diff --check origin/main...HEAD` passed with no output. The requested build/test gates are blocked by extension signing (`errSecInternalComponent`), so this rebase is not fully validated.
