#!/bin/bash

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT/scripts/common-macos.sh"

BUILD_APP="$ROOT/release/WorkBuddy Dream Skin Menu Bar.app"
INSTALL_APP="$HOME/Applications/WorkBuddy Dream Skin Menu Bar.app"
LABEL="com.rachern3.workbuddy-dream-skin.menubar"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LAUNCH_ENV=(/usr/bin/env -i "HOME=$HOME" "USER=$USER" "LOGNAME=$USER" "PATH=/usr/bin:/bin:/usr/sbin:/sbin")

EXPECTED_VERSION="$(/usr/bin/tr -d '[:space:]' < "$ROOT/VERSION")"
HOST_ARCH="$(/usr/bin/uname -m)"
PREBUILT_OK=0
if [[ -d "$BUILD_APP" ]] && /usr/bin/codesign --verify --deep --strict "$BUILD_APP" >/dev/null 2>&1; then
  BUILD_VERSION="$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$BUILD_APP/Contents/Info.plist" 2>/dev/null || true)"
  BUILD_ARCHS="$(/usr/bin/lipo -archs "$BUILD_APP/Contents/MacOS/WorkBuddyDreamSkinMenuBar" 2>/dev/null || true)"
  [[ "$BUILD_VERSION" == "$EXPECTED_VERSION" && " $BUILD_ARCHS " == *" $HOST_ARCH "* ]] && PREBUILT_OK=1
fi
if (( PREBUILT_OK == 0 )); then
  /bin/bash "$ROOT/macos/scripts/build-menubar-app.sh" --output "$BUILD_APP"
fi

if [[ -e "$INSTALL_APP" ]]; then
  [[ ! -L "$INSTALL_APP" ]] || wbds_die "拒绝覆盖符号链接：$INSTALL_APP"
  EXISTING_ID="$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$INSTALL_APP/Contents/Info.plist" 2>/dev/null || true)"
  [[ "$EXISTING_ID" == "$LABEL" ]] || wbds_die "拒绝覆盖无关应用：$INSTALL_APP"
fi

/bin/mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents"
"${LAUNCH_ENV[@]}" /bin/launchctl bootout "gui/$(/usr/bin/id -u)/$LABEL" >/dev/null 2>&1 || true
/bin/rm -rf "$INSTALL_APP"
/usr/bin/ditto "$BUILD_APP" "$INSTALL_APP"
/usr/bin/codesign --verify --deep --strict "$INSTALL_APP"

TMP_PLIST="$PLIST.tmp.$$"
trap '/bin/rm -f "$TMP_PLIST"' EXIT
{
  echo '<?xml version="1.0" encoding="UTF-8"?>'
  echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
  echo '<plist version="1.0"><dict>'
  echo '<key>Label</key><string>com.rachern3.workbuddy-dream-skin.menubar</string>'
  echo '<key>ProgramArguments</key><array>'
  echo '<string>/usr/bin/env</string>'
  echo '<string>-i</string>'
  echo '<string>HOME='"$HOME"'</string>'
  echo '<string>USER='"$USER"'</string>'
  echo '<string>LOGNAME='"$USER"'</string>'
  echo '<string>PATH=/usr/bin:/bin:/usr/sbin:/sbin</string>'
  echo '<string>LANG=zh_CN.UTF-8</string>'
  echo '<string>'"$INSTALL_APP"'/Contents/MacOS/WorkBuddyDreamSkinMenuBar</string>'
  echo '</array>'
  echo '<key>RunAtLoad</key><true/>'
  echo '<key>ProcessType</key><string>Interactive</string>'
  echo '</dict></plist>'
} > "$TMP_PLIST"
/usr/bin/plutil -lint "$TMP_PLIST" >/dev/null
/bin/chmod 600 "$TMP_PLIST"
/bin/mv "$TMP_PLIST" "$PLIST"
trap - EXIT

"${LAUNCH_ENV[@]}" /bin/launchctl bootstrap "gui/$(/usr/bin/id -u)" "$PLIST"
"${LAUNCH_ENV[@]}" /bin/launchctl kickstart -k "gui/$(/usr/bin/id -u)/$LABEL"
wbds_info "菜单栏快捷入口已安装：$INSTALL_APP"
