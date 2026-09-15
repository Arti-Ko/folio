#!/usr/bin/env bash
# Собирает Folio.app: веб-часть, релизные бинарники приложения и утилиты folio, Info.plist и ad-hoc подпись.
# Использование: Scripts/build.sh [--install]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Folio"
EXECUTABLE="FolioApp"
BUNDLE_ID="org.sleepycoffee.folio"
VERSION="${FOLIO_VERSION:-$(tr -d '[:space:]' < "$ROOT/VERSION")}"
BUILD_NUMBER="${FOLIO_BUILD:-$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)}"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
INSTALLED_APP="/Applications/$APP_NAME.app"
CLI_LINK="/opt/homebrew/bin/folio"

# Глобальный git этой машины (safe.bareRepository=explicit) ломает SwiftPM.
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=all

echo "==> Folio $VERSION ($BUILD_NUMBER)"

echo "==> веб-часть: тесты и сборка"
cd "$ROOT/web"
[ -d node_modules ] || npm ci
npm run --silent test
npm run --silent build

cd "$ROOT"
echo "==> swift build -c release"
swift build -c release --product "$EXECUTABLE"
swift build -c release --product folio
BIN_DIR="$(swift build -c release --show-bin-path)"

echo "==> собираю бандл"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/ru.lproj"
cp "$BIN_DIR/$EXECUTABLE" "$APP/Contents/MacOS/$EXECUTABLE"
cp "$BIN_DIR/folio" "$APP/Contents/MacOS/folio"
cp -R "$ROOT/web/dist" "$APP/Contents/Resources/web"

ICON_KEY=""
if [ -f "$ROOT/Assets/AppIcon.icns" ]; then
    cp "$ROOT/Assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
    ICON_KEY="<key>CFBundleIconFile</key><string>AppIcon</string>"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleExecutable</key><string>$EXECUTABLE</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleDevelopmentRegion</key><string>ru</string>
    <key>CFBundleLocalizations</key><array><string>ru</string></array>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    $ICON_KEY
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>Folio</string>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key><string>$BUNDLE_ID.page</string>
            <key>CFBundleURLSchemes</key><array><string>folio</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST

echo "==> подписываю"
codesign --force --sign - --timestamp=none "$APP/Contents/MacOS/folio" >/dev/null
codesign --force --sign - --timestamp=none "$APP" >/dev/null

if [ "${1:-}" != "--install" ]; then
    echo "готово: $APP"
    exit 0
fi

echo "==> ставлю в /Applications"
if pgrep -x "$EXECUTABLE" >/dev/null; then
    osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        pgrep -x "$EXECUTABLE" >/dev/null || break
        sleep 0.5
    done
fi
rm -rf "$INSTALLED_APP"
cp -R "$APP" "$INSTALLED_APP"

if [ -d "$(dirname "$CLI_LINK")" ]; then
    if [ ! -e "$CLI_LINK" ] || [ -L "$CLI_LINK" ]; then
        ln -sfn "$INSTALLED_APP/Contents/MacOS/folio" "$CLI_LINK"
        echo "утилита: $CLI_LINK"
    else
        echo "пропускаю $CLI_LINK: там лежит не ссылка"
    fi
fi
echo "готово: $INSTALLED_APP"
