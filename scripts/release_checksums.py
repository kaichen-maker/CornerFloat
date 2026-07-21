#!/usr/bin/env python3
"""Generate and verify a strict SHA-256 manifest for release assets."""

from __future__ import annotations

import argparse
import hashlib
import re
from pathlib import Path


MANIFEST_LINE = re.compile(r"([0-9a-f]{64})  ([^\r\n]+)")


def fail(message: str) -> None:
    raise SystemExit(f"Release checksum validation failed: {message}")


def asset_name(path: Path) -> str:
    name = path.name
    if not name or name in {".", ".."} or Path(name).name != name:
        fail(f"unsafe asset name: {name!r}")
    if any(character in name for character in ("/", "\\", "\r", "\n")):
        fail(f"unsafe asset name: {name!r}")
    return name


def digest(path: Path) -> str:
    if not path.is_file():
        fail(f"asset does not exist or is not a regular file: {path}")
    hasher = hashlib.sha256()
    try:
        with path.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                hasher.update(chunk)
    except OSError as error:
        fail(f"cannot read asset {path}: {error}")
    return hasher.hexdigest()


def indexed_assets(paths: list[Path]) -> dict[str, Path]:
    assets: dict[str, Path] = {}
    for path in paths:
        name = asset_name(path)
        if name in assets:
            fail(f"duplicate asset basename: {name}")
        assets[name] = path
    return assets


def parse_manifest(path: Path) -> dict[str, str]:
    if not path.is_file():
        fail(f"manifest does not exist or is not a regular file: {path}")
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeError) as error:
        fail(f"cannot read manifest {path}: {error}")
    if not lines:
        fail("manifest is empty")
    entries: dict[str, str] = {}
    for line_number, line in enumerate(lines, start=1):
        match = MANIFEST_LINE.fullmatch(line)
        if not match:
            fail(f"malformed manifest line {line_number}")
        expected_digest, name = match.groups()
        if asset_name(Path(name)) != name:
            fail(f"unsafe manifest asset name on line {line_number}: {name!r}")
        if name in entries:
            fail(f"duplicate manifest entry: {name}")
        entries[name] = expected_digest
    return entries


def generate(args: argparse.Namespace) -> None:
    assets = indexed_assets(args.files)
    output_name = asset_name(args.output)
    if output_name in assets:
        fail("the checksum manifest must not include itself")
    lines = [f"{digest(assets[name])}  {name}\n" for name in sorted(assets)]
    try:
        args.output.write_text("".join(lines), encoding="utf-8")
    except OSError as error:
        fail(f"cannot write manifest {args.output}: {error}")
    print(f"SHA-256 manifest written: {args.output} ({len(assets)} assets)")


def verify(args: argparse.Namespace) -> None:
    entries = parse_manifest(args.manifest)
    assets = indexed_assets(args.files)
    missing = sorted(set(assets) - set(entries))
    if missing:
        fail(f"manifest is missing required assets: {', '.join(missing)}")
    if args.exact and set(entries) != set(assets):
        unexpected = sorted(set(entries) - set(assets))
        fail(f"manifest contains unexpected assets: {', '.join(unexpected)}")
    for name in sorted(assets):
        actual = digest(assets[name])
        if actual != entries[name]:
            fail(
                f"SHA-256 mismatch for {name}: "
                f"manifest={entries[name]}, actual={actual}"
            )
    print(f"SHA-256 manifest OK: {len(assets)} verified asset(s)")


def main() -> None:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    generate_parser = subparsers.add_parser("generate")
    generate_parser.add_argument("--output", type=Path, required=True)
    generate_parser.add_argument("files", type=Path, nargs="+")
    generate_parser.set_defaults(handler=generate)

    verify_parser = subparsers.add_parser("verify")
    verify_parser.add_argument("--manifest", type=Path, required=True)
    verify_parser.add_argument("--exact", action="store_true")
    verify_parser.add_argument("files", type=Path, nargs="+")
    verify_parser.set_defaults(handler=verify)

    args = parser.parse_args()
    args.handler(args)


if __name__ == "__main__":
    main()
