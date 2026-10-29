#!/bin/zsh
# Archives PhotoMapper for iOS and macOS and uploads both builds to App Store Connect (TestFlight).
#
# Prerequisites:
#   - Xcode signed in to the Apple ID for team Z4K4WDMMZ6 (Xcode > Settings > Accounts).
#   - An app record in App Store Connect with bundle ID com.christophernewell.PhotoMapper
#     that includes both the iOS and macOS platforms.
#
# Usage:  Scripts/upload-testflight.sh [ios|mac|all]   (default: all)
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# Keep build output out of the iCloud-synced project folder (xattrs there break codesign).
WORK="${TMPDIR:-/tmp}/PhotoMapper-testflight"
TEAM_ID="Z4K4WDMMZ6"
WHAT="${1:-all}"

mkdir -p "$WORK"
cat > "$WORK/exportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key><string>app-store-connect</string>
	<key>destination</key><string>upload</string>
	<key>teamID</key><string>$TEAM_ID</string>
	<key>signingStyle</key><string>automatic</string>
	<key>uploadSymbols</key><true/>
	<key>manageAppVersionAndBuildNumber</key><true/>
</dict>
</plist>
PLIST

xattr -cr "$PROJECT_DIR/PhotoMapper" 2>/dev/null || true

ship() {
  local platform="$1" dest="$2"
  local archive="$WORK/PhotoMapper-$platform.xcarchive"
  echo "==> Archiving ($platform)"
  rm -rf "$archive"
  xcodebuild archive \
    -project "$PROJECT_DIR/PhotoMapper.xcodeproj" \
    -scheme PhotoMapper \
    -destination "$dest" \
    -configuration Release \
    -archivePath "$archive" \
    -derivedDataPath "$WORK/DerivedData-$platform" \
    -allowProvisioningUpdates \
    -quiet
  echo "==> Uploading ($platform) to App Store Connect"
  xcodebuild -exportArchive \
    -archivePath "$archive" \
    -exportOptionsPlist "$WORK/exportOptions.plist" \
    -exportPath "$WORK/export-$platform" \
    -allowProvisioningUpdates
}

case "$WHAT" in
  ios) ship ios 'generic/platform=iOS' ;;
  mac) ship mac 'generic/platform=macOS' ;;
  all) ship ios 'generic/platform=iOS'; ship mac 'generic/platform=macOS' ;;
  *) echo "usage: $0 [ios|mac|all]" >&2; exit 2 ;;
esac

echo "Done. Builds appear under TestFlight in App Store Connect after processing (usually 5–15 minutes)."
