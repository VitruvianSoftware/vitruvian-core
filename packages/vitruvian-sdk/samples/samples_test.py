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
against the schema, and the plain Python sample against the conformance
script. With arguments it checks the folders Bazel assembled for the Swift
samples, each named by the path of its manifest.

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
    problems = [] if len(found) == 3 else [f"three samples, not {len(found)}"]
    for path in found:
        with open(path, encoding="utf-8") as handle:
            manifest = json.load(handle)
        for error in validator.iter_errors(manifest):
            problems.append(f"{path}: {error.message}")
        name = os.path.basename(os.path.dirname(path))
        if manifest["id"] != "dev.vitruvian.samples." + name:
            problems.append(f"{path}: the id does not end with the folder's name")
    return problems


def main(arguments):
    if arguments:
        problems = []
        for manifest in arguments:
            problems += conforms(os.path.dirname(os.path.abspath(manifest)))
    else:
        problems = manifests()
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
