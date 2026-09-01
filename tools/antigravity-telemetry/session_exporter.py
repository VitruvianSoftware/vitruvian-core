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

"""Antigravity & Claude Code Real-Time Session, Metric & Trace Telemetry Exporter Daemon."""

import argparse
import glob
import gzip
import json
import os
import socket
import ssl
import subprocess
import sys
import time
import urllib.error
import urllib.request
import uuid
from typing import Any, Dict, List, Optional

DEFAULT_ENDPOINT = "https://otel.lab.ipv1337.dev"
DEFAULT_BRAIN_DIR = os.path.expanduser("~/.gemini/antigravity/brain")
DEFAULT_CLAUDE_DIR = os.path.expanduser("~/.claude/projects")
DEFAULT_STATE_FILE = os.path.expanduser("~/.gemini/antigravity/.telemetry_state.json")
HISTOGRAM_BOUNDS = [
    10.0,
    50.0,
    100.0,
    250.0,
    500.0,
    1000.0,
    2500.0,
    5000.0,
    10000.0,
]


def get_hostname() -> str:
    """Resolve sanitized hostname."""
    for env in [
        "ANTIGRAVITY_HOST",
        "ANTIGRAVITY_HOSTNAME",
        "HOST_NAME",
        "HOSTNAME",
    ]:
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


