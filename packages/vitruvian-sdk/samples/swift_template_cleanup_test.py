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

`detached` and `removed` are what `swift_template_test.py` calls at its end.
A disk mounted inside the folder must come off first: on CI's Xcode the Metal
toolchain is mounted under the home the build is given. `removed` must
outlast something still writing into the folder, and name what is left when
the folder cannot go at all. Needs no Swift; the disk case needs a Mac.
"""

import os
import subprocess
import sys
import tempfile
import threading
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from swift_template_test import detached, mounts_under, removed  # noqa: E402

# What `mount` prints on a Mac, with Xcode's Metal toolchain mounted inside
# the test's folder, under the home it gave `swift build`.
TABLE = """\
/dev/disk3s1s1 on / (apfs, sealed, local, read-only, journaled)
/dev/disk5s1 on /work/t/home/Library/Developer/DVTDownloads/MetalToolchain/mounts/389a (apfs, local, nodev, nosuid, read-only, noowners, mounted by runner)
/dev/disk6s1 on /work/t/home/Library/Developer/DVTDownloads/MetalToolchain/mounts/389a/inner disk (apfs, local, nodev, nosuid, mounted by runner)
/dev/disk7s1 on /work/t-other/x (apfs, local, nodev, nosuid, mounted by runner)
"""


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


def mounted_disk(base):
    image = os.path.join(base, "disk.dmg")
    folder = os.path.join(base, "with-disk")
    point = os.path.join(folder, "home", "mounts", "disk")
    os.makedirs(point)
    for words in (
        ["hdiutil", "create", "-quiet", "-size", "1m", "-fs", "HFS+", image],
        ["hdiutil", "attach", "-quiet", "-nobrowse", "-mountpoint", point, image],
    ):
        made = subprocess.run(words, capture_output=True, text=True, timeout=60)
        if made.returncode != 0:
            return [f"could not make a disk to test with: {made.stderr}"]
    problems = detached(folder)
    left = removed(folder, limit=5)
    if left or os.path.lexists(folder):
        subprocess.run(["hdiutil", "detach", "-force", point], capture_output=True)
        problems.append(f"a folder with a disk mounted in it was not deleted: {left}")
    return problems


def main():
    problems = []
    base = tempfile.mkdtemp(dir=os.environ.get("TEST_TMPDIR"))

    # Only what is inside the folder, the deepest first; names may hold spaces.
    found = mounts_under("/work/t", TABLE)
    mounts = "/work/t/home/Library/Developer/DVTDownloads/MetalToolchain/mounts/389a"
    if found != [mounts + "/inner disk", mounts]:
        problems.append(f"the mounts inside the folder were not found: {found}")

    # A real disk image mounted inside a folder: it comes off, then the
    # folder goes, as on CI.
    if sys.platform == "darwin":
        problems.extend(mounted_disk(base))

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
