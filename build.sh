#!/bin/bash
# Собирает MenuTimer.app и ставит его в ~/Applications (без sudo, без Xcode).
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="MenuTimer"
BUNDLE="$APP_NAME.app"
DEST="$HOME/Applications"

echo "==> Компиляция"
swift build -c release

echo "==> Сборка бандла"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp ".build/release/$APP_NAME" "$BUNDLE/Contents/MacOS/"
cp "Resources/Info.plist" "$BUNDLE/Contents/"
cp "Resources/AppIcon.icns" "$BUNDLE/Contents/Resources/"

echo "==> Ad-hoc подпись"
codesign --force --sign - "$BUNDLE"

echo "==> Установка в $DEST"
pkill -f "$DEST/$BUNDLE/Contents/MacOS/$APP_NAME" 2>/dev/null || true
sleep 1
mkdir -p "$DEST"
rm -rf "$DEST/$BUNDLE"
cp -R "$BUNDLE" "$DEST/"
# Finder кэширует иконки — трогаем бандл, чтобы он перечитал новую
touch "$DEST/$BUNDLE"

echo "==> Готово: $DEST/$BUNDLE"
echo "    Запуск: open \"$DEST/$BUNDLE\""
