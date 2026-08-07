#!/bin/bash

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

/bin/bash -n scripts/*.sh macos/scripts/*.sh ./*.command
node --check scripts/injector.mjs
node --check scripts/write-theme.mjs
node --check assets/renderer-inject.js
node --test tests/*.test.mjs
node -e '
  const fs = require("fs");
  for (const file of ["package.json", "assets/selectors.json", "presets/gothic-void-crusade/theme.json"]) {
    JSON.parse(fs.readFileSync(file, "utf8"));
  }
'

grep -q 'WorkBuddyDreamSkin launcher' scripts/install-workbuddy-dream-skin-macos.sh
grep -q '选择新背景图片' macos/menubar-app/Sources/WorkBuddyDreamSkinMenuBar/AppDelegate.swift
grep -q '恢复 WorkBuddy 官方外观' macos/menubar-app/Sources/WorkBuddyDreamSkinMenuBar/AppDelegate.swift
grep -q 'didLaunchApplicationNotification' macos/menubar-app/Sources/WorkBuddyDreamSkinMenuBar/AppDelegate.swift
if grep -q '退出菜单栏工具' macos/menubar-app/Sources/WorkBuddyDreamSkinMenuBar/AppDelegate.swift; then
  echo 'The persistent auto-restore helper must not expose a misleading quit action.' >&2
  exit 1
fi
grep -q "'<key>KeepAlive</key><true/>'" macos/scripts/install-menubar-app-macos.sh
grep -q "'<key>ThrottleInterval</key><integer>10</integer>'" macos/scripts/install-menubar-app-macos.sh
if grep -q 'kickstart -k' macos/scripts/install-menubar-app-macos.sh; then
  echo 'The menu bar installer must not force a second launch after RunAtLoad.' >&2
  exit 1
fi
grep -q 'LEGACY_APP_PID=.*wbds_job_pid' scripts/restore-workbuddy-macos.sh
grep -q 'wbds_stop_all_owned_role app' scripts/restore-workbuddy-macos.sh
grep -q 'trap cleanup_failed_start EXIT' scripts/start-workbuddy-dream-skin-macos.sh
grep -q 'wbds_publish_auto_restore' scripts/auto-attach-workbuddy-dream-skin-macos.sh
grep -q 'wbds_disable_auto_restore' scripts/restore-workbuddy-macos.sh
grep -q 'wbds_acquire_operation_lock' scripts/auto-attach-workbuddy-dream-skin-macos.sh
if grep -R '/bin/launchctl submit' scripts macos --include='*.sh' >/dev/null; then
  echo 'macOS runtime must not use launchctl submit because it creates implicit KeepAlive jobs.' >&2
  exit 1
fi

if [[ "$(uname -s)" == "Darwin" ]]; then
  /bin/bash tests/macos-lifecycle.test.sh
  /bin/bash macos/scripts/build-menubar-app.sh
fi

echo "All WorkBuddy Dream Skin checks passed."
