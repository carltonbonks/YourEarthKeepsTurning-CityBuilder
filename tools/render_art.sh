#!/usr/bin/env bash
# Renders map art from art/manifest.json into art/sprites/ (see tools/render_art.py and docs/ART_SPEC.md).
# Usage: tools/render_art.sh [id...]   (no ids renders everything)
# The first run installs Blender as a Python package (bpy, about 400 MB) into ~/.cache/render-art.
# Then it re-imports the project so Godot picks up the new sprites, if Godot is installed.
set -euo pipefail
cd "$(dirname "$0")/.."
venv=${ART_VENV:-~/.cache/render-art}
BPY_VERSION=5.2.3
if [ ! -x "$venv/bin/python" ] || ! "$venv/bin/python" -c "import bpy, PIL" 2>/dev/null; then
  echo "Installing Blender $BPY_VERSION for rendering (once)..."
  py=$(command -v python3.13 || command -v python3)
  "$py" -m venv "$venv"
  "$venv/bin/pip" install -q "bpy==$BPY_VERSION" pillow
fi
"$venv/bin/python" tools/render_art.py -- "$@" 2>&1 | grep -E "^(Rendered|Contact|No manifest|Traceback|  File|[A-Za-z]*Error)" || true
test -f art/sprites/index.json
godot=${GODOT:-~/godot/godot}
if [ -x "$godot" ]; then
  "$godot" --headless --path . --import >/dev/null 2>&1 || true
  # Sprites ship as lossy WebP (quality 0.9), less than half the download of lossless (docs/ART_SPEC.md budget).
  if grep -l "^compress/mode=0" art/sprites/*.png.import >/dev/null 2>&1; then
    sed -i 's/^compress\/mode=0/compress\/mode=1/; s/^compress\/lossy_quality=.*/compress\/lossy_quality=0.9/' art/sprites/*.png.import
    "$godot" --headless --path . --import >/dev/null 2>&1 || true
  fi
fi
echo "Sprites in art/sprites/."
