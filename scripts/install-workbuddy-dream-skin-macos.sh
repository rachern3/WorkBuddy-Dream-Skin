#!/bin/bash

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common-macos.sh"

wbds_verify_app
wbds_ensure_state_root
/bin/mkdir -p "$WBDS_INSTALL_ROOT"
/usr/bin/rsync -a --delete \
  --exclude '.git' --exclude 'node_modules' --exclude 'release' --exclude 'work' \
  "$WBDS_ROOT/" "$WBDS_INSTALL_ROOT/"
/bin/chmod +x "$WBDS_INSTALL_ROOT"/*.command "$WBDS_INSTALL_ROOT"/scripts/*.sh "$WBDS_INSTALL_ROOT"/scripts/*.mjs

wbds_info "已安装到 $WBDS_INSTALL_ROOT"
exec /bin/bash "$WBDS_INSTALL_ROOT/scripts/start-workbuddy-dream-skin-macos.sh"
