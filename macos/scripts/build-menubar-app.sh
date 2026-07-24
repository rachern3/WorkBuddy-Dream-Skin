#!/bin/bash

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SOURCE_ROOT="$ROOT/macos/menubar-app"
VERSION="$(/usr/bin/tr -d '[:space:]' < "$ROOT/VERSION")"
OUTPUT_APP="$ROOT/release/WorkBuddy Dream Skin Menu Bar.app"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      [[ $# -ge 2 ]] || { echo "--output requires a path" >&2; exit 2; }
      OUTPUT_APP="$2"
      shift 2
      ;;
    *) echo "Unknown build argument: $1" >&2; exit 2 ;;
  esac
done

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Invalid VERSION: $VERSION" >&2; exit 1; }
[[ "$(/usr/bin/basename "$OUTPUT_APP")" == *.app ]] || { echo "Output must end in .app" >&2; exit 1; }
[[ ! -L "$OUTPUT_APP" ]] || { echo "Refusing to replace symlink output: $OUTPUT_APP" >&2; exit 1; }
SWIFTC="$(/usr/bin/xcrun --find swiftc 2>/dev/null || true)"
[[ -x "$SWIFTC" ]] || { echo "swiftc not found; install Apple Command Line Tools." >&2; exit 1; }
SDK="$(/usr/bin/xcrun --show-sdk-path 2>/dev/null || true)"
[[ -d "$SDK" ]] || { echo "macOS SDK not found; install Apple Command Line Tools." >&2; exit 1; }
ARCH="$(/usr/bin/uname -m)"
case "$ARCH" in arm64|x86_64) ;; *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;; esac

TMP="$(/usr/bin/mktemp -d /tmp/workbuddy-dream-skin-menubar.XXXXXX)"
trap 'status=$?; /bin/rm -rf "$TMP"; exit "$status"' EXIT
APP="$TMP/WorkBuddy Dream Skin Menu Bar.app"
/bin/mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$(/usr/bin/dirname "$OUTPUT_APP")"

"$SWIFTC" -O -sdk "$SDK" -target "${ARCH}-apple-macosx12.0" -framework AppKit \
  "$SOURCE_ROOT"/Sources/WorkBuddyDreamSkinMenuBar/*.swift \
  -o "$APP/Contents/MacOS/WorkBuddyDreamSkinMenuBar"
/bin/chmod 755 "$APP/Contents/MacOS/WorkBuddyDreamSkinMenuBar"
/usr/bin/sed "s/__VERSION__/$VERSION/g" "$SOURCE_ROOT/Resources/Info.plist.template" > "$APP/Contents/Info.plist"
/usr/bin/plutil -lint "$APP/Contents/Info.plist" >/dev/null
/usr/bin/codesign --force --deep --sign - --timestamp=none "$APP" >/dev/null
/usr/bin/codesign --verify --deep --strict "$APP"

/bin/rm -rf "$OUTPUT_APP"
/usr/bin/ditto "$APP" "$OUTPUT_APP"
/usr/bin/codesign --verify --deep --strict "$OUTPUT_APP"
echo "Created $OUTPUT_APP"
