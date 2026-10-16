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

"""Verifies that the Vitruvian Remote extension version matches the app and release config."""

import json
import os
import plistlib
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MACMENU = os.path.dirname(HERE)
ANDROID_REMOTE = os.path.dirname(MACMENU)


def read(path):
    with open(path, encoding="utf-8") as handle:
        return handle.read()


def semver(text):
    match = re.match(r"^(\d+)\.(\d+)\.(\d+)$", text or "")
    return tuple(int(part) for part in match.groups()) if match else None


def swift_version_line(path):
    match = re.search(r'"([^"]+)" // x-release-please-version', read(path))
    return match.group(1) if match else None


def build_version_line(path):
    match = re.search(r'"([^"]+)",\s*# x-release-please-version', read(path))
    return match.group(1) if match else None


def release_please_layout(text):
    """The file as release-please writes it back: JSON.stringify, two spaces."""
    return json.dumps(json.loads(text), indent=2, ensure_ascii=False) + "\n"


def main():
    problems = []
    manifest = read(os.path.join(HERE, "vitruvian-tool.json"))
    manifest_version = json.loads(manifest).get("version")
    if manifest != release_please_layout(manifest):
        problems.append(
            "vitruvian-tool.json is not in the layout release-please writes (every array one item a line); the release PR would fail tidy-check"
        )
    if semver(manifest_version) is None:
        problems.append(
            f"vitruvian-tool.json's version {manifest_version!r} is not X.Y.Z"
        )

    swift_version = swift_version_line(
        os.path.join(MACMENU, "Sources/RemoteMenuCore/Version.swift")
    )
    if swift_version != manifest_version:
        problems.append(
            f"RemoteMenuCore/Version.swift says {swift_version}, vitruvian-tool.json says {manifest_version}"
        )

    build_version = build_version_line(os.path.join(ANDROID_REMOTE, "BUILD"))
    if build_version != manifest_version:
        problems.append(
            f"android-remote/BUILD says {build_version}, vitruvian-tool.json says {manifest_version}"
        )

    with open(os.path.join(MACMENU, "Resources/Info.plist"), "rb") as handle:
        plist = plistlib.load(handle)
    for key in ("CFBundleShortVersionString", "CFBundleVersion"):
        if plist.get(key) != manifest_version:
            problems.append(
                f"Resources/Info.plist {key} says {plist.get(key)}, vitruvian-tool.json says {manifest_version}"
            )

    config = json.loads(
        read(os.path.join(ANDROID_REMOTE, "release-please-config.json"))
    )
    package = next(iter(config["packages"].values()))
    extra = [
        entry["path"] if isinstance(entry, dict) else entry
        for entry in package.get("extra-files", [])
    ]
    for needed in (
        "BUILD",
        "macmenu/Sources/RemoteMenuCore/Version.swift",
        "macmenu/tool/vitruvian-tool.json",
        "macmenu/Resources/Info.plist",
    ):
        if needed not in extra:
            problems.append(
                f"release-please-config.json does not write the version into {needed}"
            )

    for problem in problems:
        print(problem)
    if problems:
        return 1
    print(
        f"the tool is {manifest_version}, matching Version.swift, Info.plist, and android-remote/BUILD"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
