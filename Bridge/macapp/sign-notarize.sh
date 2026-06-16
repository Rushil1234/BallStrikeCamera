#!/usr/bin/env bash
# Sign, notarize, and staple the built TrueCarry Bridge.app, then produce a
# distributable zip. Run AFTER build.sh, and after you have:
#   1. a "Developer ID Application" certificate in your Keychain, and
#   2. a stored notary profile created with:
#        xcrun notarytool store-credentials "truecarry-notary" \
#          --apple-id "you@example.com" --team-id "XXXXXXXXXX" --password "app-specific-pw"

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="TrueCarry Bridge"
APP="$HERE/dist/$APP_NAME.app"
DMG="$HERE/dist/TrueCarryBridge.dmg"
# Pass the keychain profile name as arg 1 if you named it something other than
# the default, e.g.:  ./sign-notarize.sh "True Carry"
NOTARY_PROFILE="${1:-truecarry-notary}"
ENTITLEMENTS="$HERE/entitlements.plist"

[ -d "$APP" ] || { echo "✗ $APP not found — run build.sh first."; exit 1; }

# 1. Find the Developer ID Application identity automatically
IDENTITY="$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)"/\1/')"
if [ -z "${IDENTITY:-}" ]; then
    echo "✗ No 'Developer ID Application' certificate found in your Keychain."
    echo "  Create one in Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Application."
    exit 1
fi
echo "→ Signing with: $IDENTITY"

# 2. Sign everything inside-out with the hardened runtime
codesign --force --deep --timestamp --options runtime \
    --entitlements "$ENTITLEMENTS" \
    --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

# 3. Notarize + staple the .app (zip only as a transport for notarytool).
#    We DON'T distribute the zip — Archive Utility mangles the bundled
#    Python.framework symlinks on extraction, which breaks the seal
#    ("unsealed contents present in the root directory of an embedded
#    framework"). A DMG preserves the bundle exactly, so we ship that.
TMP_ZIP="$HERE/dist/_notarize.zip"
rm -f "$TMP_ZIP"
ditto -c -k --keepParent "$APP" "$TMP_ZIP"

echo "→ Notarizing the app (this can take a few minutes)…"
xcrun notarytool submit "$TMP_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=4 "$APP" || true
rm -f "$TMP_ZIP"

# 4. Package the stapled app into a drag-to-Applications DMG, sign, notarize, staple.
echo "→ Building + signing + notarizing DMG…"
rm -f "$DMG"
STAGE="$HERE/dist/dmg_stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"                 # the stapled app
ln -s /Applications "$STAGE/Applications"   # drop target so users can drag it in
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl -a -t open --context context:primary-signature -v "$DMG" || true

echo ""
echo "✅ Notarized + stapled: $DMG"
echo "   Copy it to the site:  cp \"$DMG\" ../../Website/public/downloads/TrueCarryBridge.dmg"
