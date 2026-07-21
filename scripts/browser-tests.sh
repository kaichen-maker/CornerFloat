#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODULE_CACHE="$ROOT/.build/BrowserTestModuleCache"
TEST_BINARY="${TMPDIR:-/tmp}/CornerFloat-browser-support-tests"

mkdir -p "$MODULE_CACHE"
export SDKROOT="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
export CLANG_MODULE_CACHE_PATH="$MODULE_CACHE"

swiftc \
    "$ROOT/Sources/CornerFloat/SmartAddressResolver.swift" \
    "$ROOT/Sources/CornerFloat/BrowserSupport.swift" \
    "$ROOT/Tests/BrowserSupportTests/main.swift" \
    -o "$TEST_BINARY"
"$TEST_BINARY"
