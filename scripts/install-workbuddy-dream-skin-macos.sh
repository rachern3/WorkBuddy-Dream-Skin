#!/bin/bash

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common-macos.sh"

CREATE_LAUNCHERS=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-launchers) CREATE_LAUNCHERS=0; shift ;;
    *) wbds_die "未知参数：$1" ;;
  esac
done

wbds_verify_app
wbds_ensure_state_root
/bin/mkdir -p "$WBDS_INSTALL_ROOT"
/usr/bin/rsync -a --delete \
  --exclude '.git' --exclude 'node_modules' --exclude 'release' --exclude 'work' \
  "$WBDS_ROOT/" "$WBDS_INSTALL_ROOT/"
/bin/chmod +x "$WBDS_INSTALL_ROOT"/*.command "$WBDS_INSTALL_ROOT"/scripts/*.sh "$WBDS_INSTALL_ROOT"/scripts/*.mjs

wbds_shell_quote() {
  wbds_node -e 'process.stdout.write(JSON.stringify(process.argv[1]))' "$1"
}

wbds_write_desktop_launcher() {
  local target="$1" command="$2"
  if [[ -e "$target" ]] && ! /usr/bin/grep -q '^# WorkBuddyDreamSkin launcher$' "$target" 2>/dev/null; then
    wbds_die "拒绝覆盖无关的桌面文件：$target"
  fi
  /usr/bin/printf '%s\n' \
    '#!/bin/bash' \
    '# WorkBuddyDreamSkin launcher' \
    'set -euo pipefail' \
    "$command" > "$target"
  /bin/chmod 700 "$target"
}

if (( CREATE_LAUNCHERS )); then
  /bin/mkdir -p "$HOME/Desktop"
  START_SCRIPT="$(wbds_shell_quote "$WBDS_INSTALL_ROOT/scripts/start-workbuddy-dream-skin-macos.sh")"
  CUSTOMIZE_SCRIPT="$(wbds_shell_quote "$WBDS_INSTALL_ROOT/scripts/customize-theme-macos.sh")"
  VERIFY_SCRIPT="$(wbds_shell_quote "$WBDS_INSTALL_ROOT/scripts/verify-workbuddy-dream-skin-macos.sh")"
  RESTORE_SCRIPT="$(wbds_shell_quote "$WBDS_INSTALL_ROOT/scripts/restore-workbuddy-macos.sh")"
  wbds_write_desktop_launcher "$HOME/Desktop/WorkBuddy Dream Skin.command" "exec /bin/bash $START_SCRIPT"
  wbds_write_desktop_launcher "$HOME/Desktop/WorkBuddy Dream Skin - Customize.command" "exec /bin/bash $CUSTOMIZE_SCRIPT"
  wbds_write_desktop_launcher "$HOME/Desktop/WorkBuddy Dream Skin - Verify.command" "exec /bin/bash $VERIFY_SCRIPT"
  wbds_write_desktop_launcher "$HOME/Desktop/WorkBuddy Dream Skin - Restore.command" "exec /bin/bash $RESTORE_SCRIPT"
fi

wbds_info "已安装到 $WBDS_INSTALL_ROOT"
(( CREATE_LAUNCHERS )) && wbds_info "已在桌面创建启动、换图、验证和恢复入口。"
exec /bin/bash "$WBDS_INSTALL_ROOT/scripts/start-workbuddy-dream-skin-macos.sh"
