#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 VitruvianSoftware
"""Pins the shared Nexus Agent sources this app is built from.

Those sources live in apps/desktop/nexus-agent. This app releases only when a
file under apps/desktop/vitruvian changes, so a fix made only there would ship
in the standalone app and never in this one, with nothing saying so. The pin
makes every such change also change this folder.
"""

import argparse
import hashlib
import os
import sys
from pathlib import Path

PIN = "apps/desktop/vitruvian/bazel/nexus_agent_shared.sha256"


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
    parser.add_argument("sources", nargs="+")
    args = parser.parse_args()
    current = digest(args.sources)

    if args.check:
        pinned = Path(args.check).read_text().strip()
        if pinned == current:
            return 0
        print(
            "The shared Nexus Agent code changed and this app's pin did not.\n"
            "  1. bazel run //apps/desktop/vitruvian:pin_nexus_agent_shared\n"
            "  2. add a line for the change to the log in apps/desktop/vitruvian/UPSTREAM.md\n"
            "Both go in the same commit, so the change ships in Vitruvian's next release.",
            file=sys.stderr,
        )
        return 1

    root = os.environ.get("BUILD_WORKSPACE_DIRECTORY")
    if not root:
        print("Run with: bazel run //apps/desktop/vitruvian:pin_nexus_agent_shared", file=sys.stderr)
        return 2
    Path(root, PIN).write_text(current + "\n")
    print(f"pinned {current[:12]} in {PIN}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
