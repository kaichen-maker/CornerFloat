#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

build_with_sdk() {
    local sdk_path="$1"
    local cache_name
    local module_cache
    cache_name="$(basename "$sdk_path" | tr -cd '[:alnum:]._-')"
    module_cache="$ROOT/.build/StrictConcurrencyModuleCache-$cache_name"
    mkdir -p "$module_cache"
    SDKROOT="$sdk_path" \
    CLANG_MODULE_CACHE_PATH="$module_cache" \
    SWIFTPM_MODULECACHE_OVERRIDE="$module_cache" \
    swift build \
        --package-path "$ROOT" \
        -c debug \
        --disable-sandbox \
        -Xswiftc -strict-concurrency=complete \
        -Xswiftc -warnings-as-errors
}

PRIMARY_SDK="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
if ! build_with_sdk "$PRIMARY_SDK"; then
    FALLBACK_SDK="${FALLBACK_SDKROOT:-/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk}"
    if [[ ! -d "$FALLBACK_SDK" || "$FALLBACK_SDK" == "$PRIMARY_SDK" ]]; then
        echo "Strict-concurrency build could not use SDK: $PRIMARY_SDK" >&2
        exit 1
    fi
    echo "Retrying strict-concurrency build with compatible SDK: $FALLBACK_SDK" >&2
    build_with_sdk "$FALLBACK_SDK"
fi

echo "CornerFloat strict-concurrency check OK: complete checking with warnings as errors"
