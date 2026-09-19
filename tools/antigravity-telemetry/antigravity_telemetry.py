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

"""Antigravity & AGY Telemetry CLI: Setup, Diagnostics, Emission, and Real-time Exporter."""

import argparse
import copy
import datetime
import glob
import json
import os
import pathlib
import platform
import shutil
import subprocess
import sys
import time
from typing import Any, Dict, List, Optional, Tuple

_CURR_DIR = os.path.dirname(os.path.abspath(__file__))
if _CURR_DIR not in sys.path:
    sys.path.insert(0, _CURR_DIR)

from http_client import TelemetryHttpClient
from otlp_builder import (
    DEFAULT_LATENCY_BOUNDS,
    build_api_request_metric,
    build_metrics_payload,
    build_resource,
    build_session_count_metric,
    build_span,
    build_subagent_spawn_metric,
    build_token_usage_metric,
    build_tool_call_count_metric,
    build_tool_call_latency_metric,
    build_traces_payload,
    build_turn_count_metric,
    get_hostname,
)
from telemetry_hook import process_event

DEFAULT_ENDPOINT = "https://otel.lab.ipv1337.dev"
# Gemini CLI's settings file. Google retired that CLI for individual accounts,
# and `agy` never reads this path — it is kept only so `setup` can clean the
# dead telemetry hooks it used to install here.
LEGACY_GEMINI_SETTINGS_PATH = os.path.expanduser("~/.gemini/settings.json")
DEFAULT_SETTINGS_PATH = LEGACY_GEMINI_SETTINGS_PATH
# Where the transcript exporter and its launchd job live.
DEFAULT_HOOKS_DIR = os.path.expanduser("~/.gemini/hooks")
DEFAULT_HOOK_NAME = "telemetry_hook.py"
EXPORTER_NAME = "session_exporter.py"
LAUNCH_AGENT_LABEL = "com.google.antigravity.telemetry"
LAUNCH_AGENT_PATH = os.path.expanduser(
    f"~/Library/LaunchAgents/{LAUNCH_AGENT_LABEL}.plist"
)
EXPORTER_LOG_DIR = os.path.expanduser("~/.gemini/antigravity/logs")


def get_default_settings_path() -> str:
    """Return default settings.json path respecting environment override."""
    return os.environ.get("GEMINI_SETTINGS_PATH", DEFAULT_SETTINGS_PATH)


def strip_legacy_hooks(
    existing_settings: Dict[str, Any],
) -> Tuple[Dict[str, Any], List[str]]:
    """Remove the telemetry hooks earlier versions wrote into Gemini CLI's
    settings.json.

    Nothing executes them any more: Gemini CLI is retired for individual
    accounts, and `agy` never opens this file (its own config lives in
    ~/.gemini/antigravity-cli/settings.json and ~/.gemini/config/). Returns the
    cleaned settings and the event names that were touched.
    """
    updated = copy.deepcopy(existing_settings)
    removed: List[str] = []
    hooks = updated.get("hooks")
    if not isinstance(hooks, dict):
        return updated, removed

    for event_name in list(hooks.keys()):
        matchers = hooks.get(event_name)
        if not isinstance(matchers, list):
            continue
        kept_matchers = []
        for matcher in matchers:
            if not isinstance(matcher, dict):
                kept_matchers.append(matcher)
                continue
            inner = matcher.get("hooks")
            if not isinstance(inner, list):
                kept_matchers.append(matcher)
                continue
            kept = [
                h
                for h in inner
                if not (
                    isinstance(h, dict)
                    and (
                        h.get("name") == "telemetry-hook"
                        or "telemetry_hook" in str(h.get("command", ""))
                        or "stream-hook" in str(h.get("command", ""))
                        or "stream_hook" in str(h.get("command", ""))
                    )
                )
            ]
            if len(kept) != len(inner):
                removed.append(event_name)
            if kept:
                matcher["hooks"] = kept
                kept_matchers.append(matcher)
        if kept_matchers:
            hooks[event_name] = kept_matchers
        else:
            del hooks[event_name]

    if not hooks:
        updated.pop("hooks", None)
    else:
        updated["hooks"] = hooks
    return updated, sorted(set(removed))


