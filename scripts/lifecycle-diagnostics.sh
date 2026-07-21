#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${CORNERFLOAT_LIFECYCLE_APP:-}"
IDLE_SECONDS="${LIFECYCLE_IDLE_SECONDS:-5}"
CPU_LIMIT="${IDLE_CPU_LIMIT_PERCENT:-8}"
LOG="$(mktemp "${TMPDIR:-/tmp}/cornerfloat-lifecycle.XXXXXX")"
SAMPLES="$(mktemp "${TMPDIR:-/tmp}/cornerfloat-energy.XXXXXX")"
PID=""

cleanup() {
    if [[ -n "$PID" ]] && kill -0 "$PID" 2>/dev/null; then
        kill "$PID" 2>/dev/null || true
    fi
    rm -f "$LOG" "$SAMPLES"
}
trap cleanup EXIT INT TERM

if [[ -z "$APP" ]]; then
    "$ROOT/scripts/build.sh"
    APP="$ROOT/dist/CornerFloat.app"
fi
BINARY="$APP/Contents/MacOS/CornerFloat"
if [[ ! -x "$BINARY" ]]; then
    echo "Lifecycle diagnostic app is missing an executable: $BINARY" >&2
    exit 1
fi

"$BINARY" --lifecycle-diagnostics --idle-seconds="$IDLE_SECONDS" >"$LOG" 2>&1 &
PID=$!

ready=0
for ((attempt = 0; attempt < 120; attempt += 1)); do
    if grep -qF "CornerFloat lifecycle diagnostic idle-begin" "$LOG"; then
        ready=1
        break
    fi
    if ! kill -0 "$PID" 2>/dev/null; then
        break
    fi
    sleep 0.1
done

if [[ "$ready" -ne 1 ]]; then
    if kill -0 "$PID" 2>/dev/null; then
        kill "$PID" 2>/dev/null || true
    fi
    set +e
    wait "$PID"
    status=$?
    set -e
    cat "$LOG"
    echo "Lifecycle diagnostic did not reach the idle sampling phase (exit $status)." >&2
    exit 1
fi

for ((sample = 0; sample < 8; sample += 1)); do
    if ! kill -0 "$PID" 2>/dev/null; then
        break
    fi
    ps -p "$PID" -o %cpu= -o rss= | awk 'NF == 2 { print $1, $2 }' >>"$SAMPLES"
    sleep 0.4
done

finished=0
for ((attempt = 0; attempt < 300; attempt += 1)); do
    if ! kill -0 "$PID" 2>/dev/null; then
        finished=1
        break
    fi
    sleep 0.1
done
if [[ "$finished" -ne 1 ]]; then
    kill "$PID" 2>/dev/null || true
    wait "$PID" 2>/dev/null || true
    cat "$LOG"
    echo "Lifecycle diagnostic exceeded its 30 second completion timeout." >&2
    exit 1
fi

set +e
wait "$PID"
status=$?
set -e
PID=""
cat "$LOG"

if [[ "$status" -ne 0 ]]; then
    echo "Lifecycle diagnostic exited with status $status." >&2
    exit "$status"
fi

python3 - "$LOG" <<'PY'
import json
import sys

prefix = "CornerFloat lifecycle diagnostic OK: "
with open(sys.argv[1], encoding="utf-8") as stream:
    matches = [line[len(prefix):].strip() for line in stream if line.startswith(prefix)]
if len(matches) != 1:
    raise SystemExit("Lifecycle diagnostic must emit exactly one JSON report")
report = json.loads(matches[0])
required_true = {
    "rehomedOffscreenPanel": True,
    "finalEdgeAutoHidden": False,
}
for key, expected in required_true.items():
    if report.get(key) != expected:
        raise SystemExit(f"Lifecycle diagnostic {key} was {report.get(key)!r}, expected {expected!r}")
if report.get("screenCount", 0) < 1:
    raise SystemExit("Lifecycle diagnostic reported no screens")
if report.get("sleepNotifications", 0) < 1 or report.get("wakeNotifications", 0) < 1:
    raise SystemExit("Lifecycle diagnostic sleep/wake callbacks were incomplete")
if report.get("spaceNotifications", 0) < 1 or report.get("screenConfigurationCallbacks", 0) < 1:
    raise SystemExit("Lifecycle diagnostic Space/display callbacks were incomplete")
if report.get("visibilityCallbacks", 0) < 6:
    raise SystemExit("Lifecycle diagnostic visibility callbacks were incomplete")
if report.get("edgeCollapseCallbacks", 0) < 2:
    raise SystemExit("Lifecycle diagnostic edge collapse/reveal callbacks were incomplete")
behaviors = set(report.get("panelCollectionBehavior", []))
if not {"canJoinAllSpaces", "fullScreenAuxiliary"}.issubset(behaviors):
    raise SystemExit("Lifecycle diagnostic panel collection behavior is incomplete")
PY

if [[ ! -s "$SAMPLES" ]]; then
    echo "No idle energy samples were collected." >&2
    exit 1
fi

sample_count="$(wc -l <"$SAMPLES" | tr -d ' ')"
if [[ "$sample_count" -lt 3 ]]; then
    echo "Too few idle energy samples were collected: $sample_count." >&2
    exit 1
fi

average_cpu="$(awk '{ sum += $1; count += 1 } END { if (count) printf "%.2f", sum / count; else print "nan" }' "$SAMPLES")"
peak_cpu="$(awk 'BEGIN { peak = 0 } { if ($1 > peak) peak = $1 } END { printf "%.2f", peak }' "$SAMPLES")"
peak_rss_kb="$(awk 'BEGIN { peak = 0 } { if ($2 > peak) peak = $2 } END { print peak }' "$SAMPLES")"

if ! awk -v actual="$average_cpu" -v limit="$CPU_LIMIT" 'BEGIN { exit !(actual <= limit) }'; then
    echo "Idle CPU acceptance failed: average ${average_cpu}% exceeds ${CPU_LIMIT}%." >&2
    exit 1
fi

echo "CornerFloat idle energy diagnostic OK: averageCPU=${average_cpu}% peakCPU=${peak_cpu}% peakRSS=${peak_rss_kb}KB samples=$sample_count"
