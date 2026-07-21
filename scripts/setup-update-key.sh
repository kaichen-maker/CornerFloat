#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ACCOUNT="${SPARKLE_KEY_ACCOUNT:-com.calvinkai.cornerfloat}"
EXPORT_PATH="${SPARKLE_PRIVATE_KEY_EXPORT:-}"
TOOL="$ROOT/.build/artifacts/sparkle/Sparkle/bin/generate_keys"

if [[ ! -x "$TOOL" ]]; then
    echo "Sparkle key tool is missing. Run 'scripts/swiftpm.sh resolve' first." >&2
    exit 1
fi

echo "This creates or reads the CornerFloat EdDSA update key in your login Keychain."
echo "Store an encrypted backup of the private key; losing it prevents existing installs from trusting future updates."
"$TOOL" --account "$ACCOUNT"

if [[ -n "$EXPORT_PATH" ]]; then
    if [[ -e "$EXPORT_PATH" ]]; then
        echo "Refusing to overwrite an existing private-key export: $EXPORT_PATH" >&2
        exit 1
    fi
    umask 077
    "$TOOL" --account "$ACCOUNT" -x "$EXPORT_PATH"
    chmod 600 "$EXPORT_PATH"
    echo "Sparkle private key exported with owner-only permissions: $EXPORT_PATH"
else
    echo "To create an owner-only raw export for immediate transfer into encrypted/offline storage, rerun with SPARKLE_PRIVATE_KEY_EXPORT=/secure/path/CornerFloat-Sparkle.key."
fi
