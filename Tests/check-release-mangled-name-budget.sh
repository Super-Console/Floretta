#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "usage: bash Tests/check-release-mangled-name-budget.sh <DocumentEditor.o> [budget-bytes]" >&2
  exit 64
fi

object_file=$1
budget=${2:-600}
if [[ ! -f "$object_file" ]]; then
  echo "object file not found: $object_file" >&2
  exit 66
fi

xcrun nm -gU "$object_file" | awk -v budget="$budget" '
BEGIN {
    names[1] = "canvasStack"
    names[2] = "editorCore"
    names[3] = "CanvasStackView"
    names[4] = "EditorCoreView"
    names[5] = "CanvasStageView"
    names[6] = "CanvasNoticesView"
    names[7] = "BottomBarRowView"
    names[8] = "ZenExitOverlayView"
    names[9] = "OutlinePanelView"
    names[10] = "OutlinePanelHeaderView"
    names[11] = "OutlineWideButtonView"
    names[12] = "OutlineCloseButtonView"
}
{
    symbol = $NF
    category = ""
    if (symbol ~ /DocumentEditorV11canvasStack/) category = "canvasStack"
    else if (symbol ~ /DocumentEditorV10editorCore/) category = "editorCore"
    else if (symbol ~ /DocumentEditorV[0-9]+CanvasStackView/) category = "CanvasStackView"
    else if (symbol ~ /DocumentEditorV[0-9]+EditorCoreView/) category = "EditorCoreView"
    else if (symbol ~ /DocumentEditorV[0-9]+CanvasStageView/) category = "CanvasStageView"
    else if (symbol ~ /DocumentEditorV[0-9]+CanvasNoticesView/) category = "CanvasNoticesView"
    else if (symbol ~ /DocumentEditorV[0-9]+BottomBarRowView/) category = "BottomBarRowView"
    else if (symbol ~ /DocumentEditorV[0-9]+ZenExitOverlayView/) category = "ZenExitOverlayView"
    else if (symbol ~ /DocumentEditorV[0-9]+OutlinePanelView/) category = "OutlinePanelView"
    else if (symbol ~ /DocumentEditorV[0-9]+OutlinePanelHeaderView/) category = "OutlinePanelHeaderView"
    else if (symbol ~ /DocumentEditorV[0-9]+OutlineWideButtonView/) category = "OutlineWideButtonView"
    else if (symbol ~ /DocumentEditorV[0-9]+OutlineCloseButtonView/) category = "OutlineCloseButtonView"
    if (category != "") {
        size = length(symbol)
        if (!(category in maxima) || size > maxima[category]) maxima[category] = size
        counts[category]++
    }
}
END {
    found = 0
    failed = 0
    for (i = 1; i <= 12; i++) {
        category = names[i]
        if (category in counts) {
            found++
            printf "%s: max %d bytes (budget %d; %d symbol(s))\n", category, maxima[category], budget, counts[category]
            if (maxima[category] > budget) failed = 1
        }
    }
    if (!found) {
        print "no DocumentEditor crash-path symbols found in object" > "/dev/stderr"
        exit 2
    }
    exit failed ? 1 : 0
}'
