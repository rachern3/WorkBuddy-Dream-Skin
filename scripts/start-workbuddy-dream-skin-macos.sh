#!/bin/bash

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common-macos.sh"

if [[ -f "$WBDS_ACTIVE_THEME_DIR/theme.json" ]]; then
  THEME_DIR="$WBDS_ACTIVE_THEME_DIR"
else
  THEME_DIR="$WBDS_ROOT/presets/gothic-void-crusade"
fi
while [[ $# -gt 0 ]]; do
  case "$1" in
    --theme)
      [[ $# -ge 2 ]] || wbds_die "--theme 需要目录参数。"
      THEME_DIR="$(cd "$2" && pwd)"
      shift 2
      ;;
    *) wbds_die "未知参数：$1" ;;
  esac
done

[[ -f "$THEME_DIR/theme.json" ]] || wbds_die "主题目录缺少 theme.json：$THEME_DIR"
wbds_verify_app
wbds_ensure_state_root
wbds_acquire_operation_lock || wbds_die "另一个皮肤操作正在进行，请稍后重试。"
trap wbds_release_operation_lock EXIT

if [[ -f "$WBDS_SESSION_STATE" ]]; then
  old_port="$(wbds_read_state port || true)"
  if [[ -n "$old_port" ]] && /usr/bin/curl -fsS --max-time 1 "http://127.0.0.1:${old_port}/json/version" >/dev/null 2>&1; then
    wbds_die "皮肤会话已在运行（端口 $old_port）。请先运行 Restore 或 Verify。"
  fi
  /bin/mv "$WBDS_SESSION_STATE" "$WBDS_STATE_ROOT/session.stale-$(/bin/date +%s).json"
fi

running_pids="$(wbds_workbuddy_pids || true)"
[[ -z "$running_pids" ]] || wbds_die "WorkBuddy 已在运行（PID ${running_pids//$'\n'/,}）。请先确认没有执行中的任务并正常退出 WorkBuddy。"

PORT="$(wbds_choose_port)"
wbds_enable_auto_restore "$PORT"
LEGACY_INJECTOR_PID="$(wbds_job_pid "$WBDS_INJECTOR_LABEL" || true)"
wbds_job_remove "$WBDS_APP_LABEL"
wbds_job_remove "$WBDS_INJECTOR_LABEL"
wbds_stop_owned_pid "$LEGACY_INJECTOR_PID" injector "旧注入器" || wbds_die "旧主题注入器未能安全停止。"
wbds_stop_all_owned_role injector "残留注入器" || wbds_die "残留主题注入器未能安全停止。"
/bin/rm -f "$WBDS_INJECTOR_STATE"

cleanup_failed_start() {
  local status=$?
  wbds_stop_owned_pid "${INJECTOR_PID:-}" injector "注入器" || true
  wbds_job_remove "$WBDS_INJECTOR_LABEL"
  wbds_job_remove "$WBDS_APP_LABEL"
  wbds_stop_owned_pid "${APP_PID:-}" app "WorkBuddy" || true
  /bin/rm -f "$WBDS_SESSION_STATE" "$WBDS_INJECTOR_STATE"
  wbds_release_operation_lock
  return "$status"
}
trap cleanup_failed_start EXIT

wbds_info "正在以本机 CDP 模式启动官方 WorkBuddy（127.0.0.1:${PORT}）…"
wbds_launch_once "$WBDS_APP_LABEL" "$WBDS_APP_JOB_PLIST" \
  /usr/bin/env -i "HOME=$HOME" "USER=${USER:-$(/usr/bin/id -un)}" \
  "LOGNAME=${LOGNAME:-${USER:-$(/usr/bin/id -un)}}" "PATH=/usr/bin:/bin:/usr/sbin:/sbin" \
  "LANG=${LANG:-zh_CN.UTF-8}" "TMPDIR=${TMPDIR:-/tmp}" \
  "WORKBUDDY_REMOTE_DEBUGGING_PORT=$PORT" \
  "$WBDS_EXECUTABLE" --remote-debugging-address=127.0.0.1
APP_PID="$WBDS_LAST_SPAWN_PID"

wbds_wait_for_cdp "$PORT" || wbds_die "WorkBuddy 没有在 30 秒内开放已验证的 CDP 端口。"

wbds_pid_matches_role "$APP_PID" app || wbds_die "无法确认 WorkBuddy 主进程。"
LISTENER_PIDS="$(/usr/sbin/lsof -nP -t -iTCP:"$PORT" -sTCP:LISTEN 2>/dev/null | /usr/bin/sort -u)"
[[ "$LISTENER_PIDS" == "$APP_PID" ]] || wbds_die "CDP 监听进程与刚启动的 WorkBuddy 主进程不一致。"

wbds_launch_once "$WBDS_INJECTOR_LABEL" "$WBDS_INJECTOR_JOB_PLIST" \
  /usr/bin/env -i "HOME=$HOME" "USER=${USER:-$(/usr/bin/id -un)}" \
  "LOGNAME=${LOGNAME:-${USER:-$(/usr/bin/id -un)}}" "PATH=/usr/bin:/bin:/usr/sbin:/sbin" \
  "LANG=${LANG:-zh_CN.UTF-8}" "TMPDIR=${TMPDIR:-/tmp}" ELECTRON_RUN_AS_NODE=1 \
  "$WBDS_EXECUTABLE" "$WBDS_ROOT/scripts/injector.mjs" \
  --port "$PORT" --watch --theme "$THEME_DIR" --state "$WBDS_INJECTOR_STATE"
INJECTOR_PID="$WBDS_LAST_SPAWN_PID"

deadline=$((SECONDS + 20))
while (( SECONDS < deadline )); do
  RECORDED_INJECTOR_PID="$(/usr/bin/plutil -extract pid raw -o - "$WBDS_INJECTOR_STATE" 2>/dev/null || true)"
  [[ "$RECORDED_INJECTOR_PID" == "$INJECTOR_PID" ]] && break
  /bin/sleep 0.25
done
[[ "$RECORDED_INJECTOR_PID" == "$INJECTOR_PID" ]] || wbds_die "注入器 PID 与刚启动的进程不一致。"

ACTIVE=0
deadline=$((SECONDS + 20))
while (( SECONDS < deadline )); do
  if STATUS="$(wbds_node "$WBDS_ROOT/scripts/injector.mjs" --port "$PORT" --status --json 2>/dev/null)"; then
    if [[ "$STATUS" == *'"active":true'* && "$STATUS" == *'"style":true'* && "$STATUS" == *'"art":true'* ]]; then
      ACTIVE=1
      break
    fi
  fi
  /bin/sleep 0.25
done
(( ACTIVE == 1 )) || wbds_die "主题运行时没有在 20 秒内完成注入。"

wbds_write_session_state "$PORT" "$APP_PID" "$THEME_DIR"
wbds_release_operation_lock
trap - EXIT
wbds_info "已启用。WorkBuddy PID=${APP_PID}，CDP=127.0.0.1:${PORT}"
wbds_info "恢复官方外观：双击 Restore WorkBuddy.command"
