#!/usr/bin/env python3
"""Build a local .app without requiring Xcode. No global toolchain changes."""
from pathlib import Path
import argparse
import os
import plistlib
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--configuration", choices=["debug", "release"], default="debug")
    parser.add_argument("--open", action="store_true")
    args = parser.parse_args()
    package = ROOT / "apps/macos"
    info = plistlib.loads((package / "Configuration/Info.plist").read_bytes())
    icon = info.get("CFBundleIconFile")
    if not icon or not (package / "Resources" / icon).is_file():
        parser.error("Application icon is missing; run python3 scripts/export-macos-icon.py first")
    subprocess.run(["swift", "build", "--package-path", str(package), "-c", args.configuration], check=True)
    binary_path = Path(subprocess.check_output(["swift", "build", "--package-path", str(package), "-c", args.configuration, "--show-bin-path"], text=True).strip())
    app = ROOT / "build/macos/Aqmino.app"
    contents = app / "Contents"
    (contents / "MacOS").mkdir(parents=True, exist_ok=True)
    (contents / "Resources").mkdir(exist_ok=True)
    # Replacing the inode preserves a running preview's executable mapping.
    handle, temporary = tempfile.mkstemp(prefix="Aqmino-", dir=contents / "MacOS")
    os.close(handle)
    try:
        shutil.copy2(binary_path / "Aqmino", temporary)
        os.replace(temporary, contents / "MacOS/Aqmino")
    finally:
        if os.path.exists(temporary): os.unlink(temporary)
    shutil.copy2(package / "Configuration/Info.plist", contents / "Info.plist")
    for resource in (package / "Resources").iterdir():
        if resource.name.startswith("."):
            continue
        destination = contents / "Resources" / resource.name
        if resource.is_dir():
            shutil.copytree(resource, destination, dirs_exist_ok=True)
        else:
            shutil.copy2(resource, destination)
    for notice in ("LICENSE", "NOTICE"):
        shutil.copy2(ROOT / notice, contents / "Resources" / f"{notice}.txt")
    # Launch Services uses the bundle timestamp to notice updated icon metadata.
    os.utime(app, None)
    subprocess.run(["codesign", "--force", "--sign", "-", str(app)], check=True)
    subprocess.run(["codesign", "--verify", "--strict", str(app)], check=True)
    print(app)
    if args.open:
        subprocess.run(["open", str(app)], check=True)

if __name__ == "__main__":
    main()
