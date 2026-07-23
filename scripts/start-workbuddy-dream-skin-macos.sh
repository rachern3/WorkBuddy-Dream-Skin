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
wbds_job_remove "$WBDS_APP_LABEL"
wbds_job_remove "$WBDS_INJECTOR_LABEL"

cleanup_failed_start() {
  wbds_job_remove "$WBDS_INJECTOR_LABEL"
  wbds_job_remove "$WBDS_APP_LABEL"
  /bin/rm -f "$WBDS_SESSION_STATE" "$WBDS_INJECTOR_STATE"
}
trap cleanup_failed_start ERR

wbds_info "正在以本机 CDP 模式启动官方 WorkBuddy（127.0.0.1:${PORT}）…"
/bin/launchctl submit -l "$WBDS_APP_LABEL" -- \
  /usr/bin/env "WORKBUDDY_REMOTE_DEBUGGING_PORT=$PORT" \
  "$WBDS_EXECUTABLE" --remote-debugging-address=127.0.0.1

wbds_wait_for_cdp "$PORT" || wbds_die "WorkBuddy 没有在 30 秒内开放已验证的 CDP 端口。"

APP_PID="$(wbds_workbuddy_pids)"
[[ "$APP_PID" =~ ^[0-9]+$ ]] || wbds_die "无法确认 WorkBuddy 主进程。"
LISTENER_PIDS="$(/usr/sbin/lsof -nP -t -iTCP:"$PORT" -sTCP:LISTEN 2>/dev/null | /usr/bin/sort -u)"
[[ "$LISTENER_PIDS" == "$APP_PID" ]] || wbds_die "CDP 监听进程与刚启动的 WorkBuddy 主进程不一致。"

/bin/launchctl submit -l "$WBDS_INJECTOR_LABEL" -- \
  /usr/bin/env ELECTRON_RUN_AS_NODE=1 \
  "$WBDS_EXECUTABLE" "$WBDS_ROOT/scripts/injector.mjs" \
  --port "$PORT" --watch --theme "$THEME_DIR" --state "$WBDS_INJECTOR_STATE"

deadline=$((SECONDS + 20))
while (( SECONDS < deadline )); do
  [[ -s "$WBDS_INJECTOR_STATE" ]] && break
  /bin/sleep 0.25
done
[[ -s "$WBDS_INJECTOR_STATE" ]] || wbds_die "注入器没有在 20 秒内进入运行状态。"

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
trap - ERR
wbds_info "已启用。WorkBuddy PID=${APP_PID}，CDP=127.0.0.1:${PORT}"
wbds_info "恢复官方外观：双击 Restore WorkBuddy.command"
