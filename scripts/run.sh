#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/CornerFloat.app"

"$ROOT/scripts/build.sh"

if [[ "${CORNERFLOAT_RUN_FOREGROUND:-0}" == "1" ]]; then
    exec "$APP/Contents/MacOS/CornerFloat"
fi

open "$APP"
printf 'Opened %s\n' "$APP"
