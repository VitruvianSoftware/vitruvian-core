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

"""Hermetic Unit Tests for Antigravity Telemetry CLI, OTLP Builders, and HTTP Client."""

import argparse
import gzip
import http.server
import io
import json
import os
import shutil
import sys
import tempfile
import threading
import unittest
from typing import Any, Dict, List
from unittest.mock import patch

_CURR_DIR = os.path.dirname(os.path.abspath(__file__))
if _CURR_DIR not in sys.path:
    sys.path.insert(0, _CURR_DIR)

from antigravity_telemetry import (
    build_parser,
    cmd_emit,
    cmd_export,
    cmd_setup,
    cmd_status,
    patch_settings_json,
)
from http_client import TelemetryHttpClient
from otlp_builder import (
    DEFAULT_LATENCY_BOUNDS,
    build_api_request_metric,
    build_histogram_datapoint,
    build_metrics_payload,
    build_resource,
    build_session_count_metric,
    build_span,
    build_subagent_spawn_metric,
    build_sum_datapoint,
    build_token_usage_metric,
    build_tool_call_count_metric,
    build_tool_call_latency_metric,
    build_traces_payload,
    build_turn_count_metric,
    compute_histogram_buckets,
    get_hostname,
    otel_attr,
    otel_attrs,
)


class MockOTLPHandler(http.server.BaseHTTPRequestHandler):
    """In-process HTTP request handler for hermetic OTLP testing."""

    received_requests: List[Dict[str, Any]] = []

    def do_POST(self) -> None:
        content_length = int(self.headers.get("Content-Length", 0))
        raw_body = self.rfile.read(content_length)

        if self.headers.get("Content-Encoding") == "gzip":
            body = gzip.decompress(raw_body).decode("utf-8")
        else:
            body = raw_body.decode("utf-8")

        payload = json.loads(body) if body.strip() else {}

        MockOTLPHandler.received_requests.append(
            {
                "path": self.path,
                "headers": dict(self.headers),
                "payload": payload,
            }
        )

        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b'{"partialSuccess": {}}')

    def log_message(self, format: str, *args: Any) -> None:
        pass


