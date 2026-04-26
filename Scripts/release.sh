#!/usr/bin/env bash
# Release build → sign → notarize → staple → notarized DMG.
#
# All signing/notary inputs default to sensible local-dev values; override
# via env if you need to:
#   DEVELOPMENT_TEAM    Apple Team ID. Default: read from Configs/Local.xcconfig.
#   CODESIGN_IDENTITY   "Developer ID Application: <Name> (TEAMID)".
#                       Default: auto-discovered from keychain by team ID.
#   NOTARY_PROFILE      keychain profile from `xcrun notarytool store-credentials`.
#                       Default: "notarytool".
set -euo pipefail

cd "$(dirname "$0")/.."

# --------------------------------------------------------------------------
# Resolve inputs
# --------------------------------------------------------------------------

if [ -z "${DEVELOPMENT_TEAM:-}" ]; then
  DEVELOPMENT_TEAM=$(awk -F'=' '/^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=/{gsub(/[[:space:]]/,"",$2); print $2; exit}' \
    Configs/Local.xcconfig 2>/dev/null || true)
fi
: "${DEVELOPMENT_TEAM:?DEVELOPMENT_TEAM not set and not found in Configs/Local.xcconfig}"

if [ -z "${CODESIGN_IDENTITY:-}" ]; then
  CODESIGN_IDENTITY=$(security find-identity -p codesigning -v \
    | grep "Developer ID Application:" \
    | grep "($DEVELOPMENT_TEAM)" \
    | head -1 \
    | sed -E 's/.*"(.*)"$/\1/' || true)
fi
: "${CODESIGN_IDENTITY:?No Developer ID Application identity found in keychain for team $DEVELOPMENT_TEAM}"

NOTARY_PROFILE="${NOTARY_PROFILE:-notarytool}"

echo "Team:     $DEVELOPMENT_TEAM"
echo "Identity: $CODESIGN_IDENTITY"
echo "Notary:   $NOTARY_PROFILE"
echo

# --------------------------------------------------------------------------
# Build paths
# --------------------------------------------------------------------------

BUILD_DIR=".build"
ARCHIVE_PATH="$BUILD_DIR/MandroidFinder.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
EXPORT_OPTIONS="$BUILD_DIR/exportOptions.plist"
APP="$EXPORT_DIR/MandroidFinder.app"
APP_ZIP="$BUILD_DIR/MandroidFinder.zip"
DMG_STAGING="$BUILD_DIR/dmg-staging"
DMG="$BUILD_DIR/MandroidFinder.dmg"

mkdir -p "$BUILD_DIR"

# --------------------------------------------------------------------------
# Step 1: generate Xcode project + archive
# --------------------------------------------------------------------------

echo "==> 1/7  xcodegen + archive"
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen not found. Install with: brew install xcodegen" >&2
  exit 1
fi
xcodegen generate

xcodebuild \
  -project MandroidFinder.xcodeproj \
  -scheme MandroidFinder \
  -configuration Release \
  -destination 'platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  archive

# --------------------------------------------------------------------------
# Step 2: export with Developer ID
# --------------------------------------------------------------------------

echo
echo "==> 2/7  exportArchive"
cat > "$EXPORT_OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>teamID</key><string>${DEVELOPMENT_TEAM}</string>
    <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -allowProvisioningUpdates

# --------------------------------------------------------------------------
# Step 3: notarize and staple the .app itself
#
# Why this and the DMG? If a user ever extracts MandroidFinder.app out of
# the DMG and copies it somewhere else, a staple on the .app survives
# while a staple on only the DMG would not.
# --------------------------------------------------------------------------

echo
echo "==> 3/7  zip the app for notarization"
rm -f "$APP_ZIP"
ditto -c -k --keepParent "$APP" "$APP_ZIP"

echo
echo "==> 4/7  notarize the app (this can take a minute or two)"
xcrun notarytool submit "$APP_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait

echo
echo "==> 5/7  staple the app"
xcrun stapler staple "$APP"

# --------------------------------------------------------------------------
# Step 4: build DMG, sign, notarize, staple
#
# DMG (vs flat zip) avoids the AppleDouble (`._*`) extraction problem that
# breaks Gatekeeper when end-users unzip with non-Apple tools.
# --------------------------------------------------------------------------

echo
echo "==> 6/7  assemble + sign the DMG"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$APP" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

rm -f "$DMG"
hdiutil create \
  -volname "MandroidFinder" \
  -srcfolder "$DMG_STAGING" \
  -ov \
  -format UDZO \
  "$DMG"

codesign \
  --sign "$CODESIGN_IDENTITY" \
  --options runtime \
  --timestamp \
  "$DMG"

echo
echo "==> 7/7  notarize + staple the DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"

# --------------------------------------------------------------------------
# Verify
# --------------------------------------------------------------------------

echo
echo "==> Verification"
spctl --assess --type open --context context:primary-signature --verbose "$DMG"
xcrun stapler validate "$DMG" >/dev/null
echo "    DMG stapled: yes"
xcrun stapler validate "$APP" >/dev/null
echo "    App stapled: yes"

# --------------------------------------------------------------------------
# Restore the dev environment's File Provider extension registration.
#
# `xcodebuild archive` walks its intermediate output directory and quietly
# registers our `.appex` from there with `pluginkit`. That intermediate
# location lives under `Build/Intermediates.noindex/ArchiveIntermediates/`
# and gets cleaned up later — leaving the system pointing at a
# now-nonexistent bundle, which makes Finder enumerations time out for
# any registered domain. Re-point pluginkit at the live Debug build
# (if present) so dev work continues to work after a release.
# --------------------------------------------------------------------------

EXT_BUNDLE_ID="com.danielkao.mandroidfinder.fileprovider"
DEBUG_APPEX=$(ls -d "$HOME/Library/Developer/Xcode/DerivedData/MandroidFinder-"*"/Build/Products/Debug/MandroidFinder.app/Contents/PlugIns/MandroidFileProvider.appex" 2>/dev/null | head -1 || true)

echo
echo "==> Restoring dev File Provider registration"
# Flush every current registration of our extension (may include stale
# ArchiveIntermediates path from this build).
while IFS= read -r path; do
  [ -n "$path" ] || continue
  pluginkit -r "$path" 2>/dev/null || true
done < <(pluginkit -m -v -p com.apple.fileprovider-nonui 2>/dev/null \
         | awk -v id="$EXT_BUNDLE_ID" '$1 ~ id {print $NF}')

if [ -n "$DEBUG_APPEX" ] && [ -d "$DEBUG_APPEX" ]; then
  pluginkit -a "$DEBUG_APPEX"
  echo "    Registered: $DEBUG_APPEX"
else
  echo "    (no Debug build at expected path — re-run Scripts/build.sh after this if you intend to keep developing)"
fi

echo
echo "✅ Release ready"
echo "    DMG: $DMG ($(du -h "$DMG" | cut -f1))"
echo "    App: $APP"
echo
echo "Next: gh release create v<x.y.z> $DMG --title \"...\" --notes \"...\""
