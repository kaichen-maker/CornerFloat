#!/usr/bin/env python3
"""Dependency-free repository checks that also work in a source archive."""

from __future__ import annotations

import ast
import re
import sys
from pathlib import Path
from urllib.parse import unquote, urlsplit


ROOT = Path(__file__).resolve().parent.parent
SKIPPED_PARTS = {".git", ".build", ".build-ci", "dist", "__pycache__"}
MARKDOWN_LINK = re.compile(r"!?\[[^\]]*\]\((<[^>]+>|[^\s)]+)(?:\s+[^)]*)?\)")


def repository_files(suffix: str) -> list[Path]:
    return sorted(
        path
        for path in ROOT.rglob(f"*{suffix}")
        if not SKIPPED_PARTS.intersection(path.relative_to(ROOT).parts)
    )


def check_python_syntax(errors: list[str]) -> None:
    for path in repository_files(".py"):
        try:
            ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
        except (OSError, SyntaxError, UnicodeError) as error:
            errors.append(f"invalid Python: {path.relative_to(ROOT)}: {error}")


def check_markdown_links(errors: list[str]) -> None:
    for path in repository_files(".md"):
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeError) as error:
            errors.append(f"unreadable Markdown: {path.relative_to(ROOT)}: {error}")
            continue
        for match in MARKDOWN_LINK.finditer(text):
            raw_target = match.group(1).strip("<>")
            if not raw_target or raw_target.startswith("#"):
                continue
            parsed = urlsplit(raw_target)
            if parsed.scheme or raw_target.startswith("//"):
                continue
            target_path = unquote(parsed.path)
            if not target_path:
                continue
            target = (path.parent / target_path).resolve()
            try:
                target.relative_to(ROOT)
            except ValueError:
                errors.append(
                    f"Markdown link escapes repository: {path.relative_to(ROOT)} -> {raw_target}"
                )
                continue
            if not target.exists():
                errors.append(
                    f"broken Markdown link: {path.relative_to(ROOT)} -> {raw_target}"
                )


def check_image_signatures(errors: list[str]) -> None:
    signatures = {
        ".png": (b"\x89PNG\r\n\x1a\n",),
        ".jpg": (b"\xff\xd8\xff",),
        ".jpeg": (b"\xff\xd8\xff",),
        ".gif": (b"GIF87a", b"GIF89a"),
    }
    for suffix, expected in signatures.items():
        for path in repository_files(suffix):
            try:
                header = path.read_bytes()[:16]
            except OSError as error:
                errors.append(f"unreadable image: {path.relative_to(ROOT)}: {error}")
                continue
            if not any(header.startswith(signature) for signature in expected):
                errors.append(
                    f"image contents do not match extension: {path.relative_to(ROOT)}"
                )


def main() -> int:
    errors: list[str] = []
    check_python_syntax(errors)
    check_markdown_links(errors)
    check_image_signatures(errors)
    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        return 1
    print("CornerFloat static checks OK: Python syntax, Markdown links, and image formats")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
