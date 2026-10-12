# Copyright (c) 2026 VitruvianSoftware
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
"""The Swift tool that `vitruvian-tool init --template swift` writes builds.

    swift_template_test.py <the vitruvian-tool program>

The command is run as a person would run it, against a copy of this package.
Then the `build.sh` it wrote is run as it stands, which is `swift build`: the
Swift toolchain of the Mac, not Bazel's. What that leaves in `tool/` must
pass `validate` and run under `run`.

Everything is inside one temporary folder, which is deleted at the end: the
copy of the package, the new tool, and a home and a temporary folder of their
own for `swift build`, so that it reads and writes nothing of the person's.
One thing escapes that: the Swift compiler makes an empty folder in the Mac's
own temporary folder whatever it is told. `sweep` takes away the ones this
build made.
The package has no dependency but itself, so nothing is fetched. Every program
started here has a time limit, and is killed with whatever it started when
the limit passes.
"""

import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
PACKAGE = os.path.dirname(HERE)

# What `swift build` reads of the package: its manifest, and every folder a
# target of that manifest names. SwiftPM refuses a package with one missing.
PACKAGE_PARTS = ["Package.swift", "Sources", "Tests", "samples"]

# Seconds. The build compiles the kit and the tool from nothing.
BUILD_LIMIT = 600
COMMAND_LIMIT = 30


def started(words, limit, env, cwd=None):
    """Runs a program to its end, or kills it and all it started when the
    limit passes. Gives its exit status, or None when it was killed, and
    what it printed."""
    process = subprocess.Popen(
        words,
        cwd=cwd,
        env=env,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        start_new_session=True,
    )
    try:
        printed, _ = process.communicate(timeout=limit)
        return process.returncode, printed
    except subprocess.TimeoutExpired:
        # Its own session, so its own process group: nothing else is in it.
        os.killpg(process.pid, signal.SIGKILL)
        printed, _ = process.communicate()
        return None, printed + f"\nkilled after {limit} seconds"


def swift_environment(root):
    """What `swift build` is given: a home and a temporary folder inside the
    test's own folder, so SwiftPM's caches, its configuration and the
    compiler's module cache land there and nowhere else."""
    home = os.path.join(root, "home")
    temporary = os.path.join(root, "tmp")
    modules = os.path.join(root, "modules")
    for folder in (home, temporary, modules):
        os.makedirs(folder)
    environment = {
        "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
        # Foundation asks this before the password database for the home
        # folder; SwiftPM puts `Library/Caches/org.swift.swiftpm` under it.
        "CFFIXED_USER_HOME": home,
        "HOME": home,
        "TMPDIR": temporary,
        "CLANG_MODULE_CACHE_PATH": modules,
    }
    # Which Xcode, when the machine says so by the environment.
    for name in ("DEVELOPER_DIR", "SDKROOT", "TOOLCHAINS"):
        if name in os.environ:
            environment[name] = os.environ[name]
    return environment


