# Export compliance declaration

- Added `ITSAppUsesNonExemptEncryption=false` to the iOS and macOS main Info.plist files. The repository contains no additional extension-specific Info.plist files.
- Added an upload preflight check to `docs/RELEASE.md`.
- Validation: `plutil -lint` passed for both plists; extracting the key returned `false` for both; `git diff --check` passed.
- No signing settings, versions, or business code changed. No simulator was booted at the start of this task.
