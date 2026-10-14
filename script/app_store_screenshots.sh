#!/usr/bin/env bash
# Generates Mac App Store screenshots (2880×1800) from the real app running in
# its DEBUG screenshot mode (see macOS/Screenshots/MacScreenshotStage.swift).
#
# Usage: script/app_store_screenshots.sh [output-dir] [scene ...]
# Needs Screen Recording permission for the terminal running it, and a
# display at least 1440×900 pt in a 2× (Retina) mode.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${1:-$ROOT_DIR/AppStoreScreenshots/macOS}"
shift || true
SCENES=("$@")
if [ ${#SCENES[@]} -eq 0 ]; then
  SCENES=(menuBar overview topDomains services system blocklists)
fi

APP_NAME="Pi Stats"
DERIVED_DATA="$ROOT_DIR/.derivedData-codex-macos"
APP_BINARY="$DERIVED_DATA/Build/Products/Debug/$APP_NAME.app/Contents/MacOS/$APP_NAME"
RECT_FILE="$(mktemp -t pistats-screenshot-rect)"

xcodebuild \
  -quiet \
  -project "$ROOT_DIR/PiStats.xcodeproj" \
  -scheme macOS \
  -configuration Debug \
  -destination "platform=macOS,arch=arm64" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  build

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

index=0
for scene in "${SCENES[@]}"; do
  index=$((index + 1))
  for appearance in light dark; do
    mkdir -p "$OUT_DIR/$appearance"
    output="$OUT_DIR/$appearance/$(printf '%02d' "$index")-$scene.png"
    rm -f "$RECT_FILE"

    "$APP_BINARY" --app-store-screenshots \
      --screenshot-scene "$scene" \
      --screenshot-appearance "$appearance" \
      --screenshot-rect-file "$RECT_FILE" \
      -AppleLanguages "(en)" -AppleLocale en_US >/dev/null 2>&1 &
    app_pid=$!

    for _ in $(seq 1 40); do
      [ -s "$RECT_FILE" ] && break
      sleep 0.25
    done
    if [ ! -s "$RECT_FILE" ]; then
      echo "Timed out staging $scene ($appearance)" >&2
      kill "$app_pid" 2>/dev/null || true
      exit 1
    fi

    # Let charts, tables and async loads settle.
    sleep 1.5
    screencapture -x -R "$(cat "$RECT_FILE")" "$output"
    kill "$app_pid" 2>/dev/null || true
    wait "$app_pid" 2>/dev/null || true

    size="$(sips -g pixelWidth -g pixelHeight "$output" | awk '/pixel/ {print $2}' | paste -sd x -)"
    echo "$output ($size)"
  done
done

rm -f "$RECT_FILE"
