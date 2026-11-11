#!/usr/bin/env bash
# Release-gate guard: unsigned compile on both platforms, plus FlorettaTests.
# Usage (from the repo root): bash scripts/check-compile-and-tests.sh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

log_dir="${FLORETTA_GUARD_LOG_DIR:-/tmp/floretta-release-gate}"
mkdir -p "$log_dir"

run_logged() {
  local label="$1"; shift
  local log="$log_dir/${label}.log"
  echo "==> $label (log: $log)"
  if ! "$@" >"$log" 2>&1; then
    local rc=$?
    tail -n 60 "$log" || true
    echo "FAILED: $label (exit $rc)" >&2
    return "$rc"
  fi
  echo "PASSED: $label (exit 0)"
}

echo '==> FlorettaCore import boundary'
bash scripts/check-floretta-core-imports.sh
echo "GUARD=$?"

run_logged macos-compile \
  xcodebuild build -project Floretta.xcodeproj -scheme Floretta-macOS \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  -quiet

run_logged ios-compile \
  xcodebuild build -project Floretta.xcodeproj -scheme Floretta-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  -quiet

run_logged macos-florettatests \
  xcodebuild test -project Floretta.xcodeproj -scheme Floretta-macOS \
  -destination 'platform=macOS' \
  -only-testing:FlorettaTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
