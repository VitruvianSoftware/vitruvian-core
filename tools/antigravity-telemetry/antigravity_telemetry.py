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
import json
import os
import pathlib
import platform
import shutil
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
DEFAULT_SETTINGS_PATH = os.path.expanduser("~/.gemini/settings.json")
DEFAULT_HOOKS_DIR = os.path.expanduser("~/.gemini/hooks")
DEFAULT_HOOK_NAME = "telemetry_hook.py"


def get_default_settings_path() -> str:
    """Return default settings.json path respecting environment override."""
    return os.environ.get("GEMINI_SETTINGS_PATH", DEFAULT_SETTINGS_PATH)


def patch_settings_json(
    existing_settings: Dict[str, Any],
    endpoint: str,
    hook_script_path: str,
) -> Dict[str, Any]:
    """Idempotently updates telemetry and lifecycle hook configuration in settings dict."""
    updated = copy.deepcopy(existing_settings)

    # 1. Mutate telemetry block
    if "telemetry" not in updated or not isinstance(updated["telemetry"], dict):
        updated["telemetry"] = {}

    t = updated["telemetry"]
    t["enabled"] = True
    t["target"] = t.get("target", "local")
    t["useCliAuth"] = t.get("useCliAuth", False)
    t["useCollector"] = True
    t["otlpEndpoint"] = endpoint
    t["otlpProtocol"] = "http"
    t["traces"] = True

    # 2. Mutate lifecycle hooks block
    if "hooks" not in updated or not isinstance(updated["hooks"], dict):
        updated["hooks"] = {}

    hook_events = {
        "AfterModel": {"timeout": 2000},
        "AfterTool": {"timeout": 2000},
        "AfterAgent": {"timeout": 5000},
    }

    # Purge any deprecated BeforeTool/PreToolUse telemetry hooks to avoid permission gating
    for deprecated_event in ("BeforeTool", "PreToolUse"):
        if deprecated_event in updated.get("hooks", {}):
            del updated["hooks"][deprecated_event]

    for event_name, config in hook_events.items():
        if event_name not in updated["hooks"] or not isinstance(
            updated["hooks"][event_name], list
        ):
            updated["hooks"][event_name] = []

        event_matchers = updated["hooks"][event_name]
        wildcard_matcher = None
        for m in event_matchers:
            if isinstance(m, dict) and m.get("matcher") == "*":
                wildcard_matcher = m
                break

        if wildcard_matcher is None:
            wildcard_matcher = {"matcher": "*", "hooks": []}
            event_matchers.append(wildcard_matcher)

        hooks_list = wildcard_matcher.setdefault("hooks", [])

        existing_hook = None
        for h in hooks_list:
            if isinstance(h, dict) and (
                h.get("name") == "telemetry-hook"
                or "telemetry_hook" in h.get("command", "")
            ):
                existing_hook = h
                break

        hook_def = {
            "name": "telemetry-hook",
            "type": "command",
            "command": hook_script_path,
            "timeout": config["timeout"],
        }

        if existing_hook is not None:
            existing_hook.update(hook_def)
        else:
            hooks_list.append(hook_def)

    return updated


# ==============================================================================
# Subcommand: setup
# ==============================================================================


def cmd_setup(args: argparse.Namespace) -> int:
    """Automate developer machine setup for Antigravity & agy telemetry."""
    endpoint = args.endpoint.rstrip("/")
    settings_path = os.path.abspath(os.path.expanduser(args.settings_path))
    hooks_dir = os.path.abspath(os.path.expanduser(args.hooks_dir))
    hook_dest = os.path.join(hooks_dir, args.hook_script_name)

    # 1. Locate source telemetry_hook.py
    current_dir = os.path.dirname(os.path.abspath(__file__))
    source_hook = os.path.join(current_dir, "telemetry_hook.py")
    if not os.path.exists(source_hook):
        source_hook = os.path.join(current_dir, "telemetry-hook")
    if not os.path.exists(source_hook):
        source_hook = hook_dest

    results: Dict[str, Any] = {
        "status": "success",
        "settings_path": settings_path,
        "hooks_dir": hooks_dir,
        "hook_script": hook_dest,
        "endpoint": endpoint,
        "dry_run": args.dry_run,
    }

    if not args.dry_run:
        # Create directories
        os.makedirs(os.path.dirname(settings_path), mode=0o755, exist_ok=True)
        os.makedirs(hooks_dir, mode=0o755, exist_ok=True)

        # Copy hook script if source exists and is different
        if os.path.exists(source_hook) and os.path.abspath(
            source_hook
        ) != os.path.abspath(hook_dest):
            shutil.copy2(source_hook, hook_dest)
            os.chmod(hook_dest, 0o755)
        elif os.path.exists(hook_dest):
            os.chmod(hook_dest, 0o755)

    # 2. Read existing settings
    existing_settings: Dict[str, Any] = {}
    if os.path.exists(settings_path):
        try:
            with open(settings_path, "r", encoding="utf-8") as f:
                content = f.read().strip()
                if content:
                    existing_settings = json.loads(content)
        except Exception as e:
            if not args.json:
                sys.stderr.write(f"Error reading {settings_path}: {e}\n")
            results["status"] = "error"
            results["error"] = f"Failed to read existing settings: {e}"
            if args.json:
                print(json.dumps(results, indent=2))
            return 1

    # 3. Patch settings
    patched = patch_settings_json(
        existing_settings=existing_settings,
        endpoint=endpoint,
        hook_script_path=hook_dest,
    )

    if not args.dry_run:
        # Create backup
        if not args.no_backup and os.path.exists(settings_path):
            ts = datetime.datetime.now().strftime("%Y%m%d%H%M%S")
            backup_path = f"{settings_path}.bak.{ts}"
            shutil.copy2(settings_path, backup_path)
            results["backup_path"] = backup_path

        # Atomic write
        tmp_path = f"{settings_path}.tmp.{os.getpid()}"
        with open(tmp_path, "w", encoding="utf-8") as f:
            json.dump(patched, f, indent=2)
            f.write("\n")
        os.replace(tmp_path, settings_path)

    if args.json:
        print(json.dumps(results, indent=2))
    else:
        print("Antigravity Telemetry Setup")
        print("==========================")
        print(f"Target Endpoint:  {endpoint}")
        print(f"Settings Path:    {settings_path}")
        print(f"Hook Script Path: {hook_dest}")
        if args.dry_run:
            print("Mode:             DRY-RUN (no files modified)")
        else:
            print("Status:           Configuration applied successfully.")
    return 0


