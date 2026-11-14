# Canvas polish · Batch 5

- Branch/PR: `feat/canvas-polish`, https://github.com/Super-Console/Floretta/pull/18 (open, not merged); commits `62267ee`, `a1757f1`, `54d0b0b`.
- D10: confirmed inspector page intrinsic-height changes could cause AppKit's shared toolbar host to recenter. Existing stable top inset/native picker mitigation predates this batch; added `testInspectorModeSwitchKeepsNativePickerInStableTopInset`.
- D9: lowered the color-block LOD cutoff from 9pt to 5pt so 50% zoom retains vector titles at their actual scaled point size. `testOnScreenFontSizeMatchesTheEditFieldAndStaysInsideTheStops` passed. No visual screenshot run.
- D4: baseline already contained the `easeOutBack` petal director and environment Reduce Motion handling. Added `testReduceMotionDoesNotArmPetalAnimationForMapOpenOrBranchExpand`; full core tests report 0 layout passes during animation and 29,919ns pose sampling per frame.
- Verification: `swift test --package-path FlorettaCore` passed (390 tests, 1 skipped, 0 failures). macOS/iOS `xcodebuild build` and requested macOS `xcodebuild test` compile but fail signing extensions with `errSecInternalComponent` despite `CODE_SIGNING_ALLOWED=NO`; see `.dispatch/DONE-canvas-polish.md` for exact commands and outcomes.
- No versions, budget thresholds, localization, UI smoke identifiers, shared checklist documents, or release artifacts changed. No simulator started; final check found one booted simulator and existing `opencode serve` processes, all left untouched. `/tmp/dd-canvas5` remains pending cleanup approval.
