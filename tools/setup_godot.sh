#!/usr/bin/env bash
# Downloads the Godot version CI uses to ~/godot/godot (Linux x86_64), so tests and tools run headless.
# Usage: tools/setup_godot.sh            (add "web" to also fetch the web export templates)
set -euo pipefail
version=$(grep -m1 'GODOT_VERSION:' .github/workflows/ci.yml | sed 's/.*"\(.*\)".*/\1/')
base="https://github.com/godotengine/godot/releases/download/${version}-stable"
if [ ! -x ~/godot/godot ] || ! ~/godot/godot --version 2>/dev/null | grep -q "^${version}"; then
  mkdir -p ~/godot
  tmp=$(mktemp -d)
  curl -fsSL -o "$tmp/godot.zip" "$base/Godot_v${version}-stable_linux.x86_64.zip"
  unzip -qo "$tmp/godot.zip" -d "$tmp"
  mv "$tmp/Godot_v${version}-stable_linux.x86_64" ~/godot/godot
  rm -rf "$tmp"
fi
if [ "${1:-}" = "web" ]; then
  dest=~/.local/share/godot/export_templates/${version}.stable
  if [ ! -f "$dest/version.txt" ]; then
    tmp=$(mktemp -d)
    curl -fsSL -o "$tmp/templates.tpz" "$base/Godot_v${version}-stable_export_templates.tpz"
    mkdir -p "$dest"
    unzip -jq "$tmp/templates.tpz" 'templates/web_nothreads_*' 'templates/version.txt' -d "$dest"
    rm -rf "$tmp"
  fi
fi
~/godot/godot --version
