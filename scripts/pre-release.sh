#!/usr/bin/env bash
# Mandatory pre-archive validation. Run from any directory.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

simulator_ids_from_json() {
  /usr/bin/python3 -c '
import json
import sys

catalog = json.load(sys.stdin)
for devices in catalog.get("devices", {}).values():
    for device in devices:
        if device.get("state") == "Booted":
            print(device["udid"])
'
}

declare -a baseline_simulator_ids=()
declare -a started_simulator_ids=()
baseline_json="$(xcrun simctl list devices booted -j)"
while IFS= read -r simulator_id; do
  [[ -n "$simulator_id" ]] && baseline_simulator_ids+=("$simulator_id")
done < <(printf '%s' "$baseline_json" | simulator_ids_from_json)

contains_simulator() {
  local wanted="$1"
  shift
  local simulator_id
  for simulator_id in "$@"; do
    [[ "$simulator_id" == "$wanted" ]] && return 0
  done
  return 1
}

cleanup() {
  local status=$?
  trap - EXIT INT TERM
  local shut_down=0
  local simulator_id
  if ((${#started_simulator_ids[@]} > 0)); then
    for simulator_id in "${started_simulator_ids[@]}"; do
      if xcrun simctl shutdown "$simulator_id"; then
        ((shut_down += 1))
      else
        echo "FAILED: could not shut down simulator started by this run: $simulator_id" >&2
        status=1
      fi
    done
  fi

  local baseline_untouched="${#baseline_simulator_ids[@]}"
  local booted_ids=()
  local booted_json='{}'
  if ! booted_json="$(xcrun simctl list devices booted -j)"; then
    echo "FAILED: could not read simulator state during cleanup" >&2
    status=1
  fi
  while IFS= read -r simulator_id; do
    [[ -n "$simulator_id" ]] && booted_ids+=("$simulator_id")
  done < <(printf '%s' "$booted_json" | simulator_ids_from_json)

  if ((${#started_simulator_ids[@]} > 0)); then
    for simulator_id in "${started_simulator_ids[@]}"; do
      if ((${#booted_ids[@]} > 0)) && contains_simulator "$simulator_id" "${booted_ids[@]}"; then
        echo "FAILED: simulator started by this run is still booted: $simulator_id" >&2
        status=1
      fi
    done
  fi

  if ((${#baseline_simulator_ids[@]} > 0)); then
    for simulator_id in "${baseline_simulator_ids[@]}"; do
      if ((${#booted_ids[@]} == 0)) || ! contains_simulator "$simulator_id" "${booted_ids[@]}"; then
        echo "WARNING: baseline simulator is no longer booted (not modified by cleanup): $simulator_id" >&2
      fi
    done
  fi

  echo "本次启动并已关闭 ${shut_down} 台；baseline 中其他 ${baseline_untouched} 台未触碰"
  echo "booted=${#booted_ids[@]}"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

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

if ((${#baseline_simulator_ids[@]} == 0)) || ! contains_simulator "$ios_simulator_id" "${baseline_simulator_ids[@]}"; then
  xcrun simctl boot "$ios_simulator_id"
  started_simulator_ids+=("$ios_simulator_id")
fi
xcrun simctl bootstatus "$ios_simulator_id" -b

# Leftover /tmp/floretta-run-theme-shots (or perf-probe) flags opt the
# ThemeModesScreenshotUITests in, but this gate does not start the
# external screenshot poller. Force-disable those opt-ins and skip the
# class so a stale flag cannot fail pre-release. Do not delete the flag
# files; an intentional poller run still works when FLORETTA_RUN_THEME_SHOTS=1
# (or a flag without =0) is used outside this script.
export FLORETTA_RUN_THEME_SHOTS=0
export FLORETTA_RUN_PERF_PROBE=0
run_logged 'UI smoke tests' \
  env FLORETTA_RUN_THEME_SHOTS=0 FLORETTA_RUN_PERF_PROBE=0 \
  xcodebuild test -project Floretta.xcodeproj -scheme Floretta-iOS \
  -destination "platform=iOS Simulator,id=$ios_simulator_id" \
  -skip-testing:FlorettaUITests/ThemeModesScreenshotUITests \
  CODE_SIGNING_ALLOWED=NO

run_logged 'macOS compile' \
  xcodebuild build -project Floretta.xcodeproj -scheme Floretta-macOS \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO

run_logged 'iOS compile' \
  xcodebuild build -project Floretta.xcodeproj -scheme Floretta-iOS \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO

run_logged 'macOS FlorettaTests' \
  xcodebuild test -project Floretta.xcodeproj -scheme Floretta-macOS \
  -destination 'platform=macOS' \
  -only-testing:FlorettaTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
