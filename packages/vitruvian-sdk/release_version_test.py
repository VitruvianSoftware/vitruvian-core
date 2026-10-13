#!/usr/bin/env python3
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
"""The SDK's version is one number, kept in files that must agree.

    release_version_test.py

release-please writes it into .release-please-manifest.json and, through the
extra-files of release-please-config.json, into Words.swift, which is what
`vitruvian-tool --version` prints and what `init --template swift` asks for,
and into the kits and the kit samples, which samples_test holds to one
version: a release that bumps fewer than all of them fails there, after it
has merged. This finds a missing extra-file before it merges.
The mirror's release.yml refuses a binary that reports another version than
the manifest; this finds the same mistake before it merges. Before the first
release the manifest says 0.0.0, and the version is the config's
initial-version.
"""

import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PATH = "packages/vitruvian-sdk"
WORDS = "Sources/VitruvianToolCLI/Words.swift"
# The kits and the kit samples, each with the updater release-please needs.
KIT_PLACES = [
    ("json", "kits/typescript/package.json", "$.version"),
    ("toml", "kits/python/pyproject.toml", "$.project.version"),
    (
        "json",
        "samples/hello-typescript/package.json",
        "$.dependencies['@vitruviansoftware/tool-kit']",
    ),
    ("generic", "samples/hello-python-kit/requirements.txt", None),
]


def read(name):
    with open(os.path.join(HERE, name), encoding="utf-8") as handle:
        return handle.read()


def main():
    problems = []
    try:
        config = json.loads(read("release-please-config.json"))
        manifest = json.loads(read(".release-please-manifest.json"))
    except OSError as error:
        print(f"version: FAILED, {error.filename} is missing", file=sys.stderr)
        return 1
    package = config.get("packages", {}).get(PATH)
    if package is None:
        print(f"version: FAILED, the config has no package {PATH}", file=sys.stderr)
        return 1
    for key, wanted in [("release-type", "simple"), ("include-component-in-tag", True)]:
        if config.get(key) != wanted:
            problems.append(f"{key} is {config.get(key)!r}, not {wanted!r}")
    if package.get("component") != "vitruvian-sdk":
        problems.append(
            "the component is not vitruvian-sdk: the tag would not be vitruvian-sdk-vX.Y.Z"
        )
    if WORDS not in package.get("extra-files", []):
        problems.append(
            f"{WORDS} is not in extra-files: --version would not follow a release"
        )
    for kind, path, jsonpath in KIT_PLACES:
        entry = next(
            (
                e
                for e in package.get("extra-files", [])
                if isinstance(e, dict) and e.get("path") == path
            ),
            None,
        )
        want = f"{kind}" + (f" at {jsonpath}" if jsonpath else "")
        if (
            entry is None
            or entry.get("type") != kind
            or (jsonpath and entry.get("jsonpath") != jsonpath)
        ):
            problems.append(
                f"{path} is not in extra-files as {want}: a release would bump "
                "Words.swift and not it, and samples_test would fail the release"
            )
        elif not os.path.exists(os.path.join(HERE, path)):
            problems.append(f"extra-files names {path}, which is not there")
    if f"{PATH}/.github" not in package.get("exclude-paths", []):
        problems.append(
            f"{PATH}/.github is not in exclude-paths: a change to the mirror's CI would cut a release"
        )
    marked = [
        line for line in read(WORDS).split("\n") if "x-release-please-version" in line
    ]
    found = [
        re.search(r'static let version = "(\d+\.\d+\.\d+)"', line) for line in marked
    ]
    if len(marked) != 1 or not found[0]:
        problems.append(
            f'{WORDS} must hold one `static let version = "X.Y.Z" // x-release-please-version` line, not {marked}'
        )
        words = None
    else:
        words = found[0].group(1)
    released = manifest.get(PATH)
    expected = package.get("initial-version") if released == "0.0.0" else released
    if words and words != expected:
        problems.append(
            f"Words.swift says {words}, and the manifest says {released}"
            + (f" with initial-version {expected}" if released == "0.0.0" else "")
        )
    for problem in problems:
        print(problem, file=sys.stderr)
    print("version: " + ("FAILED" if problems else f"OK, {words}"))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
