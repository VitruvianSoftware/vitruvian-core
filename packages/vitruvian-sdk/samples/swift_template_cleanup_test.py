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
"""The Swift template test deletes its own folder, and says what it could not.

    swift_template_cleanup_test.py

`removed` is what `swift_template_test.py` calls at its end. It must outlast
something that is still writing into the folder, and name what is left when
the folder cannot go at all. Needs no Swift and no Mac.
"""

import os
import sys
import tempfile
import threading
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from swift_template_test import removed  # noqa: E402


def writer(folder, seconds):
    """Keeps making files in the folder until the time is up, as long as
    the folder is there."""
    end = time.monotonic() + seconds
    count = 0
    while time.monotonic() < end:
        try:
            with open(os.path.join(folder, f"late-{count}"), "w") as out:
                out.write("x")
        except OSError:
            pass
        count += 1


def main():
    problems = []
    base = tempfile.mkdtemp(dir=os.environ.get("TEST_TMPDIR"))

    # Something still writing for two seconds: the folder goes all the same.
    busy = os.path.join(base, "busy")
    os.makedirs(os.path.join(busy, "deep", "deeper"))
    thread = threading.Thread(target=writer, args=(busy, 2), daemon=True)
    thread.start()
    time.sleep(0.2)
    left = removed(busy, limit=10)
    thread.join()
    if left or os.path.lexists(busy):
        problems.append(f"a folder being written into was not deleted: {left}")

    # A folder that cannot go: what is left is named, and nothing waits long.
    # Root deletes a locked folder all the same, so this is not tried as root
    # (as on CI's remote machines).
    if os.geteuid() != 0:
        stuck = os.path.join(base, "stuck")
        locked = os.path.join(stuck, "locked")
        os.makedirs(locked)
        with open(os.path.join(locked, "kept"), "w") as out:
            out.write("x")
        os.chmod(locked, 0o500)
        try:
            began = time.monotonic()
            left = removed(stuck, limit=1)
            took = time.monotonic() - began
        finally:
            os.chmod(locked, 0o700)
        if left != ["locked", "locked/kept"]:
            problems.append(f"what could not be deleted was not named: {left}")
        if took > 5:
            problems.append(f"giving up took {took:.0f} seconds, not about one")
    if removed(base, limit=5):
        problems.append("the test's own folder was not deleted")

    for problem in problems:
        print(problem, file=sys.stderr)
    print("swift template cleanup: " + ("FAILED" if problems else "OK"))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
