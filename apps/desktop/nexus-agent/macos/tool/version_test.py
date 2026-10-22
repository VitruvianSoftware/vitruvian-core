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
app's version: release-please writes it into macos/Sources/NexusAgent/Version.swift
and, from this change on, into the tool's manifest (tool/vitruvian-tool.json)
and the tool's Version.swift, through the extra-files of
release-please-config.json. The catalog's CI refuses a zip whose manifest's
version is not the entry's; this finds the same mistake before it merges.

Package.swift names the kit the mirror builds against. The tool needs the
kit the line below names: `ToolWaker` came with 1.1.0, and 1.2.0 answers
what the app sends while handed work waits for an answer (before it, a
command sent just after the Quick Prompt was shown could sit unanswered for
seconds). An older one fails here.
"""

import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MACOS = os.path.dirname(HERE)
APP = os.path.dirname(MACOS)
# The first SDK release with slot docking (`onSlot`, `dockToSlot`), notices
# (`showNotice`), and `Panel.onClose`.
KIT_THE_TOOL_NEEDS = (1, 9, 0)


def read(path):
    with open(path, encoding="utf-8") as handle:
        return handle.read()


def semver(text):
    match = re.match(r"^(\d+)\.(\d+)\.(\d+)$", text or "")
    return tuple(int(part) for part in match.groups()) if match else None


def version_line(path):
    match = re.search(r'"([^"]+)" // x-release-please-version', read(path))
    return match.group(1) if match else None


def main():
    problems = []
    manifest_version = json.loads(read(os.path.join(HERE, "vitruvian-tool.json"))).get(
        "version"
    )
    tool_version = version_line(
        os.path.join(MACOS, "Sources/NexusAgentToolCore/Version.swift")
    )
    app_version = version_line(os.path.join(MACOS, "Sources/NexusAgent/Version.swift"))
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
        "macos/tool/vitruvian-tool.json",
        "macos/Sources/NexusAgentToolCore/Version.swift",
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
    elif (semver(kit.group(1)) or (0, 0, 0)) < KIT_THE_TOOL_NEEDS:
        problems.append(
            f"Package.swift builds against kit {kit.group(1)}, older than the kit the tool needs ({'.'.join(map(str, KIT_THE_TOOL_NEEDS))}): its handed work can leave a command unanswered"
        )
    for problem in problems:
        print(problem)
    if problems:
        return 1
    print(
        f"the tool is {manifest_version}, the app's version, in every file that says so, against kit {kit.group(1)} or later"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
