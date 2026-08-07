#!/bin/bash

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/common-macos.sh"

TMP="$(/usr/bin/mktemp -d /tmp/workbuddy-dream-skin-lifecycle.XXXXXX)"
trap '/bin/rm -rf "$TMP"' EXIT
MARKER="$TMP/invocations"
PLIST="$TMP/one-shot.plist"

wbds_write_oneshot_job "com.rachern3.workbuddy-dream-skin.test" "$PLIST" \
  /bin/sh -c 'printf "%s\n" "$PPID" >> "$1"' wbds-once "$MARKER"

[[ "$(/usr/bin/plutil -extract KeepAlive raw -o - "$PLIST")" == "false" ]]
[[ "$(/usr/bin/plutil -extract RunAtLoad raw -o - "$PLIST")" == "true" ]]
[[ "$(/usr/bin/plutil -extract ProgramArguments.0 raw -o - "$PLIST")" == "/bin/sh" ]]
[[ "$(/usr/bin/plutil -extract ProgramArguments.4 raw -o - "$PLIST")" == "$MARKER" ]]

WBDS_EXECUTABLE="/Applications/WorkBuddy.app/Contents/MacOS/Electron"
WBDS_ROOT="/tmp/workbuddy-dream-skin-test"
wbds_command_matches_role "$WBDS_EXECUTABLE" workbuddy-main
wbds_command_matches_role "$WBDS_EXECUTABLE --remote-debugging-address=127.0.0.1" app
wbds_command_matches_role "$WBDS_EXECUTABLE --remote-debugging-address=127.0.0.1 --remote-debugging-port=9432" workbuddy-main
! wbds_command_matches_role "$WBDS_EXECUTABLE --require /tmp/bootstrap.cjs" workbuddy-main
! wbds_command_matches_role "$WBDS_EXECUTABLE /tmp/sidecar-entry.js --token example" workbuddy-main
wbds_command_matches_role "$WBDS_EXECUTABLE $WBDS_ROOT/scripts/injector.mjs --port 9432 --watch --theme /tmp/theme" injector

echo "macOS one-shot lifecycle check passed."
