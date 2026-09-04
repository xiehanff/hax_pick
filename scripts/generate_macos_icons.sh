#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_ICON="$ROOT_DIR/assets/app-icon.png"
OUTPUT_DIR="${1:-$ROOT_DIR/hax_pick}"

if [[ ! -f "$SOURCE_ICON" ]]; then
  echo "error: source icon not found: $SOURCE_ICON" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

width="$(sips -g pixelWidth "$SOURCE_ICON" | awk '/pixelWidth/ {print $2}')"
height="$(sips -g pixelHeight "$SOURCE_ICON" | awk '/pixelHeight/ {print $2}')"

if [[ -z "$width" || -z "$height" || "$width" != "$height" ]]; then
  echo "error: app icon must be a square PNG" >&2
  exit 1
fi

if (( width < 1024 )); then
  echo "error: app icon must be at least 1024x1024; got ${width}x${height}" >&2
  exit 1
fi

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
iconset="$work_dir/AppIcon.iconset"
mkdir -p "$iconset"

resize() {
  local pixels="$1"
  local output="$2"
  sips -z "$pixels" "$pixels" "$SOURCE_ICON" --out "$output" >/dev/null
}

resize 16   "$iconset/icon_16x16.png"
resize 32   "$iconset/icon_16x16@2x.png"
resize 32   "$iconset/icon_32x32.png"
resize 64   "$iconset/icon_32x32@2x.png"
resize 128  "$iconset/icon_128x128.png"
resize 256  "$iconset/icon_128x128@2x.png"
resize 256  "$iconset/icon_256x256.png"
resize 512  "$iconset/icon_256x256@2x.png"
resize 512  "$iconset/icon_512x512.png"
resize 1024 "$iconset/icon_512x512@2x.png"

iconutil -c icns "$iconset" -o "$OUTPUT_DIR/AppIcon.icns"

# MenuBarExtra renders the image at 16pt. Keep explicit 1x/2x files so the
# bundle resolves the correct representation on both standard and Retina displays.
resize 16 "$OUTPUT_DIR/MenuBarIcon.png"
resize 32 "$OUTPUT_DIR/MenuBarIcon@2x.png"

echo "Generated macOS icons from assets/app-icon.png"
