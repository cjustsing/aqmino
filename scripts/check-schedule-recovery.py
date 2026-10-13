#!/usr/bin/env python3
"""Check lifecycle recovery with real native observers/timers and isolated data."""
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent


def main():
    core = ROOT / "packages/AqminoCore"
    subprocess.run(["swift", "build", "--package-path", str(core)], cwd=ROOT, check=True)
    binaries = Path(subprocess.check_output(
        ["swift", "build", "--package-path", str(core), "--show-bin-path"], text=True).strip())
    output = ROOT / "build/checks"
    output.mkdir(parents=True, exist_ok=True)
    # Reuse only the notification/login fakes. The lifecycle observer and timer
    # below are the exact adapters shipped in the app.
    replacements = (ROOT / "scripts/AppModelTestPlatform.swift").read_text()
    marker = "\n@MainActor\nfinal class ReminderScheduler"
    assert replacements.count(marker) == 1
    adapters = output / "RecoveryTestPlatform.swift"
    adapters.write_text(replacements.split(marker)[0])
    sources = [
        "scripts/StandaloneTestSupport.swift",
        "apps/macos/Sources/App/AppModel.swift",
        "apps/macos/Sources/App/StateCoordinator.swift",
        "apps/macos/Sources/Platform/FileStateStore.swift",
        "apps/macos/Sources/Platform/ReminderScheduler.swift",
        "apps/macos/Sources/Platform/SystemEventObserver.swift",
        "apps/macos/Sources/UI/AppStyle.swift",
        "apps/macos/Sources/Features/Settings/SettingsDraft.swift",
        "apps/macos/Tests/Standalone/ScheduleRecoveryChecks.swift",
    ]
    executable = output / "ScheduleRecoveryChecks"
    subprocess.run([
        "swiftc", "-swift-version", "5", "-parse-as-library", "-I", str(binaries / "Modules"),
        str(adapters), *[str(ROOT / path) for path in sources],
        *[str(path) for path in sorted((binaries / "AqminoCore.build").glob("*.o"))],
        "-o", str(executable),
    ], cwd=ROOT, check=True)
    subprocess.run([str(executable)], cwd=ROOT, check=True)


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        sys.exit(error.returncode)