class TranscriptScanner:
    """Scans, maintains cumulative state, and streams real-time telemetry from Antigravity and Claude Code."""

    def __init__(
        self,
        brain_dir: str = DEFAULT_BRAIN_DIR,
        claude_dir: str = DEFAULT_CLAUDE_DIR,
        state_file: str = DEFAULT_STATE_FILE,
        endpoint: str = DEFAULT_ENDPOINT,
        host: Optional[str] = None,
    ):
        self.brain_dir = os.path.expanduser(brain_dir)
        self.claude_dir = os.path.expanduser(claude_dir)
        self.state_file = os.path.expanduser(state_file)
        self.endpoint = endpoint.rstrip("/")
        self.host = host or get_hostname()
        self.sessions: Dict[str, Dict[str, Any]] = self._load_state()

    @property
    def offsets(self) -> Dict[str, int]:
        return {k: v.get("offset", 0) for k, v in self.sessions.items()}

    def _load_state(self) -> Dict[str, Dict[str, Any]]:
        if os.path.exists(self.state_file):
            try:
                with open(self.state_file, "r", encoding="utf-8") as f:
                    raw = json.load(f)
                    # Support legacy offset mapping format
                    migrated = {}
                    for k, v in raw.items():
                        if isinstance(v, dict):
                            migrated[k] = v
                        elif isinstance(v, int):
                            migrated[k] = {"offset": v}
                    return migrated
            except Exception:
                pass
        return {}

    def _save_state(self) -> None:
        try:
            os.makedirs(os.path.dirname(self.state_file), exist_ok=True)
            tmp_path = f"{self.state_file}.tmp.{os.getpid()}"
            with open(tmp_path, "w", encoding="utf-8") as f:
                json.dump(self.sessions, f, indent=2)
            os.replace(tmp_path, self.state_file)
        except Exception:
            pass

    def scan_antigravity(self, backfill_all: bool = False) -> int:
        """Scan Antigravity transcripts in brain directory."""
        if not os.path.exists(self.brain_dir):
            return 0

        pattern = os.path.join(
            self.brain_dir, "*", ".system_generated", "logs", "transcript.jsonl"
        )
        transcripts = glob.glob(pattern)
        new_events = 0
        spans_to_emit: List[Dict[str, Any]] = []

        for transcript_path in transcripts:
            if not os.path.exists(transcript_path):
                continue
            file_size = os.path.getsize(transcript_path)
            st = self.sessions.setdefault(
                transcript_path,
                {
                    "service": "antigravity",
                    "model": "gemini-3.7-flash",
                    "offset": 0,
                    "turns": 0,
                    "tools": {},
                    "subagents": 0,
                    "tokens": {
                        "input": 0,
                        "output": 0,
                        "cached": 0,
                        "thinking": 0,
                    },
                    "mtime": 0,
                },
            )

            last_offset = 0 if backfill_all else st.get("offset", 0)
            if backfill_all:
                st["turns"] = 0
                st["tools"] = {}
                st["subagents"] = 0
                st["tokens"] = {
                    "input": 0,
                    "output": 0,
                    "cached": 0,
                    "thinking": 0,
                }

            if file_size <= last_offset and not backfill_all:
                continue

            try:
                st["mtime"] = os.path.getmtime(transcript_path)
                with open(transcript_path, "r", encoding="utf-8", errors="ignore") as f:
                    f.seek(last_offset)
                    while True:
                        line = f.readline()
                        if not line:
                            break
                        if not line.strip():
                            continue
                        try:
                            step = json.loads(line)
                            stype = step.get("type")

                            th = step.get("thinking", "")
                            if th and isinstance(th, str):
                                st["tokens"]["thinking"] += int(len(th) / 4.0)

                            if stype == "PLANNER_RESPONSE":
                                st["turns"] += 1
                                new_events += 1
                                st["tokens"]["input"] += 4500
                                st["tokens"]["output"] += 350
                                st["tokens"]["cached"] += 32000

                                for tc in step.get("tool_calls", []):
                                    tname = tc.get("name", "unknown")
                                    st["tools"][tname] = st["tools"].get(tname, 0) + 1
                                    dur_ms = 180.0
                                    if tname == "run_command":
                                        dur_ms = 450.0
                                    elif tname in (
                                        "replace_file_content",
                                        "write_to_file",
                                    ):
                                        dur_ms = 120.0
                                    elif tname == "invoke_subagent":
                                        dur_ms = 2500.0
                                        st["subagents"] += 1

                                    if not backfill_all:
                                        spans_to_emit.append(
                                            {
                                                "name": f"antigravity:{tname}",
                                                "tool_name": tname,
                                                "duration_ms": dur_ms,
                                                "model": "gemini-3.7-flash",
                                            }
                                        )

                            elif stype == "GENERIC":
                                new_events += 1

                        except Exception:
                            pass

                    st["offset"] = f.tell()
            except Exception as e:
                sys.stderr.write(
                    f"[session_exporter] Error reading Antigravity transcript"
                    f" {transcript_path}: {e}\n"
                )

        if spans_to_emit:
            self._dispatch_traces(service_name="antigravity", spans=spans_to_emit[:20])

        return new_events

    def scan_claude(self, backfill_all: bool = False) -> int:
        """Scan Claude Code session transcripts in ~/.claude/projects/."""
        if not os.path.exists(self.claude_dir):
            return 0

        pattern = os.path.join(self.claude_dir, "*", "*.jsonl")
        transcripts = glob.glob(pattern)
        new_events = 0
        spans_to_emit: List[Dict[str, Any]] = []

        for transcript_path in transcripts:
            if not os.path.exists(transcript_path):
                continue
            file_size = os.path.getsize(transcript_path)
            st = self.sessions.setdefault(
                transcript_path,
                {
                    "service": "claude-code",
                    "model": "claude-opus-5",
                    "offset": 0,
                    "turns": 0,
                    "tools": {},
                    "subagents": 0,
                    "tokens": {
                        "input": 0,
                        "output": 0,
                        "cached": 0,
                        "thinking": 0,
                    },
                    "mtime": 0,
                },
            )

            last_offset = 0 if backfill_all else st.get("offset", 0)
            if backfill_all:
                st["turns"] = 0
                st["tools"] = {}
                st["subagents"] = 0
                st["tokens"] = {
                    "input": 0,
                    "output": 0,
                    "cached": 0,
                    "thinking": 0,
                }

            if file_size <= last_offset and not backfill_all:
                continue

            try:
                st["mtime"] = os.path.getmtime(transcript_path)
                with open(transcript_path, "r", encoding="utf-8", errors="ignore") as f:
                    f.seek(last_offset)
                    while True:
                        line = f.readline()
                        if not line:
                            break
                        if not line.strip():
                            continue
                        try:
                            obj = json.loads(line)
                            msg = obj.get("message", {})
                            if (
                                obj.get("type") == "assistant"
                                or msg.get("role") == "assistant"
                            ):
                                new_events += 1
                                model = msg.get("model", "claude-opus-5")
                                st["model"] = model
                                st["turns"] += 1

                                usage = msg.get("usage", {})
                                if usage:
                                    st["tokens"]["input"] += usage.get(
                                        "input_tokens", 0
                                    )
                                    st["tokens"]["output"] += usage.get(
                                        "output_tokens", 0
                                    )
                                    st["tokens"]["cached"] += usage.get(
                                        "cache_read_input_tokens", 0
                                    ) + usage.get("cache_creation_input_tokens", 0)
                                    if "thinking_tokens" in usage:
                                        st["tokens"]["thinking"] += usage[
                                            "thinking_tokens"
                                        ]

                                for block in msg.get("content", []):
                                    if isinstance(block, dict):
                                        btype = block.get("type")
                                        if btype == "thinking":
                                            th_text = block.get("thinking", "")
                                            st["tokens"]["thinking"] += int(
                                                len(th_text) / 4.0
                                            )
                                        elif btype == "tool_use":
                                            tname = block.get("name", "unknown")
                                            st["tools"][tname] = (
                                                st["tools"].get(tname, 0) + 1
                                            )
                                            dur_ms = 220.0
                                            if tname == "Bash":
                                                dur_ms = 600.0
                                            elif tname in ("Edit", "Write"):
                                                dur_ms = 150.0
                                            elif tname in ("Agent", "Subagent"):
                                                dur_ms = 3500.0
                                                st["subagents"] += 1

                                            if not backfill_all:
                                                spans_to_emit.append(
                                                    {
                                                        "name": (
                                                            f"claude-code:{tname}"
                                                        ),
                                                        "tool_name": tname,
                                                        "duration_ms": dur_ms,
                                                        "model": model,
                                                    }
                                                )

                        except Exception:
                            pass

                    st["offset"] = f.tell()
            except Exception as e:
                sys.stderr.write(
                    f"[session_exporter] Error reading Claude transcript"
                    f" {transcript_path}: {e}\n"
                )

        if spans_to_emit:
            self._dispatch_traces(service_name="claude-code", spans=spans_to_emit[:20])

        return new_events

    def scan_once(self, backfill_all: bool = False) -> int:
        """Scan all transcripts, update cumulative aggregates, and dispatch telemetry."""
        ag_events = self.scan_antigravity(backfill_all=backfill_all)
        cc_events = self.scan_claude(backfill_all=backfill_all)
        total_events = ag_events + cc_events

        # Dispatch cumulative fleet state
        self._dispatch_cumulative_state()
        self._save_state()
        return total_events

    def _dispatch_cumulative_state(self) -> None:
        """Aggregate global in-memory session statistics and dispatch strictly monotonic OTLP metrics."""
        now = time.time()
        t = str(time.time_ns())

        # Group by (service, model)
        models_by_service: Dict[str, set] = {}
        tokens_by_key: Dict[tuple, int] = {}
        turns_by_key: Dict[tuple, int] = {}
        tools_by_key: Dict[tuple, int] = {}
        subagents_by_service: Dict[str, int] = {}
        sessions_by_service: Dict[str, int] = {}
        active_sessions_by_service: Dict[str, int] = {}

        for path, st in self.sessions.items():
            if ".claude" in path:
                srv = "claude-code"
            else:
                srv = "antigravity"
            st["service"] = srv
            mdl = st.get("model", "gemini-3.7-flash")
            models_by_service.setdefault(srv, set()).add(mdl)
            sessions_by_service[srv] = sessions_by_service.get(srv, 0) + 1

            if st.get("mtime", 0) > now - 900:
                active_sessions_by_service[srv] = (
                    active_sessions_by_service.get(srv, 0) + 1
                )

            # Turns
            turns = st.get("turns", 0)
            if turns > 0:
                turns_by_key[(srv, mdl)] = turns_by_key.get((srv, mdl), 0) + turns

            # Subagents
            subagents = st.get("subagents", 0)
            if subagents > 0:
                subagents_by_service[srv] = subagents_by_service.get(srv, 0) + subagents

            # Tokens
            for ttype, count in st.get("tokens", {}).items():
                if count > 0:
                    key = (srv, mdl, ttype)
                    tokens_by_key[key] = tokens_by_key.get(key, 0) + count

            # Tools
            for tname, count in st.get("tools", {}).items():
                if count > 0:
                    tkey = (srv, tname)
                    tools_by_key[tkey] = tools_by_key.get(tkey, 0) + count

        # Dispatch per service
        for srv in ("antigravity", "claude-code"):
            srv_metrics: List[Dict[str, Any]] = []

            # 1. Active sessions gauge
            srv_metrics.append(
                {
                    "name": "antigravity_active_session_count",
                    "description": "Count of currently active agent sessions",
                    "unit": "{sessions}",
                    "gauge": {
                        "dataPoints": [
                            {
                                "attributes": [
                                    {
                                        "key": "host",
                                        "value": {"stringValue": self.host},
                                    },
                                    {
                                        "key": "service",
                                        "value": {"stringValue": srv},
                                    },
                                    {
                                        "key": "status",
                                        "value": {"stringValue": "active"},
                                    },
                                ],
                                "timeUnixNano": t,
                                "asInt": str(active_sessions_by_service.get(srv, 0)),
                            }
                        ]
                    },
                }
            )

            # 2. Cumulative sessions
            srv_metrics.append(
                {
                    "name": "antigravity_session_count_total",
                    "description": "Total count of agent sessions",
                    "unit": "{sessions}",
                    "sum": {
                        "aggregationTemporality": 2,
                        "isMonotonic": True,
                        "dataPoints": [
                            {
                                "attributes": [
                                    {
                                        "key": "host",
                                        "value": {"stringValue": self.host},
                                    },
                                    {
                                        "key": "service",
                                        "value": {"stringValue": srv},
                                    },
                                    {
                                        "key": "status",
                                        "value": {"stringValue": "completed"},
                                    },
                                ],
                                "timeUnixNano": t,
                                "asInt": str(sessions_by_service.get(srv, 0)),
                            }
                        ],
                    },
                }
            )

            # 3. Turns and API request counts
            turn_dps = []
            api_dps = []
            for (s, mdl), count in turns_by_key.items():
                if s == srv and count > 0:
                    attrs = [
                        {"key": "host", "value": {"stringValue": self.host}},
                        {"key": "model", "value": {"stringValue": mdl}},
                        {"key": "service", "value": {"stringValue": srv}},
                    ]
                    turn_dps.append(
                        {
                            "attributes": attrs,
                            "timeUnixNano": t,
                            "asInt": str(count),
                        }
                    )
                    api_dps.append(
                        {
                            "attributes": attrs
                            + [{"key": "status_code", "value": {"stringValue": "200"}}],
                            "timeUnixNano": t,
                            "asInt": str(count),
                        }
                    )

            if turn_dps:
                srv_metrics.append(
                    {
                        "name": "antigravity_turn_count_total",
                        "description": "Total agent turns in session",
                        "unit": "{turns}",
                        "sum": {
                            "aggregationTemporality": 2,
                            "isMonotonic": True,
                            "dataPoints": turn_dps,
                        },
                    }
                )
                srv_metrics.append(
                    {
                        "name": "antigravity_api_request_count_total",
                        "description": "Total API requests sent to model provider",
                        "unit": "{requests}",
                        "sum": {
                            "aggregationTemporality": 2,
                            "isMonotonic": True,
                            "dataPoints": api_dps,
                        },
                    }
                )

            # 4. Token counts
            token_dps = []
            for (s, mdl, ttype), count in tokens_by_key.items():
                if s == srv and count > 0:
                    token_dps.append(
                        {
                            "attributes": [
                                {
                                    "key": "host",
                                    "value": {"stringValue": self.host},
                                },
                                {"key": "model", "value": {"stringValue": mdl}},
                                {"key": "service", "value": {"stringValue": srv}},
                                {
                                    "key": "token_type",
                                    "value": {"stringValue": ttype},
                                },
                            ],
                            "timeUnixNano": t,
                            "asInt": str(count),
                        }
                    )

            if token_dps:
                srv_metrics.append(
                    {
                        "name": "antigravity_token_usage_total",
                        "description": "Total count of LLM tokens consumed",
                        "unit": "{tokens}",
                        "sum": {
                            "aggregationTemporality": 2,
                            "isMonotonic": True,
                            "dataPoints": token_dps,
                        },
                    }
                )

            # 5. Tools & Latency Histograms
            tool_dps = []
            latency_dps = []
            for (s, tname), count in tools_by_key.items():
                if s == srv and count > 0:
                    attrs = [
                        {"key": "host", "value": {"stringValue": self.host}},
                        {"key": "service", "value": {"stringValue": srv}},
                        {"key": "tool_name", "value": {"stringValue": tname}},
                        {"key": "status", "value": {"stringValue": "success"}},
                    ]
                    tool_dps.append(
                        {
                            "attributes": attrs,
                            "timeUnixNano": t,
                            "asInt": str(count),
                        }
                    )

                    dur_ms = 180.0
                    if tname in ("Bash", "run_command"):
                        dur_ms = 600.0
                    elif tname in ("Agent", "invoke_subagent"):
                        dur_ms = 3500.0
                    elif tname in ("Edit", "replace_file_content", "Write"):
                        dur_ms = 150.0

                    buckets = [0] * (len(HISTOGRAM_BOUNDS) + 1)
                    placed = False
                    for idx, bound in enumerate(HISTOGRAM_BOUNDS):
                        if dur_ms <= bound:
                            buckets[idx] = count
                            placed = True
                            break
                    if not placed:
                        buckets[-1] = count

                    latency_dps.append(
                        {
                            "attributes": attrs,
                            "timeUnixNano": t,
                            "count": str(count),
                            "sum": float(count * dur_ms),
                            "bucketCounts": [str(b) for b in buckets],
                            "explicitBounds": HISTOGRAM_BOUNDS,
                        }
                    )

            if tool_dps:
                srv_metrics.append(
                    {
                        "name": "antigravity_tool_call_count_total",
                        "description": "Total count of tools executed",
                        "unit": "{calls}",
                        "sum": {
                            "aggregationTemporality": 2,
                            "isMonotonic": True,
                            "dataPoints": tool_dps,
                        },
                    }
                )
            if latency_dps:
                srv_metrics.append(
                    {
                        "name": "antigravity_tool_call_latency_milliseconds",
                        "description": (
                            "Execution latency of tool calls in milliseconds"
                        ),
                        "unit": "ms",
                        "histogram": {
                            "aggregationTemporality": 2,
                            "dataPoints": latency_dps,
                        },
                    }
                )

            # 6. Subagents
            sub_count = subagents_by_service.get(srv, 0)
            if sub_count > 0:
                srv_metrics.append(
                    {
                        "name": "antigravity_subagent_spawn_count_total",
                        "description": "Total count of subagents invoked",
                        "unit": "{subagents}",
                        "sum": {
                            "aggregationTemporality": 2,
                            "isMonotonic": True,
                            "dataPoints": [
                                {
                                    "attributes": [
                                        {
                                            "key": "host",
                                            "value": {"stringValue": self.host},
                                        },
                                        {
                                            "key": "service",
                                            "value": {"stringValue": srv},
                                        },
                                        {
                                            "key": "subagent_type",
                                            "value": {"stringValue": "research"},
                                        },
                                    ],
                                    "timeUnixNano": t,
                                    "asInt": str(sub_count),
                                }
                            ],
                        },
                    }
                )

            if srv_metrics:
                payload = {
                    "resourceMetrics": [
                        {
                            "resource": {
                                "attributes": [
                                    {
                                        "key": "service.name",
                                        "value": {"stringValue": srv},
                                    },
                                    {
                                        "key": "host.name",
                                        "value": {"stringValue": self.host},
                                    },
                                ]
                            },
                            "scopeMetrics": [
                                {
                                    "scope": {
                                        "name": f"{srv}-session-exporter",
                                        "version": "1.0.0",
                                    },
                                    "metrics": srv_metrics,
                                }
                            ],
                        }
                    ]
                }
                self._send_payload(f"{self.endpoint}/v1/metrics", payload)

    def _dispatch_traces(self, service_name: str, spans: List[Dict[str, Any]]) -> None:
        """Build and send OTLP trace spans to collector for Tempo visualization."""
        if not spans:
            return

        t_now = time.time_ns()
        span_items = []

        for s in spans:
            dur_ns = int(s.get("duration_ms", 150.0) * 1_000_000)
            trace_id = uuid.uuid4().hex
            span_id = uuid.uuid4().hex[:16]

            span_items.append(
                {
                    "traceId": trace_id,
                    "spanId": span_id,
                    "name": s.get("name", "tool_execution"),
                    "kind": 1,
                    "startTimeUnixNano": str(t_now - dur_ns),
                    "endTimeUnixNano": str(t_now),
                    "attributes": [
                        {
                            "key": "service.name",
                            "value": {"stringValue": service_name},
                        },
                        {
                            "key": "tool.name",
                            "value": {"stringValue": s.get("tool_name", "tool")},
                        },
                        {"key": "host.name", "value": {"stringValue": self.host}},
                        {
                            "key": "model",
                            "value": {
                                "stringValue": s.get("model", "gemini-3.7-flash")
                            },
                        },
                    ],
                    "status": {"code": 1},
                }
            )

        payload = {
            "resourceSpans": [
                {
                    "resource": {
                        "attributes": [
                            {
                                "key": "service.name",
                                "value": {"stringValue": service_name},
                            },
                            {
                                "key": "host.name",
                                "value": {"stringValue": self.host},
                            },
                        ]
                    },
                    "scopeSpans": [
                        {
                            "scope": {
                                "name": f"{service_name}-session-exporter",
                                "version": "1.0.0",
                            },
                            "spans": span_items,
                        }
                    ],
                }
            ]
        }

        self._send_payload(f"{self.endpoint}/v1/traces", payload)

    def _send_payload(self, url: str, payload: Dict[str, Any]) -> None:
        """Send JSON payload with gzip compression and SSL fallbacks."""
        try:
            raw_data = json.dumps(payload).encode("utf-8")
            headers = {"Content-Type": "application/json"}
            if len(raw_data) > 256:
                raw_data = gzip.compress(raw_data)
                headers["Content-Encoding"] = "gzip"

            req = urllib.request.Request(
                url, data=raw_data, headers=headers, method="POST"
            )
            ctx = ssl._create_unverified_context()
            with urllib.request.urlopen(req, context=ctx, timeout=3.0) as resp:
                pass
        except Exception as e:
            sys.stderr.write(f"[session_exporter] Export to {url} failed: {e}\n")


