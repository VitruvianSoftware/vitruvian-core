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

"""Antigravity Lifecycle Hook Engine: Standalone OTLP Telemetry Exporter."""

import gzip
import json
import os
import socket
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
from typing import Any, Dict, List, Optional, Tuple, Union

DEFAULT_ENDPOINT = "https://otel.lab.ipv1337.dev"
DEFAULT_LATENCY_BOUNDS = [
    10.0,
    50.0,
    100.0,
    250.0,
    500.0,
    1000.0,
    2500.0,
    5000.0,
    10000.0,
    30000.0,
    60000.0,
]
_TOOL_TIMERS: Dict[str, float] = {}


def get_hostname() -> str:
    """Resolve sanitized hostname."""
    for env in ["ANTIGRAVITY_HOST", "ANTIGRAVITY_HOSTNAME", "HOST_NAME", "HOSTNAME"]:
        val = os.environ.get(env)
        if val and val.strip():
            return val.strip().split(".")[0]
    if os.path.exists("/usr/sbin/scutil"):
        try:
            res = subprocess.run(
                ["/usr/sbin/scutil", "--get", "LocalHostName"],
                capture_output=True,
                text=True,
                timeout=1,
            )
            if res.returncode == 0 and res.stdout.strip():
                return res.stdout.strip()
        except Exception:
            pass
    return socket.gethostname().split(".")[0]


def get_target_endpoint() -> str:
    """Resolve OTLP destination endpoint."""
    return os.environ.get(
        "ANTIGRAVITY_OTLP_ENDPOINT",
        os.environ.get("OTEL_EXPORTER_OTLP_ENDPOINT", DEFAULT_ENDPOINT),
    ).rstrip("/")


class TelemetryHttpClient:
    """Fail-safe HTTP Client using urllib.request with strict timeouts."""

    def __init__(
        self,
        base_url: str = DEFAULT_ENDPOINT,
        timeout: float = 2.0,
        user_agent: str = "antigravity-telemetry/1.0.0",
    ):
        self.base_url = base_url.rstrip("/")
        self.timeout = timeout
        self.user_agent = user_agent

    def resolve_url(self, path_or_url: str) -> str:
        if path_or_url.startswith(("http://", "https://")):
            return path_or_url
        p = path_or_url.lstrip("/")
        if self.base_url.endswith(p):
            return self.base_url
        return f"{self.base_url}/{p}"

    def post_json(
        self,
        path_or_url: str,
        payload: Dict[str, Any],
        compress: bool = True,
        silent: bool = True,
    ) -> Tuple[bool, int, str]:
        url = self.resolve_url(path_or_url)
        try:
            raw_data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
            headers = {
                "Content-Type": "application/json",
                "User-Agent": self.user_agent,
                "Accept": "application/json",
            }
            if compress and len(raw_data) > 256:
                raw_data = gzip.compress(raw_data)
                headers["Content-Encoding"] = "gzip"

            req = urllib.request.Request(
                url=url,
                data=raw_data,
                headers=headers,
                method="POST",
            )
            try:
                with urllib.request.urlopen(req, timeout=self.timeout) as resp:
                    return (
                        True,
                        resp.status,
                        resp.read().decode("utf-8", errors="replace"),
                    )
            except urllib.error.URLError as e:
                if "certificate verify failed" in str(e).lower():
                    import ssl

                    ctx = ssl._create_unverified_context()
                    with urllib.request.urlopen(
                        req, context=ctx, timeout=self.timeout
                    ) as resp:
                        return (
                            True,
                            resp.status,
                            resp.read().decode("utf-8", errors="replace"),
                        )
                raise
        except urllib.error.HTTPError as e:
            err_msg = f"HTTP {e.code}: {e.reason}"
            if not silent:
                sys.stderr.write(f"[TelemetryHttpClient] {err_msg}\n")
            return (False, e.code, err_msg)
        except Exception as e:
            err_msg = f"Error: {e}"
            if not silent:
                sys.stderr.write(f"[TelemetryHttpClient] {err_msg}\n")
            return (False, 0, err_msg)


