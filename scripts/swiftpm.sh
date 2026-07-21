#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if (($# == 0)); then
    echo "Usage: scripts/swiftpm.sh <Swift package command> [arguments...]" >&2
    exit 64
fi

run_with_sdk() {
    local sdk_path="$1"
    shift
    local cache_name
    local module_cache
    cache_name="$(basename "$sdk_path" | tr -cd '[:alnum:]._-')"
    module_cache="$ROOT/.build/SwiftPMModuleCache-$cache_name"
    mkdir -p "$module_cache"
    SDKROOT="$sdk_path" \
    CLANG_MODULE_CACHE_PATH="$module_cache" \
    SWIFT_MODULECACHE_PATH="$module_cache" \
    SWIFTPM_MODULECACHE_OVERRIDE="$module_cache" \
    swift package --disable-sandbox --package-path "$ROOT" "$@"
}

PRIMARY_SDK="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
if run_with_sdk "$PRIMARY_SDK" "$@"; then
    exit 0
fi

FALLBACK_SDK="${FALLBACK_SDKROOT:-/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk}"
if [[ ! -d "$FALLBACK_SDK" || "$FALLBACK_SDK" == "$PRIMARY_SDK" ]]; then
    echo "Swift Package Manager could not use SDK: $PRIMARY_SDK" >&2
    exit 1
fi

echo "Retrying Swift Package Manager with compatible SDK: $FALLBACK_SDK" >&2
run_with_sdk "$FALLBACK_SDK" "$@"
