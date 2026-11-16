#!/usr/bin/env bash
# Offscreen pixel proof that the macOS leading navigation capsule centres the
# document name: the text's black-pixel midpoint on the capsule's midpoint.
#
# Usage (repo root):
#   bash scripts/measure-title-capsule.sh            # shipped layout
#   bash scripts/measure-title-capsule.sh --baseline # pre-fix [back][name] row
#
# Nothing is launched, shown, or screenshotted: the probe renders the real
# `DocumentTitleCapsule` (extracted verbatim from DocumentEditor.swift) in an
# offscreen NSHostingView, never in an ordered-front window.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
gen="${TMPDIR:-/tmp}/floretta-title-capsule"
bin="${FLORETTA_TITLE_CAPSULE_BIN:-$gen/probe}"

rm -rf "$gen"
mkdir -p "$gen"

python3 - "$root" "$gen" <<'PY'
import io
import re
import sys

root, gen = sys.argv[1], sys.argv[2]


def extract(source, marker):
    start = source.index(marker)
    depth = 0
    seen = False
    for index in range(start, len(source)):
        char = source[index]
        if char == "{":
            depth += 1
            seen = True
        elif char == "}":
            depth -= 1
            if seen and depth == 0:
                return source[start:index + 1]
    raise SystemExit("unterminated declaration for " + marker)


editor = io.open(root + "/Floretta/Shared/Shell/DocumentEditor.swift", encoding="utf-8").read()
bar = io.open(root + "/Floretta/Shared/Shell/EditorStatusBar.swift", encoding="utf-8").read()

capsule = extract(editor, "private struct DocumentTitleCapsule: View {")
capped = extract(bar, "struct CappedWidthLayout: Layout {")

if "chevron.backward" not in capsule:
    raise SystemExit("extracted the wrong declaration: no chevron in it")
if "backSlot" not in capsule:
    raise SystemExit("the capsule has no trailing mirror slot")
if not re.search(r"HStack\(spacing: Self\.gap\)", capsule):
    raise SystemExit("the capsule no longer builds an HStack from one gap constant")

# The declaration is `private` inside DocumentEditor.swift; at file scope the
# probe needs it without the access keyword. That is the only edit applied to
# the extracted text — the layout code itself is byte-for-byte the product's.
probe_source = capsule.replace(
    "private struct DocumentTitleCapsule", "struct DocumentTitleCapsule", 1
)
io.open(gen + "/DocumentTitleCapsule.swift", "w", encoding="utf-8").write(
    "import SwiftUI\n\n" + probe_source + "\n"
)
io.open(gen + "/CappedWidthLayout.swift", "w", encoding="utf-8").write(
    "import SwiftUI\n\n" + capped + "\n"
)
print("extracted %d + %d chars from the product source" % (len(capsule), len(capped)))
PY

swiftc -O -swift-version 5 \
  -o "$bin" \
  "$gen/DocumentTitleCapsule.swift" \
  "$gen/CappedWidthLayout.swift" \
  "$root/scripts/measure-title-capsule.swift" \
  -framework SwiftUI -framework AppKit

exec "$bin" "$@"
