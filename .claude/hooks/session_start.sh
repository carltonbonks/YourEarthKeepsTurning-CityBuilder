#!/usr/bin/env bash
# Cloud sessions start in a fresh container: fetch Godot and import the project so tools/test.sh works straight away.
# Local sessions are left alone (run tools/setup_godot.sh yourself once).
[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || exit 0
cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0
tools/setup_godot.sh >/dev/null 2>&1 || { echo "Godot setup failed; run tools/setup_godot.sh to see why."; exit 0; }
~/godot/godot --headless --path . --import >/dev/null 2>&1
echo "Godot ready at ~/godot/godot. Tests: tools/test.sh [filter]. Bots: tools/balance.sh [runs] [styles]."
