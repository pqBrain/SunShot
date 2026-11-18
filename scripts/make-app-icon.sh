#!/usr/bin/env bash
# S17: builds AppIcon.icns from Sunshot's own drawing code (Sources/SunshotRender/AppIconArtwork.swift), so no
# binary artwork is checked in. Usage: scripts/make-app-icon.sh <output.icns>
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:?usage: make-app-icon.sh <output.icns>}"
WORK="$ROOT/.build/app-icon"
rm -rf "$WORK"
mkdir -p "$WORK"
swiftc -O -swift-version 6 -o "$WORK/make-app-icon" \
  "$ROOT/Sources/SunshotRender/AppIconArtwork.swift" "$ROOT/scripts/app-icon/main.swift"
"$WORK/make-app-icon" "$WORK/AppIcon.iconset"
# Drop @2x entries whose pixels duplicate a 1x entry (16@2x = 32, 128@2x = 256, 256@2x = 512): AppKit picks icon
# reps by pixel size, so they only add ~220 KB of identical PNGs to the bundle.
rm -f "$WORK/AppIcon.iconset/icon_16x16@2x.png" "$WORK/AppIcon.iconset/icon_128x128@2x.png" \
  "$WORK/AppIcon.iconset/icon_256x256@2x.png"
iconutil -c icns "$WORK/AppIcon.iconset" -o "$OUT"