def _otel_attr(key: str, value: Any) -> Dict[str, Any]:
    if isinstance(value, bool):
        return {"key": key, "value": {"boolValue": value}}
    elif isinstance(value, int):
        return {"key": key, "value": {"intValue": str(value)}}
    elif isinstance(value, float):
        return {"key": key, "value": {"doubleValue": value}}
    return {"key": key, "value": {"stringValue": str(value)}}


def _otel_attrs(attrs_dict: Dict[str, Any]) -> List[Dict[str, Any]]:
    return [_otel_attr(k, v) for k, v in attrs_dict.items() if v is not None]


def build_sum_dp(
    value: int,
    attributes: Dict[str, Any],
    time_unix_nano: Optional[int] = None,
) -> Dict[str, Any]:
    return {
        "attributes": _otel_attrs(attributes),
        "timeUnixNano": str(time_unix_nano or time.time_ns()),
        "asInt": str(value),
    }


def build_sum_metric(
    name: str,
    description: str,
    unit: str,
    datapoints: List[Dict[str, Any]],
    aggregation_temporality: int = 2,
) -> Dict[str, Any]:
    return {
        "name": name,
        "description": description,
        "unit": unit,
        "sum": {
            "aggregationTemporality": aggregation_temporality,
            "isMonotonic": True,
            "dataPoints": datapoints,
        },
    }


def build_hist_dp(
    values: Union[List[float], float],
    attributes: Dict[str, Any],
    time_unix_nano: Optional[int] = None,
    explicit_bounds: Optional[List[float]] = None,
) -> Dict[str, Any]:
    bounds = explicit_bounds or DEFAULT_LATENCY_BOUNDS
    vals = [values] if isinstance(values, (int, float)) else list(values)
    counts = [0] * (len(bounds) + 1)
    for v in vals:
        placed = False
        for i, b in enumerate(bounds):
            if v <= b:
                counts[i] += 1
                placed = True
                break
        if not placed:
            counts[-1] += 1

    return {
        "attributes": _otel_attrs(attributes),
        "timeUnixNano": str(time_unix_nano or time.time_ns()),
        "count": str(len(vals)),
        "sum": float(sum(vals)),
        "bucketCounts": [str(c) for c in counts],
        "explicitBounds": bounds,
    }


def build_hist_metric(
    name: str,
    description: str,
    unit: str,
    datapoints: List[Dict[str, Any]],
    aggregation_temporality: int = 2,
) -> Dict[str, Any]:
    return {
        "name": name,
        "description": description,
        "unit": unit,
        "histogram": {
            "aggregationTemporality": aggregation_temporality,
            "dataPoints": datapoints,
        },
    }


def build_token_usage_metric(
    input_tokens: int,
    output_tokens: int,
    thinking_tokens: int,
    cached_tokens: int,
    model: str,
    host: str,
) -> Dict[str, Any]:
    t = time.time_ns()
    datapoints = [
        build_sum_dp(
            input_tokens,
            {"host": host, "model": model, "token_type": "input"},
            time_unix_nano=t,
        ),
        build_sum_dp(
            output_tokens,
            {"host": host, "model": model, "token_type": "output"},
            time_unix_nano=t,
        ),
        build_sum_dp(
            thinking_tokens,
            {"host": host, "model": model, "token_type": "thinking"},
            time_unix_nano=t,
        ),
        build_sum_dp(
            cached_tokens,
            {"host": host, "model": model, "token_type": "cached"},
            time_unix_nano=t,
        ),
    ]
    return build_sum_metric(
        name="antigravity_token_usage_total",
        description="Cumulative count of LLM tokens consumed by Antigravity",
        unit="{tokens}",
        datapoints=datapoints,
    )


def build_api_request_metric(
    model: str,
    status_code: str,
    count: int = 1,
    host: str = "default",
) -> Dict[str, Any]:
    dp = build_sum_dp(
        count,
        {"host": host, "model": model, "status_code": status_code},
    )
    return build_sum_metric(
        name="antigravity_api_request_count_total",
        description="Total count of API requests made to Gemini LLM endpoints",
        unit="{requests}",
        datapoints=[dp],
    )


def build_turn_count_metric(
    model: str,
    count: int = 1,
    host: str = "default",
) -> Dict[str, Any]:
    dp = build_sum_dp(count, {"host": host, "model": model})
    return build_sum_metric(
        name="antigravity_turn_count_total",
        description="Total agent turns completed in Antigravity sessions",
        unit="{turns}",
        datapoints=[dp],
    )


