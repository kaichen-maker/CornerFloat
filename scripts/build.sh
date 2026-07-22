#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="${DIST_DIR:-$ROOT/dist}"
APP="$DIST_DIR/CornerFloat.app"
CONTENTS="$APP/Contents"
CONFIGURATION="${CONFIGURATION:-release}"
UNIVERSAL="${UNIVERSAL:-0}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
DEVELOPER_ID_PROVISIONING_PROFILE_FILE="${DEVELOPER_ID_PROVISIONING_PROFILE_FILE:-}"
SIGNING_ENTITLEMENTS_FILE="${SIGNING_ENTITLEMENTS_FILE:-}"
ALLOW_INSECURE_LOCAL_UPDATE_TEST="${ALLOW_INSECURE_LOCAL_UPDATE_TEST:-0}"
SPARKLE_FRAMEWORK="$ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
SPARKLE_MACHO_RELATIVE_PATHS=(
    "Versions/B/Sparkle"
    "Versions/B/Autoupdate"
    "Versions/B/Updater.app/Contents/MacOS/Updater"
    "Versions/B/XPCServices/Installer.xpc/Contents/MacOS/Installer"
    "Versions/B/XPCServices/Downloader.xpc/Contents/MacOS/Downloader"
)
SPARKLE_SIGNABLE_RELATIVE_PATHS=(
    "Versions/B/Autoupdate"
    "Versions/B/Updater.app"
    "Versions/B/XPCServices/Installer.xpc"
    "Versions/B/XPCServices/Downloader.xpc"
    "."
)
VALIDATOR="$ROOT/scripts/validate_release.py"
BASE_SIGNING_ENTITLEMENTS_FILE="$ROOT/Resources/CornerFloat.entitlements"
LOCAL_LOOPBACK_FEED=false

if [[ "$UNIVERSAL" != "0" && "$UNIVERSAL" != "1" ]]; then
    echo "UNIVERSAL must be 0 or 1, found: $UNIVERSAL" >&2
    exit 1
fi

SIGNING_MODE_ARGS=(signing-mode)
if [[ -n "$DEVELOPER_ID_PROVISIONING_PROFILE_FILE" ]]; then
    SIGNING_MODE_ARGS+=(
        --provisioning-profile "$DEVELOPER_ID_PROVISIONING_PROFILE_FILE"
    )
fi
if [[ -n "$SIGNING_ENTITLEMENTS_FILE" ]]; then
    SIGNING_MODE_ARGS+=(--signing-entitlements "$SIGNING_ENTITLEMENTS_FILE")
fi
SIGNING_MODE="$(python3 "$VALIDATOR" "${SIGNING_MODE_ARGS[@]}")"
plutil -lint "$BASE_SIGNING_ENTITLEMENTS_FILE" >/dev/null
if [[ "$SIGN_IDENTITY" == "-" && "$SIGNING_MODE" != "baseline" ]]; then
    echo "Passkey-enabled signing requires a Developer ID identity, not an ad-hoc signature." >&2
    exit 1
fi

