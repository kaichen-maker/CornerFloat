#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
UPDATE_FEED_URL="${UPDATE_FEED_URL:-}"
SPARKLE_PUBLIC_KEY="${SPARKLE_PUBLIC_KEY:-}"
SPARKLE_PRIVATE_KEY_FILE="${SPARKLE_PRIVATE_KEY_FILE:-}"
DEVELOPER_ID_PROVISIONING_PROFILE_FILE="${DEVELOPER_ID_PROVISIONING_PROFILE_FILE:-}"
SPARKLE_TOOLS="$ROOT/.build/artifacts/sparkle/Sparkle/bin"
VALIDATOR="$ROOT/scripts/validate_release.py"

require_value() {
    local name="$1"
    local value="$2"
    if [[ -z "$value" ]]; then
        echo "$name is required for a public release." >&2
        exit 1
    fi
}

require_value SIGN_IDENTITY "$SIGN_IDENTITY"
require_value NOTARY_PROFILE "$NOTARY_PROFILE"
require_value UPDATE_FEED_URL "$UPDATE_FEED_URL"
require_value SPARKLE_PUBLIC_KEY "$SPARKLE_PUBLIC_KEY"
require_value SPARKLE_PRIVATE_KEY_FILE "$SPARKLE_PRIVATE_KEY_FILE"

EXPECTED_TEAM_ID="$(python3 "$VALIDATOR" identity --identity "$SIGN_IDENTITY")"
python3 "$VALIDATOR" https-url \
    --url "$UPDATE_FEED_URL" \
    --label "public update feed URL"
DOWNLOAD_PREFIX="${UPDATE_DOWNLOAD_URL_PREFIX:-${UPDATE_FEED_URL%/*}}"
python3 "$VALIDATOR" https-url \
    --url "$DOWNLOAD_PREFIX" \
    --label "public update download prefix" \
    --prefix
if [[ ! -f "$SPARKLE_PRIVATE_KEY_FILE" ]]; then
    echo "Sparkle private key file does not exist: $SPARKLE_PRIVATE_KEY_FILE" >&2
    exit 1
