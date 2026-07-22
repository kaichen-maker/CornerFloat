#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODULE_CACHE="$ROOT/.build/AudioRouteTestModuleCache"
TEST_BINARY="${TMPDIR:-/tmp}/CornerFloat-audio-route-tests"

mkdir -p "$MODULE_CACHE"
export SDKROOT="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
export CLANG_MODULE_CACHE_PATH="$MODULE_CACHE"

swiftc \
    -strict-concurrency=complete \
    -warnings-as-errors \
    "$ROOT/Sources/CornerFloat/AudioRouteSupport.swift" \
    "$ROOT/Tests/AudioRouteSupportTests/main.swift" \
    -framework CoreAudio \
    -o "$TEST_BINARY"
"$TEST_BINARY"
