#!/usr/bin/env python3
"""Build a modern PNG-backed .icns file without requiring a full Xcode install."""

from __future__ import annotations

import argparse
import struct
from pathlib import Path


PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"

# Apple icon-family element names. Retina element names intentionally share
# pixel dimensions with a lower-scale standard element.
ELEMENTS = (
    ("icp4", "icon_16x16.png", (16, 16)),
    ("icp5", "icon_32x32.png", (32, 32)),
    ("icp6", "icon_32x32@2x.png", (64, 64)),
    ("ic07", "icon_128x128.png", (128, 128)),
    ("ic08", "icon_256x256.png", (256, 256)),
    ("ic09", "icon_512x512.png", (512, 512)),
    ("ic10", "icon_512x512@2x.png", (1024, 1024)),
    ("ic11", "icon_16x16@2x.png", (32, 32)),
    ("ic12", "icon_32x32@2x.png", (64, 64)),
    ("ic13", "icon_128x128@2x.png", (256, 256)),
    ("ic14", "icon_256x256@2x.png", (512, 512)),
)


def png_size(data: bytes) -> tuple[int, int]:
    if not data.startswith(PNG_SIGNATURE) or data[12:16] != b"IHDR":
        raise ValueError("not a PNG file")
    return struct.unpack(">II", data[16:24])


def build(iconset: Path, output: Path) -> None:
    chunks: list[bytes] = []
    for element_name, filename, expected_size in ELEMENTS:
        data = (iconset / filename).read_bytes()
        actual_size = png_size(data)
        if actual_size != expected_size:
            raise ValueError(
                f"{filename} is {actual_size[0]}x{actual_size[1]}; "
                f"expected {expected_size[0]}x{expected_size[1]}"
            )
        chunks.append(struct.pack(">4sI", element_name.encode("ascii"), len(data) + 8) + data)

    payload = b"".join(chunks)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(struct.pack(">4sI", b"icns", len(payload) + 8) + payload)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("iconset", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    build(args.iconset, args.output)


if __name__ == "__main__":
    main()
