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
  local rc
  echo "==> $label (log: $log)"
  set +e
  "$@" >"$log" 2>&1
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    tail -n 60 "$log" || true
    echo "FAILED: $label (exit $rc)" >&2
    return "$rc"
  fi
  echo "PASSED: $label (exit 0)"
}

failed=0
declare -a step_results=()

if ! run_logged core-imports \
  bash scripts/check-floretta-core-imports.sh; then
  failed=1
  step_results+=("FAILED: core-imports")
else
  step_results+=("PASSED: core-imports")
fi

if ! run_logged macos-compile \
  xcodebuild build -project Floretta.xcodeproj -scheme Floretta-macOS \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  -quiet; then
  failed=1
  step_results+=("FAILED: macos-compile")
else
  step_results+=("PASSED: macos-compile")
fi

if ! run_logged ios-compile \
  xcodebuild build -project Floretta.xcodeproj -scheme Floretta-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  -quiet; then
  failed=1
  step_results+=("FAILED: ios-compile")
else
  step_results+=("PASSED: ios-compile")
fi

if ! run_logged macos-florettatests \
  xcodebuild test -project Floretta.xcodeproj -scheme Floretta-macOS \
  -destination 'platform=macOS' \
  -only-testing:FlorettaTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""; then
  failed=1
  step_results+=("FAILED: macos-florettatests")
else
  step_results+=("PASSED: macos-florettatests")
fi

echo
echo "==> Summary"
for result in "${step_results[@]}"; do
  echo "$result"
done

if [ "$failed" -ne 0 ]; then
  exit 1
fi
