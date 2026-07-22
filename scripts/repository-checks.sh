#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/CornerFloat.app"
APP_RESOURCES="$ROOT/dist/CornerFloat.app/Contents/Resources"
APP_INFO="$APP/Contents/Info.plist"
SOURCE_ENTITLEMENTS="$ROOT/Resources/CornerFloat.entitlements"
AUDIO_INPUT_ENTITLEMENT="com.apple.security.device.audio-input"
AUDIO_INPUT_ENTITLEMENT_KEY_PATH='com\.apple\.security\.device\.audio-input'
CAMERA_ENTITLEMENT="com.apple.security.device.camera"
CAMERA_ENTITLEMENT_KEY_PATH='com\.apple\.security\.device\.camera'

required_files=(
    README.md
    README.zh-CN.md
    LICENSE
    THIRD_PARTY_NOTICES.md
    THIRD_PARTY_LICENSES/Sparkle-LICENSE
    CONTRIBUTING.md
    CODE_OF_CONDUCT.md
    SECURITY.md
    GOVERNANCE.md
    CHANGELOG.md
    docs/ARCHITECTURE.md
    docs/decisions/0001-web-workspaces-without-window-mirroring.md
    docs/decisions/0002-portable-local-library.md
    docs/DATA_FORMAT.md
    docs/GOOD_FIRST_ISSUES.md
    docs/images/cornerfloat-welcome.png
    docs/images/cornerfloat-settings.png
    docs/ROADMAP.md
    Resources/CornerFloat.entitlements
    Sources/CornerFloat/LaunchAtLoginController.swift
    scripts/install.sh
    scripts/static_checks.py
    scripts/strict-concurrency-check.sh
    scripts/uninstall.sh
    docs/SOURCE_BUILD.md
    scripts/run.sh
    .github/workflows/ci.yml
    .github/ISSUE_TEMPLATE/bug_report.yml
    .github/ISSUE_TEMPLATE/feature_request.yml
    .github/pull_request_template.md
)

for relative_path in "${required_files[@]}"; do
    if [[ ! -s "$ROOT/$relative_path" ]]; then
        echo "Required open-source file is missing or empty: $relative_path" >&2
        exit 1
    fi
done

for executable_script in \
    "$ROOT/scripts/install.sh" \
    "$ROOT/scripts/strict-concurrency-check.sh" \
    "$ROOT/scripts/uninstall.sh"; do
    if [[ ! -x "$executable_script" ]]; then
        echo "Required command is not executable: ${executable_script#"$ROOT/"}" >&2
        exit 1
    fi
done

while IFS= read -r -d '' shell_script; do
    bash -n "$shell_script"
done < <(find "$ROOT/scripts" -type f -name '*.sh' -print0)
python3 "$ROOT/scripts/static_checks.py"
plutil -lint "$ROOT/Resources/Info.plist" >/dev/null
plutil -lint "$APP_INFO" >/dev/null
plutil -lint "$SOURCE_ENTITLEMENTS" >/dev/null

validate_info_plist_media_boundary() {
    local info_plist="$1"
    local microphone_usage_description microphone_usage_type
    microphone_usage_type="$(
        plutil -type NSMicrophoneUsageDescription "$info_plist" 2>/dev/null || true
    )"
    if [[ "$microphone_usage_type" != "string" ]]; then
        echo "Microphone usage description must be a string: $info_plist" >&2
        return 1
    fi
    microphone_usage_description="$(
        plutil -extract NSMicrophoneUsageDescription raw "$info_plist" 2>/dev/null || true
    )"
    if [[ -z "${microphone_usage_description//[[:space:]]/}" ]]; then
        echo "Microphone usage description is missing or empty: $info_plist" >&2
        return 1
    fi
    if plutil -extract NSCameraUsageDescription xml1 -o - "$info_plist" \
        >/dev/null 2>&1; then
        echo "Camera usage description must remain absent: $info_plist" >&2
        return 1
    fi
}

for info_plist in "$ROOT/Resources/Info.plist" "$APP_INFO"; do
    validate_info_plist_media_boundary "$info_plist"
done

test_info_plist_media_boundary() (
    local fixture
    fixture="$(mktemp "${TMPDIR:-/tmp}/CornerFloat-privacy-metadata.XXXXXX")"
    trap 'rm -f "$fixture"' EXIT

    cp "$ROOT/Resources/Info.plist" "$fixture"
    plutil -replace NSMicrophoneUsageDescription -bool true "$fixture"
    if validate_info_plist_media_boundary "$fixture" >/dev/null 2>&1; then
        echo "Privacy metadata check accepted a non-string microphone description." >&2
        exit 1
    fi

    cp "$ROOT/Resources/Info.plist" "$fixture"
    plutil -insert NSCameraUsageDescription \
        -json '{"unexpected":"dictionary"}' "$fixture"
    if validate_info_plist_media_boundary "$fixture" >/dev/null 2>&1; then
        echo "Privacy metadata check missed a non-string camera usage key." >&2
        exit 1
    fi
)
test_info_plist_media_boundary

