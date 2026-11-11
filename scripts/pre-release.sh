#!/usr/bin/env bash
# Mandatory pre-archive validation. Run from any directory.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

cleanup() {
  local status=$?
  trap - EXIT INT TERM
  echo "Shutting down iOS simulators..."
  xcrun simctl shutdown all || status=1
  local booted
  booted="$(xcrun simctl list devices booted | grep -c 'Booted' || true)"
  echo "booted=$booted"
  [[ "$booted" == "0" ]] || status=1
  exit "$status"
}
trap cleanup EXIT INT TERM

run_logged() {
  local label="$1"; shift
  local log
  log="$(mktemp "${TMPDIR:-/tmp}/floretta-pre-release.XXXXXXXXXX")"
  echo "==> $label (log: $log)"
  "$@" >"$log" 2>&1 &
  local pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    tail -n 8 "$log" || true
    sleep 5
  done
  local result=0
  wait "$pid" || result=$?
  tail -n 40 "$log" || true
  if [[ $result -ne 0 ]]; then
    echo "FAILED: $label (exit $result)" >&2
    return "$result"
  fi
  echo "PASSED: $label"
}

echo '==> FlorettaCore import boundary'
bash scripts/check-floretta-core-imports.sh

run_logged 'FlorettaCore unit tests' swift test

ios_simulator_id="$(xcrun simctl list devices available -j | /usr/bin/python3 -c '
import json
import sys

catalog = json.load(sys.stdin)
for runtime, devices in catalog.get("devices", {}).items():
    if not runtime.startswith("com.apple.CoreSimulator.SimRuntime.iOS"):
        continue
    for device in devices:
        if device.get("isAvailable") and "iPhone" in device.get("name", ""):
            print(device["udid"])
            raise SystemExit(0)
raise SystemExit("No available iPhone simulator found")
')"

if ! xcrun simctl list devices booted | grep -Fq "$ios_simulator_id"; then
  xcrun simctl boot "$ios_simulator_id"
fi
xcrun simctl bootstatus "$ios_simulator_id" -b

run_logged 'UI smoke tests' \
  xcodebuild test -project Floretta.xcodeproj -scheme Floretta-iOS \
  -destination "platform=iOS Simulator,id=$ios_simulator_id" CODE_SIGNING_ALLOWED=NO

run_logged 'macOS compile' \
  xcodebuild build -project Floretta.xcodeproj -scheme Floretta-macOS \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO

run_logged 'iOS compile' \
  xcodebuild build -project Floretta.xcodeproj -scheme Floretta-iOS \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
