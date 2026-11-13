#!/usr/bin/env bash
# A27 macOS inspector pin: read AXFrame.minY in the selected and empty states.
# Usage (from the repo root, after building a current-source Debug app):
#   bash scripts/assert-macos-a27-inspector-pin.sh /path/to/Floretta-macOS.app
# Does not use /Applications or any already-installed build.
# Does not pass -FlorettaEditChrome (that path still opens no window).
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
app="${1:-}"
if [ -z "$app" ] || [ ! -d "$app" ]; then
  echo "usage: $0 /path/to/Floretta-macOS.app" >&2
  exit 64
fi

bin="${FLORETTA_A27_BIN:-/tmp/floretta-a27-assert}"
swiftc -O -o "$bin" "$root/scripts/assert-macos-a27-inspector-pin.swift"   -framework ApplicationServices -framework AppKit
exec "$bin" "$app"
