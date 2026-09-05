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

"""
agent_ci_monitor.py
Asynchronous background monitoring engine for local AI agents and GitHub CI/CD status.
Designed for mac-controller Milestone 3 (AI Agent & CI/CD Pipeline Deck).
"""

import os
import sys
import re
import json
import time
import subprocess
import threading
from typing import Dict, Any, Tuple, Optional, List

# Agent State Constants
AGENT_STATE_IDLE = "idle"
AGENT_STATE_RUNNING = "running"
AGENT_STATE_REVIEW = "review"
AGENT_STATE_ERROR = "error"

# CI Status Constants
CI_STATUS_UNKNOWN = "unknown"
CI_STATUS_PASSING = "passing"
CI_STATUS_FAILING = "failing"
CI_STATUS_PENDING = "pending"
CI_STATUS_NONE = "none"


def _safe_int(val: Any, default: int = 0) -> int:
    """
    Safely converts val to int, returning default on ValueError, TypeError, or OverflowError.
    Handles float strings like '12.0' as well as standard ints and numeric strings.
    """
    if val is None:
        return default
    try:
        return int(val)
    except (ValueError, TypeError):
        try:
            return int(float(val))
        except (ValueError, TypeError, OverflowError):
            return default


def detect_agent_error(content: str) -> bool:
    """
    Inspects progress.md content for explicit agent error/failure signals.
    Avoids false positives from benign phrases like '0 errors' or 'no failed tests'.
    """
    if not content or not content.strip():
        return False

    if re.search(
        r"(?:status|state)\s*[:=]\s*(?:\*\*)?\s*(?:error|failed|failure|blocked)\b",
        content,
        re.IGNORECASE,
    ):
        return True

    if re.search(
        r"^#+\s*(?:verification failure|failure|blocked)\b",
        content,
        re.IGNORECASE | re.MULTILINE,
    ):
        return True
    if re.search(
        r"^#+\s*error\b(?! handling| recovery)", content, re.IGNORECASE | re.MULTILINE
    ):
        return True

    for line in content.splitlines():
        line_clean = line.strip()
        if re.match(r"^(?:ERROR|FATAL|FAILED|CRITICAL)\s*:", line_clean, re.IGNORECASE):
            return True
        if re.match(
            r"^[-*]\s*(?:\[[ x/]\]\s*)?(?:ERROR|BLOCKED|FAILED)\s*:",
            line_clean,
            re.IGNORECASE,
        ):
            return True

    return False


def parse_agent_processes(pgrep_output: str) -> Tuple[Optional[str], int]:
    """
    Parses `pgrep -fl` output to detect active AI agent processes.
    Returns (agent_name, process_count).
    """
    if not pgrep_output or not pgrep_output.strip():
        return None, 0

    lines = [line.strip() for line in pgrep_output.strip().split("\n") if line.strip()]
    count = 0
    has_agy = False
    has_claude = False

    for line in lines:
        if "pgrep" in line or "grep" in line:
            continue

        lower = line.lower()
        if re.search(r"\b(antigravity|agy)\b", lower):
            has_agy = True
            count += 1
        elif re.search(r"\bclaude(?:-code)?\b", lower):
            has_claude = True
            count += 1

    if has_agy and has_claude:
        detected_name = "Teamwork"
    elif has_agy:
        detected_name = "Antigravity"
    elif has_claude:
        detected_name = "Claude Code"
    else:
        detected_name = None

    return detected_name, count


def determine_agent_state(
    process_running: bool,
    last_mtime: float,
    current_time: float,
    has_error: bool = False,
) -> str:
    """
    Determines agent state from process presence and progress.md mtime.
    Rules:
      - If has_error -> ERROR
      - If not process_running -> IDLE
      - If last_mtime <= 0 -> RUNNING (grace period)
      - If current_time - last_mtime < 45s -> RUNNING
      - If 45s <= current_time - last_mtime < 300s -> REVIEW
      - If current_time - last_mtime >= 300s -> IDLE
    """
    if has_error:
        return AGENT_STATE_ERROR
    if not process_running:
        return AGENT_STATE_IDLE

    if last_mtime <= 0:
        return AGENT_STATE_RUNNING

    elapsed = max(0.0, current_time - last_mtime)
    if elapsed < 45.0:
        return AGENT_STATE_RUNNING
    elif elapsed < 300.0:
        return AGENT_STATE_REVIEW
    else:
        return AGENT_STATE_IDLE