def check(root, command, problems):
    sdk = os.path.join(root, "vitruvian-sdk")
    os.makedirs(sdk)
    for part in PACKAGE_PARTS:
        source = os.path.join(PACKAGE, part)
        if os.path.isdir(source):
            shutil.copytree(source, os.path.join(sdk, part))
        else:
            shutil.copy(source, os.path.join(sdk, part))

    environment = swift_environment(root)
    folder = os.path.join(root, "fresh")
    status, printed = started(
        [
            command,
            "init",
            folder,
            "--id",
            "com.example.fresh",
            "--name",
            "Fresh",
            "--publisher",
            "Example",
            "--template",
            "swift",
            "--sdk",
            sdk,
        ],
        COMMAND_LIMIT,
        environment,
    )
    script = os.path.join(folder, "build.sh")
    if status != 0 or not os.access(script, os.X_OK):
        problems.append(f"init did not write the Swift template:\n{printed}")
        return

    began = time.monotonic()
    status, printed = started([script], BUILD_LIMIT, environment, cwd=root)
    print(f"build.sh: {time.monotonic() - began:.0f} seconds")
    tool = os.path.join(folder, "tool")
    program = os.path.join(tool, "bin", "tool")
    if status != 0 or not os.access(program, os.X_OK):
        problems.append(
            f"build.sh did not build the tool (status {status}):\n{printed[-6000:]}"
        )
        return
    if f"The folder to add to Vitruvian is {os.path.realpath(tool)}" not in printed:
        problems.append(f"build.sh does not name the folder to add:\n{printed[-2000:]}")
    # A tool's folder is what the app copies: the package's build output
    # must not be in it.
    inside = sorted(
        os.path.relpath(os.path.join(at, name), tool)
        for at, _, names in os.walk(tool)
        for name in names
    )
    if inside != ["bin/tool", "vitruvian-tool.json"]:
        problems.append(f"the built tool's folder holds more than a tool: {inside}")

    status, printed = started([command, "validate", tool], COMMAND_LIMIT, environment)
    if status != 0 or "ok       manifest: com.example.fresh 0.1.0" not in printed:
        problems.append(f"validate does not pass the built Swift tool:\n{printed}")
    status, printed = started(
        [command, "run", tool, "--command", "hello"], COMMAND_LIMIT, environment
    )
    if status != 0 or "ran      hello" not in printed or "run: OK" not in printed:
        problems.append(f"the built Swift tool does not run:\n{printed}")


def system_temp():
    """The Mac's own per-user temporary folder, whatever TMPDIR says."""
    # _CS_DARWIN_USER_TEMP_DIR, which Python has no name for.
    try:
        return os.path.realpath(os.confstr(65537))
    except (ValueError, OSError):
        return None


def swift_leftovers(folder):
    """The empty folders the Swift compiler leaves in the system temp folder.

    Each `swiftc` makes one, `TemporaryDirectory.XXXXXX` holding an empty
    `.keep-directory`, in the Mac's own temporary folder and not in TMPDIR,
    and does not always take it away again.
    """
    if not folder or not os.path.isdir(folder):
        return set()
    return {
        name for name in os.listdir(folder) if name.startswith("TemporaryDirectory.")
    }


def sweep(folder, before, began):
    """Deletes the leftovers this test's build made, and only those.

    A folder is taken for ours when it was not there before the build, was
    made after the test began, is ours, has been still for two seconds, and
    holds nothing but one empty `.keep-directory`. A compiler another build
    is running right now makes its own a moment before it uses it, so one
    that young is left alone.
    """
    for name in swift_leftovers(folder) - before:
        path = os.path.join(folder, name)
        try:
            about = os.lstat(path)
            marker = os.path.join(path, ".keep-directory")
            mine = about.st_uid == os.getuid() and not os.path.islink(path)
            young = time.time() - about.st_mtime < 2
            if not mine or young or about.st_birthtime < began:
                continue
            if os.listdir(path) != [".keep-directory"] or os.lstat(marker).st_size != 0:
                continue
            os.remove(marker)
            os.rmdir(path)
        except OSError:
            continue


def main(arguments):
    command = os.path.abspath(arguments[0])
    problems = []
    began = time.time() - 1
    system = system_temp()
    before = swift_leftovers(system)
    # Under Bazel this is the test's own temporary folder.
    root = tempfile.mkdtemp(
        prefix="vitruvian-swift-template-", dir=os.environ.get("TEST_TMPDIR")
    )
    try:
        check(root, command, problems)
    finally:
        shutil.rmtree(root, ignore_errors=True)
        if os.path.exists(root):
            problems.append(f"the test's folder was not deleted: {root}")
        time.sleep(2.1)
        sweep(system, before, began)

    for problem in problems:
        print(problem, file=sys.stderr)
    print("swift template: " + ("FAILED" if problems else "OK"))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
