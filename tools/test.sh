#!/usr/bin/env bash
# Runs the test suite headless and fails on any failed check or GDScript error.
# A script error stops a test part-way without failing a check, so the log is searched for errors too.
# Usage: tools/test.sh [filter...]   (uses ~/godot/godot unless GODOT is set; see tools/setup_godot.sh)
# A filter runs only tests whose "file::method" contains it, e.g. tools/test.sh market or tools/test.sh test_gate.gd::test_raiders
# Set QUICK=1 to skip the import step when no script or resource was added since the last run.
set -uo pipefail
godot=${GODOT:-~/godot/godot}
[ -n "${QUICK:-}" ] || "$godot" --headless --path . --import >/dev/null 2>&1
log=$(mktemp)
"$godot" --headless --path . -s res://tests/run_tests.gd -- "$@" 2>&1 | tee "$log" | grep -E "^(PASS|FAIL|        )|passed,|SCRIPT ERROR|Parse Error"
status=${PIPESTATUS[0]}
if grep -qE "SCRIPT ERROR|Parse Error" "$log"; then
  echo "Script errors during the tests (see above)."
  status=1
fi
rm -f "$log"
exit "$status"
