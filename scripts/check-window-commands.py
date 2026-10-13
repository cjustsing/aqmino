#!/usr/bin/env python3
"""Exercise the production Cmd+W menu command in a hidden AppKit window."""
from pathlib import Path
import platform
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent


def main():
    core = ROOT / "packages/AqminoCore"
    subprocess.run(["swift", "build", "--package-path", str(core)], cwd=ROOT, check=True)
    binaries = Path(subprocess.check_output(["swift", "build", "--package-path", str(core), "--show-bin-path"], text=True).strip())
    directory = ROOT / "build/checks"
    directory.mkdir(parents=True, exist_ok=True)
    entry = (ROOT / "apps/macos/Sources/App/AqminoApp.swift").read_text()
    marker = "@MainActor\nfinal class AqminoAppDelegate"
    assert entry.count(marker) == 1 and entry.count("private func makeMainMenu()") == 1
    # Remove the executable entry point and expose only the factory to the check.
    # The menu implementation remains the current production source, unchanged.
    extracted = directory / "WindowCommandAppDelegate.swift"
    extracted.write_text("import AppKit\nimport AqminoCore\n\n" + (marker + entry.split(marker, 1)[1]).replace("private func makeMainMenu()", "func makeMainMenu()"))
    excluded = {
        "App/AqminoApp.swift", "Platform/NotificationAdapter.swift", "Platform/LoginItemController.swift",
        "Platform/ReminderScheduler.swift", "Platform/SystemEventObserver.swift",
    }
    sources_root = ROOT / "apps/macos/Sources"
    sources = [p for p in sorted(sources_root.rglob("*.swift")) if str(p.relative_to(sources_root)) not in excluded]
    sources.extend([ROOT / "scripts/AppModelTestPlatform.swift", extracted,
                    ROOT / "apps/macos/Tests/Standalone/WindowCommandsChecks.swift"])
    output = directory / "WindowCommandsChecks"
    subprocess.run(["swiftc", "-swift-version", "5", "-DDEBUG", "-parse-as-library",
                    "-target", f"{platform.machine()}-apple-macosx13.0", "-I", str(binaries / "Modules"),
                    *map(str, sources), *map(str, sorted((binaries / "AqminoCore.build").glob("*.o"))),
                    "-o", str(output)], cwd=ROOT, check=True)
    subprocess.run([str(output)], cwd=ROOT, check=True, timeout=15)


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        sys.exit(error.returncode)
