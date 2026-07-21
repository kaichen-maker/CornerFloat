#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPARKLE_ROOT="$ROOT/.build/artifacts/sparkle/Sparkle"
SPARKLE_TOOLS="$SPARKLE_ROOT/bin"
SPARKLE_FRAMEWORK_DIR="$SPARKLE_ROOT/Sparkle.xcframework/macos-arm64_x86_64"
SPARKLE_FRAMEWORK="$SPARKLE_FRAMEWORK_DIR/Sparkle.framework"
SPARKLE_CHECKOUT="$ROOT/.build/checkouts/Sparkle"
VALIDATOR="$ROOT/scripts/validate_release.py"
EXPECTED_SPARKLE_VERSION="2.9.4"

fail() {
    echo "CornerFloat Sparkle E2E failed: $*" >&2
    exit 1
}

for tool in bash base64 clang codesign curl ditto head plutil python3 shasum swift; do
    command -v "$tool" >/dev/null 2>&1 || fail "required tool is missing: $tool"
done

for path in \
    "$SPARKLE_TOOLS/generate_appcast" \
    "$SPARKLE_TOOLS/sign_update" \
    "$SPARKLE_FRAMEWORK" \
    "$SPARKLE_CHECKOUT/sparkle-cli/main.m" \
    "$SPARKLE_CHECKOUT/sparkle-cli/SPUCommandLineDriver.m" \
    "$SPARKLE_CHECKOUT/sparkle-cli/SPUCommandLineUserDriver.m"; do
    [[ -e "$path" ]] || fail "Sparkle 2.9.4 artifact is missing: $path"
done

RESOLVED_SPARKLE_VERSION="$(python3 - "$ROOT/Package.resolved" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as stream:
    package = json.load(stream)
for pin in package.get("pins", []):
    if pin.get("identity") == "sparkle":
        print(pin.get("state", {}).get("version", ""))
        break
PY
)"
[[ "$RESOLVED_SPARKLE_VERSION" == "$EXPECTED_SPARKLE_VERSION" ]] \
    || fail "expected Sparkle $EXPECTED_SPARKLE_VERSION, Package.resolved has ${RESOLVED_SPARKLE_VERSION:-no version}"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/CornerFloat-sparkle-e2e.XXXXXX")"
PRIVATE_KEY="$WORK/ephemeral-ed25519.key"
SERVER_PID=""
INSTALL_PID=""
touch "$WORK/.cornerfloat-sparkle-e2e-root"

