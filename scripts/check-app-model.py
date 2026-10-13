#!/usr/bin/env python3
"""Exercise the real AppModel queue and file store with test-only platform adapters."""
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent

def main():
    core = ROOT / "packages/AqminoCore"
    subprocess.run(["swift", "build", "--package-path", str(core)], cwd=ROOT, check=True)
    binaries = Path(subprocess.check_output(["swift", "build", "--package-path", str(core), "--show-bin-path"], text=True).strip())
    output = ROOT / "build/checks/AppModelChecks"
    output.parent.mkdir(parents=True, exist_ok=True)
    sources = [
        "scripts/StandaloneTestSupport.swift", "scripts/AppModelTestPlatform.swift",
        "apps/macos/Sources/App/AppModel.swift", "apps/macos/Sources/App/StateCoordinator.swift",
        "apps/macos/Sources/Platform/FileStateStore.swift", "apps/macos/Sources/UI/AppStyle.swift",
        "apps/macos/Sources/Features/Settings/SettingsDraft.swift",
        "apps/macos/Tests/Standalone/AppModelChecks.swift",
    ]
    subprocess.run(["swiftc", "-swift-version", "5", "-parse-as-library", "-I", str(binaries / "Modules"),
                    *[str(ROOT / path) for path in sources],
                    *[str(path) for path in sorted((binaries / "AqminoCore.build").glob("*.o"))],
                    "-o", str(output)], cwd=ROOT, check=True)
    subprocess.run([str(output)], cwd=ROOT, check=True)

if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        sys.exit(error.returncode)
