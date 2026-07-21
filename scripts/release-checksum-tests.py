#!/usr/bin/env python3
"""Focused regression tests for strict release checksum manifests."""

from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
CHECKSUMS = ROOT / "scripts" / "release_checksums.py"


def run(*arguments: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(CHECKSUMS), *arguments],
        check=False,
        capture_output=True,
        text=True,
    )


def require_success(result: subprocess.CompletedProcess[str], label: str) -> None:
    if result.returncode != 0:
        raise SystemExit(f"{label} failed: {result.stderr}")


def expect_failure(result: subprocess.CompletedProcess[str], fragment: str) -> None:
    if result.returncode == 0 or fragment not in result.stderr:
        raise SystemExit(
            f"expected checksum failure containing {fragment!r}; "
            f"returncode={result.returncode}, stderr={result.stderr!r}"
        )


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="CornerFloat-checksum-test-") as temporary:
        root = Path(temporary)
        appcast = root / "appcast.xml"
        archive = root / "CornerFloat-0.5.0-7-macOS-arm64.zip"
        manifest = root / "SHA256SUMS.txt"
        appcast.write_bytes(b"feed")
        archive.write_bytes(b"signed archive")

        require_success(
            run(
                "generate",
                "--output",
                str(manifest),
                str(archive),
                str(appcast),
            ),
            "manifest generation",
        )
        first_manifest = manifest.read_bytes()
        listed_names = [
            line.split("  ", maxsplit=1)[1]
            for line in manifest.read_text(encoding="utf-8").splitlines()
        ]
        if listed_names != sorted(listed_names):
            raise SystemExit(f"manifest entries are not sorted: {listed_names!r}")
        require_success(
            run(
                "generate",
                "--output",
                str(manifest),
                str(appcast),
                str(archive),
            ),
            "reverse-order manifest generation",
        )
        if manifest.read_bytes() != first_manifest:
            raise SystemExit("manifest output depends on the input argument order")
        require_success(
            run(
                "verify",
                "--manifest",
                str(manifest),
                "--exact",
                str(appcast),
                str(archive),
            ),
            "exact manifest verification",
        )

        archive.write_bytes(b"tampered archive")
        expect_failure(
            run("verify", "--manifest", str(manifest), str(archive)),
            "SHA-256 mismatch",
        )

        manifest.write_text("0" * 64 + "  ../escape.zip\n", encoding="utf-8")
        expect_failure(
            run("verify", "--manifest", str(manifest), str(archive)),
            "unsafe manifest asset name",
        )

        manifest.write_text(
            "0" * 64 + "  appcast.xml\n" + "1" * 64 + "  appcast.xml\n",
            encoding="utf-8",
        )
        expect_failure(
            run("verify", "--manifest", str(manifest), str(appcast)),
            "duplicate manifest entry",
        )

    print(
        "CornerFloat release-checksum tests OK: manifests are deterministic, "
        "tampering is rejected, and unsafe or duplicate names fail closed"
    )


if __name__ == "__main__":
    main()
