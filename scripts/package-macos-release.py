#!/usr/bin/env python3
"""Package a verified, locally signed macOS preview with a SHA-256 checksum."""
from pathlib import Path
import hashlib
import json
import plistlib
import re
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parent.parent


def main():
    app = ROOT / "build/macos/Aqmino.app"
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    source_info = plistlib.loads((ROOT / "apps/macos/Configuration/Info.plist").read_bytes())
    if info != source_info:
        raise RuntimeError("Bundle metadata differs from the source; rebuild the application first")
    version = info["CFBundleShortVersionString"]
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise RuntimeError("Expected a three-component release version")
    executable = app / "Contents/MacOS" / info["CFBundleExecutable"]
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    architectures = subprocess.check_output(["lipo", "-archs", str(executable)], text=True).split()
    if architectures == ["arm64"]:
        architecture = "arm64"
    elif architectures == ["x86_64"]:
        architecture = "x86_64"
    elif set(architectures) == {"arm64", "x86_64"}:
        architecture = "universal"
    else:
        raise RuntimeError(f"Unsupported architectures: {architectures}")
    output = ROOT / "build/releases" / f"v{version}"
    output.mkdir(parents=True, exist_ok=True)
    archive = output / f"Aqmino-{version}-macos-{architecture}.zip"
    with tempfile.TemporaryDirectory(prefix="aqmino-release-") as temporary:
        temporary = Path(temporary)
        candidate = temporary / archive.name
        subprocess.run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(app), str(candidate)], check=True)
        with zipfile.ZipFile(candidate) as bundle:
            if bundle.testzip() is not None:
                raise RuntimeError("Release archive failed its integrity check")
        extracted = temporary / "extracted"
        subprocess.run(["ditto", "-x", "-k", str(candidate), str(extracted)], check=True)
        restored = extracted / app.name
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(restored)], check=True)
        for path in app.rglob("*"):
            if path.is_file():
                relative = path.relative_to(app)
                if path.read_bytes() != (restored / relative).read_bytes():
                    raise RuntimeError(f"Archive changed bundle file: {relative}")
        candidate.replace(archive)
    checksum = hashlib.sha256(archive.read_bytes()).hexdigest()
    checksums = output / "SHA256SUMS.txt"
    checksums.write_text(f"{checksum}  {archive.name}\n")
    metadata = output / "release-info.json"
    metadata.write_text(json.dumps({
        "version": version,
        "build": info["CFBundleVersion"],
        "architecture": architecture,
        "minimum_macos": info["LSMinimumSystemVersion"],
        "bundle_identifier": info["CFBundleIdentifier"],
        "signing": "ad-hoc",
        "notarized": False,
        "archive": archive.name,
        "sha256": checksum,
    }, indent=2) + "\n")
    print(archive)
    print(checksums)
    print(metadata)


if __name__ == "__main__":
    main()