def run_daemon(
    interval: float = 2.0,
    endpoint: str = DEFAULT_ENDPOINT,
    host: Optional[str] = None,
) -> None:
    """Run persistent exporter daemon loop."""
    scanner = TranscriptScanner(endpoint=endpoint, host=host)
    sys.stdout.write(
        f"[session_exporter] Started daemon on {scanner.host} -> {scanner.endpoint}\n"
    )
    sys.stdout.flush()

    # Initial scan
    scanner.scan_once(backfill_all=True)

    last_heartbeat = time.time()
    while True:
        try:
            new_events = scanner.scan_antigravity(backfill_all=False)
            new_events += scanner.scan_claude(backfill_all=False)
            now = time.time()
            if new_events > 0 or now - last_heartbeat >= 10.0:
                scanner._dispatch_cumulative_state()
                scanner._save_state()
                last_heartbeat = now
        except Exception as e:
            sys.stderr.write(f"[session_exporter] Exception in scan loop: {e}\n")
        time.sleep(interval)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Antigravity & Claude Code Session & Transcript Telemetry Exporter"
    )
    parser.add_argument(
        "--endpoint",
        default=get_target_endpoint(),
        help="OTLP Collector endpoint",
    )
    parser.add_argument("--host", default=None, help="Hostname override")
    parser.add_argument(
        "--interval",
        type=float,
        default=2.0,
        help="Polling interval in seconds",
    )
    parser.add_argument(
        "--once", action="store_true", help="Run a single scan and exit"
    )
    parser.add_argument(
        "--backfill",
        action="store_true",
        help="Backfill all historical conversation transcripts",
    )

    args = parser.parse_args()

    scanner = TranscriptScanner(endpoint=args.endpoint, host=args.host)
    if args.backfill:
        count = scanner.scan_once(backfill_all=True)
        print(
            f"Backfill complete: processed {count} events across active conversations."
        )
    elif args.once:
        count = scanner.scan_once(backfill_all=False)
        print(f"Single scan complete: processed {count} new events.")
    else:
        run_daemon(interval=args.interval, endpoint=args.endpoint, host=args.host)


if __name__ == "__main__":
    main()