# ==============================================================================
# Subcommand: status
# ==============================================================================


def cmd_status(args: argparse.Namespace) -> int:
    """Inspect local settings and verify connectivity to OTLP Collector."""
    endpoint = args.endpoint.rstrip("/")
    settings_path = os.path.abspath(os.path.expanduser(args.settings_path))
    hooks_dir = os.path.abspath(os.path.expanduser(args.hooks_dir))
    hook_script = os.path.join(hooks_dir, "telemetry_hook.py")
    host = get_hostname()
    timeout = args.timeout

    checks: Dict[str, Dict[str, Any]] = {}
    local_passed = True
    remote_passed = True

    # 1. settings_file check
    if os.path.exists(settings_path):
        try:
            with open(settings_path, "r", encoding="utf-8") as f:
                settings_data = json.load(f)
            checks["settings_file"] = {
                "passed": True,
                "path": settings_path,
                "message": f"Valid JSON ({len(settings_data)} keys)",
            }
        except Exception as e:
            local_passed = False
            settings_data = {}
            checks["settings_file"] = {
                "passed": False,
                "path": settings_path,
                "message": f"Corrupt JSON: {e}",
            }
    else:
        local_passed = False
        settings_data = {}
        checks["settings_file"] = {
            "passed": False,
            "path": settings_path,
            "message": "File does not exist",
        }

    # 2. telemetry_config check
    t_cfg = settings_data.get("telemetry", {})
    t_enabled = t_cfg.get("enabled", False)
    t_collector = t_cfg.get("useCollector", False)
    t_endpoint = t_cfg.get("otlpEndpoint", "")
    t_traces = t_cfg.get("traces", False)

    if t_enabled and t_collector and t_endpoint == endpoint:
        checks["telemetry_config"] = {
            "passed": True,
            "endpoint": t_endpoint,
            "enabled": t_enabled,
            "traces": t_traces,
            "message": f"Enabled -> {t_endpoint}",
        }
    else:
        local_passed = False
        checks["telemetry_config"] = {
            "passed": False,
            "endpoint": t_endpoint,
            "enabled": t_enabled,
            "traces": t_traces,
            "message": f"Config mismatch (enabled={t_enabled}, collector={t_collector}, endpoint={t_endpoint})",
        }

    # 3. hooks_config check
    hooks_block = settings_data.get("hooks", {})
    required_hooks = ["AfterModel", "AfterTool", "AfterAgent"]
    registered = []
    for evt in required_hooks:
        matchers = hooks_block.get(evt, [])
        for m in matchers:
            for h in m.get("hooks", []):
                if h.get("name") == "telemetry-hook" or "telemetry_hook" in h.get(
                    "command", ""
                ):
                    registered.append(evt)
                    break

    if len(set(registered)) == len(required_hooks):
        checks["hooks_config"] = {
            "passed": True,
            "registered_events": registered,
            "message": f"Registered for {', '.join(required_hooks)}",
        }
    else:
        local_passed = False
        checks["hooks_config"] = {
            "passed": False,
            "registered_events": registered,
            "message": f"Missing hooks: {set(required_hooks) - set(registered)}",
        }

    # 4. hook_binary check
    if os.path.exists(hook_script) and os.access(hook_script, os.X_OK):
        checks["hook_binary"] = {
            "passed": True,
            "path": hook_script,
            "executable": True,
            "message": "Script exists and is executable",
        }
    else:
        local_passed = False
        checks["hook_binary"] = {
            "passed": False,
            "path": hook_script,
            "executable": os.access(hook_script, os.X_OK)
            if os.path.exists(hook_script)
            else False,
            "message": "Hook script missing or not executable",
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
        "setup", help="Configure ~/.gemini/settings.json and install hooks"
    )
    p_setup.add_argument(
        "--endpoint",
        default=DEFAULT_ENDPOINT,
        help=f"OTLP collector endpoint (default: {DEFAULT_ENDPOINT})",
    )
    p_setup.add_argument(
        "--settings-path",
        default=get_default_settings_path(),
        help="Path to settings.json",
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
        "status", help="Diagnose local settings and OTLP collector connectivity"
    )
    p_status.add_argument(
        "--endpoint",
        default=DEFAULT_ENDPOINT,
        help=f"OTLP collector endpoint (default: {DEFAULT_ENDPOINT})",
    )
    p_status.add_argument(
        "--settings-path",
        default=get_default_settings_path(),
        help="Path to settings.json",
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