def parse_agent_progress(progress_content: str) -> Dict[str, Any]:
    """
    Extracts current task and metadata from progress.md content.
    """
    res = {"task": "Idle", "active_subagents": 0, "status": "idle"}
    if not progress_content or not progress_content.strip():
        return res

    lines = progress_content.strip().split("\n")
    for line in lines:
        line_clean = line.strip()

        # Check status line: e.g. **Current Status:** In Progress
        if "status:" in line_clean.lower():
            parts = line_clean.split(":", 1)
            if len(parts) > 1:
                res["status"] = parts[1].strip().strip("*_#` ")

        # Look for in-progress task items: e.g. - [/] Task description or - [ ] current
        if line_clean.startswith("- [/]") or line_clean.startswith("* [/]"):
            task_text = line_clean[5:].strip()
            if task_text:
                res["task"] = task_text
                break
        elif line_clean.startswith("- [ ]") and res["task"] == "Idle":
            task_text = line_clean[5:].strip()
            if task_text:
                res["task"] = task_text

    return res


def parse_git_status(porcelain_output: str) -> Tuple[str, bool, int]:
    """
    Parses `git status --porcelain -b` output.
    Returns (branch_name, is_dirty, dirty_files_count).
    """
    if not porcelain_output or not porcelain_output.strip():
        return "main", False, 0

    lines = [l for l in porcelain_output.strip().split("\n") if l.strip()]
    if not lines:
        return "main", False, 0

    first_line = lines[0]
    branch = "main"

    if first_line.startswith("##"):
        content = first_line[2:].strip()
        m = re.match(
            r"^(?:Initial commit on |No commits yet on )?([^\s]+?)(?:\.\.\.|\s|$)",
            content,
        )
        if m:
            branch = m.group(1)

    dirty_files = len(lines) - 1 if len(lines) > 1 else 0
    is_dirty = dirty_files > 0

    return branch, is_dirty, dirty_files


def parse_gh_pr_checks(checks_json_str: str) -> Dict[str, Any]:
    """
    Parses `gh pr checks --json name,state,bucket` output.
    Returns dict: {"status": ..., "passed": ..., "total": ...}
    """
    default_res = {"status": CI_STATUS_UNKNOWN, "passed": 0, "total": 0}

    if not checks_json_str or not checks_json_str.strip():
        default_res["status"] = CI_STATUS_NONE
        return default_res

    try:
        checks = json.loads(checks_json_str)
    except Exception:
        return default_res

    if not isinstance(checks, list):
        return default_res

    if len(checks) == 0:
        return {"status": CI_STATUS_NONE, "passed": 0, "total": 0}

    total = len(checks)
    passed = 0
    has_failing = False
    has_pending = False

    for c in checks:
        if not isinstance(c, dict):
            continue
        state = str(c.get("state", "")).upper()
        bucket = str(c.get("bucket", "")).lower()

        if bucket == "pass" or state in ("SUCCESS", "PASS", "PASSED"):
            passed += 1
        elif bucket == "fail" or state in (
            "FAILURE",
            "FAIL",
            "FAILED",
            "ERROR",
            "CANCELLED",
        ):
            has_failing = True
        elif bucket == "pending" or state in ("PENDING", "IN_PROGRESS", "QUEUED"):
            has_pending = True

    if has_failing:
        status = CI_STATUS_FAILING
    elif has_pending:
        status = CI_STATUS_PENDING
    elif passed == total and total > 0:
        status = CI_STATUS_PASSING
    else:
        status = CI_STATUS_PASSING if passed > 0 else CI_STATUS_UNKNOWN

    return {"status": status, "passed": passed, "total": total}


