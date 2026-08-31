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

"""Antigravity Lifecycle Hook: Streams token and execution telemetry via OTLP."""

import json
import os
import sys
import threading
import time
from typing import Any, Dict, List, Optional

_CURR_DIR = os.path.dirname(os.path.abspath(__file__))
if _CURR_DIR not in sys.path:
    sys.path.insert(0, _CURR_DIR)

from http_client import TelemetryHttpClient
from otlp_builder import (
    build_api_request_metric,
    build_metrics_payload,
    build_session_count_metric,
    build_subagent_spawn_metric,
    build_token_usage_metric,
    build_tool_call_count_metric,
    build_tool_call_latency_metric,
    build_turn_count_metric,
    get_hostname,
)

DEFAULT_ENDPOINT = "https://otel.lab.ipv1337.dev"
_TOOL_TIMERS: Dict[str, float] = {}


def get_target_endpoint() -> str:
    """Resolve OTLP destination endpoint."""
    return os.environ.get(
        "ANTIGRAVITY_OTLP_ENDPOINT",
        os.environ.get("OTEL_EXPORTER_OTLP_ENDPOINT", DEFAULT_ENDPOINT),
    ).rstrip("/")


def process_event(
    data: Dict[str, Any],
    endpoint: Optional[str] = None,
    host: Optional[str] = None,
) -> List[Dict[str, Any]]:
    """Parse hook event and generate metric objects."""
    h = host or get_hostname()
    hook_event = data.get("hook_event", data.get("hookEvent", ""))
    metrics: List[Dict[str, Any]] = []

    if hook_event == "AfterModel":
        resp = data.get("llm_response", data.get("llmResponse", {}))
        usage = resp.get("usage_metadata", resp.get("usageMetadata", {}))
        model = resp.get("model", data.get("model", "gemini-3.7-flash"))

        input_tokens = int(
            usage.get("prompt_token_count", usage.get("promptTokenCount", 0))
        )
        output_tokens = int(
            usage.get("candidates_token_count", usage.get("candidatesTokenCount", 0))
        )
        thinking_tokens = int(
            usage.get("thinking_token_count", usage.get("thinkingTokenCount", 0))
        )
        cached_tokens = int(
            usage.get(
                "cached_content_token_count", usage.get("cachedContentTokenCount", 0)
            )
        )

        # Fallback for thought token counting from content parts
        if thinking_tokens == 0:
            candidates = resp.get("candidates", [])
            for cand in candidates:
                for part in cand.get("content", {}).get("parts", []):
                    if part.get("thought", False) and "text" in part:
                        thinking_tokens += max(1, len(part["text"].split()))

        # Emit token usage metric
        metrics.append(
            build_token_usage_metric(
                input_tokens=input_tokens,
                output_tokens=output_tokens,
                thinking_tokens=thinking_tokens,
                cached_tokens=cached_tokens,
                model=model,
                host=h,
            )
        )

        # Emit API request and Turn counts
        metrics.append(
            build_api_request_metric(
                model=model,
                status_code="200",
                count=1,
                host=h,
            )
        )
        metrics.append(
            build_turn_count_metric(
                model=model,
                count=1,
                host=h,
            )
        )

    elif hook_event == "BeforeTool":
        tool_name = data.get("tool_name", data.get("toolName", "unknown"))
        _TOOL_TIMERS[tool_name] = time.time()

        if tool_name == "invoke_subagent":
            tool_input = data.get("tool_input", data.get("toolInput", {}))
            subagent_type = (
                tool_input.get("Recipient")
                or tool_input.get("role")
                or tool_input.get("subagent_type")
                or tool_input.get("agent_name")
                or "general"
            )
            metrics.append(
                build_subagent_spawn_metric(
                    subagent_type=str(subagent_type),
                    count=1,
                    host=h,
                )
            )

    elif hook_event == "AfterTool":
        tool_name = data.get("tool_name", data.get("toolName", "unknown"))
        error = data.get("error", data.get("is_error", False))
        status = "failure" if error else "success"

        start_time = _TOOL_TIMERS.pop(tool_name, None)
        if "duration_ms" in data or "latency_ms" in data:
            duration_ms = float(data.get("duration_ms", data.get("latency_ms", 0.0)))
        elif start_time:
            duration_ms = max(1.0, (time.time() - start_time) * 1000.0)
        else:
            duration_ms = 25.0

        metrics.append(
            build_tool_call_count_metric(
                tool_name=tool_name,
                status=status,
                count=1,
                host=h,
            )
        )
        metrics.append(
            build_tool_call_latency_metric(
                tool_name=tool_name,
                latency_ms=duration_ms,
                status=status,
                host=h,
            )
        )

    elif hook_event == "AfterAgent":
        status = data.get("status", "completed")
        metrics.append(
            build_session_count_metric(
                status=status,
                count=1,
                host=h,
            )
        )

    return metrics


def _dispatch_otlp_async(payload: Dict[str, Any], endpoint: str) -> None:
    """Send OTLP payload in a daemon background thread."""
    client = TelemetryHttpClient(base_url=endpoint, timeout=2.0)

    def _send() -> None:
        client.post_json("v1/metrics", payload, compress=True, silent=True)

    t = threading.Thread(target=_send, daemon=True)
    t.start()


def main() -> None:
    """Main hook entrypoint."""
    try:
        raw = sys.stdin.read()
        data = json.loads(raw) if raw.strip() else {}
        endpoint = get_target_endpoint()
        host = get_hostname()

        metrics = process_event(data, endpoint=endpoint, host=host)
        if metrics:
            payload = build_metrics_payload(metrics, host_name=host)
            _dispatch_otlp_async(payload, endpoint)
    except Exception as e:
        sys.stderr.write(f"[telemetry_hook] Warning: {e}\n")
    finally:
        sys.stdout.write("{}\n")
        sys.stdout.flush()
        sys.exit(0)


if __name__ == "__main__":
    main()
