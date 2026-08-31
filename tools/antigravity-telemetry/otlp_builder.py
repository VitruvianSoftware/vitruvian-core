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

"""OTLP/HTTP JSON Payload Builder for Antigravity & AGY Telemetry."""

import os
import secrets
import socket
import subprocess
import time
from typing import Any, Dict, List, Optional, Union

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


def get_hostname() -> str:
    """Resolve workstation hostname, stripping domain suffixes."""
    for env_var in ["ANTIGRAVITY_HOST", "ANTIGRAVITY_HOSTNAME"]:
        val = os.environ.get(env_var)
        if val and val.strip():
            return val.strip().split(".")[0]

    otel_attrs = os.environ.get("OTEL_RESOURCE_ATTRIBUTES", "")
    if otel_attrs:
        for pair in otel_attrs.split(","):
            if "=" in pair:
                k, v = pair.split("=", 1)
                if k.strip() in ("host.name", "host"):
                    return v.strip().split(".")[0]

    for env_var in ["HOST_NAME", "HOSTNAME"]:
        val = os.environ.get(env_var)
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

    hostname = socket.gethostname()
    for suffix in [".local", ".lan", ".home"]:
        if hostname.endswith(suffix):
            hostname = hostname[: -len(suffix)]
    return hostname.split(".")[0]


def otel_attr(key: str, value: Any) -> Dict[str, Any]:
    """Format single key-value attribute according to OTLP JSON spec."""
    if isinstance(value, bool):
        return {"key": key, "value": {"boolValue": value}}
    elif isinstance(value, int):
        return {"key": key, "value": {"intValue": str(value)}}
    elif isinstance(value, float):
        return {"key": key, "value": {"doubleValue": value}}
    else:
        return {"key": key, "value": {"stringValue": str(value)}}


def otel_attrs(attrs_dict: Dict[str, Any]) -> List[Dict[str, Any]]:
    """Format dictionary of attributes into OTLP attribute array."""
    return [otel_attr(k, v) for k, v in attrs_dict.items() if v is not None]


def build_resource(
    service_name: str = "antigravity", host_name: Optional[str] = None
) -> Dict[str, Any]:
    """Construct standard OTLP resource block."""
    host = host_name or get_hostname()
    return {
        "attributes": [
            {"key": "service.name", "value": {"stringValue": service_name}},
            {"key": "service.version", "value": {"stringValue": "1.0.0"}},
            {"key": "host.name", "value": {"stringValue": host}},
        ]
    }


def compute_histogram_buckets(
    values: List[float], explicit_bounds: List[float]
) -> List[str]:
    """Partition observed values into explicit histogram buckets."""
    counts = [0] * (len(explicit_bounds) + 1)
    for v in values:
        placed = False
        for i, bound in enumerate(explicit_bounds):
            if v <= bound:
                counts[i] += 1
                placed = True
                break
        if not placed:
            counts[-1] += 1
    return [str(c) for c in counts]


def build_sum_datapoint(
    value: int,
    attributes: Dict[str, Any],
    time_unix_nano: Optional[int] = None,
    start_time_unix_nano: Optional[int] = None,
) -> Dict[str, Any]:
    """Construct sum/counter datapoint."""
    now_ns = time_unix_nano or time.time_ns()
    dp: Dict[str, Any] = {
        "attributes": otel_attrs(attributes),
        "timeUnixNano": str(now_ns),
        "asInt": str(value),
    }
    if start_time_unix_nano is not None:
        dp["startTimeUnixNano"] = str(start_time_unix_nano)
    return dp


def build_histogram_datapoint(
    values: Union[List[float], float],
    attributes: Dict[str, Any],
    explicit_bounds: Optional[List[float]] = None,
    time_unix_nano: Optional[int] = None,
) -> Dict[str, Any]:
    """Construct explicit-bounds histogram datapoint."""
    bounds = explicit_bounds if explicit_bounds is not None else DEFAULT_LATENCY_BOUNDS
    vals = [values] if isinstance(values, (int, float)) else list(values)
    now_ns = time_unix_nano or time.time_ns()
    bucket_counts = compute_histogram_buckets(vals, bounds)
    return {
        "attributes": otel_attrs(attributes),
        "timeUnixNano": str(now_ns),
        "count": str(len(vals)),
        "sum": float(sum(vals)),
        "bucketCounts": bucket_counts,
        "explicitBounds": bounds,
    }


