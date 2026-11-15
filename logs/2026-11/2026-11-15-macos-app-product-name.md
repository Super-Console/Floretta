# macOS app product name change

- Changed the macOS application product filename to `Floretta.app`; target and scheme remain `Floretta-macOS`.
- Updated the Xcode product reference and scheme buildable names, macOS size-check product discovery, and inspector/packaging script references. iOS target settings remain unchanged.
- macOS and iOS `xcodebuild build` succeeded when code-signing settings were passed as Xcode build-setting arguments; `Floretta.app` contains the three expected `.appex` bundles. Bundle display name and identifier read back as `Floretta` and `net.timhuang.floretta`.
- `swift test --package-path FlorettaCore`: 393 tests, 1 skipped, 0 failures.
- The requested packaged-size script could not run on this Mac: `/bin/bash` is 3.2 and rejects `shopt -s inherit_errexit`; no newer Bash was found. No dependency was installed.
- The exact requested environment-variable form for the macOS build hit `errSecInternalComponent` while signing a debug extension; the build passed using `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=''` as Xcode build settings.
