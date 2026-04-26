#!/usr/bin/env bash
# Generates the Xcode project from project.yml and builds the app.
# Requires: xcodegen (brew install xcodegen)
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen not found. Install with: brew install xcodegen" >&2
  exit 1
fi

if [ ! -f Configs/Local.xcconfig ]; then
  echo "Missing Configs/Local.xcconfig." >&2
  echo "  Copy Configs/Local.xcconfig.example and fill in your DEVELOPMENT_TEAM and BUNDLE_ID_PREFIX." >&2
  exit 1
fi

xcodegen generate

xcodebuild \
  -project MandroidFinder.xcodeproj \
  -scheme MandroidFinder \
  -configuration Debug \
  -destination 'platform=macOS' \
  -allowProvisioningUpdates \
  build
