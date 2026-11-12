#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SOURCE="assets/AppIcon-source.png"
OUTPUT="Resources/AppIcon.icns"
if [[ -f "$OUTPUT" && "$OUTPUT" -nt "$SOURCE" && "$OUTPUT" -nt "$0" ]]; then
    exit 0
fi
ICONSET="build/AppIcon.iconset"
mkdir -p "$ICONSET" Resources
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$SOURCE" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    retina=$((size * 2))
    sips -z "$retina" "$retina" "$SOURCE" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil --convert icns "$ICONSET" --output "$OUTPUT"