def build_sum_metric(
    name: str,
    description: str,
    unit: str,
    datapoints: List[Dict[str, Any]],
    is_monotonic: bool = True,
    aggregation_temporality: int = 2,
) -> Dict[str, Any]:
    """Construct OTLP Sum Metric dictionary."""
    return {
        "name": name,
        "description": description,
        "unit": unit,
        "sum": {
            "aggregationTemporality": aggregation_temporality,
            "isMonotonic": is_monotonic,
            "dataPoints": datapoints,
        },
    }


def build_histogram_metric(
    name: str,
    description: str,
    unit: str,
    datapoints: List[Dict[str, Any]],
    aggregation_temporality: int = 2,
) -> Dict[str, Any]:
    """Construct OTLP Histogram Metric dictionary."""
    return {
        "name": name,
        "description": description,
        "unit": unit,
        "histogram": {
            "aggregationTemporality": aggregation_temporality,
            "dataPoints": datapoints,
        },
    }


# ==============================================================================
# The 7 Standard Metrics Builders
# ==============================================================================


def build_token_usage_metric(
    input_tokens: int = 0,
    output_tokens: int = 0,
    thinking_tokens: int = 0,
    cached_tokens: int = 0,
    model: str = "gemini-3.7-flash",
    host: Optional[str] = None,
    time_unix_nano: Optional[int] = None,
) -> Dict[str, Any]:
    """Construct antigravity_token_usage_total metric with all token streams."""
    h = host or get_hostname()
    dps = []
    for token_type, val in [
        ("input", input_tokens),
        ("output", output_tokens),
        ("thinking", thinking_tokens),
        ("cached", cached_tokens),
    ]:
        dps.append(
            build_sum_datapoint(
                value=val,
                attributes={"host": h, "token_type": token_type, "model": model},
                time_unix_nano=time_unix_nano,
            )
        )
    return build_sum_metric(
        name="antigravity_token_usage_total",
        description="Total tokens consumed by Antigravity and AGY CLI",
        unit="{tokens}",
        datapoints=dps,
        is_monotonic=True,
    )


def build_api_request_metric(
    model: str = "gemini-3.7-flash",
    status_code: Union[int, str] = "200",
    count: int = 1,
    host: Optional[str] = None,
    time_unix_nano: Optional[int] = None,
) -> Dict[str, Any]:
    """Construct antigravity_api_request_count_total metric."""
    h = host or get_hostname()
    dp = build_sum_datapoint(
        value=count,
        attributes={"host": h, "model": model, "status_code": str(status_code)},
        time_unix_nano=time_unix_nano,
    )
    return build_sum_metric(
        name="antigravity_api_request_count_total",
        description="Total API requests to LLM backend",
        unit="{requests}",
        datapoints=[dp],
        is_monotonic=True,
    )


def build_tool_call_count_metric(
    tool_name: str,
    status: str = "success",
    count: int = 1,
    host: Optional[str] = None,
    time_unix_nano: Optional[int] = None,
) -> Dict[str, Any]:
    """Construct antigravity_tool_call_count_total metric."""
    h = host or get_hostname()
    dp = build_sum_datapoint(
        value=count,
        attributes={"host": h, "tool_name": tool_name, "status": status},
        time_unix_nano=time_unix_nano,
    )
    return build_sum_metric(
        name="antigravity_tool_call_count_total",
        description="Total tool calls executed by Antigravity and AGY agents",
        unit="{calls}",
        datapoints=[dp],
        is_monotonic=True,
    )


def build_tool_call_latency_metric(
    tool_name: str,
    latency_ms: Union[List[float], float],
    status: str = "success",
    host: Optional[str] = None,
    explicit_bounds: Optional[List[float]] = None,
    time_unix_nano: Optional[int] = None,
) -> Dict[str, Any]:
    """Construct antigravity_tool_call_latency_milliseconds histogram metric."""
    h = host or get_hostname()
    dp = build_histogram_datapoint(
        values=latency_ms,
        attributes={"host": h, "tool_name": tool_name, "status": status},
        explicit_bounds=explicit_bounds,
        time_unix_nano=time_unix_nano,
    )
    return build_histogram_metric(
        name="antigravity_tool_call_latency_milliseconds",
        description="Tool call duration distribution in milliseconds",
        unit="ms",
        datapoints=[dp],
    )


