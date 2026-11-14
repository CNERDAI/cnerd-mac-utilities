#!/bin/bash
# Builds the downloadable version of CNERD Mac Utilities: a Release build for Apple silicon and
# Intel, signed with a Developer ID certificate, packed into a .dmg, and optionally notarized.
#
# Usage:
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" TEAM_ID=TEAMID ./release.sh
#   Add NOTARY_PROFILE=name to also notarize with Apple and staple the ticket.
#
# One-time setup for notarization (it asks for an app-specific password):
#   xcrun notarytool store-credentials "name" --apple-id "you@example.com" --team-id TEAMID
#
# SIGN_IDENTITY and TEAM_ID can also be set in Config/release.env, which is not committed.
#
# Every release needs a new version. Raise it first with ./version.sh patch, minor, or major.
# This script stops if the version already has a release tag (v1.1.0 and so on).
set -euo pipefail
cd "$(dirname "$0")"
[ -f Config/release.env ] && source Config/release.env

APP_NAME="CNERD Mac Utilities"
: "${SIGN_IDENTITY:?Set SIGN_IDENTITY to your Developer ID Application certificate name}"
: "${TEAM_ID:?Set TEAM_ID to your Apple developer team ID}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
OUT="release"
LOG="$OUT/release.log"

mkdir -p "$OUT"
: > "$LOG"
say() { echo "$@" | tee -a "$LOG"; }

VERSION="$(./version.sh number)"
if git rev-parse -q --verify "refs/tags/v$VERSION" > /dev/null 2>&1 && [ "$(git rev-parse "v$VERSION^{commit}")" != "$(git rev-parse HEAD)" ]; then
  say "Version $VERSION was already released (tag v$VERSION is on an earlier commit)."
  say "Raise the version first: ./version.sh patch   (or minor, or major)"
  exit 1
fi
XCODEGEN="$(command -v xcodegen || echo /opt/homebrew/bin/xcodegen)"
"$XCODEGEN" generate >> "$LOG" 2>&1

DMG="$OUT/CNERD-Mac-Utilities-$VERSION.dmg"
say "Building $APP_NAME $(./version.sh)"

xcodebuild -project CNERDMacUtilities.xcodeproj -scheme CNERDMacUtilities -configuration Release \
  -derivedDataPath build-release -destination 'generic/platform=macOS' \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$SIGN_IDENTITY" DEVELOPMENT_TEAM="$TEAM_ID" \
  OTHER_CODE_SIGN_FLAGS="--timestamp" CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  build >> "$LOG" 2>&1 || { say "BUILD FAILED. See $LOG"; exit 1; }

APP="build-release/Build/Products/Release/$APP_NAME.app"
codesign --verify --deep --strict "$APP" >> "$LOG" 2>&1 || { say "SIGNATURE CHECK FAILED"; exit 1; }
lipo -archs "$APP/Contents/MacOS/$APP_NAME" | sed 's/^/Architectures: /' | tee -a "$LOG"

# The installer: a disk image with the app and a shortcut to the Applications folder.
STAGE="$OUT/dmg-staging"
rm -rf "$STAGE"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/$APP_NAME.app"
ln -sfn /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >> "$LOG" 2>&1
codesign --sign "$SIGN_IDENTITY" --timestamp "$DMG" >> "$LOG" 2>&1
say "Installer: $DMG ($(du -h "$DMG" | cut -f1 | tr -d ' '))"

if [ -n "$NOTARY_PROFILE" ]; then
  say "Sending to Apple for notarization (this can take a few minutes)"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait 2>&1 | tee -a "$LOG"
  xcrun stapler staple "$DMG" 2>&1 | tee -a "$LOG"
  spctl -a -t open --context context:primary-signature -vv "$DMG" 2>&1 | tee -a "$LOG"
  say "Notarized and stapled. Ready to publish."
else
  say "NOT notarized. Set NOTARY_PROFILE to send it to Apple. Without that, macOS will block it on other Macs."
fi
# The checksum is taken last, because stapling the notarization ticket changes the file.
shasum -a 256 "$DMG" | tee "$DMG.sha256" >> "$LOG"
say "SHA-256: $(cut -d' ' -f1 "$DMG.sha256")"
say "DONE"
