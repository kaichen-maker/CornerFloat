#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_APP="$ROOT/dist/CornerFloat.app"
INSTALL_DIR="${CORNERFLOAT_INSTALL_DIR:-$HOME/Applications}"
DESTINATION="$INSTALL_DIR/CornerFloat.app"

if [[ ! -d "$SOURCE_APP" ]]; then
    echo "Local app is missing. Run 'make build' first." >&2
    exit 1
fi

mkdir -p "$INSTALL_DIR"
rm -rf "$DESTINATION"
ditto "$SOURCE_APP" "$DESTINATION"
codesign --verify --deep --strict "$DESTINATION"

echo "Installed CornerFloat at $DESTINATION"
echo "Open it from Finder or run: open '$DESTINATION'"
