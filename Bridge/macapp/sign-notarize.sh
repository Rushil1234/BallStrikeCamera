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
ZIP="$HERE/dist/TrueCarryBridge.zip"
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

# 3. Zip for notarization
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

# 4. Notarize (waits for Apple's result)
echo "→ Submitting to Apple notary service (this can take a few minutes)…"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait

# 5. Staple the ticket so it works offline
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

# 6. Gatekeeper sanity check (should say: accepted, source=Notarized Developer ID)
spctl --assess --type execute --verbose=4 "$APP" || true

# 7. Re-zip the stapled app for distribution
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo ""
echo "✅ Notarized + stapled: $APP"
echo "   Distributable:       $ZIP"
echo "   Copy it to the site:  cp \"$ZIP\" ../../Website/public/downloads/TrueCarryBridge.zip"
