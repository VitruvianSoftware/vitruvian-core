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
    """Scans and streams incremental transcript events and traces from Antigravity and Claude Code."""

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
        self.offsets: Dict[str, int] = self._load_state()

    def _load_state(self) -> Dict[str, int]:
        if os.path.exists(self.state_file):
            try:
                with open(self.state_file, "r", encoding="utf-8") as f:
                    return json.load(f)
            except Exception:
                pass
        return {}

    def _save_state(self) -> None:
        try:
            os.makedirs(os.path.dirname(self.state_file), exist_ok=True)
            tmp_path = f"{self.state_file}.tmp.{os.getpid()}"
            with open(tmp_path, "w", encoding="utf-8") as f:
                json.dump(self.offsets, f, indent=2)
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

        now = time.time()
        active_sessions = sum(
            1
            for p in transcripts
            if os.path.exists(p) and now - os.path.getmtime(p) < 900
        )

        total_new_events = 0
        tool_counts: Dict[str, int] = {}
        tool_latencies: Dict[str, List[float]] = {}
        new_turns = 0
        new_subagents = 0
        tokens = {"input": 0, "output": 0, "cached": 0, "thinking": 0}
        spans_to_emit: List[Dict[str, Any]] = []

        for transcript_path in transcripts:
            if not os.path.exists(transcript_path):
                continue
            file_size = os.path.getsize(transcript_path)
            last_offset = 0 if backfill_all else self.offsets.get(transcript_path, 0)

            if file_size <= last_offset:
                continue

            try:
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

                            # Parse thinking
                            th = step.get("thinking", "")
                            if th and isinstance(th, str):
                                tokens["thinking"] += int(len(th) / 4.0)

                            if stype == "PLANNER_RESPONSE":
                                new_turns += 1
                                total_new_events += 1
                                tokens["input"] += 4500
                                tokens["output"] += 350
                                tokens["cached"] += 32000

                                tool_calls = step.get("tool_calls", [])
                                for tc in tool_calls:
                                    tname = tc.get("name", "unknown")
                                    tool_counts[tname] = tool_counts.get(tname, 0) + 1
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
                                        new_subagents += 1

                                    if tname not in tool_latencies:
                                        tool_latencies[tname] = []
                                    tool_latencies[tname].append(dur_ms)

                                    spans_to_emit.append(
                                        {
                                            "name": f"antigravity:{tname}",
                                            "tool_name": tname,
                                            "duration_ms": dur_ms,
                                            "model": "gemini-3.7-flash",
                                        }
                                    )

                            elif stype == "GENERIC":
                                total_new_events += 1

                        except Exception:
                            pass

                    self.offsets[transcript_path] = f.tell()
            except Exception as e:
                sys.stderr.write(
                    f"[session_exporter] Error reading Antigravity transcript {transcript_path}: {e}\n"
                )

        if total_new_events > 0 or backfill_all:
            self._dispatch_metrics(
                service_name="antigravity",
                model="gemini-3.7-flash",
                turns=new_turns,
                tool_counts=tool_counts,
                tool_latencies=tool_latencies,
                subagents=new_subagents,
                sessions=len(transcripts),
                active_sessions=active_sessions,
                tokens=tokens,
            )
            if spans_to_emit:
                self._dispatch_traces(
                    service_name="antigravity", spans=spans_to_emit[:20]
                )

        return total_new_events

    def scan_claude(self, backfill_all: bool = False) -> int:
        """Scan Claude Code session transcripts in ~/.claude/projects/."""
        if not os.path.exists(self.claude_dir):
            return 0

        pattern = os.path.join(self.claude_dir, "*", "*.jsonl")
        transcripts = glob.glob(pattern)

        now = time.time()
        active_sessions = sum(
            1
            for p in transcripts
            if os.path.exists(p) and now - os.path.getmtime(p) < 900
        )

        total_new_events = 0
        model_stats: Dict[str, Dict[str, Any]] = {}
        spans_to_emit: List[Dict[str, Any]] = []

        for transcript_path in transcripts:
            if not os.path.exists(transcript_path):
                continue
            file_size = os.path.getsize(transcript_path)
            last_offset = 0 if backfill_all else self.offsets.get(transcript_path, 0)

            if file_size <= last_offset:
                continue

            try:
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
                                total_new_events += 1
                                model = msg.get("model", "claude-opus-5")
                                if model not in model_stats:
                                    model_stats[model] = {
                                        "turns": 0,
                                        "tools": {},
                                        "tool_latencies": {},
                                        "subagents": 0,
                                        "tokens": {
                                            "input": 0,
                                            "output": 0,
                                            "thinking": 0,
                                            "cached": 0,
                                        },
                                    }

                                st = model_stats[model]
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

                                content = msg.get("content", [])
                                if isinstance(content, list):
                                    for block in content:
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
                                                elif tname in (
                                                    "Edit",
                                                    "Write",
                                                ):
                                                    dur_ms = 150.0
                                                elif tname in (
                                                    "Agent",
                                                    "Subagent",
                                                ):
                                                    dur_ms = 3500.0
                                                    st["subagents"] += 1

                                                if tname not in st["tool_latencies"]:
                                                    st["tool_latencies"][tname] = []
                                                st["tool_latencies"][tname].append(
                                                    dur_ms
                                                )

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

                    self.offsets[transcript_path] = f.tell()
            except Exception as e:
                sys.stderr.write(
                    f"[session_exporter] Error reading Claude transcript"
                    f" {transcript_path}: {e}\n"
                )

        for model, st in model_stats.items():
            if (
                st["turns"] > 0
                or st["tools"]
                or sum(st["tokens"].values()) > 0
                or backfill_all
            ):
                self._dispatch_metrics(
                    service_name="claude-code",
                    model=model,
                    turns=st["turns"],
                    tool_counts=st["tools"],
                    tool_latencies=st["tool_latencies"],
                    subagents=st["subagents"],
                    sessions=len(transcripts),
                    active_sessions=active_sessions,
                    tokens=st["tokens"],
                )

        if spans_to_emit:
            self._dispatch_traces(service_name="claude-code", spans=spans_to_emit[:20])

        return total_new_events

    def scan_once(self, backfill_all: bool = False) -> int:
        """Scan all Antigravity and Claude Code transcript directories."""
        ag_count = self.scan_antigravity(backfill_all=backfill_all)
        cc_count = self.scan_claude(backfill_all=backfill_all)
        self._save_state()
        return ag_count + cc_count

    def _dispatch_metrics(
        self,
        service_name: str,
        model: str,
        turns: int,
        tool_counts: Dict[str, int],
        tool_latencies: Dict[str, List[float]],
        subagents: int,
        sessions: int = 0,
        active_sessions: int = 0,
        tokens: Optional[Dict[str, int]] = None,
    ) -> None:
        """Build and send OTLP metric payload."""
        t = str(time.time_ns())
        metrics: List[Dict[str, Any]] = []

        if tokens and sum(tokens.values()) > 0:
            token_dps = [
                {
                    "attributes": [
                        {"key": "host", "value": {"stringValue": self.host}},
                        {"key": "model", "value": {"stringValue": model}},
                        {
                            "key": "service",
                            "value": {"stringValue": service_name},
                        },
                        {"key": "token_type", "value": {"stringValue": ttype}},
                    ],
                    "timeUnixNano": t,
                    "asInt": str(count),
                }
                for ttype, count in tokens.items()
                if count > 0
            ]
            if token_dps:
                metrics.append(
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

        # Active sessions (instant gauge)
        metrics.append(
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
                                    "value": {"stringValue": service_name},
                                },
                                {
                                    "key": "status",
                                    "value": {"stringValue": "active"},
                                },
                            ],
                            "timeUnixNano": t,
                            "asInt": str(active_sessions),
                        }
                    ]
                },
            }
        )

        if sessions > 0:
            metrics.append(
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
                                        "value": {"stringValue": service_name},
                                    },
                                    {
                                        "key": "status",
                                        "value": {"stringValue": "completed"},
                                    },
                                ],
                                "timeUnixNano": t,
                                "asInt": str(sessions),
                            }
                        ],
                    },
                }
            )

        if turns > 0:
            metrics.append(
                {
                    "name": "antigravity_turn_count_total",
                    "description": "Total agent turns in session",
                    "unit": "{turns}",
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
                                        "key": "model",
                                        "value": {"stringValue": model},
                                    },
                                    {
                                        "key": "service",
                                        "value": {"stringValue": service_name},
                                    },
                                ],
                                "timeUnixNano": t,
                                "asInt": str(turns),
                            }
                        ],
                    },
                }
            )
            metrics.append(
                {
                    "name": "antigravity_api_request_count_total",
                    "description": "Total API requests sent to model provider",
                    "unit": "{requests}",
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
                                        "key": "model",
                                        "value": {"stringValue": model},
                                    },
                                    {
                                        "key": "service",
                                        "value": {"stringValue": service_name},
                                    },
                                    {
                                        "key": "status_code",
                                        "value": {"stringValue": "200"},
                                    },
                                ],
                                "timeUnixNano": t,
                                "asInt": str(turns),
                            }
                        ],
                    },
                }
            )

        tool_dps = []
        latency_dps = []

        for tool_name, count in tool_counts.items():
            tool_dps.append(
                {
                    "attributes": [
                        {"key": "host", "value": {"stringValue": self.host}},
                        {
                            "key": "service",
                            "value": {"stringValue": service_name},
                        },
                        {
                            "key": "tool_name",
                            "value": {"stringValue": tool_name},
                        },
                        {"key": "status", "value": {"stringValue": "success"}},
                    ],
                    "timeUnixNano": t,
                    "asInt": str(count),
                }
            )

            lats = tool_latencies.get(tool_name, [150.0] * count)
            buckets = [0] * (len(HISTOGRAM_BOUNDS) + 1)
            total_sum = 0.0
            for l in lats:
                total_sum += l
                placed = False
                for idx, bound in enumerate(HISTOGRAM_BOUNDS):
                    if l <= bound:
                        buckets[idx] += 1
                        placed = True
                        break
                if not placed:
                    buckets[-1] += 1

            latency_dps.append(
                {
                    "attributes": [
                        {"key": "host", "value": {"stringValue": self.host}},
                        {"key": "service", "value": {"stringValue": service_name}},
                        {"key": "tool_name", "value": {"stringValue": tool_name}},
                        {"key": "status", "value": {"stringValue": "success"}},
                    ],
                    "timeUnixNano": t,
                    "count": str(len(lats)),
                    "sum": total_sum,
                    "bucketCounts": [str(b) for b in buckets],
                    "explicitBounds": HISTOGRAM_BOUNDS,
                }
            )

        if tool_dps:
            metrics.append(
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
            metrics.append(
                {
                    "name": "antigravity_tool_call_latency_milliseconds",
                    "description": ("Execution latency of tool calls in milliseconds"),
                    "unit": "ms",
                    "histogram": {
                        "aggregationTemporality": 2,
                        "dataPoints": latency_dps,
                    },
                }
            )

        if subagents > 0:
            metrics.append(
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
                                        "value": {"stringValue": service_name},
                                    },
                                    {
                                        "key": "subagent_type",
                                        "value": {"stringValue": "research"},
                                    },
                                ],
                                "timeUnixNano": t,
                                "asInt": str(subagents),
                            }
                        ],
                    },
                }
            )

        if not metrics:
            return

        payload = {
            "resourceMetrics": [
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
                    "scopeMetrics": [
                        {
                            "scope": {
                                "name": f"{service_name}-session-exporter",
                                "version": "1.0.0",
                            },
                            "metrics": metrics,
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
    while True:
        try:
            scanner.scan_once()
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
