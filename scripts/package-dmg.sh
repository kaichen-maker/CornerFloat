#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${APP_PATH:-$ROOT/dist/CornerFloat.app}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
VALIDATOR="$ROOT/scripts/validate_release.py"

if [[ ! -d "$APP" ]]; then
    echo "CornerFloat.app not found. Run scripts/build.sh first." >&2
    exit 1
fi
APP_EXECUTABLE="$APP/Contents/MacOS/CornerFloat"
if [[ ! -f "$APP_EXECUTABLE" ]]; then
    echo "CornerFloat executable is missing: $APP_EXECUTABLE" >&2
    exit 1
fi

APP_ARCHITECTURES="$(xcrun lipo -archs "$APP_EXECUTABLE" | xargs)"
case "$APP_ARCHITECTURES" in
    arm64|x86_64)
        ARCH_LABEL="$APP_ARCHITECTURES"
        printf '%s\n' "$APP_ARCHITECTURES" | python3 "$VALIDATOR" architecture-set \
            --label "DMG CornerFloat executable" \
            --required-architecture "$ARCH_LABEL"
        ;;
    "arm64 x86_64"|"x86_64 arm64")
        ARCH_LABEL="universal"
        printf '%s\n' "$APP_ARCHITECTURES" | python3 "$VALIDATOR" architecture-set \
            --label "DMG CornerFloat Universal 2 executable" \
            --required-architecture arm64 \
            --required-architecture x86_64
        ;;
    *)
        echo "Unsupported CornerFloat architecture set: $APP_ARCHITECTURES" >&2
        exit 1
        ;;
esac

VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")"
python3 "$VALIDATOR" version \
    --info-plist "$APP/Contents/Info.plist" \
    --tag "v$VERSION"

validate_signature() {
    local target="$1"
    shift
    local signature_info
    if [[ -d "$target" ]]; then
        codesign --verify --deep --strict --verbose=2 "$target"
    else
        codesign --verify --strict --verbose=2 "$target"
    fi
    signature_info="$(codesign --display --verbose=4 "$target" 2>&1)"
    python3 "$VALIDATOR" signature \
        --identity "$SIGN_IDENTITY" \
        "$@" <<<"$signature_info"
}

if [[ "$SIGN_IDENTITY" != "-" ]]; then
    python3 "$VALIDATOR" identity --identity "$SIGN_IDENTITY" >/dev/null
    validate_signature "$APP" --require-runtime
fi

DMG="$ROOT/dist/CornerFloat-$VERSION-macOS-$ARCH_LABEL.dmg"
STAGING="$(mktemp -d /tmp/CornerFloat-dmg.XXXXXX)"
trap 'rm -rf "$STAGING"' EXIT

ditto "$APP" "$STAGING/CornerFloat.app"
ln -s /Applications "$STAGING/Applications"
cp "$ROOT/PRIVACY.md" "$STAGING/Privacy Policy.md"
cp "$ROOT/SUPPORT.md" "$STAGING/Support.md"

rm -f "$DMG"
hdiutil create \
    -volname "CornerFloat $VERSION" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    "$DMG"
hdiutil verify "$DMG"

if [[ "$SIGN_IDENTITY" != "-" ]]; then
    codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG"
    validate_signature "$DMG"
fi

echo "$DMG"