cleanup() {
    local status=$?
    trap - EXIT INT TERM
    if [[ -n "$INSTALL_PID" ]] && kill -0 "$INSTALL_PID" 2>/dev/null; then
        kill "$INSTALL_PID" 2>/dev/null || true
        wait "$INSTALL_PID" 2>/dev/null || true
    fi
    if [[ -n "$SERVER_PID" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi

    # The test key is never imported into Keychain. Remove it even when the
    # caller asks to retain non-secret diagnostics from a failed run.
    rm -f "$PRIVATE_KEY"
    if [[ "${KEEP_SPARKLE_E2E_TEMP:-0}" == "1" ]]; then
        echo "Sparkle E2E diagnostics retained without the private key: $WORK" >&2
    elif [[ -f "$WORK/.cornerfloat-sparkle-e2e-root" ]]; then
        rm -rf "$WORK"
    fi
    exit "$status"
}
trap cleanup EXIT INT TERM

mkdir -p \
    "$WORK/home" \
    "$WORK/tmp" \
    "$WORK/modules" \
    "$WORK/feed" \
    "$WORK/new-dist" \
    "$WORK/ordinary-dist" \
    "$WORK/old-dist"
export HOME="$WORK/home"
export CFFIXED_USER_HOME="$WORK/home"
export TMPDIR="$WORK/tmp"
export CLANG_MODULE_CACHE_PATH="$WORK/modules"
export SWIFT_MODULECACHE_PATH="$WORK/modules"
umask 077

echo "[1/9] Creating an ephemeral Ed25519 seed outside Keychain"
head -c 32 /dev/urandom | base64 > "$PRIVATE_KEY"
chmod 600 "$PRIVATE_KEY"

derive_public_key() {
    local sdk fallback
    sdk="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
    if SDKROOT="$sdk" swift "$ROOT/scripts/derive_sparkle_public_key.swift" "$PRIVATE_KEY"; then
        return
    fi
    fallback="${FALLBACK_SDKROOT:-/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk}"
    [[ -d "$fallback" && "$fallback" != "$sdk" ]] \
        || fail "unable to derive the temporary Sparkle public key"
    SDKROOT="$fallback" swift "$ROOT/scripts/derive_sparkle_public_key.swift" "$PRIVATE_KEY"
}

PUBLIC_KEY="$(derive_public_key)"
[[ -n "$PUBLIC_KEY" ]] || fail "derived public key is empty"

PORT="$(python3 - <<'PY'
import socket

with socket.socket() as server:
    server.bind(("127.0.0.1", 0))
    print(server.getsockname()[1])
PY
)"
HTTP_PREFIX="http://127.0.0.1:$PORT"
TEST_FEED_URL="$HTTP_PREFIX/appcast.xml"

echo "[2/9] Building the current app with a guarded loopback test feed"
DIST_DIR="$WORK/new-dist" \
UPDATE_FEED_URL="$TEST_FEED_URL" \
SPARKLE_PUBLIC_KEY="$PUBLIC_KEY" \
ALLOW_INSECURE_LOCAL_UPDATE_TEST="1" \
SIGN_IDENTITY="-" \
    "$ROOT/scripts/build.sh" >/dev/null

NEW_APP="$WORK/new-dist/CornerFloat.app"
[[ -d "$NEW_APP" ]] || fail "isolated current app was not built"
NEW_VERSION="$(plutil -extract CFBundleShortVersionString raw "$NEW_APP/Contents/Info.plist")"
NEW_BUILD="$(plutil -extract CFBundleVersion raw "$NEW_APP/Contents/Info.plist")"
[[ "$NEW_BUILD" =~ ^[1-9][0-9]*$ ]] || fail "current build is not a positive integer: $NEW_BUILD"
(( NEW_BUILD > 1 )) || fail "current build must be greater than 1 for the old-version fixture"
OLD_BUILD="$((NEW_BUILD - 1))"
OLD_VERSION="0.4.9"

BUILT_PUBLIC_KEY="$(plutil -extract SUPublicEDKey raw "$NEW_APP/Contents/Info.plist")"
BUILT_FEED_URL="$(plutil -extract SUFeedURL raw "$NEW_APP/Contents/Info.plist")"
BUILT_INSECURE_TEST_FLAG="$(plutil -extract SUAllowsInsecureUpdate raw "$NEW_APP/Contents/Info.plist")"
[[ "$BUILT_PUBLIC_KEY" == "$PUBLIC_KEY" \
    && "$BUILT_FEED_URL" == "$TEST_FEED_URL" \
    && "$BUILT_INSECURE_TEST_FLAG" == "true" ]] \
    || fail "the isolated app does not contain the temporary test update identity"

echo "[3/9] Proving normal and release-template builds cannot carry the insecure flag"
if plutil -extract SUAllowsInsecureUpdate raw "$ROOT/Resources/Info.plist" >/dev/null 2>&1; then
    fail "Resources/Info.plist must never contain SUAllowsInsecureUpdate"
fi
DIST_DIR="$WORK/ordinary-dist" SIGN_IDENTITY="-" "$ROOT/scripts/build.sh" >/dev/null
ORDINARY_INFO="$WORK/ordinary-dist/CornerFloat.app/Contents/Info.plist"
if plutil -extract SUAllowsInsecureUpdate raw "$ORDINARY_INFO" >/dev/null 2>&1; then
    fail "an ordinary build unexpectedly contains SUAllowsInsecureUpdate"
fi
if plutil -extract SUFeedURL raw "$ORDINARY_INFO" >/dev/null 2>&1 \
    || plutil -extract SUPublicEDKey raw "$ORDINARY_INFO" >/dev/null 2>&1; then
    fail "an ordinary build unexpectedly contains a configured update identity"
fi

echo "[4/9] Preparing old build $OLD_BUILD and signed new build $NEW_BUILD"
OLD_APP="$WORK/old-dist/CornerFloat.app"
ditto "$NEW_APP" "$OLD_APP"
plutil -replace CFBundleShortVersionString -string "$OLD_VERSION" "$OLD_APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$OLD_BUILD" "$OLD_APP/Contents/Info.plist"
codesign --force --deep --sign - "$OLD_APP" >/dev/null
codesign --verify --deep --strict "$OLD_APP"

ARCH="$(uname -m)"
UPDATE_ARCHIVE="$WORK/feed/CornerFloat-$NEW_VERSION-$NEW_BUILD-macOS-$ARCH.zip"
ditto -c -k --sequesterRsrc --keepParent "$NEW_APP" "$UPDATE_ARCHIVE"
cp "$ROOT/RELEASE_NOTES.md" "${UPDATE_ARCHIVE%.zip}.md"

echo "[5/9] Generating and independently verifying the Sparkle appcast signature"
"$SPARKLE_TOOLS/generate_appcast" \
    --download-url-prefix "$HTTP_PREFIX/" \
    --embed-release-notes \
    --versions "$NEW_BUILD" \
    --ed-key-file "$PRIVATE_KEY" \
    "$WORK/feed" >/dev/null

APPCAST="$WORK/feed/appcast.xml"
[[ -f "$APPCAST" ]] || fail "Sparkle did not generate appcast.xml"
APPCAST_SIGNATURE="$(python3 "$VALIDATOR" appcast \
    --appcast "$APPCAST" \
    --archive "$UPDATE_ARCHIVE" \
    --build "$NEW_BUILD" \
    --short-version "$NEW_VERSION" \
    --download-prefix "$HTTP_PREFIX" \
    --allow-local-test-url \
    --print-signature)"
"$SPARKLE_TOOLS/sign_update" \
    --verify \
    --ed-key-file "$PRIVATE_KEY" \
    "$UPDATE_ARCHIVE" \
    "$APPCAST_SIGNATURE" >/dev/null

TAMPERED_ARCHIVE="$WORK/tampered-update.zip"
cp "$UPDATE_ARCHIVE" "$TAMPERED_ARCHIVE"
printf 'tamper' >> "$TAMPERED_ARCHIVE"
if "$SPARKLE_TOOLS/sign_update" \
    --verify \
    --ed-key-file "$PRIVATE_KEY" \
    "$TAMPERED_ARCHIVE" \
    "$APPCAST_SIGNATURE" >/dev/null 2>&1; then
    fail "Sparkle accepted a deliberately modified update archive"
fi
rm -f "$TAMPERED_ARCHIVE"

echo "[6/9] Building Sparkle's official sparkle-cli tester from the pinned checkout"
SPARKLE_CLI="$WORK/sparkle-cli"
clang \
    -fobjc-arc \
    -fmodules \
    -mmacosx-version-min=14.0 \
    '-DSPU_OBJC_DIRECT=__attribute__((objc_direct))' \
    '-DSPU_OBJC_DIRECT_MEMBERS=__attribute__((objc_direct_members))' \
    -F "$SPARKLE_FRAMEWORK_DIR" \
    -framework Sparkle \
    -framework AppKit \
    "$SPARKLE_CHECKOUT/sparkle-cli/main.m" \
    "$SPARKLE_CHECKOUT/sparkle-cli/SPUCommandLineDriver.m" \
    "$SPARKLE_CHECKOUT/sparkle-cli/SPUCommandLineUserDriver.m" \
    "-Wl,-rpath,$SPARKLE_FRAMEWORK_DIR" \
    -o "$SPARKLE_CLI"

echo "[7/9] Serving the feed on an ephemeral loopback-only HTTP endpoint"
python3 -m http.server "$PORT" \
    --bind 127.0.0.1 \
    --directory "$WORK/feed" \
    >"$WORK/http-server.log" 2>&1 &
SERVER_PID=$!

server_ready=0
for ((attempt = 0; attempt < 50; attempt++)); do
    if curl --fail --silent --show-error "$HTTP_PREFIX/appcast.xml" >/dev/null 2>&1; then
        server_ready=1
        break
    fi
    sleep 0.1
done
[[ "$server_ready" == "1" ]] || fail "loopback update server did not become ready"

echo "[8/9] Asking Sparkle to read the app's feed/key and select build $NEW_BUILD over $OLD_BUILD"
PROBE_LOG="$WORK/sparkle-probe.log"
set +e
"$SPARKLE_CLI" "$OLD_APP" \
    --probe \
    --user-agent-name CornerFloatSparkleE2ETest \
    --verbose >"$PROBE_LOG" 2>&1
PROBE_STATUS=$?
set -e
if [[ "$PROBE_STATUS" != "0" ]] || ! grep -Fq "Update available!" "$PROBE_LOG"; then
    sed -n '1,160p' "$PROBE_LOG" >&2
    fail "Sparkle did not select the newer appcast item (exit $PROBE_STATUS)"
fi

if [[ "${SPARKLE_E2E_PROBE_ONLY:-0}" == "1" ]]; then
    echo "CornerFloat Sparkle E2E OK (probe-only): official Sparkle read SUFeedURL/SUPublicEDKey from the app, selected $NEW_VERSION ($NEW_BUILD), and EdDSA accepted only the untouched archive"
    exit 0
fi

echo "[9/9] Downloading, verifying, extracting, and installing through Sparkle"
INSTALL_LOG="$WORK/sparkle-install.log"
"$SPARKLE_CLI" "$OLD_APP" \
    --check-immediately \
    --user-agent-name CornerFloatSparkleE2ETest \
    --verbose >"$INSTALL_LOG" 2>&1 &
INSTALL_PID=$!

install_timed_out=1
for ((attempt = 0; attempt < 1200; attempt++)); do
    if ! kill -0 "$INSTALL_PID" 2>/dev/null; then
        install_timed_out=0
        break
    fi
    sleep 0.1
done
if [[ "$install_timed_out" == "1" ]]; then
    kill "$INSTALL_PID" 2>/dev/null || true
    wait "$INSTALL_PID" 2>/dev/null || true
    INSTALL_PID=""
    sed -n '1,220p' "$INSTALL_LOG" >&2
    fail "Sparkle installation did not finish within 120 seconds"
fi

set +e
wait "$INSTALL_PID"
INSTALL_STATUS=$?
set -e
INSTALL_PID=""
if [[ "$INSTALL_STATUS" != "0" ]]; then
    sed -n '1,220p' "$INSTALL_LOG" >&2
    fail "Sparkle installation exited with status $INSTALL_STATUS"
fi

INSTALLED_VERSION="$(plutil -extract CFBundleShortVersionString raw "$OLD_APP/Contents/Info.plist")"
INSTALLED_BUILD="$(plutil -extract CFBundleVersion raw "$OLD_APP/Contents/Info.plist")"
if [[ "$INSTALLED_VERSION" != "$NEW_VERSION" || "$INSTALLED_BUILD" != "$NEW_BUILD" ]]; then
    sed -n '1,220p' "$INSTALL_LOG" >&2
    fail "installed bundle is $INSTALLED_VERSION ($INSTALLED_BUILD), expected $NEW_VERSION ($NEW_BUILD)"
fi

for phase in "Downloading Update" "Extracting Update" "Installing Update"; do
    grep -Fq "$phase" "$INSTALL_LOG" \
        || fail "Sparkle did not report the expected '$phase' phase"
done
codesign --verify --deep --strict "$OLD_APP"
NEW_EXECUTABLE_HASH="$(shasum -a 256 "$NEW_APP/Contents/MacOS/CornerFloat" | awk '{print $1}')"
INSTALLED_EXECUTABLE_HASH="$(shasum -a 256 "$OLD_APP/Contents/MacOS/CornerFloat" | awk '{print $1}')"
[[ "$INSTALLED_EXECUTABLE_HASH" == "$NEW_EXECUTABLE_HASH" ]] \
    || fail "installed executable does not match the signed update archive"

echo "CornerFloat Sparkle E2E OK: official Sparkle read SUFeedURL/SUPublicEDKey from the app, selected, downloaded, EdDSA-verified, extracted, and installed $NEW_VERSION ($NEW_BUILD) over $OLD_VERSION ($OLD_BUILD); tampering was rejected; Keychain was not used"
