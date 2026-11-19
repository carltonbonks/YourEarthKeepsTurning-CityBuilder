#!/usr/bin/env bash
# Brings a sound file into the game the way docs/SOUND_SPEC.md asks: Ogg Vorbis, 44.1 kHz, mono (or stereo with
# --stereo, for beds and music), its loudest peak set to -1 dBFS so every file starts level and the manifest's
# volume_db alone sets how loud a moment plays. Any format ffmpeg reads goes in (wav, ogg, flac, mp3).
# Usage: tools/import_sound.sh <source file> <dest under audio/, e.g. audio/sfx/ui_click_01.ogg> [--stereo]
# Then add the file and its licence line to audio/manifest.json and run tools/test.sh sound.
set -euo pipefail
src=$1
dst=$2
channels=1
[ "${3:-}" = "--stereo" ] && channels=2
peak=$(ffmpeg -hide_banner -nostats -i "$src" -af volumedetect -f null - 2>&1 | sed -n 's/.*max_volume: \([-0-9.]*\) dB.*/\1/p')
gain=$(awk -v p="$peak" 'BEGIN { printf "%.2f", -1.0 - p }')
mkdir -p "$(dirname "$dst")"
ffmpeg -hide_banner -loglevel error -y -i "$src" -map_metadata -1 -ac "$channels" -ar 44100 -af "volume=${gain}dB" \
  -c:a libvorbis -q:a 5 "$dst"
echo "$dst  (peak was ${peak} dB, gain ${gain} dB)"
