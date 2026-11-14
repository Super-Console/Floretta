# PR #15 theme-fonts rebase

- Rebased `feat/theme-fonts` onto `origin/main` (`ab9969d`), resolving the `EditorStatusBar.swift` conflict by retaining theme typography and J's removal of the bottom zoom control. J's toolbar/title, appearance heading, and native sidebar changes remain in the rebased tree.
- `swift test --package-path FlorettaCore`: 388 tests, 1 skipped, 0 failures (baseline 386).
- macOS and iOS builds, plus `FlorettaTests`, are blocked at extension code signing with `errSecInternalComponent`; no keychain changes made. Details and exact output are in `DONE-theme-rebase.md`.
- `git diff --check origin/main...HEAD`: passed.
- Pushed only `feat/theme-fonts` with `--force-with-lease` (`a7936f2` → `d6fb139`); no `main` push.
