#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

"$ROOT/scripts/doctor.sh"

printf '\nResolving pinned Swift dependencies...\n'
"$ROOT/scripts/swiftpm.sh" resolve

printf '\nCornerFloat is ready for development. Next run:\n'
printf '  make build\n'
printf '  make test\n'
