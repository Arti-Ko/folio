#!/usr/bin/env bash
# Рисует иконку и собирает Assets/AppIcon.icns со всеми размерами.
# Использование: Scripts/make-icon.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT/Assets/AppIcon-1024.png"
WORK="$(mktemp -d)"
ICONSET="$WORK/AppIcon.iconset"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$ROOT/Assets" "$ICONSET"
swift "$ROOT/Scripts/make-icon.swift" "$SOURCE"

for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$SOURCE" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$SOURCE" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o "$ROOT/Assets/AppIcon.icns"
echo "готово: Assets/AppIcon.icns"
