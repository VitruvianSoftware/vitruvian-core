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

"""Unit tests for Self-Updating Remote Loader Shim (telemetry_loader.py)."""

import http.server
import io
import json
import os
import shutil
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch

_CURR_DIR = os.path.dirname(os.path.abspath(__file__))
if _CURR_DIR not in sys.path:
    sys.path.insert(0, _CURR_DIR)

import telemetry_loader


class MockRawGitHubHandler(http.server.BaseHTTPRequestHandler):
    """Mock HTTP handler simulating raw.githubusercontent.com."""

    fetch_count = 0
    engine_content = b'#!/usr/bin/env python3\nimport sys\n# process_event\nsys.stdout.write(\'{"decision": "allow", "engine_version": "2.0"}\\n\')\nsys.exit(0)\n'

    def do_GET(self) -> None:
        MockRawGitHubHandler.fetch_count += 1
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(MockRawGitHubHandler.engine_content)

    def log_message(self, format: str, *args: object) -> None:
        pass


class TelemetryLoaderTestSuite(unittest.TestCase):
    """Test suite verifying auto-update, caching, and fail-open guarantees of loader."""

    server: http.server.HTTPServer
    server_thread: threading.Thread
    server_url: str

    @classmethod
    def setUpClass(cls) -> None:
        cls.server = http.server.HTTPServer(("127.0.0.1", 0), MockRawGitHubHandler)
        cls.port = cls.server.server_port
        cls.server_url = f"http://127.0.0.1:{cls.port}/telemetry_hook.py"
        cls.server_thread = threading.Thread(
            target=cls.server.serve_forever, daemon=True
        )
        cls.server_thread.start()

    @classmethod
    def tearDownClass(cls) -> None:
        cls.server.shutdown()
        cls.server.server_close()

    def setUp(self) -> None:
        self.test_dir = tempfile.mkdtemp()
        self.test_cache = os.path.join(self.test_dir, ".engine.py")
        MockRawGitHubHandler.fetch_count = 0

    def tearDown(self) -> None:
        shutil.rmtree(self.test_dir, ignore_errors=True)

    def test_first_time_fetch_and_execution(self) -> None:
        """Verify loader synchronously downloads engine when cache is missing and executes it."""
        with (
            patch("telemetry_loader.CACHE_FILE", self.test_cache),
            patch("telemetry_loader.RAW_HOOK_URL", self.server_url),
            patch("sys.stdin", io.StringIO('{"hook_event": "AfterModel"}')),
            patch("sys.stdout", new_callable=io.StringIO) as mock_stdout,
            self.assertRaises(SystemExit) as cm,
        ):
            telemetry_loader.main()

        self.assertEqual(cm.exception.code, 0)
        out = json.loads(mock_stdout.getvalue().strip())
        self.assertEqual(out.get("decision"), "allow")
        self.assertEqual(out.get("engine_version"), "2.0")
        self.assertTrue(os.path.exists(self.test_cache))
        self.assertEqual(MockRawGitHubHandler.fetch_count, 1)

    def test_fail_open_on_network_error_when_no_cache(self) -> None:
        """Verify loader fails-open with decision allow if network is unreachable and no cache exists."""
        bad_url = "http://127.0.0.1:1/nonexistent.py"
        with (
            patch("telemetry_loader.CACHE_FILE", self.test_cache),
            patch("telemetry_loader.RAW_HOOK_URL", bad_url),
            patch("sys.stdin", io.StringIO('{"hook_event": "BeforeTool"}')),
            patch("sys.stdout", new_callable=io.StringIO) as mock_stdout,
            self.assertRaises(SystemExit) as cm,
        ):
            telemetry_loader.main()

        self.assertEqual(cm.exception.code, 0)
        out = json.loads(mock_stdout.getvalue().strip())
        self.assertEqual(out.get("decision"), "allow")


if __name__ == "__main__":
    unittest.main()
