#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 VitruvianSoftware
"""Pins the sources this app is built from that live outside its folder.

One set does: the tool protocol's Swift code, in packages/vitruvian-sdk. (The
shared Nexus Agent code was another until the Nexus Agent feature became the
Nexus Agent tool from the catalog, in stage F of tools for everyone.) This app
is tested and released only when a file under apps/desktop/vitruvian changes,
so a change made only there would reach neither this app's tests nor its next
release, with nothing saying so. A pin makes every such change also change
this folder. `--name` says which set.
"""

import argparse
import hashlib
import os
import sys
from pathlib import Path

# Each set: what to call it, and the target that pins it again.
PINS = {
    "tool_protocol": ("The tool protocol's Swift code", "pin_tool_protocol"),
}


def digest(paths):
    h = hashlib.sha256()
    for path in sorted(paths):
        h.update(path.encode())
        h.update(b"\0")
        h.update(Path(path).read_bytes())
        h.update(b"\0")
    return h.hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", metavar="PIN_FILE")
    parser.add_argument("--name", default="tool_protocol", choices=sorted(PINS))
    parser.add_argument("sources", nargs="+")
    args = parser.parse_args()
    current = digest(args.sources)
    what, target = PINS[args.name]
    pin = f"apps/desktop/vitruvian/bazel/{args.name}.sha256"

    if args.check:
        pinned = Path(args.check).read_text().strip()
        if pinned == current:
            return 0
        print(
            f"{what} changed and this app's pin did not.\n"
            f"  1. bazel run //apps/desktop/vitruvian:{target}\n"
            "  2. add a line for the change to the log in apps/desktop/vitruvian/UPSTREAM.md\n"
            "Both go in the same commit, so the change ships in Vitruvian's next release.",
            file=sys.stderr,
        )
        return 1

    root = os.environ.get("BUILD_WORKSPACE_DIRECTORY")
    if not root:
        print(
            f"Run with: bazel run //apps/desktop/vitruvian:{target}",
            file=sys.stderr,
        )
        return 2
    Path(root, pin).write_text(current + "\n")
    print(f"pinned {current[:12]} in {pin}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
