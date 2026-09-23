#!/usr/bin/env bash
# Both suites: pytest for resolve-db-path.py, Qt's own qmltestrunner for
# logic.js (the panel's rules, on the same engine the panel runs on).
set -euo pipefail
cd "$(dirname "$0")"

python3 -m pytest tests

bash tests/panel/run.sh

qmltestrunner=$(command -v /usr/lib/qt6/bin/qmltestrunner || command -v qmltestrunner)
QT_QPA_PLATFORM=offscreen "$qmltestrunner" -input tests/qml
