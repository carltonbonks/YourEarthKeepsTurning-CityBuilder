#!/usr/bin/env bash
# Runs the balance bots for several styles at once (one Godot process per style, as many at a time as there are cores)
# and prints each style's report. A 60-run style takes ~12 minutes alone, so this is the quick way to get PR win rates.
# Usage: tools/balance.sh [runs] [styles...]     e.g. tools/balance.sh 60 balanced workers
#   Defaults: 60 runs; styles balanced workers heroes market bronze. Extra balance_run.gd args go in BOT_ARGS,
#   e.g. BOT_ARGS="gates=0". Set OUT=<dir> LABEL=<name> to also keep the records as <dir>/bots-<name>-<style>.jsonl
#   (for run_report.gd and export_csv.py).
set -uo pipefail
godot=${GODOT:-~/godot/godot}
runs=${1:-60}
shift || true
styles=("$@")
[ ${#styles[@]} -gt 0 ] || styles=(balanced workers heroes market bronze)
logs=$(mktemp -d)
for style in "${styles[@]}"; do
  out=""
  [ -n "${OUT:-}" ] && out="out=$(realpath "$OUT")/bots-${LABEL:-dev}-$style.jsonl label=${LABEL:-dev}"
  # shellcheck disable=SC2086
  "$godot" --headless --path . -s res://tools/balance_run.gd -- runs="$runs" style="$style" $out ${BOT_ARGS:-} \
    >"$logs/$style.log" 2>&1 &
  while [ "$(jobs -rp | wc -l)" -ge "$(nproc)" ]; do wait -n; done
done
wait
for style in "${styles[@]}"; do
  sed -n '/^Style:/,$p' "$logs/$style.log"
  grep -E "SCRIPT ERROR|Parse Error" "$logs/$style.log" && echo "Script errors in the $style run (log: $logs/$style.log)"
  echo
done
