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

"""Antigravity & Claude Code Real-Time Session & Transcript Telemetry Exporter Daemon."""

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
from typing import Any, Dict, List, Optional, Tuple

DEFAULT_ENDPOINT = "https://otel.lab.ipv1337.dev"
DEFAULT_BRAIN_DIR = os.path.expanduser("~/.gemini/antigravity/brain")
DEFAULT_CLAUDE_DIR = os.path.expanduser("~/.claude/projects")
DEFAULT_STATE_FILE = os.path.expanduser("~/.gemini/antigravity/.telemetry_state.json")


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
    """Scans and streams incremental transcript events from active Antigravity and Claude Code sessions."""

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

        total_new_events = 0
        tool_counts: Dict[str, int] = {}
        new_turns = 0
        new_subagents = 0

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

                            if stype == "PLANNER_RESPONSE":
                                new_turns += 1
                                total_new_events += 1
                                tool_calls = step.get("tool_calls", [])
                                for tc in tool_calls:
                                    tname = tc.get("name", "unknown")
                                    tool_counts[tname] = tool_counts.get(tname, 0) + 1
                                    if tname == "invoke_subagent":
                                        new_subagents += 1

                            elif stype == "GENERIC":
                                total_new_events += 1

                        except Exception:
                            pass

                    self.offsets[transcript_path] = f.tell()
            except Exception as e:
                sys.stderr.write(
                    f"[session_exporter] Error reading Antigravity transcript {transcript_path}: {e}\n"
                )

        if total_new_events > 0 and (new_turns > 0 or tool_counts):
            self._dispatch_metrics(
                service_name="antigravity",
                model="gemini-3.7-flash",
                turns=new_turns,
                tool_counts=tool_counts,
                subagents=new_subagents,
                tokens=None,
            )

        return total_new_events

    def scan_claude(self, backfill_all: bool = False) -> int:
        """Scan Claude Code session transcripts in ~/.claude/projects/."""
        if not os.path.exists(self.claude_dir):
            return 0

        pattern = os.path.join(self.claude_dir, "*", "*.jsonl")
        transcripts = glob.glob(pattern)

        total_new_events = 0
        model_stats: Dict[str, Dict[str, Any]] = {}

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

                                content = msg.get("content", [])
                                if isinstance(content, list):
                                    for block in content:
                                        if (
                                            isinstance(block, dict)
                                            and block.get("type") == "tool_use"
                                        ):
                                            tname = block.get("name", "unknown")
                                            st["tools"][tname] = (
                                                st["tools"].get(tname, 0) + 1
                                            )
                                            if tname in ("Agent", "Subagent"):
                                                st["subagents"] += 1

                        except Exception:
                            pass

                    self.offsets[transcript_path] = f.tell()
            except Exception as e:
                sys.stderr.write(
                    f"[session_exporter] Error reading Claude transcript {transcript_path}: {e}\n"
                )

        for model, st in model_stats.items():
            if st["turns"] > 0 or st["tools"] or sum(st["tokens"].values()) > 0:
                self._dispatch_metrics(
                    service_name="claude-code",
                    model=model,
                    turns=st["turns"],
                    tool_counts=st["tools"],
                    subagents=st["subagents"],
                    tokens=st["tokens"],
                )

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
        subagents: int,
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

        tool_dps = []
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

        try:
            raw_data = json.dumps(payload).encode("utf-8")
            headers = {"Content-Type": "application/json"}
            if len(raw_data) > 256:
                raw_data = gzip.compress(raw_data)
                headers["Content-Encoding"] = "gzip"

            req = urllib.request.Request(
                f"{self.endpoint}/v1/metrics",
                data=raw_data,
                headers=headers,
                method="POST",
            )
            ctx = ssl._create_unverified_context()
            with urllib.request.urlopen(req, context=ctx, timeout=3.0) as resp:
                pass
        except Exception as e:
            sys.stderr.write(f"[session_exporter] OTLP export failed: {e}\n")


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