if [[ -n "${UPDATE_FEED_URL:-}" || -n "${SPARKLE_PUBLIC_KEY:-}" ]]; then
    if [[ -z "${UPDATE_FEED_URL:-}" || -z "${SPARKLE_PUBLIC_KEY:-}" ]]; then
        echo "UPDATE_FEED_URL and SPARKLE_PUBLIC_KEY must be supplied together." >&2
        exit 1
    fi
    if [[ "$UPDATE_FEED_URL" == https://* ]]; then
        python3 "$ROOT/scripts/validate_release.py" https-url \
            --url "$UPDATE_FEED_URL" \
            --label "update feed URL" >/dev/null
    elif [[ "$UPDATE_FEED_URL" == file://* ]]; then
        : # Reserved for isolated development tests; public releases reject it.
    elif [[ "$ALLOW_INSECURE_LOCAL_UPDATE_TEST" == "1" ]]; then
        python3 "$ROOT/scripts/validate_release.py" local-test-url \
            --url "$UPDATE_FEED_URL" \
            --label "loopback update test feed URL" >/dev/null
        LOCAL_LOOPBACK_FEED=true
    else
        echo "UPDATE_FEED_URL must use HTTPS (or file:// for an isolated update test)." >&2
        echo "Loopback HTTP additionally requires ALLOW_INSECURE_LOCAL_UPDATE_TEST=1 and an explicit port." >&2
        exit 1
    fi
fi

build_with_sdk() {
    local sdk_path="$1"
    local cache_name
    cache_name="$(basename "$sdk_path" | tr -cd '[:alnum:]._-')"
    local module_cache="$ROOT/.build/ModuleCache-$cache_name"
    mkdir -p "$module_cache"
    SDKROOT="$sdk_path" \
    CLANG_MODULE_CACHE_PATH="$module_cache" \
    SWIFTPM_MODULECACHE_OVERRIDE="$module_cache" \
    swift build \
        --package-path "$ROOT" \
        -c "$CONFIGURATION" \
        --sdk "$sdk_path" \
        --disable-sandbox
}

build_architecture_with_sdk() {
    local sdk_path="$1"
    local architecture="$2"
    local cache_name triple module_cache
    cache_name="$(basename "$sdk_path" | tr -cd '[:alnum:]._-')"
    triple="$architecture-apple-macosx14.0"
    module_cache="$ROOT/.build/ModuleCache-$cache_name-$architecture"
    mkdir -p "$module_cache"
    SDKROOT="$sdk_path" \
    CLANG_MODULE_CACHE_PATH="$module_cache" \
    SWIFTPM_MODULECACHE_OVERRIDE="$module_cache" \
    swift build \
        --package-path "$ROOT" \
        -c "$CONFIGURATION" \
        --triple "$triple" \
        --sdk "$sdk_path" \
        --disable-sandbox
}

build_universal_with_sdk() {
    local sdk_path="$1"
    build_architecture_with_sdk "$sdk_path" arm64 || return
    build_architecture_with_sdk "$sdk_path" x86_64 || return
}

validate_architecture_set() {
    local binary="$1"
    local label="$2"
    shift 2
    local validator_args=(architecture-set --label "$label")
    local architecture
    if [[ ! -f "$binary" ]]; then
        echo "Required Mach-O binary is missing: $binary" >&2
        return 1
    fi
    for architecture in "$@"; do
        validator_args+=(--required-architecture "$architecture")
    done
    xcrun lipo -archs "$binary" | python3 "$VALIDATOR" "${validator_args[@]}"
}

PRIMARY_SDK="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
FALLBACK_SDK="${FALLBACK_SDKROOT:-/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk}"
if [[ "$UNIVERSAL" == "1" ]]; then
    if ! build_universal_with_sdk "$PRIMARY_SDK"; then
        if [[ ! -d "$FALLBACK_SDK" || "$FALLBACK_SDK" == "$PRIMARY_SDK" ]]; then
            echo "Swift could not build Universal 2 with SDK: $PRIMARY_SDK" >&2
            exit 1
        fi
        echo "Retrying both Universal 2 slices with compatible SDK: $FALLBACK_SDK" >&2
        build_universal_with_sdk "$FALLBACK_SDK"
    fi
    ARM_EXECUTABLE="$ROOT/.build/arm64-apple-macosx/$CONFIGURATION/CornerFloat"
    X86_EXECUTABLE="$ROOT/.build/x86_64-apple-macosx/$CONFIGURATION/CornerFloat"
    validate_architecture_set "$ARM_EXECUTABLE" "CornerFloat arm64 slice" arm64
    validate_architecture_set "$X86_EXECUTABLE" "CornerFloat x86_64 slice" x86_64
    UNIVERSAL_BUILD_DIR="$ROOT/.build/CornerFloat-universal/$CONFIGURATION"
    mkdir -p "$UNIVERSAL_BUILD_DIR"
    BUILT_EXECUTABLE="$UNIVERSAL_BUILD_DIR/CornerFloat"
    rm -f "$BUILT_EXECUTABLE"
    xcrun lipo -create \
        "$ARM_EXECUTABLE" \
        "$X86_EXECUTABLE" \
        -output "$BUILT_EXECUTABLE"
    validate_architecture_set "$BUILT_EXECUTABLE" "CornerFloat Universal 2 executable" arm64 x86_64
    ARCH_LABEL="universal"
elif ! build_with_sdk "$PRIMARY_SDK"; then
    if [[ ! -d "$FALLBACK_SDK" || "$FALLBACK_SDK" == "$PRIMARY_SDK" ]]; then
        echo "Swift could not build with SDK: $PRIMARY_SDK" >&2
        exit 1
    fi
    echo "Retrying with compatible SDK: $FALLBACK_SDK" >&2
    build_with_sdk "$FALLBACK_SDK"
    BUILT_EXECUTABLE="$ROOT/.build/$CONFIGURATION/CornerFloat"
    ARCH_LABEL="$(uname -m)"
else
    BUILT_EXECUTABLE="$ROOT/.build/$CONFIGURATION/CornerFloat"
    ARCH_LABEL="$(uname -m)"
fi

if [[ ! -d "$SPARKLE_FRAMEWORK" ]]; then
    echo "Sparkle.framework is missing. Run 'scripts/swiftpm.sh resolve' first." >&2
    exit 1
fi

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$CONTENTS/Frameworks"
cp "$BUILT_EXECUTABLE" "$CONTENTS/MacOS/CornerFloat"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
cp "$ROOT/Resources/PrivacyPolicy.html" "$CONTENTS/Resources/PrivacyPolicy.html"
cp "$ROOT/Resources/Support.html" "$CONTENTS/Resources/Support.html"
cp "$ROOT/LICENSE" "$CONTENTS/Resources/LICENSE"
cp "$ROOT/THIRD_PARTY_NOTICES.md" "$CONTENTS/Resources/THIRD_PARTY_NOTICES.md"
cp "$ROOT/THIRD_PARTY_LICENSES/Sparkle-LICENSE" \
    "$CONTENTS/Resources/Sparkle-LICENSE"
cp "$ROOT/PRIVACY.md" "$CONTENTS/Resources/PRIVACY.md"
cp "$ROOT/SUPPORT.md" "$CONTENTS/Resources/SUPPORT.md"
ditto "$SPARKLE_FRAMEWORK" "$CONTENTS/Frameworks/Sparkle.framework"

# Never carry Sparkle's insecure transport override from the source template or
# a previous build. The guarded loopback test below is the only insertion path.
plutil -remove SUAllowsInsecureUpdate "$CONTENTS/Info.plist" 2>/dev/null || true

if [[ -n "${UPDATE_FEED_URL:-}" || -n "${SPARKLE_PUBLIC_KEY:-}" ]]; then
    plutil -remove SUFeedURL "$CONTENTS/Info.plist" 2>/dev/null || true
    plutil -remove SUPublicEDKey "$CONTENTS/Info.plist" 2>/dev/null || true
    plutil -insert SUFeedURL -string "$UPDATE_FEED_URL" "$CONTENTS/Info.plist"
    plutil -insert SUPublicEDKey -string "$SPARKLE_PUBLIC_KEY" "$CONTENTS/Info.plist"
    if [[ "$LOCAL_LOOPBACK_FEED" == "true" ]]; then
        plutil -insert SUAllowsInsecureUpdate -bool true "$CONTENTS/Info.plist"
    fi
fi

plutil -lint "$CONTENTS/Info.plist"

if [[ "$SIGN_IDENTITY" == "-" ]]; then
    # Ad-hoc development signatures have no Team ID, so Hardened Runtime
    # library validation would reject Sparkle's separately signed framework.
    # Public Developer ID builds below enable Hardened Runtime everywhere.
    # Managed web-browser passkey entitlements cannot be embedded in an ad-hoc
    # signature: macOS rejects that process before launch. A Developer ID build
    # includes it only when a validated profile/entitlements pair is supplied.
    codesign --force --deep --sign - "$APP"
    # Apply microphone access only to CornerFloat itself. Passing entitlements
    # to a recursive signature would incorrectly grant the same capability to
    # Sparkle's updater and XPC helpers.
    codesign --force --sign - \
        --entitlements "$BASE_SIGNING_ENTITLEMENTS_FILE" \
        "$APP"
else
    if [[ "$SIGNING_MODE" == "passkey" ]]; then
        cp "$DEVELOPER_ID_PROVISIONING_PROFILE_FILE" "$CONTENTS/embedded.provisionprofile"
    fi

    SIGN_FLAGS=(--force --sign "$SIGN_IDENTITY" --options runtime --timestamp)
    SPARKLE_VERSION="$CONTENTS/Frameworks/Sparkle.framework/Versions/B"

    if [[ -d "$SPARKLE_VERSION/XPCServices/Installer.xpc" ]]; then
        codesign "${SIGN_FLAGS[@]}" \
            --preserve-metadata=identifier,entitlements,flags,runtime \
            "$SPARKLE_VERSION/XPCServices/Installer.xpc"
    fi
    if [[ -d "$SPARKLE_VERSION/XPCServices/Downloader.xpc" ]]; then
        codesign "${SIGN_FLAGS[@]}" \
            --preserve-metadata=identifier,entitlements,flags,runtime \
            "$SPARKLE_VERSION/XPCServices/Downloader.xpc"
    fi
    codesign "${SIGN_FLAGS[@]}" "$SPARKLE_VERSION/Autoupdate"
    codesign "${SIGN_FLAGS[@]}" "$SPARKLE_VERSION/Updater.app"
    codesign "${SIGN_FLAGS[@]}" "$CONTENTS/Frameworks/Sparkle.framework"
    if [[ "$SIGNING_MODE" == "passkey" ]]; then
        codesign "${SIGN_FLAGS[@]}" --entitlements "$SIGNING_ENTITLEMENTS_FILE" "$APP"
    else
        codesign "${SIGN_FLAGS[@]}" \
            --entitlements "$BASE_SIGNING_ENTITLEMENTS_FILE" \
            "$APP"
    fi
fi

codesign --verify --deep --strict --verbose=2 "$APP"

validate_nested_media_entitlements() (
    local temporary_directory relative_path signed_entitlements key_path
    temporary_directory="$(mktemp -d /tmp/CornerFloat-nested-entitlements.XXXXXX)"
    trap 'rm -rf "$temporary_directory"' EXIT
    for relative_path in "${SPARKLE_SIGNABLE_RELATIVE_PATHS[@]}"; do
        signed_entitlements="$temporary_directory/$(printf '%s' "$relative_path" | tr '/ ' '__').plist"
        codesign --display --entitlements :- \
            "$CONTENTS/Frameworks/Sparkle.framework/$relative_path" \
            >"$signed_entitlements" 2>/dev/null
        for key_path in \
            'com\.apple\.security\.device\.audio-input' \
            'com\.apple\.security\.device\.camera'; do
            if plutil -extract "$key_path" raw "$signed_entitlements" >/dev/null 2>&1; then
                echo "Sparkle nested code must not inherit media-capture entitlement $key_path: $relative_path" >&2
                exit 1
            fi
        done
    done
)
validate_nested_media_entitlements

if [[ "$UNIVERSAL" == "1" ]]; then
    validate_architecture_set \
        "$CONTENTS/MacOS/CornerFloat" \
        "signed CornerFloat executable" \
        arm64 x86_64
else
    validate_architecture_set \
        "$CONTENTS/MacOS/CornerFloat" \
        "signed CornerFloat executable" \
        "$ARCH_LABEL"
fi
for relative_path in "${SPARKLE_MACHO_RELATIVE_PATHS[@]}"; do
    validate_architecture_set \
        "$CONTENTS/Frameworks/Sparkle.framework/$relative_path" \
        "Sparkle.framework/$relative_path" \
        arm64 x86_64
done

validate_passkey_signing_mode() (
    local app_path="$1"
    local policy="forbidden"
    local signed_entitlements
    signed_entitlements="$(mktemp /tmp/CornerFloat-build-entitlements.XXXXXX)"
    trap 'rm -f "$signed_entitlements"' EXIT
    codesign --display --entitlements :- "$app_path" \
        >"$signed_entitlements" 2>/dev/null
    if [[ "$SIGNING_MODE" == "passkey" ]]; then
        policy="required"
        if [[ ! -f "$app_path/Contents/embedded.provisionprofile" ]]; then
            echo "Passkey-enabled app is missing its embedded provisioning profile." >&2
            exit 1
        fi
    elif [[ -e "$app_path/Contents/embedded.provisionprofile" ]]; then
        echo "Baseline app must not embed a Passkey provisioning profile." >&2
        exit 1
    fi
    python3 "$VALIDATOR" entitlements \
        --entitlements-plist "$signed_entitlements" \
        --passkey-policy "$policy"
)
validate_passkey_signing_mode "$APP"
echo "Signing capability mode: $SIGNING_MODE"

ZIP="$DIST_DIR/CornerFloat-macOS-$ARCH_LABEL.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "$APP"
echo "$ZIP"