class AntigravityTelemetryTestSuite(unittest.TestCase):
    """Test suite verifying OTLP builders, resilient transport, and CLI commands."""

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
        self.test_dir = tempfile.mkdtemp(prefix="antigravity_telemetry_test_")

    def tearDown(self) -> None:
        shutil.rmtree(self.test_dir, ignore_errors=True)

    def test_hostname_resolution_precedence(self) -> None:
        """Verify get_hostname resolves environment variables with proper precedence."""
        with patch.dict(os.environ, {"ANTIGRAVITY_HOST": "custom-mbp32.local"}):
            self.assertEqual(get_hostname(), "custom-mbp32")

        with patch.dict(
            os.environ,
            {"ANTIGRAVITY_HOST": "", "ANTIGRAVITY_HOSTNAME": "custom-fedora"},
        ):
            self.assertEqual(get_hostname(), "custom-fedora")

        with patch.dict(
            os.environ,
            {
                "ANTIGRAVITY_HOST": "",
                "ANTIGRAVITY_HOSTNAME": "",
                "OTEL_RESOURCE_ATTRIBUTES": "service.name=test,host.name=node-42",
            },
        ):
            self.assertEqual(get_hostname(), "node-42")

    def test_histogram_bucket_partitioning(self) -> None:
        """Verify values are properly bucketed in explicit bounds."""
        bounds = [10.0, 50.0, 100.0]
        values = [5.0, 10.0, 12.0, 50.0, 75.0, 100.0, 500.0]
        # <= 10.0: [5.0, 10.0] -> 2
        # <= 50.0: [12.0, 50.0] -> 2
        # <= 100.0: [75.0, 100.0] -> 2
        # > 100.0: [500.0] -> 1
        buckets = compute_histogram_buckets(values, bounds)
        self.assertEqual(buckets, ["2", "2", "2", "1"])

    def test_all_seven_metrics_builders(self) -> None:
        """Verify payload generation for all 7 standard metrics."""
        host = "james-mbp32"
        model = "gemini-3.7-flash"

        # 1. antigravity_token_usage_total
        m1 = build_token_usage_metric(
            input_tokens=1000,
            output_tokens=250,
            thinking_tokens=300,
            cached_tokens=500,
            model=model,
            host=host,
        )
        self.assertEqual(m1["name"], "antigravity_token_usage_total")
        self.assertEqual(m1["unit"], "{tokens}")
        self.assertTrue(m1["sum"]["isMonotonic"])
        self.assertEqual(len(m1["sum"]["dataPoints"]), 4)

        # 2. antigravity_api_request_count_total
        m2 = build_api_request_metric(model=model, status_code=200, count=1, host=host)
        self.assertEqual(m2["name"], "antigravity_api_request_count_total")
        self.assertEqual(m2["unit"], "{requests}")

        # 3. antigravity_tool_call_count_total
        m3 = build_tool_call_count_metric(
            tool_name="run_command", status="success", count=1, host=host
        )
        self.assertEqual(m3["name"], "antigravity_tool_call_count_total")

        # 4. antigravity_tool_call_latency_milliseconds
        m4 = build_tool_call_latency_metric(
            tool_name="run_command", latency_ms=120.0, status="success", host=host
        )
        self.assertEqual(m4["name"], "antigravity_tool_call_latency_milliseconds")
        self.assertEqual(m4["unit"], "ms")
        self.assertEqual(m4["histogram"]["dataPoints"][0]["sum"], 120.0)

        # 5. antigravity_session_count_total
        m5 = build_session_count_metric(status="started", count=1, host=host)
        self.assertEqual(m5["name"], "antigravity_session_count_total")

        # 6. antigravity_turn_count_total
        m6 = build_turn_count_metric(model=model, count=1, host=host)
        self.assertEqual(m6["name"], "antigravity_turn_count_total")

        # 7. antigravity_subagent_spawn_count_total
        m7 = build_subagent_spawn_metric(subagent_type="explorer", count=1, host=host)
        self.assertEqual(m7["name"], "antigravity_subagent_spawn_count_total")

        payload = build_metrics_payload([m1, m2, m3, m4, m5, m6, m7], host_name=host)
        self.assertIn("resourceMetrics", payload)
        rm = payload["resourceMetrics"][0]
        res_attrs = {
            a["key"]: a["value"]["stringValue"] for a in rm["resource"]["attributes"]
        }
        self.assertEqual(res_attrs["service.name"], "antigravity")
        self.assertEqual(res_attrs["host.name"], host)

        metrics = rm["scopeMetrics"][0]["metrics"]
        self.assertEqual(len(metrics), 7)

    def test_trace_payload_builder(self) -> None:
        """Verify trace payload generation."""
        host = "james-mbp32"
        span = build_span(
            name="antigravity.test_span",
            start_time_ns=1000000,
            end_time_ns=2000000,
            attributes={"session.id": "test-session-123"},
        )
        payload = build_traces_payload([span], host_name=host)
        self.assertIn("resourceSpans", payload)
        spans = payload["resourceSpans"][0]["scopeSpans"][0]["spans"]
        self.assertEqual(len(spans), 1)
        self.assertEqual(spans[0]["name"], "antigravity.test_span")
        self.assertEqual(spans[0]["status"]["code"], 1)

    def test_http_client_post_and_resilience(self) -> None:
        """Verify HTTP client successfully sends payloads and handles failures gracefully."""
        client = TelemetryHttpClient(base_url=self.endpoint, timeout=2.0)

        # Success case
        ok, code, resp = client.post_json("v1/metrics", {"test": "metric_data"})
        self.assertTrue(ok)
        self.assertEqual(code, 200)
        self.assertEqual(len(MockOTLPHandler.received_requests), 1)
        self.assertEqual(
            MockOTLPHandler.received_requests[0]["payload"], {"test": "metric_data"}
        )

        # Health check
        healthy, msg = client.check_health()
        self.assertTrue(healthy)
        self.assertIn("reachable", msg)

        # Connection failure case (unreachable port)
        dead_client = TelemetryHttpClient(
            base_url="http://127.0.0.1:59999", timeout=0.2
        )
        ok_dead, code_dead, msg_dead = dead_client.post_json(
            "v1/metrics", {"test": "metric_data"}
        )
        self.assertFalse(ok_dead)
        self.assertEqual(code_dead, 0)
        self.assertTrue(
            "URLError" in msg_dead
            or "Timeout" in msg_dead
            or "ConnectionRefused" in msg_dead
            or "error" in msg_dead.lower()
        )

    def test_patch_settings_json_idempotency(self) -> None:
        """Verify patch_settings_json is idempotent and preserves existing keys."""
        existing = {
            "mcpServers": {"github": {"command": "gh-mcp"}},
            "trustedWorkspaces": ["/Users/james/Workspace"],
            "telemetry": {"userSurvey": False},
            "hooks": {
                "AfterModel": [
                    {
                        "matcher": "*",
                        "hooks": [
                            {
                                "name": "stream-to-ui",
                                "command": "/path/to/stream.py",
                                "timeout": 1000,
                            }
                        ],
                    }
                ]
            },
        }

        endpoint = "https://otel.lab.ipv1337.dev"
        hook_path = "/Users/james/.gemini/hooks/telemetry_hook.py"

        # First patch
        patched_1 = patch_settings_json(existing, endpoint, hook_path)

        # Preserves user keys
        self.assertEqual(patched_1["mcpServers"], {"github": {"command": "gh-mcp"}})
        self.assertEqual(patched_1["trustedWorkspaces"], ["/Users/james/Workspace"])
        self.assertEqual(patched_1["telemetry"]["userSurvey"], False)
        self.assertTrue(patched_1["telemetry"]["enabled"])
        self.assertEqual(patched_1["telemetry"]["otlpEndpoint"], endpoint)
        self.assertTrue(patched_1["telemetry"]["traces"])

        # Preserves sibling hook and adds telemetry-hook
        after_model_hooks = patched_1["hooks"]["AfterModel"][0]["hooks"]
        hook_names = [h["name"] for h in after_model_hooks]
        self.assertIn("stream-to-ui", hook_names)
        self.assertIn("telemetry-hook", hook_names)

        # Second patch (idempotency check)
        patched_2 = patch_settings_json(patched_1, endpoint, hook_path)
        self.assertEqual(patched_1, patched_2)

    def test_cmd_setup_and_status(self) -> None:
        """Verify cmd_setup creates files and cmd_status verifies them."""
        settings_path = os.path.join(self.test_dir, "settings.json")
        hooks_dir = os.path.join(self.test_dir, "hooks")
        hook_file = os.path.join(hooks_dir, "telemetry_hook.py")

        # 1. Run cmd_setup
        args_setup = argparse.Namespace(
            endpoint=self.endpoint,
            settings_path=settings_path,
            hooks_dir=hooks_dir,
            hook_script_name="telemetry_hook.py",
            dry_run=False,
            no_backup=True,
            json=True,
        )
        code_setup = cmd_setup(args_setup)
        self.assertEqual(code_setup, 0)
        self.assertTrue(os.path.exists(settings_path))
        self.assertTrue(os.path.exists(hook_file))
        self.assertTrue(os.access(hook_file, os.X_OK))

        # 2. Run cmd_status (should be healthy)
        args_status = argparse.Namespace(
            endpoint=self.endpoint,
            settings_path=settings_path,
            hooks_dir=hooks_dir,
            timeout=2.0,
            json=True,
        )
        code_status = cmd_status(args_status)
        self.assertEqual(code_status, 0)

    def test_cmd_emit(self) -> None:
        """Verify cmd_emit sends metrics and traces to the endpoint."""
        args_emit = argparse.Namespace(
            endpoint=self.endpoint,
            host="test-host",
            model="gemini-3.7-flash",
            tool="run_command",
            tokens_input=1000,
            tokens_output=200,
            tokens_thinking=300,
            tokens_cached=400,
            tool_latency_ms=150.0,
            count=1,
            interval=0.0,
            metrics_only=False,
            traces_only=False,
            verbose=False,
            json=True,
        )
        code_emit = cmd_emit(args_emit)
        self.assertEqual(code_emit, 0)
        self.assertEqual(len(MockOTLPHandler.received_requests), 2)  # metrics + traces
        paths = [r["path"] for r in MockOTLPHandler.received_requests]
        self.assertIn("/v1/metrics", paths)
        self.assertIn("/v1/traces", paths)

    def test_cmd_export(self) -> None:
        """Verify cmd_export processes hook JSON from file."""
        event_file = os.path.join(self.test_dir, "event.json")
        with open(event_file, "w", encoding="utf-8") as f:
            json.dump(
                {
                    "hook_event": "AfterModel",
                    "model": "gemini-3.7-flash",
                    "llm_response": {
                        "usage_metadata": {
                            "prompt_token_count": 1500,
                            "candidates_token_count": 400,
                        }
                    },
                },
                f,
            )

        args_export = argparse.Namespace(
            endpoint=self.endpoint,
            file=event_file,
            hook_mode=True,
            verbose=False,
        )
        code_export = cmd_export(args_export)
        self.assertEqual(code_export, 0)
        self.assertGreaterEqual(len(MockOTLPHandler.received_requests), 1)


if __name__ == "__main__":
    unittest.main()
