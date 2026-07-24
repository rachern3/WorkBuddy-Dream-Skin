#!/bin/bash

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common-macos.sh"

THEME_ID=""
USE_BUNDLED=0
USE_LOCAL_DEFAULT=0
APPLY_NOW=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --id)
      [[ $# -ge 2 ]] || wbds_die "--id 需要主题 id。"
      THEME_ID="$2"
      shift 2
      ;;
    --bundled) USE_BUNDLED=1; shift ;;
    --local-default) USE_LOCAL_DEFAULT=1; shift ;;
    --no-apply) APPLY_NOW=0; shift ;;
    *) wbds_die "未知参数：$1" ;;
  esac
done

if (( USE_BUNDLED + USE_LOCAL_DEFAULT > 1 )) ||
  (( USE_BUNDLED || USE_LOCAL_DEFAULT )) && [[ -n "$THEME_ID" ]]; then
  wbds_die "--bundled、--local-default 和 --id 只能选择一个。"
fi
if (( ! USE_BUNDLED && ! USE_LOCAL_DEFAULT )) && [[ -z "$THEME_ID" ]]; then
  wbds_die "请使用 --bundled、--local-default，或传入 --id 主题 id。"
fi

if (( USE_BUNDLED )); then
  SOURCE_THEME="$WBDS_ROOT/presets/gothic-void-crusade"
else
  if (( USE_LOCAL_DEFAULT )); then
    [[ -f "$WBDS_LOCAL_DEFAULT_FILE" && ! -L "$WBDS_LOCAL_DEFAULT_FILE" ]] || wbds_die "尚未设置本机默认背景。"
    THEME_ID="$(/usr/bin/tr -d '\r\n' < "$WBDS_LOCAL_DEFAULT_FILE")"
  fi
  [[ "$THEME_ID" =~ ^[a-zA-Z0-9._-]{1,96}$ ]] || wbds_die "主题 id 格式无效。"
  SOURCE_THEME="$WBDS_USER_THEMES_ROOT/$THEME_ID"
  [[ -d "$SOURCE_THEME" && ! -L "$SOURCE_THEME" ]] || wbds_die "找不到已保存主题：$THEME_ID"
fi

[[ -f "$SOURCE_THEME/theme.json" ]] || wbds_die "主题目录缺少 theme.json：$SOURCE_THEME"
wbds_verify_app
wbds_ensure_state_root
wbds_node "$WBDS_ROOT/scripts/injector.mjs" --validate --theme "$SOURCE_THEME" >/dev/null ||
  wbds_die "主题文件验证失败，当前背景未改变。"

STAGED_THEME="$(/usr/bin/mktemp -d "$WBDS_STATE_ROOT/.current-theme.XXXXXX")"
OLD_THEME="$WBDS_STATE_ROOT/.previous-theme.$$"
RESTORE_OLD=0
cleanup() {
  [[ -z "$STAGED_THEME" ]] || /bin/rm -rf "$STAGED_THEME"
  if (( RESTORE_OLD )) && [[ -d "$OLD_THEME" && ! -e "$WBDS_ACTIVE_THEME_DIR" ]]; then
    /bin/mv "$OLD_THEME" "$WBDS_ACTIVE_THEME_DIR"
  fi
}
trap cleanup EXIT
/usr/bin/rsync -a --delete "$SOURCE_THEME/" "$STAGED_THEME/"
/bin/chmod 700 "$STAGED_THEME"
/bin/chmod 600 "$STAGED_THEME"/*

if [[ -e "$WBDS_ACTIVE_THEME_DIR" ]]; then
  /bin/mv "$WBDS_ACTIVE_THEME_DIR" "$OLD_THEME"
  RESTORE_OLD=1
fi
/bin/mv "$STAGED_THEME" "$WBDS_ACTIVE_THEME_DIR"
STAGED_THEME=""
RESTORE_OLD=0
/bin/rm -rf "$OLD_THEME"
trap - EXIT

ACTIVE_ID="$(/usr/bin/plutil -extract id raw -o - "$WBDS_ACTIVE_THEME_DIR/theme.json")"
wbds_info "已切换背景：$ACTIVE_ID"
if (( APPLY_NOW )); then
  exec /bin/bash "$WBDS_ROOT/scripts/apply-theme-macos.sh" --theme "$WBDS_ACTIVE_THEME_DIR"
fi
