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

"""The built HomeSpeaker tool is a tool the app can add, and it speaks the protocol.

    conformance_test.py <built vitruvian-tool.json> <conformance.py> <vitruvian-tool>

Runs `vitruvian-tool validate` on the built folder, then the SDK's
conformance script, which plays the app to the real program: the handshake,
the `sayClipboard` command (answered with a refusal: as far as the program
is allowed to see, HomeSpeaker is not installed), an unknown command, the
island panel opened and its page read, the refusals, and a clean exit. The
program runs under a home of its own with no settings file in it, and
`HOMESPEAKER_PROGRAM` set and empty keeps it off the HomeSpeaker Launch
Services would find on this Mac, so it speaks on nothing of this Mac's.
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
    folder = os.path.join(scratch, "homespeaker")
    shutil.copytree(built, folder, symlinks=False)
    home = os.path.join(scratch, "home")
    os.makedirs(home)
    # A home of its own: the tool reads ~/.gemini/speaker_broadcast.json
    # and looks in ~/Applications, and with this Mac's home it would find
    # both. CFFIXED_USER_HOME is what NSHomeDirectory() reads. Launch
    # Services would still know this Mac's HomeSpeaker by its bundle id,
    # whatever the home: HOMESPEAKER_PROGRAM, set and empty, keeps the tool
    # off it, so nothing here can speak.
    env = dict(os.environ, HOME=home, CFFIXED_USER_HOME=home, HOMESPEAKER_PROGRAM="")
    failed = 0
    for name, command in [
        ("validate", [os.path.abspath(validate), "validate", folder]),
        ("conformance", [sys.executable, os.path.abspath(conformance), folder]),
    ]:
        done = subprocess.run(
            command, capture_output=True, text=True, timeout=180, check=False, env=env
        )
        print(f"--- {name}: exit {done.returncode}\n{done.stdout}{done.stderr}")
        if done.returncode != 0:
            failed += 1
        # The command must have been refused, not run: a run means the
        # program found a HomeSpeaker, which no test may drive.
        if name == "conformance" and "sayClipboard: refused" not in done.stdout:
            print(
                "the sayClipboard command was not refused: the program found a HomeSpeaker to drive"
            )
            failed += 1
    if failed:
        print(f"{failed} of 2 checks failed")
        return 1
    print("the built HomeSpeaker tool validates and passes the conformance script")
    return 0


if __name__ == "__main__":
    sys.exit(main())