if [[ "$(
    plutil -extract "$AUDIO_INPUT_ENTITLEMENT_KEY_PATH" raw "$SOURCE_ENTITLEMENTS" \
        2>/dev/null || true
)" != "true" ]]; then
    echo "Source signing entitlements must contain $AUDIO_INPUT_ENTITLEMENT=true." >&2
    exit 1
fi
if plutil -extract "$CAMERA_ENTITLEMENT_KEY_PATH" raw "$SOURCE_ENTITLEMENTS" \
    >/dev/null 2>&1; then
    echo "Source signing entitlements must not contain $CAMERA_ENTITLEMENT." >&2
    exit 1
fi

SIGNED_ENTITLEMENTS="$(mktemp "${TMPDIR:-/tmp}/CornerFloat-signed-entitlements.XXXXXX")"
cleanup_signed_entitlements() {
    rm -f "$SIGNED_ENTITLEMENTS"
}
trap cleanup_signed_entitlements EXIT INT TERM
if ! codesign --display --entitlements :- "$APP" >"$SIGNED_ENTITLEMENTS" 2>/dev/null; then
    echo "Could not read entitlements from the built CornerFloat signature." >&2
    exit 1
fi
if [[ "$(
    plutil -extract "$AUDIO_INPUT_ENTITLEMENT_KEY_PATH" raw "$SIGNED_ENTITLEMENTS" \
        2>/dev/null || true
)" != "true" ]]; then
    echo "Built CornerFloat signature must contain $AUDIO_INPUT_ENTITLEMENT=true." >&2
    exit 1
fi
if plutil -extract "$CAMERA_ENTITLEMENT_KEY_PATH" raw "$SIGNED_ENTITLEMENTS" \
    >/dev/null 2>&1; then
    echo "Built CornerFloat signature must not contain $CAMERA_ENTITLEMENT." >&2
    exit 1
fi

SPARKLE_VERSION="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
SPARKLE_SIGNABLES=(
    "$SPARKLE_VERSION/Autoupdate"
    "$SPARKLE_VERSION/Updater.app"
    "$SPARKLE_VERSION/XPCServices/Installer.xpc"
    "$SPARKLE_VERSION/XPCServices/Downloader.xpc"
    "$APP/Contents/Frameworks/Sparkle.framework"
)
for sparkle_signable in "${SPARKLE_SIGNABLES[@]}"; do
    nested_entitlements="$(mktemp "${TMPDIR:-/tmp}/CornerFloat-nested-entitlements.XXXXXX")"
    if ! codesign --display --entitlements :- "$sparkle_signable" \
        >"$nested_entitlements" 2>/dev/null; then
        rm -f "$nested_entitlements"
        echo "Could not read entitlements from nested Sparkle code: $sparkle_signable" >&2
        exit 1
    fi
    for media_key_path in "$AUDIO_INPUT_ENTITLEMENT_KEY_PATH" "$CAMERA_ENTITLEMENT_KEY_PATH"; do
        if plutil -extract "$media_key_path" raw "$nested_entitlements" >/dev/null 2>&1; then
            rm -f "$nested_entitlements"
            echo "Nested Sparkle code must not contain media-capture entitlement $media_key_path: $sparkle_signable" >&2
            exit 1
        fi
    done
    rm -f "$nested_entitlements"
done

UPSTREAM_SPARKLE_LICENSE="$ROOT/.build/checkouts/Sparkle/LICENSE"
if [[ ! -s "$UPSTREAM_SPARKLE_LICENSE" ]]; then
    echo "Pinned Sparkle license is unavailable; resolve dependencies first." >&2
    exit 1
fi
if ! diff -b -q \
    "$UPSTREAM_SPARKLE_LICENSE" \
    "$ROOT/THIRD_PARTY_LICENSES/Sparkle-LICENSE" >/dev/null; then
    echo "The preserved Sparkle license differs from the pinned dependency." >&2
    echo "Review the upstream terms and update THIRD_PARTY_LICENSES/Sparkle-LICENSE." >&2
    exit 1
fi

for bundled_notice in LICENSE THIRD_PARTY_NOTICES.md Sparkle-LICENSE; do
    if [[ ! -s "$APP_RESOURCES/$bundled_notice" ]]; then
        echo "Built app is missing license resource: $bundled_notice" >&2
        exit 1
    fi
done

cmp -s "$ROOT/LICENSE" "$APP_RESOURCES/LICENSE"
cmp -s \
    "$ROOT/THIRD_PARTY_NOTICES.md" \
    "$APP_RESOURCES/THIRD_PARTY_NOTICES.md"
cmp -s \
    "$ROOT/THIRD_PARTY_LICENSES/Sparkle-LICENSE" \
    "$APP_RESOURCES/Sparkle-LICENSE"

retired_feature_pattern='Mirror Existing Window|import ScreenCaptureKit|linkedFramework\("(AVFoundation|ScreenCaptureKit|ApplicationServices)"\)|NSScreenCaptureUsageDescription|NSAccessibilityUsageDescription|Privacy_(ScreenCapture|Accessibility)'
if grep -R -n -E "$retired_feature_pattern" \
    "$ROOT/Sources/CornerFloat" \
    "$ROOT/Package.swift" \
    "$ROOT/Resources/Info.plist"; then
    echo "Retired window-mirroring code, frameworks, menu text, or permission declarations remain." >&2
    exit 1
fi

APP_BINARY="$ROOT/dist/CornerFloat.app/Contents/MacOS/CornerFloat"
if otool -L "$APP_BINARY" | grep -Eq 'AVFoundation|ScreenCaptureKit|ApplicationServices'; then
    echo "Built app still links a retired window-mirroring framework." >&2
    exit 1
fi
if strings "$APP_BINARY" | grep -qF 'Mirror Existing Window'; then
    echo "Built app still contains the retired window-mirroring menu entry." >&2
    exit 1
fi

echo "CornerFloat repository checks OK: community files, media-capture privacy/signing declarations, static checks, bundled licenses, and retired mirroring surface absent"