def parse_gh_run_list(run_json_str: str) -> Dict[str, Any]:
    """
    Fallback parser for `gh run list --limit 1 --json status,conclusion`.
    """
    default_res = {"status": CI_STATUS_UNKNOWN, "passed": 0, "total": 0}
    if not run_json_str or not run_json_str.strip():
        default_res["status"] = CI_STATUS_NONE
        return default_res

    try:
        runs = json.loads(run_json_str)
    except Exception:
        return default_res

    if not isinstance(runs, list) or len(runs) == 0:
        default_res["status"] = CI_STATUS_NONE
        return default_res

    run = None
    for item in runs:
        if isinstance(item, dict):
            run = item
            break

    if run is None:
        return default_res

    st = str(run.get("status", "") or "").lower()
    conc = str(run.get("conclusion", "") or "").lower()

    if conc in ("success", "pass"):
        return {"status": CI_STATUS_PASSING, "passed": 1, "total": 1}
    elif conc in ("failure", "fail", "cancelled", "timed_out"):
        return {"status": CI_STATUS_FAILING, "passed": 0, "total": 1}
    elif st in ("in_progress", "queued", "waiting"):
        return {"status": CI_STATUS_PENDING, "passed": 0, "total": 1}

    return default_res


def build_agent_ci_payload(
    agent_info: Dict[str, Any], ci_info: Dict[str, Any]
) -> Dict[str, Any]:
    """
    Constructs the canonical 'type': 'agent_ci' serial wire protocol dictionary.
    """
    if not isinstance(agent_info, dict):
        agent_info = {}
    if not isinstance(ci_info, dict):
        ci_info = {}

    return {
        "type": "agent_ci",
        "agent": {
            "name": str(agent_info.get("name", "Agent")),
            "state": str(agent_info.get("state", AGENT_STATE_IDLE)),
            "task": str(agent_info.get("task", agent_info.get("detail", "Idle"))),
            "detail": str(agent_info.get("detail", agent_info.get("task", "Idle"))),
            "active_agents": _safe_int(agent_info.get("active_agents", 0)),
        },
        "ci": {
            "repo": str(ci_info.get("repo", "vitruvian-core")),
            "branch": str(ci_info.get("branch", "main")),
            "dirty": bool(ci_info.get("dirty", False)),
            "dirty_files": _safe_int(ci_info.get("dirty_files", 0)),
            "status": str(
                ci_info.get("status", ci_info.get("state", CI_STATUS_UNKNOWN))
            ),
            "state": str(
                ci_info.get("state", ci_info.get("status", CI_STATUS_UNKNOWN))
            ),
            "pr": _safe_int(ci_info.get("pr", 0)),
            "passed": _safe_int(ci_info.get("passed", 0)),
            "total": _safe_int(ci_info.get("total", 0)),
        },
    }


def serialize_agent_ci_packet(payload: Dict[str, Any]) -> str:
    """
    Serializes payload to newline-terminated JSON packet.
    """
    compact_json = json.dumps(payload, separators=(",", ":"))
    return compact_json + "\n"


