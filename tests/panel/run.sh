#!/usr/bin/env bash
# Compiles the real plugin QML against stubbed Omarchy shell types and runs
# every tests/panel/tst_*.qml with Qt's test runner. Panel.qml cannot run
# headless in the real shell, so this is how its behaviour is tested.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

runner=$(command -v /usr/lib/qt6/bin/qmltestrunner || command -v qmltestrunner)
cp -r "$here/stubs/." "$work/"
mkdir "$work/t"
cp "$repo"/*.qml "$repo/logic.js" "$work/t/"
cp -r "$repo/canvas" "$work/t/canvas"
cp "$here"/tst_*.qml "$work/t/"

status=0
for test in "$work"/t/tst_*.qml; do
  echo "== $(basename "$test")"
  out=$(QT_QPA_PLATFORM=offscreen "$runner" -import "$work" -input "$test" 2>&1) || status=1
  echo "$out" | grep -E "^(FAIL|Totals)|^   Loc" || true
  bad=$(echo "$out" | grep -E "TypeError|ReferenceError|non-existent|Unable to assign|anchors on an item|is not a function" | grep -v "width' of null" || true)
  if [ -n "$bad" ]; then echo "$bad"; status=1; fi
done
exit $status