fi
if [[ -n "$DEVELOPER_ID_PROVISIONING_PROFILE_FILE" ]]; then
    if [[ ! -f "$DEVELOPER_ID_PROVISIONING_PROFILE_FILE" ]]; then
        echo "Developer ID provisioning profile does not exist: $DEVELOPER_ID_PROVISIONING_PROFILE_FILE" >&2
        exit 1
    fi
    PROFILE_PERMISSIONS="$(stat -f '%Lp' "$DEVELOPER_ID_PROVISIONING_PROFILE_FILE")"
    if (( (8#$PROFILE_PERMISSIONS & 8#077) != 0 )); then
        echo "Developer ID provisioning profile must not be readable or writable by group/other (mode $PROFILE_PERMISSIONS)." >&2
        exit 1
    fi
fi
KEY_PERMISSIONS="$(stat -f '%Lp' "$SPARKLE_PRIVATE_KEY_FILE")"
if (( (8#$KEY_PERMISSIONS & 8#077) != 0 )); then
    echo "Sparkle private key must not be readable or writable by group/other (mode $KEY_PERMISSIONS)." >&2
    exit 1
fi
for required_file in "$ROOT/RELEASE_NOTES.md" "$ROOT/PRIVACY.md" "$ROOT/SUPPORT.md"; do
    if [[ ! -f "$required_file" ]]; then
        echo "Required release file is missing: $required_file" >&2
        exit 1
    fi
done
MARKETING_VERSION="$(plutil -extract CFBundleShortVersionString raw "$ROOT/Resources/Info.plist")"
RELEASE_TAG="${RELEASE_TAG:-v$MARKETING_VERSION}"
python3 "$VALIDATOR" version \
    --info-plist "$ROOT/Resources/Info.plist" \
    --tag "$RELEASE_TAG"
python3 "$VALIDATOR" release-metadata \
    --info-plist "$ROOT/Resources/Info.plist" \
    --tag "$RELEASE_TAG" \
    --release-notes "$ROOT/RELEASE_NOTES.md" \
    --changelog "$ROOT/CHANGELOG.md"
if ! security find-identity -v -p codesigning | grep -Fq "\"$SIGN_IDENTITY\""; then
    echo "The requested Developer ID identity is not installed: $SIGN_IDENTITY" >&2
    exit 1
fi

BUNDLE_ID="$(plutil -extract CFBundleIdentifier raw "$ROOT/Resources/Info.plist")"
validate_provisioning_profile() (
    local profile_path="$1"
    local output_entitlements="${2:-}"
    local signed_entitlements="${3:-}"
    local signing_certificate="${4:-}"
    local decoded_profile
    local -a validator_args
    decoded_profile="$(mktemp /tmp/CornerFloat-profile.XXXXXX)"
    trap 'rm -f "$decoded_profile"' EXIT
    if ! security cms -D -i "$profile_path" >"$decoded_profile"; then
        echo "Could not decode Developer ID provisioning profile: $profile_path" >&2
        exit 1
    fi
    validator_args=(
        profile
        --profile-plist "$decoded_profile"
        --bundle-id "$BUNDLE_ID"
        --team-id "$EXPECTED_TEAM_ID"
    )
    if [[ -n "$output_entitlements" ]]; then
        validator_args+=(--write-signing-entitlements "$output_entitlements")
    fi
    if [[ -n "$signed_entitlements" ]]; then
        validator_args+=(--signed-entitlements-plist "$signed_entitlements")
    fi
    if [[ -n "$signing_certificate" ]]; then
        validator_args+=(--signing-certificate-der "$signing_certificate")
    fi
    python3 "$VALIDATOR" "${validator_args[@]}"
)
SIGNING_ENTITLEMENTS_FILE=""
PASSKEY_RELEASE_MODE="baseline"
cleanup_signing_entitlements() {
    if [[ -n "$SIGNING_ENTITLEMENTS_FILE" ]]; then
        rm -f "$SIGNING_ENTITLEMENTS_FILE"
    fi
}
trap cleanup_signing_entitlements EXIT
if [[ -n "$DEVELOPER_ID_PROVISIONING_PROFILE_FILE" ]]; then
    SIGNING_ENTITLEMENTS_FILE="$(mktemp /tmp/CornerFloat-signing-entitlements.XXXXXX)"
    validate_provisioning_profile \
        "$DEVELOPER_ID_PROVISIONING_PROFILE_FILE" \
        "$SIGNING_ENTITLEMENTS_FILE"
    chmod 600 "$SIGNING_ENTITLEMENTS_FILE"
    PASSKEY_RELEASE_MODE="passkey"
fi
if [[ ! -x "$SPARKLE_TOOLS/generate_appcast" || ! -x "$SPARKLE_TOOLS/sign_update" ]]; then
    echo "Sparkle release tools are missing. Run 'scripts/swiftpm.sh resolve' first." >&2
    exit 1
fi

KEY_MODULE_CACHE="$ROOT/.build/SparkleKeyModuleCache"
mkdir -p "$KEY_MODULE_CACHE"
KEY_SDK="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
if ! DERIVED_PUBLIC_KEY="$(
    SDKROOT="$KEY_SDK" \
    CLANG_MODULE_CACHE_PATH="$KEY_MODULE_CACHE" \
    SWIFT_MODULECACHE_PATH="$KEY_MODULE_CACHE" \
    swift "$ROOT/scripts/derive_sparkle_public_key.swift" "$SPARKLE_PRIVATE_KEY_FILE"
)"; then
    FALLBACK_KEY_SDK="${FALLBACK_SDKROOT:-/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk}"
    if [[ ! -d "$FALLBACK_KEY_SDK" || "$KEY_SDK" == "$FALLBACK_KEY_SDK" ]]; then
        exit 1
    fi
    DERIVED_PUBLIC_KEY="$(
        SDKROOT="$FALLBACK_KEY_SDK" \
        CLANG_MODULE_CACHE_PATH="$KEY_MODULE_CACHE" \
        SWIFT_MODULECACHE_PATH="$KEY_MODULE_CACHE" \
        swift "$ROOT/scripts/derive_sparkle_public_key.swift" "$SPARKLE_PRIVATE_KEY_FILE"
    )"
fi
if [[ "$DERIVED_PUBLIC_KEY" != "$SPARKLE_PUBLIC_KEY" ]]; then
    echo "SPARKLE_PUBLIC_KEY does not match SPARKLE_PRIVATE_KEY_FILE; refusing to publish an unusable update." >&2
    exit 1
fi

export SIGN_IDENTITY UPDATE_FEED_URL SPARKLE_PUBLIC_KEY
export DEVELOPER_ID_PROVISIONING_PROFILE_FILE SIGNING_ENTITLEMENTS_FILE
export CONFIGURATION=release
export UNIVERSAL=1
"$ROOT/scripts/build.sh"

APP="$ROOT/dist/CornerFloat.app"
ARCH="universal"
ZIP="$ROOT/dist/CornerFloat-macOS-$ARCH.zip"
VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")"
BUILD="$(plutil -extract CFBundleVersion raw "$APP/Contents/Info.plist")"

validate_app_signature() (
    local app_path="$1"
    local signature_info certificate_directory certificate_prefix leaf_certificate
    certificate_directory="$(mktemp -d /tmp/CornerFloat-signing-certificate.XXXXXX)"
    trap 'rm -rf "$certificate_directory"' EXIT
    codesign --verify --deep --strict --verbose=2 "$app_path"
    validate_bundle_architectures "$app_path"
    signature_info="$(codesign --display --verbose=4 "$app_path" 2>&1)"
    python3 "$VALIDATOR" signature \
        --identity "$SIGN_IDENTITY" \
        --require-runtime <<<"$signature_info"
    certificate_prefix="$certificate_directory/certificate"
    if ! codesign --display --extract-certificates "$certificate_prefix" \
        "$app_path" >/dev/null 2>&1; then
        echo "Could not extract the signing certificate from $app_path." >&2
        exit 1
    fi
    leaf_certificate="${certificate_prefix}0"
    if [[ ! -s "$leaf_certificate" ]]; then
        echo "Extracted signing certificate is missing or empty for $app_path." >&2
        exit 1
    fi
    validate_app_entitlements "$app_path" "$leaf_certificate"
)

validate_bundle_architectures() (
    local app_path="$1"
    local framework="$app_path/Contents/Frameworks/Sparkle.framework"
    local -a binaries=(
        "$app_path/Contents/MacOS/CornerFloat"
        "$framework/Versions/B/Sparkle"
        "$framework/Versions/B/Autoupdate"
        "$framework/Versions/B/Updater.app/Contents/MacOS/Updater"
        "$framework/Versions/B/XPCServices/Installer.xpc/Contents/MacOS/Installer"
        "$framework/Versions/B/XPCServices/Downloader.xpc/Contents/MacOS/Downloader"
    )
    local binary
    for binary in "${binaries[@]}"; do
        if [[ ! -f "$binary" ]]; then
            echo "Universal release Mach-O is missing: $binary" >&2
            exit 1
        fi
        xcrun lipo -archs "$binary" | python3 "$VALIDATOR" architecture-set \
            --label "$binary" \
            --required-architecture arm64 \
            --required-architecture x86_64
    done
)

validate_app_entitlements() (
    local app_path="$1"
    local signing_certificate="$2"
    local entitlements_plist embedded_profile passkey_policy
    entitlements_plist="$(mktemp /tmp/CornerFloat-signed-entitlements.XXXXXX)"
    trap 'rm -f "$entitlements_plist"' EXIT
    if ! codesign --display --entitlements :- "$app_path" \
        >"$entitlements_plist" 2>/dev/null; then
        echo "Could not read signed entitlements from $app_path." >&2
        exit 1
    fi
    embedded_profile="$app_path/Contents/embedded.provisionprofile"
    passkey_policy="forbidden"
    if [[ "$PASSKEY_RELEASE_MODE" == "passkey" ]]; then
        passkey_policy="required"
        if [[ ! -f "$embedded_profile" ]]; then
            echo "Passkey-enabled app is missing Contents/embedded.provisionprofile: $app_path" >&2
            exit 1
        fi
    elif [[ -e "$embedded_profile" ]]; then
        echo "Baseline app must not embed a Passkey provisioning profile: $app_path" >&2
        exit 1
    fi
    python3 "$VALIDATOR" entitlements \
        --entitlements-plist "$entitlements_plist" \
        --passkey-policy "$passkey_policy"
    if [[ "$PASSKEY_RELEASE_MODE" == "passkey" ]]; then
        validate_provisioning_profile \
            "$embedded_profile" \
            "" \
            "$entitlements_plist" \
            "$signing_certificate"
    fi
)

validate_zip_artifact() (
    local archive="$1"
    local staging
    staging="$(mktemp -d /tmp/CornerFloat-release-zip.XXXXXX)"
    trap 'rm -rf "$staging"' EXIT
    ditto -x -k "$archive" "$staging"
    if [[ ! -d "$staging/CornerFloat.app" ]]; then
        echo "Release zip does not contain CornerFloat.app: $archive" >&2
        exit 1
    fi
    local entry_count
    entry_count="$(find "$staging" -mindepth 1 -maxdepth 1 -print | wc -l | tr -d '[:space:]')"
    if [[ "$entry_count" != "1" ]]; then
        echo "Release zip contains unexpected top-level artifacts: $archive" >&2
        exit 1
    fi
    local archived_version archived_build
    archived_version="$(plutil -extract CFBundleShortVersionString raw "$staging/CornerFloat.app/Contents/Info.plist")"
    archived_build="$(plutil -extract CFBundleVersion raw "$staging/CornerFloat.app/Contents/Info.plist")"
    if [[ "$archived_version" != "$VERSION" || "$archived_build" != "$BUILD" ]]; then
        echo "Release zip is stale: found $archived_version ($archived_build), expected $VERSION ($BUILD)." >&2
        exit 1
    fi
    validate_app_signature "$staging/CornerFloat.app"
)

BUILT_FEED_URL="$(plutil -extract SUFeedURL raw "$APP/Contents/Info.plist")"
BUILT_PUBLIC_KEY="$(plutil -extract SUPublicEDKey raw "$APP/Contents/Info.plist")"
if [[ "$BUILT_FEED_URL" != "$UPDATE_FEED_URL" || "$BUILT_PUBLIC_KEY" != "$SPARKLE_PUBLIC_KEY" ]]; then
    echo "Built app update settings do not match the requested feed URL and Sparkle key." >&2
    exit 1
fi
if plutil -extract SUAllowsInsecureUpdate raw "$APP/Contents/Info.plist" >/dev/null 2>&1; then
    echo "Public releases must never contain SUAllowsInsecureUpdate." >&2
    exit 1
fi
validate_app_signature "$APP"
validate_zip_artifact "$ZIP"
echo "Release signature team verified: $EXPECTED_TEAM_ID"
echo "Release signing capability mode: $PASSKEY_RELEASE_MODE"

xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
validate_app_signature "$APP"
spctl --assess --type execute --verbose=2 "$APP"

rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
validate_zip_artifact "$ZIP"

DMG="$(SIGN_IDENTITY="$SIGN_IDENTITY" APP_PATH="$APP" "$ROOT/scripts/package-dmg.sh" | tail -n 1)"
EXPECTED_DMG="$ROOT/dist/CornerFloat-$VERSION-macOS-$ARCH.dmg"
if [[ "$DMG" != "$EXPECTED_DMG" || ! -f "$DMG" ]]; then
    echo "DMG packager returned an unexpected or stale artifact: $DMG" >&2
    exit 1
fi
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
hdiutil verify "$DMG"
codesign --verify --strict --verbose=2 "$DMG"
DMG_SIGNATURE_INFO="$(codesign --display --verbose=4 "$DMG" 2>&1)"
python3 "$VALIDATOR" signature \
    --identity "$SIGN_IDENTITY" <<<"$DMG_SIGNATURE_INFO"

UPDATES="$ROOT/dist/updates"
rm -rf "$UPDATES"
mkdir -p "$UPDATES"
UPDATE_ARCHIVE="$UPDATES/CornerFloat-$VERSION-$BUILD-macOS-$ARCH.zip"
cp "$ZIP" "$UPDATE_ARCHIVE"
cp "$ROOT/RELEASE_NOTES.md" "${UPDATE_ARCHIVE%.zip}.md"

APPCAST_ARGS=(
    --download-url-prefix "${DOWNLOAD_PREFIX%/}/"
    --embed-release-notes
    --versions "$BUILD"
    --ed-key-file "$SPARKLE_PRIVATE_KEY_FILE"
)
"$SPARKLE_TOOLS/generate_appcast" "${APPCAST_ARGS[@]}" "$UPDATES"
APPCAST_SIGNATURE="$(python3 "$ROOT/scripts/validate_release.py" appcast \
    --appcast "$UPDATES/appcast.xml" \
    --archive "$UPDATE_ARCHIVE" \
    --build "$BUILD" \
    --short-version "$VERSION" \
    --download-prefix "$DOWNLOAD_PREFIX" \
    --print-signature)"
"$SPARKLE_TOOLS/sign_update" \
    --verify \
    --ed-key-file "$SPARKLE_PRIVATE_KEY_FILE" \
    "$UPDATE_ARCHIVE" \
    "$APPCAST_SIGNATURE"
python3 "$ROOT/scripts/validate_release.py" appcast \
    --appcast "$UPDATES/appcast.xml" \
    --archive "$UPDATE_ARCHIVE" \
    --build "$BUILD" \
    --short-version "$VERSION" \
    --download-prefix "$DOWNLOAD_PREFIX"

CHECKSUM_MANIFEST="$ROOT/dist/SHA256SUMS.txt"
CHECKSUM_ASSETS=(
    "$DMG"
    "$ZIP"
    "$UPDATE_ARCHIVE"
    "${UPDATE_ARCHIVE%.zip}.md"
    "$UPDATES/appcast.xml"
    "$ROOT/PRIVACY.md"
    "$ROOT/SUPPORT.md"
)
python3 "$ROOT/scripts/release_checksums.py" generate \
    --output "$CHECKSUM_MANIFEST" \
    "${CHECKSUM_ASSETS[@]}"
python3 "$ROOT/scripts/release_checksums.py" verify \
    --manifest "$CHECKSUM_MANIFEST" \
    --exact \
    "${CHECKSUM_ASSETS[@]}"

echo "Signed app: $APP"
echo "Notarized DMG: $DMG"
echo "Sparkle appcast: $UPDATES/appcast.xml"
echo "Release checksums: $CHECKSUM_MANIFEST"
