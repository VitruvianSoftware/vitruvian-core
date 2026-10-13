#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 VitruvianSoftware

"""The tool's version is one number, kept in files that must agree.

    version_test.py

release-please writes it into .release-please-manifest.json and, through
the extra-files of release-please-config.json, into vitruvian-tool.json
(what the app and the catalog read) and Version.swift (what the tool says
at `initialize`). Before the first release the manifest says 0.0.0 and the
version is the config's initial-version. The catalog's CI refuses a zip
whose manifest's version is not the entry's; this finds the same mistake
before it merges.

Package.swift names the kit the mirror builds against; `Tool.every`, which
the tool needs, came with the kit the line below names, so an older one
fails here.
"""

import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
# The SDK release that carries Tool.every(seconds:).
KIT_WITH_TIMERS = (1, 0, 0)


def read(name):
    with open(os.path.join(HERE, name), encoding="utf-8") as handle:
        return handle.read()


def semver(text):
    match = re.match(r"^(\d+)\.(\d+)\.(\d+)$", text or "")
    return tuple(int(part) for part in match.groups()) if match else None


def main():
    problems = []
    manifest_version = json.loads(read("vitruvian-tool.json")).get("version")
    swift = re.search(
        r'current = "([^"]+)" // x-release-please-version',
        read("Sources/GitHubToolCore/Version.swift"),
    )
    if not swift:
        problems.append(
            'Version.swift has no `current = "X.Y.Z" // x-release-please-version` line'
        )
    elif swift.group(1) != manifest_version:
        problems.append(
            f"Version.swift says {swift.group(1)}, vitruvian-tool.json says {manifest_version}"
        )
    if semver(manifest_version) is None:
        problems.append(
            f"vitruvian-tool.json's version {manifest_version!r} is not X.Y.Z"
        )
    if os.path.exists(os.path.join(HERE, ".release-please-manifest.json")):
        released = next(
            iter(json.loads(read(".release-please-manifest.json")).values()), None
        )
        config = json.loads(read("release-please-config.json"))
        package = next(iter(config["packages"].values()))
        expected = package.get("initial-version") if released == "0.0.0" else released
        if expected != manifest_version:
            problems.append(
                f"release-please says the version is {expected}, vitruvian-tool.json says {manifest_version}"
            )
        extra = [
            entry["path"] if isinstance(entry, dict) else entry
            for entry in package.get("extra-files", [])
        ]
        for needed in ("vitruvian-tool.json", "Sources/GitHubToolCore/Version.swift"):
            if needed not in extra:
                problems.append(
                    f"release-please-config.json does not write the version into {needed}"
                )
    kit = re.search(r'vitruvian-sdk", from: "([^"]+)"', read("Package.swift"))
    if not kit:
        problems.append(
            "Package.swift does not depend on VitruvianSoftware/vitruvian-sdk with `from:`"
        )
    elif (semver(kit.group(1)) or (0, 0, 0)) < KIT_WITH_TIMERS:
        problems.append(
            f"Package.swift builds against kit {kit.group(1)}, before Tool.every came ({'.'.join(map(str, KIT_WITH_TIMERS))})"
        )
    for problem in problems:
        print(problem)
    if problems:
        return 1
    print(
        f"the tool is {manifest_version}, in every file that says so, against a kit with timers"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
