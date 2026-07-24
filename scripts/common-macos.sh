#!/bin/bash

set -euo pipefail

WBDS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WBDS_ROOT="$(cd "$WBDS_SCRIPT_DIR/.." && pwd)"
WBDS_STATE_ROOT="${HOME}/Library/Application Support/WorkBuddyDreamSkin"
WBDS_SESSION_STATE="$WBDS_STATE_ROOT/session.json"
WBDS_INJECTOR_STATE="$WBDS_STATE_ROOT/injector.json"
WBDS_INSTALL_ROOT="${HOME}/.workbuddy-dream-skin/studio"
WBDS_USER_THEMES_ROOT="$WBDS_STATE_ROOT/themes"
WBDS_ACTIVE_THEME_DIR="$WBDS_STATE_ROOT/current-theme"
WBDS_LOCAL_DEFAULT_FILE="$WBDS_STATE_ROOT/local-default-theme-id"
WBDS_APP_LABEL="com.rachern3.workbuddy-dream-skin.app"
WBDS_INJECTOR_LABEL="com.rachern3.workbuddy-dream-skin.injector"
WBDS_EXPECTED_BUNDLE_ID="com.workbuddy.workbuddy"
WBDS_EXPECTED_TEAM_ID="FN2V63AD2J"
WBDS_DEFAULT_PORT=9432
WBDS_LAST_PORT=9532

wbds_die() {
  echo "WorkBuddy Dream Skin: $*" >&2
  exit 1
}

wbds_info() {
  echo "WorkBuddy Dream Skin: $*"
}

wbds_ensure_state_root() {
  /bin/mkdir -p "$WBDS_STATE_ROOT"
  /bin/chmod 700 "$WBDS_STATE_ROOT"
}

wbds_discover_app() {
  local candidate bundle_id
  local candidates=(
    "/Applications/WorkBuddy.app"
    "$HOME/Applications/WorkBuddy.app"
  )
  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] && candidates+=("$candidate")
  done < <(/usr/bin/mdfind "kMDItemCFBundleIdentifier == '$WBDS_EXPECTED_BUNDLE_ID'" 2>/dev/null || true)

  for candidate in "${candidates[@]}"; do
    [[ -d "$candidate" ]] || continue
    bundle_id="$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$candidate/Contents/Info.plist" 2>/dev/null || true)"
    if [[ "$bundle_id" == "$WBDS_EXPECTED_BUNDLE_ID" && -x "$candidate/Contents/MacOS/Electron" ]]; then
      WBDS_APP="$candidate"
      WBDS_EXECUTABLE="$candidate/Contents/MacOS/Electron"
      export WBDS_APP WBDS_EXECUTABLE
      return 0
    fi
  done
  wbds_die "找不到官方 WorkBuddy.app，请先安装并至少启动一次。"
}

wbds_verify_app() {
  wbds_discover_app
  local verify_output allowed_log pycache_dir runtime_arch line added_path valid_exception exception_count
  if ! verify_output="$(/usr/bin/codesign --verify --deep --strict --verbose=1 "$WBDS_APP" 2>&1)"; then
    # WorkBuddy 5.3.3's bundled Tencent Docs editor creates this log inside
    # app.asar.unpacked at runtime. It is an added data file, not executable
    # code, but it invalidates the outer resource seal. Accept only this exact
    # known path, then still verify every nested code signature while ignoring
    # resources. Any other added/changed/missing resource remains a hard fail.
    runtime_arch="$(/usr/bin/uname -m)"
    [[ "$runtime_arch" == "x86_64" ]] && runtime_arch="x64"
    allowed_log="$WBDS_APP/Contents/Resources/app.asar.unpacked/node_modules/@tencent/tencent-docs-ai-engine/bin/darwin-${runtime_arch}/editor_sdk.log"
    pycache_dir="$WBDS_APP/Contents/Resources/app.asar.unpacked/cli/vendor/shim/__pycache__"
    valid_exception=1
    exception_count=0
    [[ "${verify_output%%$'\n'*}" == "$WBDS_APP: a sealed resource is missing or invalid" ]] || valid_exception=0
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      exception_count=$((exception_count + 1))
      added_path="${line#file added: }"
      if [[ "$line" == "file added: $allowed_log" ]]; then
        [[ -f "$added_path" && ! -L "$added_path" ]] || valid_exception=0
      elif [[ "$line" == "file added: $pycache_dir/"* ]]; then
        [[ "$(/usr/bin/dirname "$added_path")" == "$pycache_dir" ]] || valid_exception=0
        [[ "$(/usr/bin/basename "$added_path")" =~ ^sitecustomize\.cpython-[0-9]+\.pyc$ ]] || valid_exception=0
        [[ -f "$added_path" && ! -L "$added_path" && ! -x "$added_path" ]] || valid_exception=0
      else
        valid_exception=0
      fi
    done < <(printf '%s\n' "$verify_output" | /usr/bin/tail -n +2)
    if (( valid_exception != 1 || exception_count < 1 )) ||
      ! /usr/bin/codesign --verify --deep --strict --ignore-resources "$WBDS_APP" >/dev/null 2>&1; then
      wbds_die "WorkBuddy 代码签名校验失败：$WBDS_APP"
    fi
  fi
  local details team
  details="$(/usr/bin/codesign -dv --verbose=4 "$WBDS_APP" 2>&1)"
  team="$(printf '%s\n' "$details" | /usr/bin/sed -n 's/^TeamIdentifier=//p' | /usr/bin/head -n 1)"
  [[ "$team" == "$WBDS_EXPECTED_TEAM_ID" ]] ||
    wbds_die "WorkBuddy Team ID 不匹配（得到 ${team:-unknown}，期望 ${WBDS_EXPECTED_TEAM_ID}）。"
}

