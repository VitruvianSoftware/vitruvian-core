#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 VitruvianSoftware

"""The built tool is a tool the app can add, and it speaks the protocol.

    conformance_test.py <built vitruvian-tool.json> <conformance.py> <vitruvian-tool>

Runs `vitruvian-tool validate` on the built folder, then the SDK's
conformance script, which plays the app to the real program: the handshake,
the `refresh` command (answered, signed out, with nothing asked of
GitHub), an unknown command, the island panel opened and its page read, the
refusals, and a clean exit. Nothing reaches the network: signed out, the
tool asks GitHub nothing.
"""

import os
import shutil
import subprocess
import sys
import tempfile


def main():
    manifest, conformance, validate = sys.argv[1:4]
    built = os.path.dirname(os.path.abspath(manifest))
    # Bazel lays the built folder out as links; the app runs a copy, and
    # `validate` refuses a program that is a link out of the folder. So the
    # folder is copied, as the app copies it, and the copy is judged.
    scratch = tempfile.mkdtemp(dir=os.environ.get("TEST_TMPDIR"))
    folder = os.path.join(scratch, "github")
    shutil.copytree(built, folder, symlinks=False)
    # A home of its own: the tool reads the GitHub CLI's login from
    # ~/.config/gh/hosts.yml, and with this Mac's it would sign in, which is
    # the network. The target also blocks the network, so a mistake here is
    # a failure, not a quiet fetch.
    env = dict(os.environ, HOME=scratch)
    failed = 0
    for name, command in [
        ("validate", [os.path.abspath(validate), "validate", folder]),
        ("conformance", [sys.executable, os.path.abspath(conformance), folder]),
    ]:
        done = subprocess.run(
            command, capture_output=True, text=True, timeout=120, check=False, env=env
        )
        print(f"--- {name}: exit {done.returncode}\n{done.stdout}{done.stderr}")
        if done.returncode != 0:
            failed += 1
    if failed:
        print(f"{failed} of 2 checks failed")
        return 1
    print("the built GitHub tool validates and passes the conformance script")
    return 0


if __name__ == "__main__":
    sys.exit(main())
