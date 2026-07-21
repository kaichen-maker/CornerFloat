#!/usr/bin/env bash

set -euo pipefail

failures=0

ok() {
    printf 'OK   %s\n' "$1"
}

fail() {
    printf 'FAIL %s\n' "$1" >&2
    failures=$((failures + 1))
}

if [[ "$(uname -s)" == "Darwin" ]]; then
    ok "Running on macOS"
else
    fail "CornerFloat requires macOS"
fi

if command -v sw_vers >/dev/null 2>&1; then
    MACOS_VERSION="$(sw_vers -productVersion)"
    MACOS_MAJOR="${MACOS_VERSION%%.*}"
    if [[ "$MACOS_MAJOR" =~ ^[0-9]+$ ]] && ((MACOS_MAJOR >= 14)); then
        ok "macOS $MACOS_VERSION (minimum 14.0)"
    else
        fail "macOS $MACOS_VERSION is older than the supported 14.0 minimum"
    fi
fi

for required_command in git make python3 swift xcode-select xcrun plutil codesign ditto; do
    if command -v "$required_command" >/dev/null 2>&1; then
        ok "$required_command is available"
    else
        fail "$required_command is missing"
    fi
done

if command -v xcode-select >/dev/null 2>&1; then
    if DEVELOPER_DIR_PATH="$(xcode-select -p 2>/dev/null)"; then
        ok "Developer tools: $DEVELOPER_DIR_PATH"
    else
        fail "Apple developer tools are not selected; run xcode-select --install"
    fi
fi

if command -v xcrun >/dev/null 2>&1; then
    if SDK_PATH="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null)"; then
        ok "macOS SDK: $SDK_PATH"
    else
        fail "xcrun cannot find a macOS SDK"
    fi
fi

if command -v swift >/dev/null 2>&1; then
    SWIFT_VERSION="$(swift --version 2>/dev/null | head -n 1 || true)"
    if [[ -n "$SWIFT_VERSION" ]]; then
        ok "$SWIFT_VERSION"
    fi
fi

if ((failures > 0)); then
    printf '\nCornerFloat doctor found %d blocking problem(s).\n' "$failures" >&2
    exit 1
fi

printf '\nCornerFloat build environment is ready.\n'