def build_subagent_spawn_metric(
    subagent_type: str,
    count: int = 1,
    host: str = "default",
) -> Dict[str, Any]:
    dp = build_sum_dp(count, {"host": host, "subagent_type": subagent_type})
    return build_sum_metric(
        name="antigravity_subagent_spawn_count_total",
        description="Total count of subagents invoked by Antigravity",
        unit="{subagents}",
        datapoints=[dp],
    )


def build_tool_call_count_metric(
    tool_name: str,
    status: str,
    count: int = 1,
    host: str = "default",
) -> Dict[str, Any]:
    dp = build_sum_dp(count, {"host": host, "tool_name": tool_name, "status": status})
    return build_sum_metric(
        name="antigravity_tool_call_count_total",
        description="Total count of tools executed by Antigravity",
        unit="{calls}",
        datapoints=[dp],
    )


def build_tool_call_latency_metric(
    tool_name: str,
    latency_ms: float,
    status: str = "success",
    host: str = "default",
) -> Dict[str, Any]:
    dp = build_hist_dp(
        latency_ms,
        {"host": host, "tool_name": tool_name, "status": status},
    )
    return build_hist_metric(
        name="antigravity_tool_call_latency_milliseconds",
        description="Latency distribution of tool calls in milliseconds",
        unit="ms",
        datapoints=[dp],
    )


def build_session_count_metric(
    status: str,
    count: int = 1,
    host: str = "default",
) -> Dict[str, Any]:
    dp = build_sum_dp(count, {"host": host, "status": status})
    return build_sum_metric(
        name="antigravity_session_count_total",
        description="Total count of Antigravity / agy interactive sessions",
        unit="{sessions}",
        datapoints=[dp],
    )


def build_metrics_payload(
    metrics: List[Dict[str, Any]],
    service_name: str = "antigravity",
    host_name: str = "default",
) -> Dict[str, Any]:
    return {
        "resourceMetrics": [
            {
                "resource": {
                    "attributes": [
                        {
                            "key": "service.name",
                            "value": {"stringValue": service_name},
                        },
                        {"key": "host.name", "value": {"stringValue": host_name}},
                    ]
                },
                "scopeMetrics": [
                    {
                        "scope": {
                            "name": "antigravity-telemetry",
                            "version": "1.0.0",
                        },
                        "metrics": metrics,
                    }
                ],
            }
        ]
    }


def process_event(
    data: Dict[str, Any],
    endpoint: Optional[str] = None,
    host: Optional[str] = None,
) -> List[Dict[str, Any]]:
    """Parse hook event and generate metric objects."""
    h = host or get_hostname()
    hook_event = data.get("hook_event", data.get("hookEvent", ""))
    metrics: List[Dict[str, Any]] = []

    if hook_event in ("AfterModel", "PostInvocation"):
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

        if thinking_tokens == 0:
            candidates = resp.get("candidates", [])
            for cand in candidates:
                for part in cand.get("content", {}).get("parts", []):
                    if part.get("thought", False) and "text" in part:
                        thinking_tokens += max(1, len(part["text"].split()))

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

    elif hook_event in ("BeforeTool", "PreToolUse"):
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

    elif hook_event in ("AfterTool", "PostToolUse"):
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

    elif hook_event in ("AfterAgent", "Stop"):
        status = data.get("status", "completed")
        metrics.append(
            build_session_count_metric(
                status=status,
                count=1,
                host=h,
            )
        )

    return metrics


def _dispatch_otlp(payload: Dict[str, Any], endpoint: str) -> None:
    """Send OTLP payload with fail-safe error isolation."""
    try:
        client = TelemetryHttpClient(base_url=endpoint, timeout=1.5)
        client.post_json("v1/metrics", payload, compress=True, silent=True)
    except Exception:
        pass


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
            _dispatch_otlp(payload, endpoint)
    except Exception as e:
        sys.stderr.write(f"[telemetry_hook] Warning: {e}\n")
    finally:
        # Explicitly return decision: allow to prevent permission deadlocks on PreToolUse hooks
        sys.stdout.write('{"decision": "allow"}\n')
        sys.stdout.flush()
        sys.exit(0)


if __name__ == "__main__":
    main()
