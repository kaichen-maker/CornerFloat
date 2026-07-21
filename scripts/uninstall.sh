#!/usr/bin/env bash

set -euo pipefail

INSTALL_DIR="${CORNERFLOAT_INSTALL_DIR:-$HOME/Applications}"
DESTINATION="$INSTALL_DIR/CornerFloat.app"

if [[ ! -e "$DESTINATION" ]]; then
    echo "CornerFloat is not installed at $DESTINATION"
    exit 0
fi

rm -rf "$DESTINATION"
echo "Removed $DESTINATION"
echo "Preferences, the CornerFloat library, and WebKit website data were preserved."
