#!/usr/bin/env python3
"""Check real SwiftUI settings loading in hidden windows with isolated data."""
from pathlib import Path
import platform
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent

def main():
    core = ROOT / "packages/AqminoCore"
    subprocess.run(["swift", "build", "--package-path", str(core)], cwd=ROOT, check=True)
    binaries = Path(subprocess.check_output(["swift", "build", "--package-path", str(core), "--show-bin-path"], text=True).strip())
    output = ROOT / "build/checks/SettingsViewChecks"
    output.parent.mkdir(parents=True, exist_ok=True)
    sources = [
        "scripts/AppModelTestPlatform.swift",
        "apps/macos/Sources/App/AppModel.swift", "apps/macos/Sources/App/StateCoordinator.swift",
        "apps/macos/Sources/Platform/FileStateStore.swift", "apps/macos/Sources/UI/AppStyle.swift",
        "apps/macos/Sources/Features/Settings/SettingsDraft.swift",
        "apps/macos/Sources/Features/Settings/SettingsView.swift",
        "apps/macos/Sources/Features/Settings/SupportView.swift",
        "apps/macos/Sources/Features/Hydration/HydrationHistoryView.swift",
        "apps/macos/Sources/Features/Reminders/ReminderSettingsView.swift",
        "apps/macos/Sources/Features/Reminders/InlineReminderView.swift",
        "apps/macos/Tests/Standalone/SettingsViewChecks.swift",
    ]
    subprocess.run(["swiftc", "-swift-version", "5", "-parse-as-library",
                    "-target", f"{platform.machine()}-apple-macosx13.0", "-I", str(binaries / "Modules"),
                    *[str(ROOT / path) for path in sources],
                    *[str(path) for path in sorted((binaries / "AqminoCore.build").glob("*.o"))],
                    "-o", str(output)], cwd=ROOT, check=True)
    subprocess.run([str(output)], cwd=ROOT, check=True, timeout=15)

if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        sys.exit(error.returncode)
