#!/bin/bash

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VERSION="$(/usr/bin/tr -d '[:space:]' < "$ROOT/VERSION")"
OUTPUT="$ROOT/release/WorkBuddy-Dream-Skin-v${VERSION}-macOS.zip"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output) [[ $# -ge 2 ]] || { echo "--output requires a path" >&2; exit 2; }; OUTPUT="$2"; shift 2 ;;
    *) echo "Unknown release argument: $1" >&2; exit 2 ;;
  esac
done

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Invalid VERSION: $VERSION" >&2; exit 1; }
/bin/bash "$ROOT/macos/scripts/build-menubar-app.sh"

TMP="$(/usr/bin/mktemp -d /tmp/workbuddy-dream-skin-release.XXXXXX)"
trap 'status=$?; /bin/rm -rf "$TMP"; exit "$status"' EXIT
PACKAGE="$TMP/WorkBuddy-Dream-Skin-v${VERSION}-macOS"
/bin/mkdir -p "$PACKAGE/release" "$(/usr/bin/dirname "$OUTPUT")"

for file in LICENSE NOTICE.md README.md VERSION package.json \
  "Install WorkBuddy Dream Skin.command" "Install WorkBuddy Menu Bar.command" \
  "Customize WorkBuddy Dream Skin.command" "Start WorkBuddy Dream Skin.command" \
  "Restore WorkBuddy.command" "Verify WorkBuddy Dream Skin.command"; do
  /bin/cp "$ROOT/$file" "$PACKAGE/$file"
done
for directory in assets presets scripts macos; do
  /usr/bin/rsync -a --exclude 'release' --exclude '.build*' "$ROOT/$directory/" "$PACKAGE/$directory/"
done
/usr/bin/ditto "$ROOT/release/WorkBuddy Dream Skin Menu Bar.app" \
  "$PACKAGE/release/WorkBuddy Dream Skin Menu Bar.app"

if /usr/bin/find "$PACKAGE" -iname '*arina*' -o -iname '*hashimoto*' | /usr/bin/grep -q .; then
  echo 'Rights-restricted Arina material entered the public macOS package.' >&2
  exit 1
fi
/usr/bin/codesign --verify --deep --strict "$PACKAGE/release/WorkBuddy Dream Skin Menu Bar.app"
/bin/rm -f "$OUTPUT"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$PACKAGE" "$OUTPUT"
[[ -s "$OUTPUT" ]] || { echo "Release ZIP is empty: $OUTPUT" >&2; exit 1; }
echo "Created $OUTPUT"
