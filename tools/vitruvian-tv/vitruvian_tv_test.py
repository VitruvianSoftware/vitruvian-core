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

"""Unit and SDK conformance tests for //tools/vitruvian-tv."""

import importlib.util
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import MagicMock, patch

BUILT_MANIFEST = None
CONFORMANCE_SCRIPT = None


def load_tool_module(folder_path: str):
    sys.path.insert(0, os.path.join(folder_path, "lib"))
    tool_py = os.path.join(folder_path, "bin", "tool.py")
    spec = importlib.util.spec_from_file_location("vitruvian_tv_tool", tool_py)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class VitruvianTVTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        built_dir = os.path.dirname(os.path.abspath(BUILT_MANIFEST))
        cls.scratch = tempfile.mkdtemp(dir=os.environ.get("TEST_TMPDIR"))
        cls.folder = os.path.join(cls.scratch, "vitruvian-tv")
        shutil.copytree(built_dir, cls.folder, symlinks=False)
        os.chmod(os.path.join(cls.folder, "bin", "tool.py"), 0o755)
        cls.mod = load_tool_module(cls.folder)

    def test_sdk_conformance_suite(self):
        res = subprocess.run(
            [sys.executable, "-B", os.path.abspath(CONFORMANCE_SCRIPT), self.folder],
            capture_output=True,
            text=True,
            timeout=60,
            check=False,
        )
        self.assertEqual(
            res.returncode,
            0,
            f"conformance failed:\n{res.stdout}\n{res.stderr}",
        )

    def test_is_safe_http_url_rejects_injection_and_non_http(self):
        self.assertTrue(
            self.mod.is_safe_http_url("https://www.youtube.com/watch?v=dQw4w9WgXcQ")
        )
        self.assertTrue(
            self.mod.is_safe_http_url("http://192.168.86.31:8080/video.mp4")
        )
        self.assertFalse(self.mod.is_safe_http_url(""))
        self.assertFalse(self.mod.is_safe_http_url("javascript:alert(1)"))
        self.assertFalse(self.mod.is_safe_http_url("file:///etc/passwd"))
        self.assertFalse(self.mod.is_safe_http_url("https://youtu.be/x'; rm -rf /; '"))
        self.assertFalse(self.mod.is_safe_http_url("https://youtu.be/x\necho injected"))

    def test_cast_clipboard_url_quotes_url_safely(self):
        app = MagicMock()
        url_with_quote = "https://youtu.be/abc'def"
        app.clipboard.read_text.return_value = MagicMock(text=url_with_quote)
        self.mod.tv.dry_run = False
        with patch.object(self.mod.tv, "run_adb_shell", return_value="") as mock_adb:
            self.mod.cast_clipboard_url(app)
            mock_adb.assert_called_once()
            cmd = mock_adb.call_args[0][0]
            self.assertIn("'https://youtu.be/abc'\"'\"'def'", cmd)

    def test_toggle_power_atomic_parses_sleep_and_awake(self):
        state = self.mod.SonyTVState()
        state.dry_run = False
        with patch.object(
            state,
            "run_adb_shell",
            return_value="POWER_STATE=SLEEP\nMemAvailable:     655360 kB",
        ):
            awake = state.toggle_power_atomic()
            self.assertFalse(awake)
            self.assertEqual(state.foreground, "Standby (Remote Start Ready)")
            self.assertEqual(state.mem_available_mb, 640)

        with patch.object(
            state,
            "run_adb_shell",
            return_value="POWER_STATE=AWAKE\nMemAvailable:     614400 kB",
        ):
            awake = state.toggle_power_atomic()
            self.assertTrue(awake)
            self.assertEqual(state.foreground, "Projectivy Home")
            self.assertEqual(state.mem_available_mb, 600)

    def test_run_adb_shell_reconnects_only_on_failure(self):
        state = self.mod.SonyTVState()
        state.dry_run = False
        ok_proc = MagicMock(returncode=0, stdout="mWakefulness=Awake\n")
        fail_proc = MagicMock(returncode=1, stdout="")
        with patch(
            "subprocess.run", side_effect=[fail_proc, MagicMock(returncode=0), ok_proc]
        ) as mock_run:
            out = state.run_adb_shell("dumpsys power")
            self.assertEqual(out, "mWakefulness=Awake")
            self.assertTrue(state.connected)
            self.assertEqual(mock_run.call_count, 3)


if __name__ == "__main__":
    BUILT_MANIFEST = sys.argv.pop(1)
    CONFORMANCE_SCRIPT = sys.argv.pop(1)
    unittest.main()