wbds_workbuddy_pids() {
  local pid command
  while read -r pid command; do
    [[ -n "$pid" ]] || continue
    if [[ "$command" == "$WBDS_EXECUTABLE" || "$command" == "$WBDS_EXECUTABLE --"* ]]; then
      printf '%s\n' "$pid"
    fi
  done < <(/bin/ps -axo pid=,command=)
}

wbds_port_is_free() {
  ! /usr/sbin/lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1
}

wbds_choose_port() {
  local port
  for ((port=WBDS_DEFAULT_PORT; port<=WBDS_LAST_PORT; port++)); do
    if wbds_port_is_free "$port"; then
      printf '%s\n' "$port"
      return 0
    fi
  done
  wbds_die "端口 $WBDS_DEFAULT_PORT-$WBDS_LAST_PORT 均被占用。"
}

wbds_wait_for_cdp() {
  local port="$1" deadline=$((SECONDS + 30))
  while (( SECONDS < deadline )); do
    if /usr/bin/curl -fsS --max-time 1 "http://127.0.0.1:${port}/json/version" 2>/dev/null |
      /usr/bin/grep -q 'WorkBuddy/'; then
      local listeners
      listeners="$(/usr/sbin/lsof -nP -iTCP:"$port" -sTCP:LISTEN 2>/dev/null || true)"
      [[ "$listeners" == *"127.0.0.1:${port}"* ]] ||
        wbds_die "CDP 端口未限制在 127.0.0.1，已中止。"
      return 0
    fi
    /bin/sleep 0.25
  done
  return 1
}

wbds_read_state() {
  local key="$1"
  [[ -f "$WBDS_SESSION_STATE" ]] || return 1
  /usr/bin/plutil -extract "$key" raw -o - "$WBDS_SESSION_STATE" 2>/dev/null
}

wbds_job_remove() {
  /bin/launchctl remove "$1" >/dev/null 2>&1 || true
}

wbds_job_pid() {
  /bin/launchctl print "gui/$(/usr/bin/id -u)/$1" 2>/dev/null |
    /usr/bin/sed -n 's/^[[:space:]]*pid = \([0-9][0-9]*\)$/\1/p' |
    /usr/bin/head -n 1
}

wbds_node() {
  ELECTRON_RUN_AS_NODE=1 "$WBDS_EXECUTABLE" "$@"
}

wbds_write_session_state() {
  local port="$1" app_pid="$2" theme_dir="$3"
  wbds_node -e '
    const fs = require("fs");
    const [file, port, appPid, app, executable, themeDir, appLabel, injectorLabel] = process.argv.slice(1);
    const value = { schema: 1, port: Number(port), appPid: Number(appPid), app, executable, themeDir, appLabel, injectorLabel, startedAt: new Date().toISOString() };
    const temp = file + ".tmp-" + process.pid;
    fs.writeFileSync(temp, JSON.stringify(value, null, 2) + "\n", { mode: 0o600 });
    fs.renameSync(temp, file);
  ' "$WBDS_SESSION_STATE" "$port" "$app_pid" "$WBDS_APP" "$WBDS_EXECUTABLE" "$theme_dir" "$WBDS_APP_LABEL" "$WBDS_INJECTOR_LABEL"
}

wbds_update_session_theme() {
  local theme_dir="$1"
  [[ -f "$WBDS_SESSION_STATE" ]] || return 1
  wbds_node -e '
    const fs = require("fs");
    const [file, themeDir] = process.argv.slice(1);
    const value = JSON.parse(fs.readFileSync(file, "utf8"));
    value.themeDir = themeDir;
    value.themeUpdatedAt = new Date().toISOString();
    const temp = file + ".tmp-" + process.pid;
    fs.writeFileSync(temp, JSON.stringify(value, null, 2) + "\n", { mode: 0o600 });
    fs.renameSync(temp, file);
  ' "$WBDS_SESSION_STATE" "$theme_dir"
}
