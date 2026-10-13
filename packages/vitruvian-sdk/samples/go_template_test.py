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
"""The Go kit as a Go author meets it, with Bazel's own Go and no network.

    go_template_test.py <go> <go.mod> <the kit's .go files ...>

The kit's files are named by their paths, which keep their folder under
go/toolkit: the ui subpackage is vetted beside the kit.
                        [--tool <the vitruvian-tool program>]

The kit is copied into a temporary folder as a module of its own, outside
any workspace, and `go vet` is run on it there. vet holds the module to the
Go of its go.mod: a call the standard library gained after Go 1.22 fails it,
which Bazel's build of the kit does not see.

With --tool, the command then starts a tool with `init --template go --sdk`
pointed at that copy, runs the `build.sh` it wrote with this Go first on the
PATH, and holds `validate`, the conformance script and `run` to pass on what
was built. The kit is the copy and has no dependency, so nothing is fetched:
GOPROXY is off, and Go's caches are inside the temporary folder.
"""

import contextlib
import io
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
PACKAGE = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(PACKAGE, "conformance"))

import conformance  # noqa: E402

LIMIT = 300


def built_tool(tool, sdk, root, run):
    """The problems of a tool `init --template go` starts, built by its own
    build.sh; the first one found, as each step needs the one before."""
    folder = os.path.join(root, "fresh")
    named = ["--id", "com.example.fresh", "--name", "Fresh", "--publisher", "Example"]
    status, printed = run(
        [tool, "init", folder, *named, "--template", "go", "--sdk", sdk]
    )
    if status != 0 or "wrote    go.mod" not in printed:
        return [f"init did not write the Go template:\n{printed}"]
    status, printed = run([os.path.join(folder, "build.sh")])
    if status != 0:
        return [f"build.sh did not build:\n{printed}"]
    built = os.path.join(folder, "tool")
    status, printed = run([tool, "validate", built])
    if status != 0:
        return [f"validate does not pass what was built:\n{printed}"]
    said = io.StringIO()
    with contextlib.redirect_stdout(said):
        status = conformance.main([built, "--expect-refusal"])
    if status != 0:
        return [f"what was built does not pass conformance:\n{said.getvalue()}"]
    status, printed = run(
        [tool, "run", built, "--command", "hello", "--command", "count"]
    )
    if status != 0 or "run: OK" not in printed:
        return [f"what was built does not run:\n{printed}"]
    return []


def main(arguments):
    tool = None
    if "--tool" in arguments:
        at = arguments.index("--tool")
        tool = os.path.abspath(arguments[at + 1])
        arguments = arguments[:at] + arguments[at + 2 :]
    go, module, sources = os.path.abspath(arguments[0]), arguments[1], arguments[2:]
    problems = []
    with tempfile.TemporaryDirectory(prefix="vitruvian-go-") as root:
        environment = {
            "PATH": os.path.dirname(go) + os.pathsep + os.environ.get("PATH", ""),
            "GOROOT": os.path.dirname(os.path.dirname(go)),
            "HOME": root,
            "GOCACHE": os.path.join(root, "cache"),
            "GOPATH": os.path.join(root, "path"),
            "GOWORK": "off",
            "GOPROXY": "off",
            "GOTOOLCHAIN": "local",
            "GOFLAGS": "-mod=mod",
            "CGO_ENABLED": "0",
        }
        for name in ("RUNFILES_DIR", "RUNFILES_MANIFEST_FILE", "TMPDIR"):
            if name in os.environ:
                environment[name] = os.environ[name]

        def run(words, cwd=None):
            done = subprocess.run(
                words,
                cwd=cwd,
                env=environment,
                capture_output=True,
                text=True,
                timeout=LIMIT,
                check=False,
            )
            return done.returncode, done.stdout + done.stderr

        sdk = os.path.join(root, "sdk")
        kit = os.path.join(sdk, "go")
        os.makedirs(os.path.join(kit, "toolkit"))
        shutil.copy(module, os.path.join(kit, "go.mod"))
        for source in sources:
            # By its path under go/, so a subpackage such as toolkit/ui keeps
            # its folder.
            inside = source.split("/go/toolkit/", 1)[1]
            os.makedirs(
                os.path.dirname(os.path.join(kit, "toolkit", inside)), exist_ok=True
            )
            shutil.copy(source, os.path.join(kit, "toolkit", inside))
        status, printed = run([go, "vet", "./..."], cwd=kit)
        if status != 0:
            problems.append(f"go vet fails the kit as its own module:\n{printed}")

        if tool is not None and not problems:
            problems += built_tool(tool, sdk, root, run)
    for problem in problems:
        print(problem, file=sys.stderr)
    print("go: " + ("FAILED" if problems else "OK"))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
