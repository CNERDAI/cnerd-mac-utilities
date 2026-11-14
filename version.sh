#!/bin/bash
# Shows or changes the app's version. The version lives in Config/Version.xcconfig.
#
# Usage:
#   ./version.sh              show the version and the build number
#   ./version.sh build        raise the build number by one (build.sh does this on every build)
#   ./version.sh patch        1.1.0 -> 1.1.1   fixes
#   ./version.sh minor        1.1.0 -> 1.2.0   new features
#   ./version.sh major        1.1.0 -> 2.0.0   big changes
#   ./version.sh set 1.4.2    set the version by hand
#   ./version.sh number       print only the version, for other scripts
#
# patch, minor, major, and set also raise the build number. The build number never goes back.
set -euo pipefail
cd "$(dirname "$0")"
FILE="Config/Version.xcconfig"

version="$(sed -n 's/^MARKETING_VERSION *= *//p' "$FILE" | tr -d ' \r')"
build="$(sed -n 's/^CURRENT_PROJECT_VERSION *= *//p' "$FILE" | tr -d ' \r')"
if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$build" =~ ^[0-9]+$ ]]; then
  echo "Cannot read the version from $FILE" >&2
  exit 1
fi
IFS=. read -r major minor patch <<< "$version"

save() {
  /usr/bin/sed -i '' \
    -e "s/^MARKETING_VERSION *=.*/MARKETING_VERSION = $1/" \
    -e "s/^CURRENT_PROJECT_VERSION *=.*/CURRENT_PROJECT_VERSION = $2/" "$FILE"
  echo "$1 ($2)"
}

case "${1:-show}" in
  show)   echo "$version ($build)" ;;
  number) echo "$version" ;;
  build)  save "$version" "$((build + 1))" ;;
  patch)  save "$major.$minor.$((patch + 1))" "$((build + 1))" ;;
  minor)  save "$major.$((minor + 1)).0" "$((build + 1))" ;;
  major)  save "$((major + 1)).0.0" "$((build + 1))" ;;
  set)
    new="${2:-}"
    if ! [[ "$new" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      echo "Give the version as three numbers, for example: ./version.sh set 1.4.2" >&2
      exit 1
    fi
    save "$new" "$((build + 1))"
    ;;
  *)
    echo "Usage: ./version.sh [build|patch|minor|major|set X.Y.Z|number]" >&2
    exit 1
    ;;
esac
