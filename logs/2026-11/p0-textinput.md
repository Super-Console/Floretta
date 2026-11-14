# P0: node text input overwritten by AX probe

## Changes

- Removed accessibility-value writes and all AX metadata from macOS and iOS node text editors.
- Replaced the state probe with a separate non-text overlay exposing only an identifier; geometry remains available as the XCUI frame.
- Updated existing chrome tests without weakening frame/fill invariants; added an AppKit text-preservation regression test and read-only corrupted-document scanner.

## Verification

- Confirmed with `NSTextView`: `string` changes from `abc` to `probe` after `setAccessibilityValue("probe")`.
- Reversed the new test to use the unsafe setter: it failed because `string` became the diagnostic identifier; restored safe setter and targeted test passed.
- macOS and iOS `CODE_SIGNING_ALLOWED=NO` builds succeeded; iOS test bundle build-for-testing succeeded.
- macOS unit suite: 461 tests, 1 skipped, 0 failures.
- Read-only scan found 11 matching nodes across 6 document/recovery files. No user document was changed; repair awaits commander decision.
- Runtime editing remains pending independent CUA verification.
