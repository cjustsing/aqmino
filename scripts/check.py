#!/usr/bin/env python3
"""Run standard XCTest with Xcode, or the same cases via a CLT assertion bridge."""
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent

def run(args):
    subprocess.run([str(a) for a in args], cwd=ROOT, check=True)

def main():
    has_xcode = subprocess.run(["xcodebuild", "-version"], capture_output=True).returncode == 0
    if has_xcode:
        run(["swift", "test", "--package-path", ROOT / "packages/AqminoCore"])
        run(["swift", "test", "--package-path", ROOT / "apps/macos"])
        return
    print("XCTest unavailable in Command Line Tools. Running the same test cases directly.", flush=True)
    package = ROOT / "packages/AqminoCore"
    run(["swift", "build", "--package-path", package])
    binary_path = Path(subprocess.check_output(["swift", "build", "--package-path", package, "--show-bin-path"], text=True).strip())
    tests = sorted((package / "Tests/AqminoCoreTests").glob("*.swift")) + sorted((ROOT / "apps/macos/Tests/Unit").glob("*.swift"))
    output = ROOT / "build/checks"; output.mkdir(parents=True, exist_ok=True)
    calls = []
    for test in tests:
        text = test.read_text()
        klass = re.search(r"final class (\w+): XCTestCase", text).group(1)
        for match in re.finditer(r"func (test\w+)\(\)\s*(async\s*)?(throws\s*)?\{", text):
            name, asynchronous, throwing = match.groups()
            invocation = ("try " if throwing else "") + ("await " if asynchronous else "") + f"test.{name}()"
            calls.append(f'''do {{
                let before = CheckLog.failures
                let test = {klass}()
                do {{ {invocation} }} catch {{ XCTFail("{name}: \\(error)") }}
                do {{ try test.tearDownWithError() }} catch {{ XCTFail("Teardown: \\(error)") }}
                if CheckLog.failures == before {{ passed += 1; print("PASS {name}") }}
            }}''')
    if not calls:
        raise RuntimeError("No tests discovered")
    runner = output / "CheckRunner.swift"
    runner.write_text("import Foundation\n@main struct CheckRunner { static func main() async { var passed = 0\n"
                      + "\n".join(calls)
                      + f'\nprint("\\(passed)/{len(calls)} cases passed; \\(CheckLog.failures) assertion failures")\n'
                      + "exit(CheckLog.failures == 0 ? 0 : 1) } }\n")
    objects = sorted((binary_path / "AqminoCore.build").glob("*.o"))
    if not objects:
        raise RuntimeError("Core object files are missing")
    run(["swiftc", "-swift-version", "5", "-D", "AQMINO_STANDALONE_CHECKS", "-parse-as-library", "-I", binary_path / "Modules",
         ROOT / "scripts/StandaloneTestSupport.swift", *tests,
         ROOT / "apps/macos/Sources/Platform/FileStateStore.swift", ROOT / "apps/macos/Sources/App/StateCoordinator.swift",
         ROOT / "apps/macos/Sources/Features/Settings/SettingsDraft.swift", ROOT / "apps/macos/Sources/UI/AppStyle.swift",
         ROOT / "apps/macos/Sources/Platform/NotificationAdapter.swift",
         *objects, runner, "-o", output / "AqminoChecks"])
    run([output / "AqminoChecks"])

if __name__ == "__main__":
    try:
        main()
    except (subprocess.CalledProcessError, RuntimeError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
