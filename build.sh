#!/bin/bash
# Regenerates the Xcode project and builds a Debug copy of the app into ./build
# Usage: ./build.sh [build|test]
#
# Every build raises the build number by one (see ./version.sh), so the app always shows which
# build is running. Running the tests does not change it.
cd "$(dirname "$0")" || exit 1
ACTION="${1:-build}"
if [ "$ACTION" = "build" ]; then
  ./version.sh build > /dev/null || { echo "EXIT:version-failed" > "$ACTION.log"; exit 1; }
fi
XCODEGEN="$(command -v xcodegen || echo /opt/homebrew/bin/xcodegen)"
"$XCODEGEN" generate > xcodegen.log 2>&1 || { echo "EXIT:xcodegen-failed" >> xcodegen.log; exit 1; }
xcodebuild -project CNERDMacUtilities.xcodeproj -scheme CNERDMacUtilities -configuration Debug \
  -derivedDataPath build -destination 'platform=macOS,arch=arm64' "$ACTION" > "$ACTION.log" 2>&1
echo "EXIT:$?" >> "$ACTION.log"
