#!/bin/bash

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common-macos.sh"

wbds_verify_app
wbds_info "官方签名：有效（Team ID ${WBDS_EXPECTED_TEAM_ID}）"

if [[ ! -f "$WBDS_SESSION_STATE" ]]; then
  wbds_info "皮肤状态：未启用"
  exit 0
fi

PORT="$(wbds_read_state port)"
STATUS="$(wbds_node "$WBDS_ROOT/scripts/injector.mjs" --port "$PORT" --status --json)" ||
  wbds_die "无法验证运行中的 WorkBuddy Renderer。"
[[ "$STATUS" == *'"active":true'* ]] || wbds_die "Renderer 已连接，但皮肤运行时未激活。"
[[ "$STATUS" == *'"style":true'* ]] || wbds_die "皮肤样式节点缺失。"
[[ "$STATUS" == *'"art":true'* ]] || wbds_die "背景层缺失。"
wbds_info "皮肤状态：健康"
printf '%s\n' "$STATUS"
