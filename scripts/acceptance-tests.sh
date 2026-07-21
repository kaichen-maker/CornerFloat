#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ACCEPTANCE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/cornerfloat-acceptance.XXXXXX")"
ACCEPTANCE_HOME="$ACCEPTANCE_ROOT/home"
ACCEPTANCE_TMP="$ACCEPTANCE_ROOT/tmp"
ACCEPTANCE_DIST="$ACCEPTANCE_ROOT/dist"
mkdir -p "$ACCEPTANCE_HOME" "$ACCEPTANCE_TMP" "$ACCEPTANCE_DIST"

cleanup_acceptance_root() {
    rm -rf "$ACCEPTANCE_ROOT"
}
trap cleanup_acceptance_root EXIT INT TERM

APP="$ACCEPTANCE_DIST/CornerFloat.app"
BINARY="$APP/Contents/MacOS/CornerFloat"
ISOLATED_APP_ENV=(
    env
    HOME="$ACCEPTANCE_HOME"
    CFFIXED_USER_HOME="$ACCEPTANCE_HOME"
    TMPDIR="$ACCEPTANCE_TMP"
)

DIST_DIR="$ACCEPTANCE_DIST" "$ROOT/scripts/build.sh"

run_and_require() {
    local name="$1"
    local expected="$2"
    local maximum_seconds="$3"
    shift 3

    local log
    log="$(mktemp "${TMPDIR:-/tmp}/cornerfloat-acceptance.XXXXXX")"
    local pid=""
    cleanup_acceptance_process() {
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
        fi
        rm -f "$log"
    }
    trap cleanup_acceptance_process RETURN

    "$@" >"$log" 2>&1 &
    pid=$!
    local ticks=$((maximum_seconds * 10))
    local finished=0
    for ((attempt = 0; attempt < ticks; attempt += 1)); do
        if ! kill -0 "$pid" 2>/dev/null; then
            finished=1
            break
        fi
        sleep 0.1
    done
    if [[ "$finished" -ne 1 ]]; then
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
        cat "$log"
        echo "$name exceeded its ${maximum_seconds}s timeout." >&2
        exit 1
    fi

    set +e
    wait "$pid"
    local status=$?
    set -e
    pid=""
    cat "$log"
    if [[ "$status" -ne 0 ]] || ! grep -qF "$expected" "$log"; then
        echo "$name failed or omitted its success evidence (exit $status)." >&2
        exit 1
    fi
    trap - RETURN
    cleanup_acceptance_process
}

run_and_require \
    "Global hot-key acceptance" \
    "CornerFloat global-hotkey self-test OK" \
    10 \
    "${ISOLATED_APP_ENV[@]}" "$BINARY" --hotkey-self-test

run_and_require \
    "AppKit UI smoke test" \
    "CornerFloat UI smoke-test OK" \
    15 \
    "${ISOLATED_APP_ENV[@]}" "$BINARY" --ui-smoke-test

"${ISOLATED_APP_ENV[@]}" \
    CORNERFLOAT_LIFECYCLE_APP="$APP" \
    "$ROOT/scripts/lifecycle-diagnostics.sh"

echo "CornerFloat AppKit acceptance tests OK: global hot key, UI lifecycle, panel close, display rehome and idle energy"
