#!/usr/bin/env python3
"""Check the real login controller with a fake ServiceManagement boundary."""
from pathlib import Path
import platform
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent


def main():
    output = ROOT / "build/checks/login-item"
    output.mkdir(parents=True, exist_ok=True)
    source = ROOT / "apps/macos/Sources/Platform/LoginItemController.swift"
    # Keep the controller unchanged; substitute only the operating-system API.
    text = source.read_text()
    if text.count("import ServiceManagement\n") != 1:
        raise RuntimeError("Expected one ServiceManagement import in the controller")
    adapted = output / "LoginItemController.swift"
    adapted.write_text(text.replace("import ServiceManagement\n", ""))
    binary = output / "LoginItemChecks"
    subprocess.run([
        "swiftc", "-swift-version", "5", "-parse-as-library",
        "-target", f"{platform.machine()}-apple-macosx13.0",
        str(adapted), str(ROOT / "apps/macos/Tests/Standalone/LoginItemChecks.swift"),
        "-o", str(binary),
    ], check=True, cwd=ROOT)
    subprocess.run([str(binary)], check=True, cwd=ROOT, timeout=10)


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        sys.exit(error.returncode)
