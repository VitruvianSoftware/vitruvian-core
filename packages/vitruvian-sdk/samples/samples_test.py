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
"""The samples are tools the app can add, and each passes the conformance
script.

    samples_test.py [a built sample's vitruvian-tool.json ...]

With no argument it checks what needs no build: the manifest of every sample
against the schema, that the kits and the samples that use them name one
version of the SDK, and the plain Python sample against the conformance
script. With arguments it checks the folders Bazel assembled for the other
samples, each named by the path of its manifest: the Swift, Go and Rust
samples built, and the kit samples with their kit beside them, as an author
ships them. A Python
program is started through the interpreter running this test; any other
through its own first line, with the folder of VITRUVIAN_NODE, when set, at
the front of the PATH.

The sample that reads the front window's title needs the Accessibility
permission of whoever starts it. A test runner has none, and nothing here
grants it: the sample must then refuse its command in plain words, and that
is a pass. So is a run inside Bazel's sandbox, where macOS answers nothing
about other apps, and so is a run on a Mac whose terminal has the permission,
where the command runs. The line printed says which was seen.
"""

import contextlib
import glob
import io
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PACKAGE = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(PACKAGE, "conformance"))

import conformance

# For each sample, by the last part of its id: the lines the conformance
# script must print, one of each group.
WANTED = {
    "hello-python": [["a command: hello: ran"], ["refusals: 1 refused"]],
    "hello-swift": [["a command: hello: ran"], ["refusals: 1 refused"]],
    "hello-typescript": [["a command: hello: ran"], ["refusals: 1 refused"]],
    "hello-python-kit": [["a command: hello: ran"], ["refusals: 1 refused"]],
    "hello-panel-swift": [
        ["a command: addOne: ran"],
        ["a panel: counter: a page of 4 blocks, and a new page after a tap on add"],
    ],
    "hello-panel-typescript": [
        ["a command: addOne: ran"],
        ["a panel: counter: a page of 4 blocks, and a new page after a tap on add"],
    ],
    "hello-panel-python": [
        ["a command: addOne: ran"],
        ["a panel: counter: a page of 4 blocks, and a new page after a tap on add"],
    ],
    "hello-go": [["a command: hello: ran"], ["refusals: 1 refused"]],
    "hello-panel-go": [
        ["a command: addOne: ran"],
        ["a panel: counter: a page of 4 blocks, and a new page after a tap on add"],
    ],
    "hello-rust": [["a command: hello: ran"], ["refusals: 1 refused"]],
    "hello-panel-rust": [
        ["a command: addOne: ran"],
        ["a panel: counter: a page of 4 blocks, and a new page after a tap on add"],
    ],
    "front-window": [
        [
            "a command: showTitle: ran",
            "a command: showTitle: refused, Accessibility is not granted",
            "a command: showTitle: refused, no app is in front",
            "a command: showTitle: refused, the app in front has no window",
        ]
    ],
}


def check(folder, *options):
    printed = io.StringIO()
    with contextlib.redirect_stdout(printed):
        status = conformance.main([folder, *options])
    return status, printed.getvalue()


def conforms(folder, *options):
    """The problems the sample in `folder` has with the conformance script."""
    with open(os.path.join(folder, "vitruvian-tool.json"), encoding="utf-8") as handle:
        name = json.load(handle)["id"].rsplit(".", 1)[-1]
    status, printed = check(folder, *options)
    problems = []
    if status != 0:
        problems.append(f"{name} does not pass:\n{printed}")
    for group in WANTED[name]:
        seen = [line for line in group if line in printed]
        if not seen:
            problems.append(f"{name}: none of {group} in:\n{printed}")
        else:
            print(f"{name}: {seen[0]}")
    return problems


def manifests():
    """Every sample's manifest, against the schema."""
    from jsonschema import Draft202012Validator

    with open(
        os.path.join(PACKAGE, "protocol", "manifest.schema.json"), encoding="utf-8"
    ) as handle:
        validator = Draft202012Validator(json.load(handle))
    found = sorted(glob.glob(os.path.join(HERE, "*", "vitruvian-tool.json")))
    names = sorted(os.path.basename(os.path.dirname(path)) for path in found)
    problems = [] if names == sorted(WANTED) else [f"the samples are {names}"]
    for path in found:
        with open(path, encoding="utf-8") as handle:
            manifest = json.load(handle)
        for error in validator.iter_errors(manifest):
            problems.append(f"{path}: {error.message}")
        name = os.path.basename(os.path.dirname(path))
        if manifest["id"] != "dev.vitruvian.samples." + name:
            problems.append(f"{path}: the id does not end with the folder's name")
    return problems


