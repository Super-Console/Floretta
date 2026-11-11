#!/usr/bin/env bash
# Build both app schemes and measure the resulting .app bundles against E4.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

settings_value() {
  local scheme="$1" destination="$2" key="$3"
  xcodebuild -showBuildSettings -project Floretta.xcodeproj -scheme "$scheme" \
    -configuration Release -destination "$destination" 2>/dev/null \
    | awk -F ' = ' -v key="$key" '$1 ~ "^[[:space:]]*" key "$" { value=$2 } END { if (value != "") print value; else exit 1 }'
}

build_and_measure() {
  local platform="$1" scheme="$2" destination="$3" budget="$4"
  local products app bytes mb
  products="$(settings_value "$scheme" "$destination" BUILT_PRODUCTS_DIR)"
  if ! xcodebuild build -project Floretta.xcodeproj -scheme "$scheme" \
    -configuration Release -destination "$destination" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" -quiet; then
    echo "ERROR $platform Release build failed; refusing to measure a stale bundle" >&2
    return 1
  fi
  app="$products/Floretta-$platform.app"
  [[ -d "$app" ]] || { echo "ERROR missing app bundle: $app" >&2; return 1; }
  bytes="$(find "$app" -type f -exec stat -f '%z' {} + | awk '{ total += $1 } END { print total+0 }')"
  mb="$(awk -v bytes="$bytes" 'BEGIN { printf "%.1f", bytes/1024/1024 }')"
  printf '%s: %s MB (limit < %s MB)\n' "$platform" "$mb" "$budget"
  awk -v bytes="$bytes" -v budget="$budget" 'BEGIN { exit !(bytes < budget * 1024 * 1024) }' || {
    echo "FAIL $platform app bundle is ${mb} MB; required < ${budget} MB" >&2
    return 1
  }
}

failed=0
build_and_measure iOS Floretta-iOS 'generic/platform=iOS' 15 || failed=1
build_and_measure macOS Floretta-macOS 'platform=macOS' 25 || failed=1
exit "$failed"
