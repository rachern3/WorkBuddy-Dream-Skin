#!/bin/bash

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

/bin/bash -n scripts/*.sh ./*.command
node --check scripts/injector.mjs
node --check assets/renderer-inject.js
node --test tests/*.test.mjs
node -e '
  const fs = require("fs");
  for (const file of ["package.json", "assets/selectors.json", "presets/gothic-void-crusade/theme.json"]) {
    JSON.parse(fs.readFileSync(file, "utf8"));
  }
'

echo "All WorkBuddy Dream Skin checks passed."
