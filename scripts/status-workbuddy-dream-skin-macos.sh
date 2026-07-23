#!/bin/bash

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common-macos.sh"

wbds_verify_app
if [[ ! -f "$WBDS_SESSION_STATE" ]]; then
  wbds_info "状态：未启用（官方应用签名有效）"
  exit 1
fi
PORT="$(wbds_read_state port)"
if ! /usr/bin/curl -fsS --max-time 1 "http://127.0.0.1:${PORT}/json/version" >/dev/null 2>&1; then
  wbds_die "状态记录存在，但 CDP 端口 $PORT 不可达。"
fi
wbds_node "$WBDS_ROOT/scripts/injector.mjs" --port "$PORT" --status --json
