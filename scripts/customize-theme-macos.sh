#!/bin/bash

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common-macos.sh"

IMAGE=""
THEME_NAME=""
APPEARANCE="auto"
APPLY_NOW=1
SET_LOCAL_DEFAULT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --image) IMAGE="${2:-}"; shift 2 ;;
    --name) THEME_NAME="${2:-}"; shift 2 ;;
    --appearance) APPEARANCE="${2:-}"; shift 2 ;;
    --no-apply) APPLY_NOW=0; shift ;;
    --set-local-default) SET_LOCAL_DEFAULT=1; shift ;;
    *) wbds_die "未知参数：$1" ;;
  esac
done

case "$APPEARANCE" in auto|light|dark) ;; *) wbds_die "appearance 只能是 auto、light 或 dark。" ;; esac

wbds_verify_app
wbds_ensure_state_root
/bin/mkdir -p "$WBDS_USER_THEMES_ROOT" "$WBDS_ACTIVE_THEME_DIR"
/bin/chmod 700 "$WBDS_USER_THEMES_ROOT" "$WBDS_ACTIVE_THEME_DIR"

if [[ -z "$IMAGE" ]]; then
  IMAGE="$(/usr/bin/osascript -e 'POSIX path of (choose file with prompt "选择一张 WorkBuddy 背景图（建议横向、宽度 2000px 以上）" of type {"public.image"})')" || {
    wbds_info "已取消选择。"
    exit 0
  }
fi
[[ -f "$IMAGE" ]] || wbds_die "找不到图片：$IMAGE"
SOURCE_BYTES="$(/usr/bin/stat -f '%z' "$IMAGE")"
[[ "$SOURCE_BYTES" -le 52428800 ]] || wbds_die "原图超过 50 MiB，请选择更小的图片。"

if [[ -z "$THEME_NAME" ]]; then
  DEFAULT_NAME="$(/usr/bin/basename "$IMAGE")"
  DEFAULT_NAME="${DEFAULT_NAME%.*}"
  THEME_NAME="$(/usr/bin/osascript - "$DEFAULT_NAME" <<'APPLESCRIPT'
on run argv
  return text returned of (display dialog "给这套主题起个名字" default answer (item 1 of argv) buttons {"取消", "继续"} default button "继续" cancel button "取消")
end run
APPLESCRIPT
  )" || {
    wbds_info "已取消创建主题。"
    exit 0
  }
fi

THEME_ID="custom-$(/bin/date '+%Y%m%d-%H%M%S')-$$"
LIBRARY_DIR="$WBDS_USER_THEMES_ROOT/$THEME_ID"
/bin/mkdir -p "$LIBRARY_DIR"
/bin/chmod 700 "$LIBRARY_DIR"
TEMP_IMAGE="$LIBRARY_DIR/.background.$$.tmp.jpg"
cleanup() { /bin/rm -f "$TEMP_IMAGE"; }
trap cleanup EXIT

/usr/bin/sips -s format jpeg -s formatOptions 84 -Z 3200 "$IMAGE" --out "$TEMP_IMAGE" >/dev/null ||
  wbds_die "macOS 无法转换这张图片，请使用 PNG、JPEG、HEIC、TIFF 或 WebP。"
[[ -s "$TEMP_IMAGE" ]] || wbds_die "转换后的图片为空。"
PREPARED_BYTES="$(/usr/bin/stat -f '%z' "$TEMP_IMAGE")"
[[ "$PREPARED_BYTES" -le 16777216 ]] || wbds_die "处理后的图片仍超过 16 MiB。"
/bin/chmod 600 "$TEMP_IMAGE"
/bin/mv -f "$TEMP_IMAGE" "$LIBRARY_DIR/background.jpg"

wbds_node "$WBDS_ROOT/scripts/write-theme.mjs" custom \
  --output-dir "$LIBRARY_DIR" --image background.jpg \
  --id "$THEME_ID" --name "$THEME_NAME" --appearance "$APPEARANCE" >/dev/null

/usr/bin/rsync -a --delete "$LIBRARY_DIR/" "$WBDS_ACTIVE_THEME_DIR/"
/bin/chmod 600 "$WBDS_ACTIVE_THEME_DIR"/*
if (( SET_LOCAL_DEFAULT )); then
  DEFAULT_TMP="$WBDS_STATE_ROOT/.local-default-theme-id.$$"
  /usr/bin/printf '%s\n' "$THEME_ID" > "$DEFAULT_TMP"
  /bin/chmod 600 "$DEFAULT_TMP"
  /bin/mv -f "$DEFAULT_TMP" "$WBDS_LOCAL_DEFAULT_FILE"
fi
trap - EXIT

wbds_info "已保存主题：${THEME_NAME}（外观：${APPEARANCE}）"
(( SET_LOCAL_DEFAULT )) && wbds_info "已设为本机默认背景。"
if (( APPLY_NOW )); then
  /bin/bash "$WBDS_ROOT/scripts/apply-theme-macos.sh" --theme "$WBDS_ACTIVE_THEME_DIR"
  /usr/bin/osascript -e 'display notification "新背景已应用，并会继续跟随系统明暗模式。" with title "WorkBuddy Dream Skin"' >/dev/null 2>&1 || true
fi
