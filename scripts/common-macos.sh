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
WBDS_AUTO_PORT_FILE="$WBDS_STATE_ROOT/auto-port"
WBDS_AUTO_RESTORE_DISABLED="$WBDS_STATE_ROOT/auto-restore-disabled"
WBDS_OPERATION_LOCK="$WBDS_STATE_ROOT/operation.lock"
WBDS_APP_JOB_PLIST="$WBDS_STATE_ROOT/app-runtime.plist"
WBDS_INJECTOR_JOB_PLIST="$WBDS_STATE_ROOT/injector-runtime.plist"
WBDS_APP_LABEL="com.rachern3.workbuddy-dream-skin.app"
WBDS_INJECTOR_LABEL="com.rachern3.workbuddy-dream-skin.injector"
WBDS_EXPECTED_BUNDLE_ID="com.workbuddy.workbuddy"
WBDS_EXPECTED_TEAM_ID="FN2V63AD2J"
WBDS_DEFAULT_PORT=9432
WBDS_LAST_PORT=9532
WBDS_LAST_SPAWN_PID=""

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
    if wbds_command_matches_role "$command" workbuddy-main; then
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

wbds_read_auto_port() {
  local port
  port="$(/usr/bin/tr -d '[:space:]' < "$WBDS_AUTO_PORT_FILE" 2>/dev/null || true)"
  [[ "$port" =~ ^[0-9]+$ ]] && (( port >= WBDS_DEFAULT_PORT && port <= WBDS_LAST_PORT )) || return 1
  printf '%s\n' "$port"
}

wbds_enable_auto_restore() {
  local port="$1" temporary
  [[ "$port" =~ ^[0-9]+$ ]] && (( port >= WBDS_DEFAULT_PORT && port <= WBDS_LAST_PORT )) ||
    wbds_die "自动恢复端口无效：$port"
  wbds_ensure_state_root
  temporary="${WBDS_AUTO_PORT_FILE}.tmp.$$"
  /usr/bin/printf '%s\n' "$port" > "$temporary"
  /bin/chmod 600 "$temporary"
  /bin/mv "$temporary" "$WBDS_AUTO_PORT_FILE"
  /bin/rm -f "$WBDS_AUTO_RESTORE_DISABLED"
  /bin/launchctl setenv WORKBUDDY_REMOTE_DEBUGGING_PORT "$port"
}

wbds_publish_auto_restore() {
  local port
  [[ ! -e "$WBDS_AUTO_RESTORE_DISABLED" ]] || return 1
  port="$(wbds_read_auto_port || true)"
  if [[ -z "$port" ]]; then
    port="$(wbds_choose_port)"
    wbds_enable_auto_restore "$port"
  else
    /bin/launchctl setenv WORKBUDDY_REMOTE_DEBUGGING_PORT "$port"
  fi
  printf '%s\n' "$port"
}

wbds_disable_auto_restore() {
  local temporary
  wbds_ensure_state_root
  temporary="${WBDS_AUTO_RESTORE_DISABLED}.tmp.$$"
  : > "$temporary"
  /bin/chmod 600 "$temporary"
  /bin/mv "$temporary" "$WBDS_AUTO_RESTORE_DISABLED"
  /bin/launchctl unsetenv WORKBUDDY_REMOTE_DEBUGGING_PORT >/dev/null 2>&1 || true
}

wbds_acquire_operation_lock() {
  local owner command
  wbds_ensure_state_root
  if /bin/mkdir "$WBDS_OPERATION_LOCK" >/dev/null 2>&1; then
    /usr/bin/printf '%s\n' "$$" > "$WBDS_OPERATION_LOCK/pid"
    /bin/chmod 700 "$WBDS_OPERATION_LOCK"
    /bin/chmod 600 "$WBDS_OPERATION_LOCK/pid"
    return 0
  fi
  [[ -d "$WBDS_OPERATION_LOCK" && ! -L "$WBDS_OPERATION_LOCK" ]] || return 1
  owner="$(/usr/bin/tr -d '[:space:]' < "$WBDS_OPERATION_LOCK/pid" 2>/dev/null || true)"
  if [[ "$owner" =~ ^[0-9]+$ ]] && /bin/kill -0 "$owner" >/dev/null 2>&1; then
    command="$(/bin/ps -p "$owner" -o command= 2>/dev/null || true)"
    [[ "$command" != *"$WBDS_ROOT/scripts/"* ]] || return 1
  fi
  /bin/rm -f "$WBDS_OPERATION_LOCK/pid"
  /bin/rmdir "$WBDS_OPERATION_LOCK" >/dev/null 2>&1 || return 1
  /bin/mkdir "$WBDS_OPERATION_LOCK" >/dev/null 2>&1 || return 1
  /usr/bin/printf '%s\n' "$$" > "$WBDS_OPERATION_LOCK/pid"
  /bin/chmod 700 "$WBDS_OPERATION_LOCK"
  /bin/chmod 600 "$WBDS_OPERATION_LOCK/pid"
}