def build_launch_agent_plist(python_path: str, exporter_path: str) -> str:
    """launchd job that keeps the transcript exporter running."""
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>{LAUNCH_AGENT_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>{python_path}</string>
        <string>{exporter_path}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>{EXPORTER_LOG_DIR}/session_exporter.log</string>
    <key>StandardErrorPath</key>
    <string>{EXPORTER_LOG_DIR}/session_exporter.err</string>
</dict>
</plist>
"""


def find_agy() -> Optional[str]:
    """Locate the Antigravity CLI, which is what produces the transcripts."""
    explicit = os.environ.get("AGY_BIN", "")
    if explicit and os.access(explicit, os.X_OK):
        return explicit
    for candidate in (
        os.path.expanduser("~/.local/bin/agy"),
        "/opt/homebrew/bin/agy",
        "/usr/local/bin/agy",
    ):
        if os.access(candidate, os.X_OK):
            return candidate
    return shutil.which("agy")


# ==============================================================================
# Subcommand: setup
# ==============================================================================


def cmd_setup(args: argparse.Namespace) -> int:
    """Install the transcript exporter and clean up the retired Gemini hooks.

    Telemetry comes from `session_exporter.py`, a launchd job that tails the
    transcript JSONL files Antigravity writes and posts OTLP to the collector.
    agy itself has no OTLP exporter and reads no telemetry settings, so
    nothing is written into any agent config here.
    """
    endpoint = args.endpoint.rstrip("/")
    hooks_dir = os.path.abspath(os.path.expanduser(args.hooks_dir))
    exporter_dest = os.path.join(hooks_dir, EXPORTER_NAME)
    settings_path = os.path.abspath(os.path.expanduser(args.settings_path))

    current_dir = os.path.dirname(os.path.abspath(__file__))
    source_exporter = os.path.join(current_dir, EXPORTER_NAME)
    python_path = os.environ.get("ANTIGRAVITY_TELEMETRY_PYTHON", "/usr/bin/python3")

    results: Dict[str, Any] = {
        "status": "success",
        "exporter": exporter_dest,
        "launch_agent": LAUNCH_AGENT_PATH,
        "endpoint": endpoint,
        "agy": find_agy(),
        "dry_run": args.dry_run,
    }

    if not os.path.exists(source_exporter):
        results["status"] = "error"
        results["error"] = f"Exporter source not found: {source_exporter}"
        if args.json:
            print(json.dumps(results, indent=2))
        else:
            sys.stderr.write(results["error"] + "\n")
        return 1

    if not args.dry_run:
        os.makedirs(hooks_dir, mode=0o755, exist_ok=True)
        os.makedirs(EXPORTER_LOG_DIR, mode=0o755, exist_ok=True)
        shutil.copy2(source_exporter, exporter_dest)
        os.chmod(exporter_dest, 0o755)

        os.makedirs(os.path.dirname(LAUNCH_AGENT_PATH), mode=0o755, exist_ok=True)
        with open(LAUNCH_AGENT_PATH, "w", encoding="utf-8") as f:
            f.write(build_launch_agent_plist(python_path, exporter_dest))

        # Reload so the new exporter is the one running.
        uid = os.getuid()
        subprocess.run(
            ["/bin/launchctl", "bootout", f"gui/{uid}/{LAUNCH_AGENT_LABEL}"],
            capture_output=True,
            check=False,
        )
        boot = subprocess.run(
            ["/bin/launchctl", "bootstrap", f"gui/{uid}", LAUNCH_AGENT_PATH],
            capture_output=True,
            check=False,
        )
        results["launch_agent_loaded"] = boot.returncode == 0
        if boot.returncode != 0:
            results["launch_agent_error"] = boot.stderr.decode(
                "utf-8", "replace"
            ).strip()

    # Clean the hooks earlier versions wrote into Gemini CLI's settings.json.
    removed_events: List[str] = []
    if os.path.exists(settings_path):
        try:
            with open(settings_path, "r", encoding="utf-8") as f:
                content = f.read().strip()
            existing_settings = json.loads(content) if content else {}
        except Exception as e:
            results["legacy_cleanup"] = f"skipped, unreadable: {e}"
            existing_settings = None
        if existing_settings is not None:
            cleaned, removed_events = strip_legacy_hooks(existing_settings)
            if removed_events and not args.dry_run:
                if not args.no_backup:
                    ts = datetime.datetime.now().strftime("%Y%m%d%H%M%S")
                    backup_path = f"{settings_path}.bak.{ts}"
                    shutil.copy2(settings_path, backup_path)
                    results["backup_path"] = backup_path
                tmp_path = f"{settings_path}.tmp.{os.getpid()}"
                with open(tmp_path, "w", encoding="utf-8") as f:
                    json.dump(cleaned, f, indent=2)
                    f.write("\n")
                os.replace(tmp_path, settings_path)
    results["legacy_hooks_removed"] = removed_events

    if args.json:
        print(json.dumps(results, indent=2))
    else:
        print("Antigravity Telemetry Setup")
        print("==========================")
        print(f"Collector endpoint: {endpoint}")
        print(f"Exporter:           {exporter_dest}")
        print(f"launchd job:        {LAUNCH_AGENT_PATH}")
        print(f"agy binary:         {results['agy'] or 'NOT FOUND'}")
        if removed_events:
            print(
                f"Removed dead Gemini CLI hooks from {settings_path}: {', '.join(removed_events)}"
            )
        if args.dry_run:
            print("Mode:               DRY-RUN (no files modified)")
        else:
            print("Status:             Exporter installed and running.")
    return 0


# ==============================================================================
# Subcommand: status
# ==============================================================================


def cmd_status(args: argparse.Namespace) -> int:
    """Report whether telemetry can actually flow, and from what."""
    endpoint = args.endpoint.rstrip("/")
    hooks_dir = os.path.abspath(os.path.expanduser(args.hooks_dir))
    exporter_path = os.path.join(hooks_dir, EXPORTER_NAME)
    settings_path = os.path.abspath(os.path.expanduser(args.settings_path))
    timeout = args.timeout
    host = getattr(args, "host", None) or get_hostname()

    checks: Dict[str, Dict[str, Any]] = {}
    local_passed = True
    remote_passed = True

    # 1. agy — the CLI whose transcripts are the data source
    agy_path = find_agy()
    checks["agy_cli"] = {
        "passed": bool(agy_path),
        "path": agy_path or "",
        "message": f"Found at {agy_path}" if agy_path else "agy not installed",
    }
    if not agy_path:
        local_passed = False

    # 2. transcript directories, per surface
    brain_dirs = {
        "antigravity": os.path.expanduser("~/.gemini/antigravity/brain"),
        "agy": os.path.expanduser("~/.gemini/antigravity-cli/brain"),
        "antigravity-ide": os.path.expanduser("~/.gemini/antigravity-ide/brain"),
    }
    found = {
        name: len(
            glob.glob(
                os.path.join(path, "*", ".system_generated", "logs", "transcript.jsonl")
            )
        )
        for name, path in brain_dirs.items()
    }
    total = sum(found.values())
    checks["transcripts"] = {
        "passed": total > 0,
        "counts": found,
        "message": ", ".join(f"{k}: {v}" for k, v in found.items()) or "none",
    }
    if total == 0:
        local_passed = False

    # 3. exporter script
    if os.path.exists(exporter_path) and os.access(exporter_path, os.X_OK):
        checks["exporter_script"] = {
            "passed": True,
            "path": exporter_path,
            "message": "Installed and executable",
        }
    else:
        local_passed = False
        checks["exporter_script"] = {
            "passed": False,
            "path": exporter_path,
            "message": "Missing or not executable — run `setup`",
        }

    # 4. launchd job actually running
    running = subprocess.run(
        ["/usr/bin/pgrep", "-f", EXPORTER_NAME], capture_output=True, check=False
    )
    pid = (
        running.stdout.decode().split("\n")[0].strip()
        if running.returncode == 0
        else ""
    )
    checks["exporter_running"] = {
        "passed": bool(pid),
        "pid": pid,
        "launch_agent": LAUNCH_AGENT_PATH,
        "message": f"Running (pid {pid})" if pid else "Not running — run `setup`",
    }
    if not pid:
        local_passed = False

    # 5. leftovers from the Gemini CLI era, which nothing executes
    legacy: List[str] = []
    if os.path.exists(settings_path):
        try:
            with open(settings_path, "r", encoding="utf-8") as f:
                content = f.read().strip()
            data = json.loads(content) if content else {}
            _, legacy = strip_legacy_hooks(data)
        except Exception:
            legacy = []
    checks["legacy_gemini_hooks"] = {
        "passed": not legacy,
        "path": settings_path,
        "events": legacy,
        "message": (
            f"Dead hooks still present for {', '.join(legacy)} — run `setup` to remove"
            if legacy
            else "None"
        ),
    }

    # 5. collector connectivity checks
    client = TelemetryHttpClient(base_url=endpoint, timeout=timeout)
    t0 = time.time()
    ok_metrics, code_m, msg_m = client.post_json(
        "v1/metrics", {"resourceMetrics": []}, silent=True
    )
    lat_m = round((time.time() - t0) * 1000, 1)

    if ok_metrics or code_m in (200, 202):
        checks["collector_metrics"] = {
            "passed": True,
            "http_status": code_m,
            "latency_ms": lat_m,
            "message": f"HTTP {code_m} ({lat_m}ms)",
        }
    else:
        remote_passed = False
        checks["collector_metrics"] = {
            "passed": False,
            "http_status": code_m,
            "latency_ms": lat_m,
            "message": f"Failed: {msg_m}",
        }

    t0 = time.time()
    ok_traces, code_t, msg_t = client.post_json(
        "v1/traces", {"resourceSpans": []}, silent=True
    )
    lat_t = round((time.time() - t0) * 1000, 1)

    if ok_traces or code_t in (200, 202):
        checks["collector_traces"] = {
            "passed": True,
            "http_status": code_t,
            "latency_ms": lat_t,
            "message": f"HTTP {code_t} ({lat_t}ms)",
        }
    else:
        remote_passed = False
        checks["collector_traces"] = {
            "passed": False,
            "http_status": code_t,
            "latency_ms": lat_t,
            "message": f"Failed: {msg_t}",
        }

    overall_status = "healthy" if (local_passed and remote_passed) else "degraded"

    if args.json:
        report = {
            "status": overall_status,
            "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "host": host,
            "endpoint": endpoint,
            "checks": checks,
        }
        print(json.dumps(report, indent=2))
    else:
        print("Antigravity Telemetry Status")
        print(f"Host:     {host} ({platform.system()} {platform.release()})")
        print(f"Endpoint: {endpoint}")
        print()
        print("Checks:")
        for name, c in checks.items():
            mark = "[✓]" if c["passed"] else "[✗]"
            print(f"  {mark} {name:<20} {c['message']}")
        print()
        if local_passed and remote_passed:
            print("Status: HEALTHY (All checks passed)")
        else:
            print("Status: DEGRADED (One or more checks failed)")

    if local_passed and remote_passed:
        return 0
    elif not local_passed and not remote_passed:
        return 3
    elif not remote_passed:
        return 2
    else:
        return 1


# ==============================================================================
# Subcommand: emit
# ==============================================================================


def cmd_emit(args: argparse.Namespace) -> int:
    """Emit synthetic or custom OTLP metrics and traces."""
    endpoint = args.endpoint.rstrip("/")
    host = args.host or get_hostname()
    model = args.model
    tool = args.tool
    client = TelemetryHttpClient(base_url=endpoint, timeout=5.0)

    metrics_records = []
    if not args.traces_only:
        # Build all 7 metric types
        metrics_records.append(
            build_token_usage_metric(
                input_tokens=args.tokens_input,
                output_tokens=args.tokens_output,
                thinking_tokens=args.tokens_thinking,
                cached_tokens=args.tokens_cached,
                model=model,
                host=host,
            )
        )
        metrics_records.append(
            build_api_request_metric(
                model=model,
                status_code="200",
                count=1,
                host=host,
            )
        )
        metrics_records.append(
            build_tool_call_count_metric(
                tool_name=tool,
                status="success",
                count=1,
                host=host,
            )
        )
        metrics_records.append(
            build_tool_call_latency_metric(
                tool_name=tool,
                latency_ms=args.tool_latency_ms,
                status="success",
                host=host,
            )
        )
        metrics_records.append(
            build_session_count_metric(
                status="started",
                count=1,
                host=host,
            )
        )
        metrics_records.append(
            build_turn_count_metric(
                model=model,
                count=1,
                host=host,
            )
        )
        metrics_records.append(
            build_subagent_spawn_metric(
                subagent_type="explorer",
                count=1,
                host=host,
            )
        )

    traces_spans = []
    if not args.metrics_only:
        now_ns = time.time_ns()
        span = build_span(
            name="antigravity.synthetic_session_turn",
            start_time_ns=now_ns - int(args.tool_latency_ms * 1e6),
            end_time_ns=now_ns,
            attributes={
                "host": host,
                "model.name": model,
                "tool.name": tool,
                "session.id": f"synthetic-{int(time.time())}",
            },
        )
        traces_spans.append(span)

    metrics_payload = (
        build_metrics_payload(metrics_records, host_name=host)
        if metrics_records
        else None
    )
    traces_payload = (
        build_traces_payload(traces_spans, host_name=host) if traces_spans else None
    )

    if args.verbose:
        if metrics_payload:
            print("OTLP Metrics Payload:")
            print(json.dumps(metrics_payload, indent=2))
        if traces_payload:
            print("OTLP Traces Payload:")
            print(json.dumps(traces_payload, indent=2))

    success = True
    for iteration in range(args.count):
        if metrics_payload:
            ok, code, msg = client.post_json(
                "v1/metrics", metrics_payload, compress=True, silent=False
            )
            if not ok and code not in (200, 202):
                success = False
                if not args.json:
                    sys.stderr.write(
                        f"Failed to emit metrics (iteration {iteration + 1}): {msg}\n"
                    )
        if traces_payload:
            ok, code, msg = client.post_json(
                "v1/traces", traces_payload, compress=True, silent=False
            )
            if not ok and code not in (200, 202):
                success = False
                if not args.json:
                    sys.stderr.write(
                        f"Failed to emit traces (iteration {iteration + 1}): {msg}\n"
                    )

        if args.interval > 0 and iteration < args.count - 1:
            time.sleep(args.interval)

    if args.json:
        out = {
            "status": "success" if success else "error",
            "host": host,
            "endpoint": endpoint,
            "metrics_emitted": len(metrics_records),
            "traces_emitted": len(traces_spans),
            "iterations": args.count,
        }
        print(json.dumps(out, indent=2))
    else:
        if success:
            print(
                f"Successfully emitted telemetry to {endpoint} (host: {host}, {args.count} iteration(s))"
            )
        else:
            print(f"Emission completed with errors to {endpoint}")
    return 0 if success else 2


# ==============================================================================
# Subcommand: export
# ==============================================================================


def cmd_export(args: argparse.Namespace) -> int:
    """Consume Antigravity hook events and export OTLP metrics."""
    endpoint = args.endpoint.rstrip("/")
    host = get_hostname()

    try:
        if args.file:
            with open(args.file, "r", encoding="utf-8") as f:
                raw = f.read()
        else:
            raw = sys.stdin.read()

        data = json.loads(raw) if raw.strip() else {}
        metrics = process_event(data, endpoint=endpoint, host=host)
        if metrics:
            payload = build_metrics_payload(metrics, host_name=host)
            client = TelemetryHttpClient(base_url=endpoint, timeout=2.0)
            ok, code, msg = client.post_json(
                "v1/metrics", payload, compress=True, silent=True
            )
            if args.verbose:
                sys.stderr.write(
                    f"[export] Dispatched {len(metrics)} metrics -> {code} ({msg})\n"
                )
    except Exception as e:
        if args.verbose:
            sys.stderr.write(f"[export] Warning: {e}\n")
    finally:
        if args.hook_mode:
            sys.stdout.write("{}\n")
            sys.stdout.flush()

    return 0


# ==============================================================================
# CLI Argument Parser & Entrypoint
# ==============================================================================


def build_parser() -> argparse.ArgumentParser:
    """Build unified argument parser."""
    parser = argparse.ArgumentParser(
        prog="antigravity-telemetry",
        description="Antigravity & AGY OTLP Telemetry Exporter, Diagnostics, and Setup Tool.",
    )
    subparsers = parser.add_subparsers(dest="subcommand", required=True)

    # setup
    p_setup = subparsers.add_parser(
        "setup",
        help="Install the transcript exporter and remove retired Gemini CLI hooks",
    )
    p_setup.add_argument(
        "--endpoint",
        default=DEFAULT_ENDPOINT,
        help=f"OTLP collector endpoint (default: {DEFAULT_ENDPOINT})",
    )
    p_setup.add_argument(
        "--settings-path",
        default=get_default_settings_path(),
        help="Gemini CLI settings.json to clean up (legacy)",
    )
    p_setup.add_argument(
        "--hooks-dir", default=DEFAULT_HOOKS_DIR, help="Path to hooks directory"
    )
    p_setup.add_argument(
        "--hook-script-name", default=DEFAULT_HOOK_NAME, help="Filename of hook script"
    )
    p_setup.add_argument(
        "--dry-run",
        action="store_true",
        help="Print planned changes without writing to disk",
    )
    p_setup.add_argument(
        "--no-backup", action="store_true", help="Disable creating settings backup"
    )
    p_setup.add_argument(
        "--json", action="store_true", help="Output machine-readable JSON"
    )

    # status
    p_status = subparsers.add_parser(
        "status",
        help="Diagnose the exporter, transcript sources, and collector connectivity",
    )
    p_status.add_argument(
        "--endpoint",
        default=DEFAULT_ENDPOINT,
        help=f"OTLP collector endpoint (default: {DEFAULT_ENDPOINT})",
    )
    p_status.add_argument(
        "--settings-path",
        default=get_default_settings_path(),
        help="Gemini CLI settings.json to clean up (legacy)",
    )
    p_status.add_argument(
        "--hooks-dir", default=DEFAULT_HOOKS_DIR, help="Path to hooks directory"
    )
    p_status.add_argument(
        "--timeout", type=float, default=5.0, help="HTTP connection timeout in seconds"
    )
    p_status.add_argument(
        "--json", action="store_true", help="Output machine-readable JSON"
    )

    # emit
    p_emit = subparsers.add_parser(
        "emit", help="Emit synthetic or custom metrics and traces"
    )
    p_emit.add_argument(
        "--endpoint",
        default=DEFAULT_ENDPOINT,
        help=f"OTLP collector endpoint (default: {DEFAULT_ENDPOINT})",
    )
    p_emit.add_argument("--host", default=None, help="Override hostname label")
    p_emit.add_argument("--model", default="gemini-3.7-flash", help="Model name label")
    p_emit.add_argument("--tool", default="run_command", help="Tool name label")
    p_emit.add_argument(
        "--tokens-input", type=int, default=1250, help="Input token count"
    )
    p_emit.add_argument(
        "--tokens-output", type=int, default=320, help="Output token count"
    )
    p_emit.add_argument(
        "--tokens-thinking", type=int, default=450, help="Thinking token count"
    )
    p_emit.add_argument(
        "--tokens-cached", type=int, default=800, help="Cached token count"
    )
    p_emit.add_argument(
        "--tool-latency-ms", type=float, default=145.0, help="Tool latency in ms"
    )
    p_emit.add_argument("--count", type=int, default=1, help="Number of iterations")
    p_emit.add_argument(
        "--interval",
        type=float,
        default=0.0,
        help="Interval between iterations in seconds",
    )
    p_emit.add_argument("--metrics-only", action="store_true", help="Emit metrics only")
    p_emit.add_argument("--traces-only", action="store_true", help="Emit traces only")
    p_emit.add_argument(
        "--verbose", action="store_true", help="Print full JSON payloads"
    )
    p_emit.add_argument(
        "--json", action="store_true", help="Output machine-readable JSON"
    )

    # export
    p_export = subparsers.add_parser(
        "export", help="Process hook events from stdin or file"
    )
    p_export.add_argument(
        "--endpoint",
        default=DEFAULT_ENDPOINT,
        help=f"OTLP collector endpoint (default: {DEFAULT_ENDPOINT})",
    )
    p_export.add_argument(
        "--file", default=None, help="Read JSON from file instead of stdin"
    )
    p_export.add_argument(
        "--hook-mode", action="store_true", help="Always output {} to stdout and exit 0"
    )
    p_export.add_argument(
        "--verbose", action="store_true", help="Log debug details to stderr"
    )

    return parser


def main() -> None:
    """Main CLI entrypoint."""
    parser = build_parser()
    args = parser.parse_args()

    if args.subcommand == "setup":
        code = cmd_setup(args)
    elif args.subcommand == "status":
        code = cmd_status(args)
    elif args.subcommand == "emit":
        code = cmd_emit(args)
    elif args.subcommand == "export":
        code = cmd_export(args)
    else:
        parser.print_help()
        code = 1

    sys.exit(code)


if __name__ == "__main__":
    main()
