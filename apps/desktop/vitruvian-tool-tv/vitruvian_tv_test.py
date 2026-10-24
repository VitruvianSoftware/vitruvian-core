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

"""SDK conformance test for //apps/desktop/vitruvian-tool-tv.

The tool's own unit tests are in src/main.rs (:vitruvian_tv_unit_test). This
runs the SDK's conformance script against the built folder, so the Rust
program answers a real app's side of the protocol over its standard input and
output. The script's data folder is not under Application Support, so the
tool runs dry and never starts adb.
"""

import os
import shutil
import subprocess
import sys
import tempfile
import unittest

BUILT_MANIFEST = None
CONFORMANCE_SCRIPT = None


class VitruvianTVConformanceTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        built_dir = os.path.dirname(os.path.abspath(BUILT_MANIFEST))
        cls.scratch = tempfile.mkdtemp(dir=os.environ.get("TEST_TMPDIR"))
        cls.folder = os.path.join(cls.scratch, "vitruvian-tv")
        shutil.copytree(built_dir, cls.folder, symlinks=False)
        os.chmod(os.path.join(cls.folder, "bin", "tool"), 0o755)

    def test_folder_holds_the_rust_program(self):
        program = os.path.join(self.folder, "bin", "tool")
        self.assertTrue(os.access(program, os.X_OK), program)
        self.assertFalse(os.path.exists(os.path.join(self.folder, "bin", "tool.py")))
        self.assertFalse(os.path.exists(os.path.join(self.folder, "lib")))

    def test_sdk_conformance_suite(self):
        env = dict(os.environ)
        env.pop("VITRUVIAN_TV_LIVE", None)
        res = subprocess.run(
            [sys.executable, "-B", os.path.abspath(CONFORMANCE_SCRIPT), self.folder],
            capture_output=True,
            text=True,
            timeout=60,
            check=False,
            env=env,
        )
        self.assertEqual(
            res.returncode,
            0,
            f"conformance failed:\n{res.stdout}\n{res.stderr}",
        )


if __name__ == "__main__":
    BUILT_MANIFEST = sys.argv.pop(1)
    CONFORMANCE_SCRIPT = sys.argv.pop(1)
    unittest.main()
