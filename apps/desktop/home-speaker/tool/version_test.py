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

"""The tool's version is the standalone app's, in every file that says it.

    version_test.py

The tool is released with the app, from the app's mirror, so it has the
app's version: release-please writes it into Sources/HomeSpeakerCore/Version.swift
and, from this change on, into the tool's manifest (tool/vitruvian-tool.json)
and the tool's Version.swift, through the extra-files of
release-please-config.json. The catalog's CI refuses a zip whose manifest's
version is not the entry's; this finds the same mistake before it merges.

Package.swift names the kit the mirror builds against; `ToolWaker`, the
`choice` block and the `chips` block, which the tool needs, came with the
kits the lines below name, so an older one fails here.
"""

import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
APP = os.path.dirname(HERE)
MACOS = APP
# The SDK release that carries ToolWaker.
KIT_WITH_WAKER = (1, 1, 0)
# The `choice` block and `App.supports(.choice)`, which Settings uses.
KIT_WITH_CHOICE = (1, 3, 0)
# The `chips` block, `PanelEvent.values` and `ProtocolFeature.chips` and
# `.sections`, which Beeper's networks use.
KIT_WITH_CHIPS = (1, 8, 0)


def read(path):
    with open(path, encoding="utf-8") as handle:
        return handle.read()


def semver(text):
    match = re.match(r"^(\d+)\.(\d+)\.(\d+)$", text or "")
    return tuple(int(part) for part in match.groups()) if match else None


def version_line(path):
    match = re.search(r'"([^"]+)" // x-release-please-version', read(path))
    return match.group(1) if match else None


def release_please_layout(text):
    """The file as release-please writes it back: JSON.stringify, two spaces."""
    return json.dumps(json.loads(text), indent=2, ensure_ascii=False) + "\n"


def main():
    problems = []
    manifest = read(os.path.join(HERE, "vitruvian-tool.json"))
    manifest_version = json.loads(manifest).get("version")
    # release-please rewrites the whole file when it bumps the version, and
    # tidy-check fails a release PR whose diff is more than the version line.
    if manifest != release_please_layout(manifest):
        problems.append(
            "vitruvian-tool.json is not in the layout release-please writes (every array one item a line); the release PR would fail tidy-check"
        )
    tool_version = version_line(
        os.path.join(MACOS, "Sources/HomeSpeakerToolCore/Version.swift")
    )
    app_version = version_line(
        os.path.join(MACOS, "Sources/HomeSpeakerCore/Version.swift")
    )
    if semver(manifest_version) is None:
        problems.append(
            f"vitruvian-tool.json's version {manifest_version!r} is not X.Y.Z"
        )
    if tool_version != manifest_version:
        problems.append(
            f"the tool's Version.swift says {tool_version}, vitruvian-tool.json says {manifest_version}"
        )
    if app_version != manifest_version:
        problems.append(
            f"the app's Version.swift says {app_version}, vitruvian-tool.json says {manifest_version}"
        )
    config = json.loads(read(os.path.join(APP, "release-please-config.json")))
    package = next(iter(config["packages"].values()))
    extra = [
        entry["path"] if isinstance(entry, dict) else entry
        for entry in package.get("extra-files", [])
    ]
    for needed in (
        "tool/vitruvian-tool.json",
        "Sources/HomeSpeakerToolCore/Version.swift",
    ):
        if needed not in extra:
            problems.append(
                f"release-please-config.json does not write the version into {needed}"
            )
    kit = re.search(
        r'vitruvian-sdk", from: "([^"]+)"', read(os.path.join(MACOS, "Package.swift"))
    )
    if not kit:
        problems.append(
            "Package.swift does not depend on VitruvianSoftware/vitruvian-sdk with `from:`"
        )
    elif (semver(kit.group(1)) or (0, 0, 0)) < KIT_WITH_WAKER:
        problems.append(
            f"Package.swift builds against kit {kit.group(1)}, before ToolWaker came ({'.'.join(map(str, KIT_WITH_WAKER))})"
        )
    elif (semver(kit.group(1)) or (0, 0, 0)) < KIT_WITH_CHOICE:
        problems.append(
            f"Package.swift builds against kit {kit.group(1)}, before the choice block came ({'.'.join(map(str, KIT_WITH_CHOICE))})"
        )
    elif (semver(kit.group(1)) or (0, 0, 0)) < KIT_WITH_CHIPS:
        problems.append(
            f"Package.swift builds against kit {kit.group(1)}, before the chips block came ({'.'.join(map(str, KIT_WITH_CHIPS))})"
        )
    for problem in problems:
        print(problem)
    if problems:
        return 1
    print(
        f"the tool is {manifest_version}, the app's version, in every file that says so, against a kit with a waker, choice and chips"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
