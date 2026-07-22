#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODULE_CACHE="$ROOT/.build/WebKitIntegrationTestModuleCache"
TEST_DIRECTORY="${TMPDIR:-/tmp}/CornerFloatWebKitIntegrationTests-$$"
TEST_BINARY="$TEST_DIRECTORY/runner"

mkdir -p "$MODULE_CACHE" "$TEST_DIRECTORY"
trap 'rm -rf "$TEST_DIRECTORY"' EXIT

compile_with_sdk() {
    local sdk_path="$1"
    SDKROOT="$sdk_path" \
    CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
    swiftc \
        -parse-as-library \
        -D CORNERFLOAT_WEBKIT_INTEGRATION_TESTS \
        "$ROOT/Sources/CornerFloat/WindowGeometry.swift" \
        "$ROOT/Sources/CornerFloat/FloatingPanelController.swift" \
        "$ROOT/Sources/CornerFloat/BrowserComponents.swift" \
        "$ROOT/Sources/CornerFloat/SmartAddressResolver.swift" \
        "$ROOT/Sources/CornerFloat/BrowserSupport.swift" \
        "$ROOT/Sources/CornerFloat/AudioRouteSupport.swift" \
        "$ROOT/Sources/CornerFloat/VoiceAudioRouteCoordinator.swift" \
        "$ROOT/Sources/CornerFloat/URLPersistenceSanitizer.swift" \
        "$ROOT/Sources/CornerFloat/DownloadDestinationTransaction.swift" \
        "$ROOT/Sources/CornerFloat/WebPanelController.swift" \
        "$ROOT/Tests/WebKitIntegrationTests/WebKitIntegrationTests.swift" \
        -framework AppKit \
        -framework WebKit \
        -framework CoreAudio \
        -o "$TEST_BINARY"
}

PRIMARY_SDK="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
if ! compile_with_sdk "$PRIMARY_SDK"; then
    FALLBACK_SDK="${FALLBACK_SDKROOT:-/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk}"
    if [[ ! -d "$FALLBACK_SDK" || "$FALLBACK_SDK" == "$PRIMARY_SDK" ]]; then
        echo "Swift could not compile WebKit integration tests with SDK: $PRIMARY_SDK" >&2
        exit 1
    fi
    echo "Retrying WebKit integration tests with compatible SDK: $FALLBACK_SDK" >&2
    compile_with_sdk "$FALLBACK_SDK"
fi

"$TEST_BINARY"
