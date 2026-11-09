#!/usr/bin/env bash
# Reproducible open-RSS check for 1GiB and 10GiB sparse packages.
# Darwin: task_info / phys_footprint (this script fails if that read fails).
# Linux: /proc/self/status VmRSS, or a soft skip when /proc is absent.
# The package open itself is StreamingTests.testOpenRSSDeltaIsIndependentOfOneAndTenGigabytePayloads.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

echo "== sampler =="
if [[ "$(uname -s)" == "Darwin" ]]; then
  bin="$(mktemp)"
  cc -O2 -o "$bin" "$root/scripts/phys_footprint.c"
  bytes="$("$bin")"
  rm -f "$bin"
  echo "sampler=phys_footprint bytes=$bytes"
  if [[ "$bytes" -le 0 ]]; then
    echo "Darwin phys_footprint was not measured" >&2
    exit 1
  fi
elif [[ -r /proc/self/status ]]; then
  awk '/^VmRSS:/ { printf "sampler=VmRSS bytes=%d\n", $2 * 1024 }' /proc/self/status
else
  echo "sampler=VmRSS skipped (no /proc)"
fi

echo "== open 1GiB and 10GiB =="
if command -v swift >/dev/null 2>&1; then
  swift test --filter 'testOpenRSSDeltaIsIndependentOfOneAndTenGigabytePayloads|testOpenOfTenGigabyteAttachmentDoesNotReadThePayload'
elif command -v xcodebuild >/dev/null 2>&1; then
  xcodebuild test \
    -project Floretta.xcodeproj \
    -scheme Floretta-macOS \
    -destination 'platform=macOS' \
    -only-testing:FlorettaTests/StreamingTests/testOpenRSSDeltaIsIndependentOfOneAndTenGigabytePayloads \
    -only-testing:FlorettaTests/StreamingTests/testOpenOfTenGigabyteAttachmentDoesNotReadThePayload
else
  echo "swift and xcodebuild are absent. The sampler above is live; the package open runs in StreamingTests on the next Mac."
fi
