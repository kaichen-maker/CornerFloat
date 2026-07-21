#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

"$ROOT/scripts/doctor.sh"

printf '\nResolving pinned Swift dependencies...\n'
"$ROOT/scripts/swiftpm.sh" resolve

printf '\nCornerFloat is ready. Choose the next step:\n'
printf '  Personal install:  make install\n'
printf '  Temporary run:     make run\n'
printf '  Contributor check: make check\n'
