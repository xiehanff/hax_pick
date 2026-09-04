#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_ICON="$ROOT_DIR/assets/app-icon.png"
MENU_BAR_TEMPLATE_SCRIPT="$ROOT_DIR/scripts/extract_menu_bar_template.swift"
OUTPUT_DIR="${1:-$ROOT_DIR/hax_pick}"

if [[ ! -f "$SOURCE_ICON" ]]; then
  echo "error: source icon not found: $SOURCE_ICON" >&2
  exit 1
fi

if [[ ! -f "$MENU_BAR_TEMPLATE_SCRIPT" ]]; then
  echo "error: menu bar template generator not found: $MENU_BAR_TEMPLATE_SCRIPT" >&2
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
  local source="$1"
  local pixels="$2"
  local output="$3"
  sips -z "$pixels" "$pixels" "$source" --out "$output" >/dev/null
}

resize "$SOURCE_ICON" 16   "$iconset/icon_16x16.png"
resize "$SOURCE_ICON" 32   "$iconset/icon_16x16@2x.png"
resize "$SOURCE_ICON" 32   "$iconset/icon_32x32.png"
resize "$SOURCE_ICON" 64   "$iconset/icon_32x32@2x.png"
resize "$SOURCE_ICON" 128  "$iconset/icon_128x128.png"
resize "$SOURCE_ICON" 256  "$iconset/icon_128x128@2x.png"
resize "$SOURCE_ICON" 256  "$iconset/icon_256x256.png"
resize "$SOURCE_ICON" 512  "$iconset/icon_256x256@2x.png"
resize "$SOURCE_ICON" 512  "$iconset/icon_512x512.png"
resize "$SOURCE_ICON" 1024 "$iconset/icon_512x512@2x.png"

iconutil -c icns "$iconset" -o "$OUTPUT_DIR/AppIcon.icns"

# MenuBarExtra needs a monochrome template mark rather than a scaled-down app tile.
# Extract the orange brand glyph, remove the rounded-square background, then keep
# explicit 1x/2x files for standard and Retina displays.
menu_bar_template="$work_dir/MenuBarIconTemplate.png"
swift "$MENU_BAR_TEMPLATE_SCRIPT" "$SOURCE_ICON" "$menu_bar_template"
resize "$menu_bar_template" 16 "$OUTPUT_DIR/MenuBarIcon.png"
resize "$menu_bar_template" 32 "$OUTPUT_DIR/MenuBarIcon@2x.png"

echo "Generated macOS icons from assets/app-icon.png"