class AgentCIMonitor:
    """
    Asynchronous background monitor for local AI agents and GitHub CI/CD status.
    Decouples slow subprocess calls (gh pr checks ~1.2s, git status, pgrep,
    filesystem traversal) into a dedicated daemon worker thread. The main daemon loop
    reads thread-safe cached payloads in <0.01ms, preserving 1Hz telemetry and 50ms
    frontmost app detection without latency spikes or watchdog timeouts.
    """

    def __init__(
        self,
        workspace_dir: Optional[str] = None,
        agent_interval: float = 3.0,
        ci_interval: float = 10.0,
    ):
        if workspace_dir is None:
            # Auto-detect git workspace root from current file location
            cur_dir = os.path.abspath(os.path.dirname(__file__))
            try:
                root_out = subprocess.check_output(
                    ["git", "rev-parse", "--show-toplevel"],
                    cwd=cur_dir,
                    text=True,
                    stderr=subprocess.DEVNULL,
                    timeout=1.0,
                ).strip()
                self.workspace_dir = (
                    root_out
                    if root_out
                    else os.path.abspath(os.path.join(cur_dir, "../.."))
                )
            except Exception:
                self.workspace_dir = os.path.abspath(os.path.join(cur_dir, "../.."))
        else:
            self.workspace_dir = os.path.abspath(workspace_dir)

        self.agent_interval = agent_interval
        self.ci_interval = ci_interval

        self._lock = threading.Lock()
        self._stop_event = threading.Event()
        self._refresh_event = threading.Event()

        # Initial baseline cached payload
        self._cached_payload: Dict[str, Any] = build_agent_ci_payload(
            {
                "name": "None",
                "state": AGENT_STATE_IDLE,
                "task": "Initializing",
                "active_agents": 0,
            },
            {
                "repo": os.path.basename(self.workspace_dir),
                "branch": "unknown",
                "dirty": False,
                "dirty_files": 0,
                "status": CI_STATUS_NONE,
                "pr": 0,
                "passed": 0,
                "total": 0,
            },
        )

        self._worker_thread = threading.Thread(
            target=self._worker_loop, name="AgentCIWorkerThread", daemon=True
        )

    def start(self) -> None:
        """Starts the background worker thread."""
        if not self._worker_thread.is_alive():
            self._worker_thread.start()

    def stop(self, timeout: float = 3.0) -> None:
        """Signals the background worker thread to stop and joins."""
        self._stop_event.set()
        self._refresh_event.set()
        if self._worker_thread.is_alive():
            self._worker_thread.join(timeout=timeout)

    def trigger_refresh(self) -> None:
        """Signals the worker thread to immediately perform an out-of-band CI & agent poll."""
        self._refresh_event.set()

    def get_payload(self) -> Dict[str, Any]:
        """Returns a thread-safe copy of the latest cached wire payload."""
        with self._lock:
            return json.loads(json.dumps(self._cached_payload))

    def _worker_loop(self) -> None:
        last_agent_poll = 0.0
        last_ci_poll = 0.0
        cached_agent = self._cached_payload["agent"]
        cached_ci = self._cached_payload["ci"]

        while not self._stop_event.is_set():
            now = time.monotonic()
            updated = False
            manual_refresh = self._refresh_event.is_set()
            if manual_refresh:
                self._refresh_event.clear()

            if self._stop_event.is_set():
                break

            # 1. Agent Poll (every agent_interval or on manual refresh)
            if manual_refresh or (now - last_agent_poll >= self.agent_interval):
                try:
                    cached_agent = self.poll_agent()
                    last_agent_poll = now
                    updated = True
                except Exception:
                    pass

            if self._stop_event.is_set():
                break

            # 2. CI Poll (every ci_interval or on manual refresh)
            if manual_refresh or (now - last_ci_poll >= self.ci_interval):
                try:
                    cached_ci = self.poll_ci()
                    last_ci_poll = now
                    updated = True
                except Exception:
                    pass

            if self._stop_event.is_set():
                break

            # 3. Update cached payload atomically under lock
            if updated:
                with self._lock:
                    self._cached_payload = build_agent_ci_payload(
                        cached_agent, cached_ci
                    )

            # Sleep with 200ms granularity; wakes up immediately on refresh or stop
            self._refresh_event.wait(timeout=0.2)

    def poll_agent(self) -> Dict[str, Any]:
        """Inspects running agent processes and workspace .agents metadata."""
        # 1. Process scanning
        running_name = None
        count = 0
        try:
            out = subprocess.check_output(
                ["pgrep", "-fl", "antigravity|claude|agy"],
                text=True,
                stderr=subprocess.DEVNULL,
                timeout=1.5,
            )
            # Filter unwanted helper/grep lines
            filtered_lines = []
            for line in out.strip().split("\n"):
                line_str = line.strip()
                if (
                    not line_str
                    or "mcp-server" in line_str
                    or "mcp-remote" in line_str
                    or "Claude Helper" in line_str
                    or "grep" in line_str
                ):
                    continue
                filtered_lines.append(line_str)

            running_name, count = parse_agent_processes("\n".join(filtered_lines))
        except Exception:
            pass

        # 2. Workspace .agents inspect
        agents_dir = os.path.join(self.workspace_dir, ".agents")
        now_ts = time.time()
        active_count = 0
        latest_task = "Idle"
        has_error = False
        newest_mtime = 0.0
        newest_prog_file: Optional[str] = None

        if os.path.isdir(agents_dir):
            try:
                agent_entries = sorted(os.listdir(agents_dir))
                for entry in agent_entries:
                    agent_folder = os.path.join(agents_dir, entry)
                    if not os.path.isdir(agent_folder):
                        continue
                    prog_file = os.path.join(agent_folder, "progress.md")
                    if os.path.isfile(prog_file):
                        try:
                            mtime = os.path.getmtime(prog_file)
                            age = now_ts - mtime
                            if age < 120.0:
                                active_count += 1
                            if mtime > newest_mtime:
                                newest_mtime = mtime
                                newest_prog_file = prog_file
                        except Exception:
                            pass
            except Exception:
                pass

        # Evaluate task and error state exclusively from the most recent progress file
        if newest_prog_file is not None:
            try:
                with open(
                    newest_prog_file, "r", encoding="utf-8", errors="ignore"
                ) as f:
                    content = f.read(2048)
                has_error = detect_agent_error(content)
                parsed_prog = parse_agent_progress(content)
                if parsed_prog.get("task") and parsed_prog["task"] != "Idle":
                    latest_task = parsed_prog["task"][:48]
            except Exception:
                pass

        agent_name = running_name if running_name else "None"
        has_process = running_name is not None
        state = determine_agent_state(has_process, newest_mtime, now_ts, has_error)

        if (
            not has_process
            and state == AGENT_STATE_IDLE
            and (latest_task == "Idle" or not latest_task)
        ):
            latest_task = "Ready"

        return {
            "name": agent_name,
            "state": state,
            "task": latest_task,
            "detail": latest_task,
            "active_agents": max(count, active_count),
        }

    def poll_ci(self) -> Dict[str, Any]:
        """Queries local git status and remote gh pr checks / gh run list."""
        branch = "main"
        dirty = False
        dirty_count = 0

        # 1. Local Git Status
        try:
            git_out = subprocess.check_output(
                ["git", "status", "--porcelain", "-b"],
                cwd=self.workspace_dir,
                text=True,
                stderr=subprocess.DEVNULL,
                timeout=2.0,
            )
            branch, dirty, dirty_count = parse_git_status(git_out)
        except Exception:
            pass

        repo_name = os.path.basename(self.workspace_dir)

        # 2. Remote GitHub Checks
        status = CI_STATUS_NONE
        pr_num = 0
        passed = 0
        total = 0

        # Check if current branch has an associated PR
        try:
            pr_out = subprocess.check_output(
                ["gh", "pr", "view", "--json", "number,state"],
                cwd=self.workspace_dir,
                text=True,
                stderr=subprocess.DEVNULL,
                timeout=3.0,
            )
            pr_data = json.loads(pr_out)
            pr_num = pr_data.get("number", 0)
        except Exception:
            pr_num = 0

        if pr_num and pr_num > 0:
            try:
                checks_out = subprocess.check_output(
                    ["gh", "pr", "checks", str(pr_num), "--json", "name,state,bucket"],
                    cwd=self.workspace_dir,
                    text=True,
                    stderr=subprocess.DEVNULL,
                    timeout=5.0,
                )
                parsed_checks = parse_gh_pr_checks(checks_out)
                status = parsed_checks["status"]
                passed = parsed_checks["passed"]
                total = parsed_checks["total"]
            except Exception:
                status = CI_STATUS_UNKNOWN
        else:
            # Fallback to gh run list
            try:
                runs_out = subprocess.check_output(
                    [
                        "gh",
                        "run",
                        "list",
                        "--limit",
                        "1",
                        "--json",
                        "status,conclusion",
                    ],
                    cwd=self.workspace_dir,
                    text=True,
                    stderr=subprocess.DEVNULL,
                    timeout=3.0,
                )
                parsed_runs = parse_gh_run_list(runs_out)
                status = parsed_runs["status"]
                passed = parsed_runs["passed"]
                total = parsed_runs["total"]
            except Exception:
                status = CI_STATUS_NONE

        return {
            "repo": repo_name,
            "branch": branch,
            "dirty": dirty,
            "dirty_files": dirty_count,
            "status": status,
            "state": status,
            "pr": pr_num,
            "passed": passed,
            "total": total,
        }
