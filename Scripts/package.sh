#!/usr/bin/env bash
# Собирает артефакты выпуска:
#   dist/Folio.dmg — установщик (перетащить в «Программы»),
#   dist/Folio.zip — архив, который скачивает встроенное автообновление.
# Использование: Scripts/package.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/Folio.app"

"$ROOT/Scripts/build.sh"

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

rm -f "$DIST/Folio.zip" "$DIST/Folio.dmg"

echo "==> архив для автообновления"
ditto -c -k --keepParent "$APP" "$DIST/Folio.zip"

echo "==> установщик DMG"
ditto "$APP" "$STAGING/Folio.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Folio" -srcfolder "$STAGING" -ov -format UDZO "$DIST/Folio.dmg" >/dev/null

echo "готово: $DIST/Folio.dmg, $DIST/Folio.zip"