wbds_release_operation_lock() {
  local owner
  [[ -d "$WBDS_OPERATION_LOCK" && ! -L "$WBDS_OPERATION_LOCK" ]] || return 0
  owner="$(/usr/bin/tr -d '[:space:]' < "$WBDS_OPERATION_LOCK/pid" 2>/dev/null || true)"
  [[ "$owner" == "$$" ]] || return 0
  /bin/rm -f "$WBDS_OPERATION_LOCK/pid"
  /bin/rmdir "$WBDS_OPERATION_LOCK" >/dev/null 2>&1 || true
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
  case "$1" in
    "$WBDS_APP_LABEL") /bin/rm -f "$WBDS_APP_JOB_PLIST" ;;
    "$WBDS_INJECTOR_LABEL") /bin/rm -f "$WBDS_INJECTOR_JOB_PLIST" ;;
  esac
}

wbds_job_pid() {
  /bin/launchctl print "gui/$(/usr/bin/id -u)/$1" 2>/dev/null |
    /usr/bin/sed -n 's/^[[:space:]]*pid = \([0-9][0-9]*\)$/\1/p' |
    /usr/bin/head -n 1
}

wbds_write_oneshot_job() {
  local label="$1" plist="$2"
  shift 2
  (( $# > 0 )) || wbds_die "创建一次性后台任务时缺少命令。"
  local temporary="${plist}.tmp.$$" index=0 argument
  /bin/rm -f "$temporary"
  /usr/bin/plutil -create xml1 "$temporary"
  /usr/bin/plutil -insert Label -string "$label" "$temporary"
  /usr/bin/plutil -insert ProgramArguments -array "$temporary"
  for argument in "$@"; do
    /usr/bin/plutil -insert "ProgramArguments.${index}" -string "$argument" "$temporary"
    index=$((index + 1))
  done
  /usr/bin/plutil -insert RunAtLoad -bool true "$temporary"
  /usr/bin/plutil -insert KeepAlive -bool false "$temporary"
  /usr/bin/plutil -insert ProcessType -string Interactive "$temporary"
  /usr/bin/plutil -insert StandardOutPath -string /dev/null "$temporary"
  /usr/bin/plutil -insert StandardErrorPath -string /dev/null "$temporary"
  /usr/bin/plutil -lint "$temporary" >/dev/null
  /bin/chmod 600 "$temporary"
  /bin/mv "$temporary" "$plist"
}

wbds_launch_once() {
  local label="$1" plist="$2" deadline
  shift 2
  wbds_write_oneshot_job "$label" "$plist" "$@"
  /bin/launchctl bootstrap "gui/$(/usr/bin/id -u)" "$plist"
  WBDS_LAST_SPAWN_PID=""
  deadline=$((SECONDS + 5))
  while (( SECONDS < deadline )); do
    WBDS_LAST_SPAWN_PID="$(wbds_job_pid "$label" || true)"
    [[ "$WBDS_LAST_SPAWN_PID" =~ ^[0-9]+$ ]] && return 0
    /bin/sleep 0.05
  done
  wbds_job_remove "$label"
  wbds_die "一次性后台任务未能启动：$label"
}

wbds_command_matches_role() {
  local command="$1" role="$2"
  local themed_app="$WBDS_EXECUTABLE --remote-debugging-address=127.0.0.1"
  case "$role" in
    app)
      [[ "$command" == "$themed_app" || "$command" == "$themed_app --"* ]]
      ;;
    workbuddy-main)
      [[ "$command" == "$WBDS_EXECUTABLE" ||
        "$command" == "$themed_app" || "$command" == "$themed_app --"* ]]
      ;;
    injector)
      [[ "$command" == "$WBDS_EXECUTABLE $WBDS_ROOT/scripts/injector.mjs --port "* &&
        "$command" == *" --watch --theme "* ]]
      ;;
    *)
      return 1
      ;;
  esac
}

wbds_pid_matches_role() {
  local pid="$1" role="$2" command
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  command="$(/bin/ps -p "$pid" -o command= 2>/dev/null || true)"
  wbds_command_matches_role "$command" "$role"
}

wbds_stop_owned_pid() {
  local pid="$1" role="$2" label="$3"
  [[ "$pid" =~ ^[0-9]+$ ]] || return 0
  /bin/kill -0 "$pid" >/dev/null 2>&1 || return 0
  if ! wbds_pid_matches_role "$pid" "$role"; then
    wbds_info "忽略不属于当前皮肤会话的 ${label} PID=${pid}。"
    return 0
  fi
  /bin/kill -TERM "$pid" >/dev/null 2>&1 || return 1
  for _ in {1..50}; do
    /bin/kill -0 "$pid" >/dev/null 2>&1 || return 0
    /bin/sleep 0.1
  done
  return 1
}

wbds_stop_all_owned_role() {
  local role="$1" label="$2" pid failed=0
  while read -r pid; do
    [[ -n "$pid" ]] || continue
    if wbds_pid_matches_role "$pid" "$role"; then
      wbds_stop_owned_pid "$pid" "$role" "$label" || failed=1
    fi
  done < <(/bin/ps -axo pid=)
  (( failed == 0 ))
}

wbds_stop_recorded_injector() {
  local pid
  pid="$(/usr/bin/plutil -extract pid raw -o - "$WBDS_INJECTOR_STATE" 2>/dev/null || true)"
  wbds_stop_owned_pid "$pid" injector "注入器"
}

wbds_stop_recorded_app() {
  local pid
  pid="$(wbds_read_state appPid || true)"
  wbds_stop_owned_pid "$pid" workbuddy-main "WorkBuddy"
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
