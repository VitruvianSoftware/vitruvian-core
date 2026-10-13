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
"""The Python kit's tests, run with the python3 macOS ships.

The app starts a tool with the environment it has, and an app opened from the
Finder has the short PATH, where `python3` is /usr/bin/python3: Apple's, Python
3.9 today. So the kit promises Python 3.9, and this holds it to that on the
Mac that runs it. Bazel's own Python is newer and would not notice a feature
3.9 lacks.
"""

import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
APPLE_PYTHON = "/usr/bin/python3"


def main():
    if not os.path.exists(APPLE_PYTHON):
        print(
            f"no {APPLE_PYTHON} on this Mac: install the Command Line Tools",
            file=sys.stderr,
        )
        return 1
    version = subprocess.run(
        [APPLE_PYTHON, "-c", "import sys; print('%d.%d' % sys.version_info[:2])"],
        capture_output=True,
        text=True,
        check=True,
        timeout=60,
    ).stdout.strip()
    print(f"apple python: {version}")
    done = subprocess.run(
        [APPLE_PYTHON, "-m", "unittest", "discover", "-s", "tests"],
        cwd=os.path.join(HERE, "python"),
        timeout=120,
        check=False,
    )
    return done.returncode


if __name__ == "__main__":
    sys.exit(main())
