#!/usr/bin/env bash
# Build the TrueCarry Bridge menu-bar .app with PyInstaller.
# Run from anywhere; paths are resolved relative to this script.
#
#   ./build.sh           # build only (no signing) — for local testing
#
# Signing + notarization is a separate step (sign-notarize.sh) so this can be
# run/tested before the Developer ID certificate exists.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
BRIDGE_DIR="$(dirname "$HERE")"
APP_NAME="TrueCarry Bridge"
BUNDLE_ID="app.truecarry.bridge"
VENV="$HERE/.buildvenv"

cd "$BRIDGE_DIR"

# 1. Isolated build environment
if [ ! -d "$VENV" ]; then
    echo "→ Creating build venv…"
    python3 -m venv "$VENV"
fi
"$VENV/bin/pip" install --quiet --upgrade pip
"$VENV/bin/pip" install --quiet pyinstaller rumps bleak

# 2. Clean previous output
rm -rf "$HERE/build" "$HERE/dist"

# 3. Build the .app
"$VENV/bin/pyinstaller" --noconfirm --clean --windowed \
    --name "$APP_NAME" \
    --osx-bundle-identifier "$BUNDLE_ID" \
    --icon "$HERE/icon.icns" \
    --collect-all bleak \
    --collect-all rumps \
    --distpath "$HERE/dist" \
    --workpath "$HERE/build" \
    --specpath "$HERE/build" \
    truecarry_menubar.py

APP="$HERE/dist/$APP_NAME.app"
PLIST="$APP/Contents/Info.plist"

# 4. Inject Info.plist keys: menu-bar agent (no Dock icon) + Bluetooth usage string
/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$PLIST" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Set :LSUIElement true" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :NSBluetoothAlwaysUsageDescription string 'TrueCarry Bridge uses Bluetooth to receive shots from your iPhone.'" "$PLIST" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Set :NSBluetoothAlwaysUsageDescription 'TrueCarry Bridge uses Bluetooth to receive shots from your iPhone.'" "$PLIST"

echo ""
echo "✅ Built: $APP"
echo "   Test it:  open \"$APP\""
echo "   Then sign + notarize with: $HERE/sign-notarize.sh"
