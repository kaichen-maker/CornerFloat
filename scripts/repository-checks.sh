#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_RESOURCES="$ROOT/dist/CornerFloat.app/Contents/Resources"

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

echo "CornerFloat repository checks OK: community files, static checks, bundled licenses, and retired mirroring surface absent"
