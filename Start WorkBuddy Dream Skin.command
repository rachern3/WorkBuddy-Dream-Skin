#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
exec /bin/bash "$ROOT/scripts/start-workbuddy-dream-skin-macos.sh" "$@"
