#!/usr/bin/env bash
# Release build: archive, export, sign, notarize, staple.
# Requires environment:
#   DEVELOPMENT_TEAM      Apple Developer Team ID
#   CODESIGN_IDENTITY     "Developer ID Application: <Name> (TEAMID)"
#   NOTARY_PROFILE        keychain profile name from `xcrun notarytool store-credentials`
set -euo pipefail

cd "$(dirname "$0")/.."

: "${DEVELOPMENT_TEAM:?must be set}"
: "${CODESIGN_IDENTITY:?must be set}"
: "${NOTARY_PROFILE:?must be set}"

xcodegen generate

ARCHIVE_PATH=".build/MandroidFinder.xcarchive"
EXPORT_PATH=".build/export"
EXPORT_OPTIONS_PLIST=".build/exportOptions.plist"

mkdir -p .build
cat > "$EXPORT_OPTIONS_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>teamID</key><string>${DEVELOPMENT_TEAM}</string>
    <key>signingStyle</key><string>manual</string>
    <key>signingCertificate</key><string>${CODESIGN_IDENTITY}</string>
</dict>
</plist>
PLIST

xcodebuild \
  -project MandroidFinder.xcodeproj \
  -scheme MandroidFinder \
  -configuration Release \
  -destination 'platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  archive

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS_PLIST"

APP="$EXPORT_PATH/MandroidFinder.app"
ZIP="$EXPORT_PATH/MandroidFinder.zip"

ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"

echo "✅ Release ready at $APP"