def versions():
    """The kits, the kit samples and the command name one version of the SDK.

    release-please bumps them all in one change; this fails a change that
    bumps some of them.
    """
    found = {}
    with open(
        os.path.join(PACKAGE, "go", "toolkit", "version.go"), encoding="utf-8"
    ) as handle:
        found["go/toolkit/version.go"] = re.search(
            r'(?m)^const Version = "([^"]+)"', handle.read()
        ).group(1)
    with open(
        os.path.join(PACKAGE, "kits", "rust", "Cargo.toml"), encoding="utf-8"
    ) as handle:
        found["kits/rust/Cargo.toml"] = re.search(
            r'(?m)^version = "([^"]+)"', handle.read()
        ).group(1)
    with open(os.path.join(HERE, "hello-go", "go.mod"), encoding="utf-8") as handle:
        found["samples/hello-go/go.mod"] = re.search(
            r"(?m)^require github\.com/VitruvianSoftware/vitruvian-sdk/go v(\S+)",
            handle.read(),
        ).group(1)
    with open(
        os.path.join(HERE, "hello-panel-go", "go.mod"), encoding="utf-8"
    ) as handle:
        found["samples/hello-panel-go/go.mod"] = re.search(
            r"(?m)^require github\.com/VitruvianSoftware/vitruvian-sdk/go v(\S+)",
            handle.read(),
        ).group(1)
    with open(
        os.path.join(HERE, "hello-rust", "Cargo.toml"), encoding="utf-8"
    ) as handle:
        found["samples/hello-rust/Cargo.toml"] = re.search(
            r'(?m)^vitruvian-tool-kit = \{ version = "([^"]+)"', handle.read()
        ).group(1)
    with open(
        os.path.join(HERE, "hello-panel-rust", "Cargo.toml"), encoding="utf-8"
    ) as handle:
        found["samples/hello-panel-rust/Cargo.toml"] = re.search(
            r'(?m)^vitruvian-tool-kit = \{ version = "([^"]+)"', handle.read()
        ).group(1)
    with open(
        os.path.join(PACKAGE, "kits", "typescript", "package.json"), encoding="utf-8"
    ) as handle:
        found["kits/typescript/package.json"] = json.load(handle)["version"]
    with open(
        os.path.join(PACKAGE, "kits", "python", "pyproject.toml"), encoding="utf-8"
    ) as handle:
        found["kits/python/pyproject.toml"] = re.search(
            r'(?m)^version = "([^"]+)"', handle.read()
        ).group(1)
    with open(
        os.path.join(HERE, "hello-typescript", "package.json"), encoding="utf-8"
    ) as handle:
        found["samples/hello-typescript/package.json"] = json.load(handle)[
            "dependencies"
        ]["@vitruviansoftware/tool-kit"]
    with open(
        os.path.join(HERE, "hello-panel-typescript", "package.json"), encoding="utf-8"
    ) as handle:
        found["samples/hello-panel-typescript/package.json"] = json.load(handle)[
            "dependencies"
        ]["@vitruviansoftware/tool-kit"]
    with open(
        os.path.join(HERE, "hello-panel-python", "requirements.txt"), encoding="utf-8"
    ) as handle:
        found["samples/hello-panel-python/requirements.txt"] = re.search(
            r"vitruvian-tool-kit==(\S+)", handle.read()
        ).group(1)
    with open(
        os.path.join(HERE, "hello-python-kit", "requirements.txt"), encoding="utf-8"
    ) as handle:
        found["samples/hello-python-kit/requirements.txt"] = re.search(
            r"vitruvian-tool-kit==(\S+)", handle.read()
        ).group(1)
    for path in sorted(
        glob.glob(os.path.join(PACKAGE, "Sources", "VitruvianToolCLI", "*.swift"))
    ):
        with open(path, encoding="utf-8") as handle:
            for version in re.findall(
                r'"(\d+\.\d+\.\d+)" // x-release-please-version', handle.read()
            ):
                found[os.path.relpath(path, PACKAGE)] = version
    if len(set(found.values())) == 1 and len(found) == 13:
        print(
            f"versions: {found['kits/typescript/package.json']}, in {len(found)} places"
        )
        return []
    return [
        f"one version of the SDK in thirteen places, and these differ or are missing: {found}"
    ]


def hermetic_node(path):
    """The absolute path of Bazel's Node, from the `external/<repo>/...` name
    the toolchain gives, or None if it is not there."""
    runfiles = os.path.dirname(os.getcwd())
    candidates = [os.path.abspath(path)]
    if path.startswith("external/"):
        inside = path[len("external/") :]
        candidates.append(os.path.join(runfiles, inside))
        if os.environ.get("RUNFILES_DIR"):
            candidates.append(os.path.join(os.environ["RUNFILES_DIR"], inside))
    for candidate in candidates:
        if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            return candidate
    return None


def main(arguments):
    if arguments:
        problems = []
        node = os.environ.get("VITRUVIAN_NODE")
        if node:
            # Bazel names its Node as `external/<repo>/.../node`. In a test's
            # runfiles that repository sits beside `_main`, the folder the test
            # runs in, not under it; and with remote execution there is no
            # `external` link at all. A Node that cannot be found is a failure,
            # not a fall-through to whatever `node` the Mac has: that hid this
            # from the Mac lane while the Linux lane had no Node at all.
            found = hermetic_node(node)
            if found is None:
                problems.append(
                    f"the hermetic Node is not where VITRUVIAN_NODE says: {node}"
                )
            else:
                os.environ["PATH"] = (
                    os.path.dirname(found) + os.pathsep + os.environ.get("PATH", "")
                )
        for manifest in arguments:
            folder = os.path.dirname(os.path.abspath(manifest))
            with open(manifest, encoding="utf-8") as handle:
                program = json.load(handle)["runtime"]["exec"]
            via = ["--via", sys.executable] if program.endswith(".py") else []
            problems += conforms(folder, *via)
    else:
        problems = manifests() + versions()
        # Through the interpreter running this test: the sample's own first
        # line asks for whatever `python3` is on the PATH.
        problems += conforms(
            os.path.join(HERE, "hello-python"),
            "--via",
            sys.executable,
            "--expect-refusal",
        )
    for problem in problems:
        print(problem, file=sys.stderr)
    print("samples: " + ("FAILED" if problems else "OK"))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
