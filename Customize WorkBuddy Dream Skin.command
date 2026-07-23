#!/bin/bash
set -euo pipefail
INSTALLED="$HOME/.workbuddy-dream-skin/studio/scripts/customize-theme-macos.sh"
if [[ -x "$INSTALLED" ]]; then
  exec /bin/bash "$INSTALLED" "$@"
fi
ROOT="$(cd "$(dirname "$0")" && pwd)"
exec /bin/bash "$ROOT/scripts/customize-theme-macos.sh" "$@"
