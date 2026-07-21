#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODULE_CACHE="$ROOT/.build/PasskeyTestModuleCache"
TEST_BINARY="${TMPDIR:-/tmp}/CornerFloat-passkey-authorization-tests"

mkdir -p "$MODULE_CACHE"
export SDKROOT="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
export CLANG_MODULE_CACHE_PATH="$MODULE_CACHE"

swiftc \
    -parse-as-library \
    "$ROOT/Sources/CornerFloat/PasskeyAuthorization.swift" \
    "$ROOT/Tests/PasskeyAuthorizationTests/main.swift" \
    -framework AppKit \
    -framework AuthenticationServices \
    -o "$TEST_BINARY"
"$TEST_BINARY"
