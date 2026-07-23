#!/bin/bash

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common-macos.sh"

THEME_DIR=""
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

[[ -n "$THEME_DIR" ]] || wbds_die "请传入 --theme 主题目录。"
[[ -f "$THEME_DIR/theme.json" ]] || wbds_die "主题目录缺少 theme.json：$THEME_DIR"
wbds_verify_app
wbds_ensure_state_root

THEME_ID="$(/usr/bin/plutil -extract id raw -o - "$THEME_DIR/theme.json" 2>/dev/null || true)"
[[ -n "$THEME_ID" ]] || wbds_die "主题配置缺少 id。"
[[ "$THEME_ID" =~ ^[a-zA-Z0-9._-]{1,96}$ ]] || wbds_die "主题 id 只能包含字母、数字、点、下划线和短横线。"
wbds_node "$WBDS_ROOT/scripts/injector.mjs" --validate --theme "$THEME_DIR" >/dev/null ||
  wbds_die "主题文件验证失败，保留当前主题。"

if [[ -f "$WBDS_SESSION_STATE" ]]; then
  PORT="$(wbds_read_state port || true)"
  if [[ "$PORT" =~ ^[0-9]+$ ]] &&
    /usr/bin/curl -fsS --max-time 1 "http://127.0.0.1:${PORT}/json/version" >/dev/null 2>&1; then
    OLD_INJECTOR_PID="$(/usr/bin/plutil -extract pid raw -o - "$WBDS_INJECTOR_STATE" 2>/dev/null || true)"
    wbds_job_remove "$WBDS_INJECTOR_LABEL"
    for _ in {1..40}; do
      if [[ ! "$OLD_INJECTOR_PID" =~ ^[0-9]+$ ]] || ! /bin/kill -0 "$OLD_INJECTOR_PID" >/dev/null 2>&1; then
        break
      fi
      /bin/sleep 0.1
    done
    if [[ "$OLD_INJECTOR_PID" =~ ^[0-9]+$ ]] && /bin/kill -0 "$OLD_INJECTOR_PID" >/dev/null 2>&1; then
      wbds_die "旧主题注入器未能安全停止。"
    fi
    /bin/rm -f "$WBDS_INJECTOR_STATE"

    /bin/launchctl submit -l "$WBDS_INJECTOR_LABEL" -- \
      /usr/bin/env ELECTRON_RUN_AS_NODE=1 \
      "$WBDS_EXECUTABLE" "$WBDS_ROOT/scripts/injector.mjs" \
      --port "$PORT" --watch --theme "$THEME_DIR" --state "$WBDS_INJECTOR_STATE"

    ACTIVE=0
    deadline=$((SECONDS + 20))
    while (( SECONDS < deadline )); do
      if STATUS="$(wbds_node "$WBDS_ROOT/scripts/injector.mjs" --port "$PORT" --status --json 2>/dev/null)"; then
        if [[ "$STATUS" == *'"active":true'* && "$STATUS" == *"\"themeId\":\"${THEME_ID}\""* ]]; then
          ACTIVE=1
          break
        fi
      fi
      /bin/sleep 0.25
    done
    (( ACTIVE == 1 )) || wbds_die "新主题未能在 20 秒内完成热应用。"
    wbds_update_session_theme "$THEME_DIR"
    wbds_info "已立即应用主题：$THEME_ID"
    exit 0
  fi
fi

RUNNING_PIDS="$(wbds_workbuddy_pids || true)"
if [[ -n "$RUNNING_PIDS" ]]; then
  BUTTON="$(/usr/bin/osascript <<'APPLESCRIPT'
button returned of (display dialog "需要重新启动 WorkBuddy 才能启用新背景。请先确认当前没有正在执行的任务。" buttons {"稍后", "重新启动并应用"} default button "重新启动并应用" cancel button "稍后" with icon caution)
APPLESCRIPT
  )" || {
    wbds_info "主题已保存，稍后退出 WorkBuddy 后再运行 Start WorkBuddy Dream Skin.command 即可应用。"
    exit 0
  }
  [[ "$BUTTON" == "重新启动并应用" ]] || exit 0
  /usr/bin/osascript -e 'tell application id "com.workbuddy.workbuddy" to quit' >/dev/null
  deadline=$((SECONDS + 20))
  while (( SECONDS < deadline )); do
    [[ -z "$(wbds_workbuddy_pids || true)" ]] && break
    /bin/sleep 0.25
  done
  [[ -z "$(wbds_workbuddy_pids || true)" ]] || wbds_die "WorkBuddy 未能正常退出；未强制结束进程。"
fi

exec /bin/bash "$WBDS_ROOT/scripts/start-workbuddy-dream-skin-macos.sh" --theme "$THEME_DIR"
