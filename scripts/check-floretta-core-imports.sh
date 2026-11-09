#!/usr/bin/env bash
# Fails when FlorettaCore imports a UI framework or branches on the operating system.
# ADR-021: Core is Foundation-only. Platform differences go through ports.
#
# Usage (from the repo root):
#   scripts/check-floretta-core-imports.sh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
core="$root/FlorettaCore"

if [[ ! -d "$core" ]]; then
  echo "FlorettaCore directory is missing: $core" >&2
  exit 1
fi

fail=0

import_hits="$(grep -REn --include='*.swift' '^[[:space:]]*import[[:space:]]+(SwiftUI|AppKit|UIKit|SwiftData)\b' "$core" || true)"
if [[ -n "$import_hits" ]]; then
  echo "FlorettaCore imports a forbidden framework:" >&2
  echo "$import_hits" >&2
  fail=1
fi

os_hits="$(grep -REn --include='*.swift' '#if[[:space:]]+os[[:space:]]*\(' "$core" || true)"
if [[ -n "$os_hits" ]]; then
  echo "FlorettaCore contains #if os(. Use a port instead:" >&2
  echo "$os_hits" >&2
  fail=1
fi

if [[ "$fail" -ne 0 ]]; then
  exit 1
fi

echo "FlorettaCore boundary ok ($core)"