def build_session_count_metric(
    status: str = "started",
    count: int = 1,
    host: Optional[str] = None,
    time_unix_nano: Optional[int] = None,
) -> Dict[str, Any]:
    """Construct antigravity_session_count_total metric."""
    h = host or get_hostname()
    dp = build_sum_datapoint(
        value=count,
        attributes={"host": h, "status": status},
        time_unix_nano=time_unix_nano,
    )
    return build_sum_metric(
        name="antigravity_session_count_total",
        description="Total sessions launched",
        unit="{sessions}",
        datapoints=[dp],
        is_monotonic=True,
    )


def build_turn_count_metric(
    model: str = "gemini-3.7-flash",
    count: int = 1,
    host: Optional[str] = None,
    time_unix_nano: Optional[int] = None,
) -> Dict[str, Any]:
    """Construct antigravity_turn_count_total metric."""
    h = host or get_hostname()
    dp = build_sum_datapoint(
        value=count,
        attributes={"host": h, "model": model},
        time_unix_nano=time_unix_nano,
    )
    return build_sum_metric(
        name="antigravity_turn_count_total",
        description="Total turns executed by Antigravity agents",
        unit="{turns}",
        datapoints=[dp],
        is_monotonic=True,
    )


def build_subagent_spawn_metric(
    subagent_type: str = "explorer",
    count: int = 1,
    host: Optional[str] = None,
    time_unix_nano: Optional[int] = None,
) -> Dict[str, Any]:
    """Construct antigravity_subagent_spawn_count_total metric."""
    h = host or get_hostname()
    dp = build_sum_datapoint(
        value=count,
        attributes={"host": h, "subagent_type": subagent_type},
        time_unix_nano=time_unix_nano,
    )
    return build_sum_metric(
        name="antigravity_subagent_spawn_count_total",
        description="Total subagents spawned",
        unit="{spawns}",
        datapoints=[dp],
        is_monotonic=True,
    )


def build_metrics_payload(
    metrics: List[Dict[str, Any]],
    service_name: str = "antigravity",
    host_name: Optional[str] = None,
    scope_name: str = "tools/antigravity-telemetry",
    scope_version: str = "1.0.0",
) -> Dict[str, Any]:
    """Wrap a list of metrics in standard OTLP /v1/metrics payload."""
    host = host_name or get_hostname()
    return {
        "resourceMetrics": [
            {
                "resource": build_resource(service_name, host),
                "scopeMetrics": [
                    {
                        "scope": {
                            "name": scope_name,
                            "version": scope_version,
                        },
                        "metrics": metrics,
                    }
                ],
            }
        ]
    }


# ==============================================================================
# Trace Payload Builder
# ==============================================================================


def build_span(
    name: str,
    start_time_ns: int,
    end_time_ns: int,
    attributes: Optional[Dict[str, Any]] = None,
    trace_id: Optional[str] = None,
    span_id: Optional[str] = None,
    parent_span_id: Optional[str] = None,
    kind: int = 1,
    status_code: int = 1,
    status_message: Optional[str] = None,
) -> Dict[str, Any]:
    """Construct OTLP span dictionary."""
    t_id = trace_id or secrets.token_hex(16)
    s_id = span_id or secrets.token_hex(8)
    attrs = otel_attrs(attributes or {})
    span: Dict[str, Any] = {
        "traceId": t_id,
        "spanId": s_id,
        "name": name,
        "kind": kind,
        "startTimeUnixNano": str(start_time_ns),
        "endTimeUnixNano": str(end_time_ns),
        "attributes": attrs,
        "status": {"code": status_code},
    }
    if parent_span_id:
        span["parentSpanId"] = parent_span_id
    if status_message:
        span["status"]["message"] = status_message
    return span


def build_traces_payload(
    spans: List[Dict[str, Any]],
    service_name: str = "antigravity",
    host_name: Optional[str] = None,
    scope_name: str = "tools/antigravity-telemetry",
    scope_version: str = "1.0.0",
) -> Dict[str, Any]:
    """Wrap a list of spans in standard OTLP /v1/traces payload."""
    host = host_name or get_hostname()
    return {
        "resourceSpans": [
            {
                "resource": build_resource(service_name, host),
                "scopeSpans": [
                    {
                        "scope": {
                            "name": scope_name,
                            "version": scope_version,
                        },
                        "spans": spans,
                    }
                ],
            }
        ]
    }
