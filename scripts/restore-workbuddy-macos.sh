#!/bin/bash

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common-macos.sh"

REOPEN=1
[[ "${1:-}" == "--no-reopen" ]] && REOPEN=0
wbds_verify_app
wbds_disable_auto_restore
LEGACY_INJECTOR_PID="$(wbds_job_pid "$WBDS_INJECTOR_LABEL" || true)"
LEGACY_APP_PID="$(wbds_job_pid "$WBDS_APP_LABEL" || true)"

if [[ ! -f "$WBDS_SESSION_STATE" ]]; then
  wbds_job_remove "$WBDS_INJECTOR_LABEL"
  wbds_job_remove "$WBDS_APP_LABEL"
  wbds_stop_owned_pid "$LEGACY_INJECTOR_PID" injector "旧注入器" || wbds_die "旧主题注入器未能安全停止。"
  wbds_stop_owned_pid "$LEGACY_APP_PID" app "旧 WorkBuddy 皮肤进程" || wbds_die "旧 WorkBuddy 皮肤进程未能安全停止。"
  wbds_stop_recorded_injector || wbds_die "主题注入器未能安全停止。"
  wbds_stop_all_owned_role injector "残留注入器" || wbds_die "残留主题注入器未能安全停止。"
  wbds_stop_all_owned_role app "残留 WorkBuddy 皮肤进程" || wbds_die "残留 WorkBuddy 皮肤进程未能安全停止。"
  /bin/rm -f "$WBDS_INJECTOR_STATE"
  wbds_info "没有活动的皮肤会话；官方 WorkBuddy 未被修改。"
  exit 0
fi

PORT="$(wbds_read_state port || true)"
RECORDED_EXECUTABLE="$(wbds_read_state executable || true)"
[[ "$RECORDED_EXECUTABLE" == "$WBDS_EXECUTABLE" ]] ||
  wbds_die "记录的 WorkBuddy 可执行文件与当前签名应用不一致，拒绝停止进程。"

if [[ "$PORT" =~ ^[0-9]+$ ]] && /usr/bin/curl -fsS --max-time 1 "http://127.0.0.1:${PORT}/json/version" >/dev/null 2>&1; then
  wbds_node "$WBDS_ROOT/scripts/injector.mjs" --port "$PORT" --cleanup --wait 5 >/dev/null 2>&1 || true
fi

wbds_job_remove "$WBDS_INJECTOR_LABEL"
wbds_job_remove "$WBDS_APP_LABEL"
wbds_stop_owned_pid "$LEGACY_INJECTOR_PID" injector "旧注入器" || wbds_die "旧主题注入器未能安全停止。"
wbds_stop_owned_pid "$LEGACY_APP_PID" app "旧 WorkBuddy 皮肤进程" || wbds_die "旧 WorkBuddy 皮肤进程未能安全停止。"
wbds_stop_recorded_injector || wbds_die "主题注入器未能安全停止。"
wbds_stop_recorded_app || wbds_die "WorkBuddy 皮肤进程未能安全停止。"
wbds_stop_all_owned_role injector "残留注入器" || wbds_die "残留主题注入器未能安全停止。"
wbds_stop_all_owned_role app "残留 WorkBuddy 皮肤进程" || wbds_die "残留 WorkBuddy 皮肤进程未能安全停止。"
/bin/rm -f "$WBDS_INJECTOR_STATE" "$WBDS_SESSION_STATE"

if (( REOPEN )); then
  /bin/sleep 1
  /usr/bin/open -b "$WBDS_EXPECTED_BUNDLE_ID"
  wbds_info "已恢复官方外观，并以普通模式重新打开 WorkBuddy。"
else
  wbds_info "已清理皮肤并关闭主题会话。"
fi
