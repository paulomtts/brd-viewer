#!/usr/bin/env bash
# Restarts the shell and fails if the plugin did not load. Needs the real shell.
set -euo pipefail
plugin="paulomtts.omarchy-project-manager"
omarchy-restart-shell >/dev/null 2>&1
sleep 8
omarchy-shell shell toggle "$plugin" >/dev/null 2>&1 || true
sleep 1
omarchy-shell shell toggle "$plugin" >/dev/null 2>&1 || true
bad=$(journalctl --user --since "-40sec" 2>/dev/null | grep -E "Plugin widget $plugin failed|summon: no live bar widget for: $plugin" || true)
if [ -n "$bad" ]; then echo "$bad"; exit 1; fi
echo "live check ok"
