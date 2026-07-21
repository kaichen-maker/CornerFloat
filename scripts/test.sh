#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

"$ROOT/scripts/build.sh"
"$ROOT/scripts/repository-checks.sh"
"$ROOT/dist/CornerFloat.app/Contents/MacOS/CornerFloat" --self-test
"$ROOT/scripts/browser-tests.sh"
"$ROOT/scripts/download-transaction-tests.sh"
"$ROOT/scripts/passkey-tests.sh"
"$ROOT/scripts/webkit-integration-tests.sh"
python3 "$ROOT/scripts/release-validator-tests.py"
python3 "$ROOT/scripts/release-checksum-tests.py"
