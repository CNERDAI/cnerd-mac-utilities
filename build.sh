#!/bin/bash
# Regenerates the Xcode project and builds a Debug copy of the app into ./build
# Usage: ./build.sh [build|test]
cd "$(dirname "$0")" || exit 1
ACTION="${1:-build}"
XCODEGEN="$(command -v xcodegen || echo /opt/homebrew/bin/xcodegen)"
"$XCODEGEN" generate > xcodegen.log 2>&1 || { echo "EXIT:xcodegen-failed" >> xcodegen.log; exit 1; }
xcodebuild -project CNERDMacUtilities.xcodeproj -scheme CNERDMacUtilities -configuration Debug \
  -derivedDataPath build -destination 'platform=macOS,arch=arm64' "$ACTION" > "$ACTION.log" 2>&1
echo "EXIT:$?" >> "$ACTION.log"
