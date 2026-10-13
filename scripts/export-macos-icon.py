#!/usr/bin/env python3
"""Export the selected square PNG master to a macOS icon using system tools."""
from pathlib import Path
import argparse
import os
import shutil
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, default=ROOT / "design/brand/app-icon/minimal-wave-master.png")
    args = parser.parse_args()
    source = args.source.resolve()
    header = source.read_bytes()[:24]
    if len(header) != 24 or header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
        parser.error("Source must be a PNG image")
    width, height = struct.unpack(">II", header[16:24])
    if width != height or width < 1024:
        parser.error("Source must be square and at least 1024 pixels wide")
    destination = ROOT / "apps/macos/Resources/Aqmino.icns"
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="aqmino-icon-") as temporary:
        folder = Path(temporary)
        iconset = folder / "Aqmino.iconset"
        iconset.mkdir()
        for size in [16, 32, 128, 256, 512]:
            for scale in [1, 2]:
                pixels = size * scale
                suffix = "@2x" if scale == 2 else ""
                output = iconset / f"icon_{size}x{size}{suffix}.png"
                subprocess.run(["sips", "--resampleHeightWidth", str(pixels), str(pixels), str(source), "--out", str(output)], check=True, stdout=subprocess.DEVNULL)
        generated = folder / "Aqmino.icns"
        subprocess.run(["iconutil", "--convert", "icns", "--output", str(generated), str(iconset)], check=True)
        # Keep replacements atomic if a preview is already reading the resource.
        handle, staged = tempfile.mkstemp(prefix=".Aqmino-", suffix=".icns", dir=destination.parent)
        os.close(handle)
        try:
            shutil.copy2(generated, staged)
            os.replace(staged, destination)
        finally:
            if os.path.exists(staged):
                os.unlink(staged)
    print(destination)

if __name__ == "__main__":
    main()
