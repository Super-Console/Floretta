#!/usr/bin/env bash
# Reproducible Space / Enter / Tab paths, plus the XMind shortcut unit suite.
# Usage (from the repo root): bash scripts/verify-xmind-shortcuts.sh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

log_dir="${FLORETTA_SHORTCUTS_LOG_DIR:-/tmp/floretta-shortcuts}"
mkdir -p "$log_dir"
log="$log_dir/unit-keyboard.log"

export HTTPS_PROXY="${HTTPS_PROXY:-http://127.0.0.1:7890}"
export HTTP_PROXY="${HTTP_PROXY:-http://127.0.0.1:7890}"
export ALL_PROXY="${ALL_PROXY:-http://127.0.0.1:7890}"

echo "==> KeyboardTests (log: $log)"
echo "START $(date '+%Y-%m-%d %H:%M:%S %Z')"
set +e
swift test --filter KeyboardTests >"$log" 2>&1
rc=$?
set -e
echo "END $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "EXIT:$rc"
if [ "$rc" -ne 0 ]; then
  tail -n 80 "$log" || true
  exit "$rc"
fi
# Confirm the three main paths were executed.
for name in testSpaceEnterTabMainPaths testSpaceEntersEditAndF2DoesTheSame testMarkedChineseTextDoesNotCreateOrDeleteNodes; do
  if ! grep -q "$name" "$log"; then
    echo "missing test in log: $name" >&2
    exit 1
  fi
done
echo "PASSED: KeyboardTests (exit 0)"
