#!/bin/bash

set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
exec /bin/bash "$ROOT/macos/scripts/install-menubar-app-macos.sh"
