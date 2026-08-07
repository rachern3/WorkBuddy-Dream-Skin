#!/bin/bash

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common-macos.sh"

[[ ! -e "$WBDS_AUTO_RESTORE_DISABLED" ]] || exit 0
wbds_verify_app
wbds_ensure_state_root

PORT="$(wbds_publish_auto_restore || true)"
[[ "$PORT" =~ ^[0-9]+$ ]] || exit 0

RUNNING_PIDS="$(wbds_workbuddy_pids || true)"
[[ "$RUNNING_PIDS" =~ ^[0-9]+$ ]] || exit 0
APP_PID="$RUNNING_PIDS"

READY=0
deadline=$((SECONDS + 20))
while (( SECONDS < deadline )); do
  /bin/kill -0 "$APP_PID" >/dev/null 2>&1 || exit 0
  if /usr/bin/curl -fsS --max-time 1 "http://127.0.0.1:${PORT}/json/version" 2>/dev/null |
    /usr/bin/grep -q 'WorkBuddy/'; then
    LISTENER_PIDS="$(/usr/sbin/lsof -nP -t -iTCP:"$PORT" -sTCP:LISTEN 2>/dev/null | /usr/bin/sort -u)"
    [[ "$LISTENER_PIDS" == "$APP_PID" ]] || exit 0
    READY=1
    break
  fi
  /bin/sleep 0.25
done
(( READY == 1 )) || exit 0
wbds_acquire_operation_lock || exit 0
trap wbds_release_operation_lock EXIT

if [[ -f "$WBDS_ACTIVE_THEME_DIR/theme.json" ]]; then
  THEME_DIR="$WBDS_ACTIVE_THEME_DIR"
else
  THEME_DIR="$WBDS_ROOT/presets/gothic-void-crusade"
fi
THEME_ID="$(/usr/bin/plutil -extract id raw -o - "$THEME_DIR/theme.json" 2>/dev/null || true)"
[[ "$THEME_ID" =~ ^[a-zA-Z0-9._-]{1,96}$ ]] || wbds_die "自动恢复主题 id 无效。"
wbds_node "$WBDS_ROOT/scripts/injector.mjs" --validate --theme "$THEME_DIR" >/dev/null ||
  wbds_die "自动恢复主题文件验证失败。"

if STATUS="$(wbds_node "$WBDS_ROOT/scripts/injector.mjs" --port "$PORT" --status --json 2>/dev/null)" &&
  [[ "$STATUS" == *'"active":true'* && "$STATUS" == *"\"themeId\":\"${THEME_ID}\""* ]]; then
  wbds_write_session_state "$PORT" "$APP_PID" "$THEME_DIR"
  wbds_release_operation_lock
  trap - EXIT
  exit 0
fi

LEGACY_INJECTOR_PID="$(wbds_job_pid "$WBDS_INJECTOR_LABEL" || true)"
wbds_job_remove "$WBDS_INJECTOR_LABEL"
wbds_stop_owned_pid "$LEGACY_INJECTOR_PID" injector "旧注入器" || wbds_die "旧主题注入器未能安全停止。"
wbds_stop_recorded_injector || wbds_die "记录的主题注入器未能安全停止。"
wbds_stop_all_owned_role injector "残留注入器" || wbds_die "残留主题注入器未能安全停止。"
/bin/rm -f "$WBDS_INJECTOR_STATE"

cleanup_failed_attach() {
  local status=$?
  wbds_stop_owned_pid "${INJECTOR_PID:-}" injector "自动恢复注入器" || true
  wbds_job_remove "$WBDS_INJECTOR_LABEL"
  /bin/rm -f "$WBDS_INJECTOR_STATE"
  wbds_release_operation_lock
  return "$status"
}
trap cleanup_failed_attach EXIT

wbds_launch_once "$WBDS_INJECTOR_LABEL" "$WBDS_INJECTOR_JOB_PLIST" \
  /usr/bin/env -i "HOME=$HOME" "USER=${USER:-$(/usr/bin/id -un)}" \
  "LOGNAME=${LOGNAME:-${USER:-$(/usr/bin/id -un)}}" "PATH=/usr/bin:/bin:/usr/sbin:/sbin" \
  "LANG=${LANG:-zh_CN.UTF-8}" "TMPDIR=${TMPDIR:-/tmp}" ELECTRON_RUN_AS_NODE=1 \
  "$WBDS_EXECUTABLE" "$WBDS_ROOT/scripts/injector.mjs" \
  --port "$PORT" --watch --theme "$THEME_DIR" --state "$WBDS_INJECTOR_STATE"
INJECTOR_PID="$WBDS_LAST_SPAWN_PID"

ACTIVE=0
deadline=$((SECONDS + 20))
while (( SECONDS < deadline )); do
  RECORDED_INJECTOR_PID="$(/usr/bin/plutil -extract pid raw -o - "$WBDS_INJECTOR_STATE" 2>/dev/null || true)"
  if [[ "$RECORDED_INJECTOR_PID" == "$INJECTOR_PID" ]] &&
    STATUS="$(wbds_node "$WBDS_ROOT/scripts/injector.mjs" --port "$PORT" --status --json 2>/dev/null)" &&
    [[ "$STATUS" == *'"active":true'* && "$STATUS" == *"\"themeId\":\"${THEME_ID}\""* ]]; then
    ACTIVE=1
    break
  fi
  /bin/sleep 0.25
done
(( ACTIVE == 1 )) || wbds_die "背景自动恢复未能在 20 秒内完成。"

wbds_write_session_state "$PORT" "$APP_PID" "$THEME_DIR"
wbds_release_operation_lock
trap - EXIT
wbds_info "背景已自动恢复到 WorkBuddy PID=${APP_PID}。"
