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

"""Hermetic Unit Tests for Antigravity Lifecycle Hook (telemetry_hook.py)."""

import http.server
import io
import json
import sys
import threading
import unittest
from typing import Any, Dict, List
from unittest.mock import patch

import os

_CURR_DIR = os.path.dirname(os.path.abspath(__file__))
if _CURR_DIR not in sys.path:
    sys.path.insert(0, _CURR_DIR)

from telemetry_hook import main as hook_main, process_event


class MockOTLPHandler(http.server.BaseHTTPRequestHandler):
    """In-process mock handler for hook testing."""

    received_requests: List[Dict[str, Any]] = []

    def do_POST(self) -> None:
        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length).decode("utf-8")
        payload = json.loads(body) if body.strip() else {}

        MockOTLPHandler.received_requests.append(
            {
                "path": self.path,
                "payload": payload,
            }
        )

        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b'{"partialSuccess": {}}')

    def log_message(self, format: str, *args: Any) -> None:
        pass


class TelemetryHookTestSuite(unittest.TestCase):
    """Test suite verifying hook event extraction and protocol contract."""

    server: http.server.HTTPServer
    server_thread: threading.Thread
    endpoint: str

    @classmethod
    def setUpClass(cls) -> None:
        MockOTLPHandler.received_requests = []
        cls.server = http.server.HTTPServer(("127.0.0.1", 0), MockOTLPHandler)
        cls.port = cls.server.server_port
        cls.endpoint = f"http://127.0.0.1:{cls.port}"
        cls.server_thread = threading.Thread(
            target=cls.server.serve_forever, daemon=True
        )
        cls.server_thread.start()

    @classmethod
    def tearDownClass(cls) -> None:
        cls.server.shutdown()
        cls.server.server_close()

    def setUp(self) -> None:
        MockOTLPHandler.received_requests.clear()

    def test_after_model_event_extraction(self) -> None:
        """Verify AfterModel event creates token usage, request count, and turn count metrics."""
        event = {
            "hook_event": "AfterModel",
            "model": "gemini-3.7-flash",
            "llm_response": {
                "usage_metadata": {
                    "prompt_token_count": 1200,
                    "candidates_token_count": 350,
                    "thinking_token_count": 150,
                    "cached_content_token_count": 500,
                },
                "candidates": [{"content": {"parts": [{"text": "Sample answer"}]}}],
            },
        }

        metrics = process_event(event, endpoint=self.endpoint, host="test-host")
        self.assertEqual(len(metrics), 3)

        token_metric = next(
            m for m in metrics if m["name"] == "antigravity_token_usage_total"
        )
        self.assertEqual(len(token_metric["sum"]["dataPoints"]), 4)

        req_metric = next(
            m for m in metrics if m["name"] == "antigravity_api_request_count_total"
        )
        self.assertEqual(req_metric["sum"]["dataPoints"][0]["asInt"], "1")

        turn_metric = next(
            m for m in metrics if m["name"] == "antigravity_turn_count_total"
        )
        self.assertEqual(turn_metric["sum"]["dataPoints"][0]["asInt"], "1")

    def test_tool_lifecycle_events(self) -> None:
        """Verify BeforeTool and AfterTool events record counts and latency."""
        # 1. Normal tool execution
        before_event = {"hook_event": "BeforeTool", "tool_name": "view_file"}
        process_event(before_event, endpoint=self.endpoint, host="test-host")

        after_event = {
            "hook_event": "AfterTool",
            "tool_name": "view_file",
            "duration_ms": 45.0,
            "error": False,
        }
        metrics = process_event(after_event, endpoint=self.endpoint, host="test-host")
        self.assertEqual(len(metrics), 2)

        count_metric = next(
            m for m in metrics if m["name"] == "antigravity_tool_call_count_total"
        )
        lat_metric = next(
            m
            for m in metrics
            if m["name"] == "antigravity_tool_call_latency_milliseconds"
        )

        status_attr = next(
            a["value"]["stringValue"]
            for a in count_metric["sum"]["dataPoints"][0]["attributes"]
            if a["key"] == "status"
        )
        self.assertEqual(status_attr, "success")
        self.assertEqual(lat_metric["histogram"]["dataPoints"][0]["sum"], 45.0)

        # 2. Subagent spawning tool
        spawn_event = {
            "hook_event": "BeforeTool",
            "tool_name": "invoke_subagent",
            "tool_input": {"role": "explorer"},
        }
        spawn_metrics = process_event(
            spawn_event, endpoint=self.endpoint, host="test-host"
        )
        self.assertEqual(len(spawn_metrics), 1)
        subagent_metric = spawn_metrics[0]
        self.assertEqual(
            subagent_metric["name"], "antigravity_subagent_spawn_count_total"
        )
        subagent_type = next(
            a["value"]["stringValue"]
            for a in subagent_metric["sum"]["dataPoints"][0]["attributes"]
            if a["key"] == "subagent_type"
        )
        self.assertEqual(subagent_type, "explorer")

    def test_after_agent_event(self) -> None:
        """Verify AfterAgent event produces session count metric."""
        event = {"hook_event": "AfterAgent", "status": "completed"}
        metrics = process_event(event, endpoint=self.endpoint, host="test-host")
        self.assertEqual(len(metrics), 1)
        self.assertEqual(metrics[0]["name"], "antigravity_session_count_total")

    def test_hook_main_stdout_contract_and_fail_open(self) -> None:
        """Verify hook_main always prints {} on stdout and exits 0 under all conditions."""
        # 1. Valid event
        with (
            patch("sys.stdin", io.StringIO(json.dumps({"hook_event": "AfterAgent"}))),
            patch("sys.stdout", new_callable=io.StringIO) as mock_stdout,
            self.assertRaises(SystemExit) as cm,
        ):
            hook_main()
        self.assertEqual(cm.exception.code, 0)
        self.assertEqual(mock_stdout.getvalue().strip(), "{}")

        # 2. Corrupt JSON
        with (
            patch("sys.stdin", io.StringIO("invalid json content!!!")),
            patch("sys.stdout", new_callable=io.StringIO) as mock_stdout,
            self.assertRaises(SystemExit) as cm,
        ):
            hook_main()
        self.assertEqual(cm.exception.code, 0)
        self.assertEqual(mock_stdout.getvalue().strip(), "{}")

        # 3. Empty input
        with (
            patch("sys.stdin", io.StringIO("")),
            patch("sys.stdout", new_callable=io.StringIO) as mock_stdout,
            self.assertRaises(SystemExit) as cm,
        ):
            hook_main()
        self.assertEqual(cm.exception.code, 0)
        self.assertEqual(mock_stdout.getvalue().strip(), "{}")


if __name__ == "__main__":
    unittest.main()
