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
mac-controller/tests/test_agent_ci.py
Comprehensive automated test suite for Milestone 3 (AI Agent & CI/CD Pipeline Deck).

Covers:
1. Agent process detection & name identification
2. Workspace state & task parsing from progress.md
3. Agent state transitions (idle, running, review, error) based on heartbeat mtime
4. Git branch parsing and working tree dirty state extraction
5. GitHub PR checks (gh pr checks) and workflow run list JSON parsing
6. Wire protocol JSON serialization, framing, and ArduinoJson v7 deserialization compatibility
7. Round-trip serialization fidelity and buffer sizing safety
8. Host command dispatcher simulation for ESP32 touch button action callbacks
9. AgentCIMonitor async threading and thread-safe payload retrieval
"""

import os
import sys
import json
import time
import subprocess
import unittest
from unittest.mock import patch, MagicMock

# Allow importing local monitor module from host_companion
sys.path.insert(
    0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../host_companion"))
)

# Ensure serial module is mocked if pyserial is not installed in the environment
if "serial" not in sys.modules:
    sys.modules["serial"] = MagicMock()

from agent_ci_monitor import (
    AGENT_STATE_IDLE,
    AGENT_STATE_RUNNING,
    AGENT_STATE_REVIEW,
    AGENT_STATE_ERROR,
    CI_STATUS_UNKNOWN,
    CI_STATUS_PASSING,
    CI_STATUS_FAILING,
    CI_STATUS_PENDING,
    CI_STATUS_NONE,
    AgentCIMonitor,
    parse_agent_processes,
    determine_agent_state,
    parse_agent_progress,
    parse_git_status,
    parse_gh_pr_checks,
    parse_gh_run_list,
    build_agent_ci_payload,
    serialize_agent_ci_packet,
)
from mac_stats_daemon import handle_esp_command


class TestAgentProcessDetection(unittest.TestCase):
    """Tests agent process detection from pgrep output."""

    def test_detect_antigravity(self):
        pgrep_out = "12345 /opt/homebrew/bin/python3 -m antigravity\n"
        name, count = parse_agent_processes(pgrep_out)
        self.assertEqual(name, "Antigravity")
        self.assertEqual(count, 1)

    def test_detect_agy_alias(self):
        pgrep_out = "54321 /usr/local/bin/agy\n"
        name, count = parse_agent_processes(pgrep_out)
        self.assertEqual(name, "Antigravity")
        self.assertEqual(count, 1)

    def test_detect_claude_code(self):
        pgrep_out = "99999 /Users/user/.npm-global/bin/claude\n"
        name, count = parse_agent_processes(pgrep_out)
        self.assertEqual(name, "Claude Code")
        self.assertEqual(count, 1)

    def test_multiple_subagents(self):
        pgrep_out = (
            "10001 /usr/local/bin/antigravity\n"
            "10002 /usr/local/bin/antigravity --worker\n"
            "10003 /usr/local/bin/antigravity --worker\n"
        )
        name, count = parse_agent_processes(pgrep_out)
        self.assertEqual(name, "Antigravity")
        self.assertEqual(count, 3)

    def test_no_agent_process(self):
        pgrep_out = (
            "12300 /System/Library/CoreServices/Finder.app/Contents/MacOS/Finder\n"
        )
        name, count = parse_agent_processes(pgrep_out)
        self.assertIsNone(name)
        self.assertEqual(count, 0)

    def test_empty_pgrep_output(self):
        name, count = parse_agent_processes("")
        self.assertIsNone(name)
        self.assertEqual(count, 0)

    def test_ignore_grep_self(self):
        pgrep_out = "44444 pgrep -fl antigravity\n"
        name, count = parse_agent_processes(pgrep_out)
        self.assertIsNone(name)
        self.assertEqual(count, 0)


class TestAgentStateTransitions(unittest.TestCase):
    """Tests agent lifecycle state transitions (idle, running, review, error)."""

    def test_error_overrides_all(self):
        state = determine_agent_state(
            process_running=True,
            last_mtime=time.time(),
            current_time=time.time(),
            has_error=True,
        )
        self.assertEqual(state, AGENT_STATE_ERROR)

    def test_no_process_is_idle(self):
        state = determine_agent_state(
            process_running=False, last_mtime=time.time(), current_time=time.time()
        )
        self.assertEqual(state, AGENT_STATE_IDLE)

    def test_recent_heartbeat_is_running(self):
        now = 1000.0
        mtime = now - 15.0  # 15 seconds ago (< 45s)
        state = determine_agent_state(
            process_running=True, last_mtime=mtime, current_time=now
        )
        self.assertEqual(state, AGENT_STATE_RUNNING)

    def test_waiting_review_state(self):
        now = 1000.0
        mtime = now - 90.0  # 90 seconds ago (45s <= t < 300s)
        state = determine_agent_state(
            process_running=True, last_mtime=mtime, current_time=now
        )
        self.assertEqual(state, AGENT_STATE_REVIEW)

    def test_stale_heartbeat_is_idle(self):
        now = 1000.0
        mtime = now - 350.0  # 350 seconds ago (>= 300s)
        state = determine_agent_state(
            process_running=True, last_mtime=mtime, current_time=now
        )
        self.assertEqual(state, AGENT_STATE_IDLE)

    def test_no_mtime_with_process_defaults_running(self):
        state = determine_agent_state(
            process_running=True, last_mtime=0, current_time=1000.0
        )
        self.assertEqual(state, AGENT_STATE_RUNNING)


class TestAgentProgressParsing(unittest.TestCase):
    """Tests parsing task description and status from progress.md markdown."""

    def test_parse_active_task(self):
        content = (
            "# Progress\n"
            "**Current Status:** In Progress\n\n"
            "## Tasks\n"
            "- [x] Task 1 done\n"
            "- [/] Implement Smart Deck UI\n"
            "- [ ] Task 3 planned\n"
        )
        parsed = parse_agent_progress(content)
        self.assertEqual(parsed["task"], "Implement Smart Deck UI")
        self.assertEqual(parsed["status"], "In Progress")

    def test_parse_first_uncompleted_task_when_no_in_progress(self):
        content = (
            "# Progress\n"
            "**Current Status:** Working\n\n"
            "- [x] Initial setup\n"
            "- [ ] Build ArduinoJson Deserializer\n"
        )
        parsed = parse_agent_progress(content)
        self.assertEqual(parsed["task"], "Build ArduinoJson Deserializer")

    def test_empty_content(self):
        parsed = parse_agent_progress("")
        self.assertEqual(parsed["task"], "Idle")
        self.assertEqual(parsed["status"], "idle")


class TestGitStatusParsing(unittest.TestCase):
    """Tests git status --porcelain -b parsing."""

    def test_clean_feature_branch(self):
        out = "## feat/mac-controller...origin/feat/mac-controller\n"
        branch, dirty, count = parse_git_status(out)
        self.assertEqual(branch, "feat/mac-controller")
        self.assertFalse(dirty)
        self.assertEqual(count, 0)

    def test_dirty_main_branch(self):
        out = (
            "## main...origin/main [ahead 2, behind 1]\n"
            " M mac-controller/src/main.cpp\n"
            " M mac-controller/src/ui.cpp\n"
            "?? mac-controller/tests/test_agent_ci.py\n"
        )
        branch, dirty, count = parse_git_status(out)
        self.assertEqual(branch, "main")
        self.assertTrue(dirty)
        self.assertEqual(count, 3)

    def test_detached_head(self):
        out = "## HEAD (no branch)\n"
        branch, dirty, count = parse_git_status(out)
        self.assertEqual(branch, "HEAD")
        self.assertFalse(dirty)
        self.assertEqual(count, 0)

    def test_initial_unborn_branch(self):
        out = "## Initial commit on main\n"
        branch, dirty, count = parse_git_status(out)
        self.assertEqual(branch, "main")
        self.assertFalse(dirty)
        self.assertEqual(count, 0)

    def test_empty_output(self):
        branch, dirty, count = parse_git_status("")
        self.assertEqual(branch, "main")
        self.assertFalse(dirty)
        self.assertEqual(count, 0)


class TestGitHubChecksParsing(unittest.TestCase):
    """Tests gh pr checks and gh run list JSON output parsing."""

    def test_all_checks_passing(self):
        checks_data = [
            {"name": "build", "state": "SUCCESS", "bucket": "pass"},
            {"name": "test", "state": "SUCCESS", "bucket": "pass"},
            {"name": "lint", "state": "SUCCESS", "bucket": "pass"},
        ]
        res = parse_gh_pr_checks(json.dumps(checks_data))
        self.assertEqual(res["status"], CI_STATUS_PASSING)
        self.assertEqual(res["passed"], 3)
        self.assertEqual(res["total"], 3)

    def test_one_check_failing(self):
        checks_data = [
            {"name": "build", "state": "SUCCESS", "bucket": "pass"},
            {"name": "test", "state": "FAILURE", "bucket": "fail"},
            {"name": "lint", "state": "SUCCESS", "bucket": "pass"},
        ]
        res = parse_gh_pr_checks(json.dumps(checks_data))
        self.assertEqual(res["status"], CI_STATUS_FAILING)
        self.assertEqual(res["passed"], 2)
        self.assertEqual(res["total"], 3)

    def test_checks_pending(self):
        checks_data = [
            {"name": "build", "state": "SUCCESS", "bucket": "pass"},
            {"name": "test", "state": "PENDING", "bucket": "pending"},
        ]
        res = parse_gh_pr_checks(json.dumps(checks_data))
        self.assertEqual(res["status"], CI_STATUS_PENDING)
        self.assertEqual(res["passed"], 1)
        self.assertEqual(res["total"], 2)

    def test_empty_checks_list(self):
        res = parse_gh_pr_checks("[]")
        self.assertEqual(res["status"], CI_STATUS_NONE)
        self.assertEqual(res["total"], 0)

    def test_invalid_json_checks(self):
        res = parse_gh_pr_checks("{not valid json}")
        self.assertEqual(res["status"], CI_STATUS_UNKNOWN)

    def test_gh_run_list_fallback_success(self):
        run_data = [{"status": "completed", "conclusion": "success"}]
        res = parse_gh_run_list(json.dumps(run_data))
        self.assertEqual(res["status"], CI_STATUS_PASSING)

    def test_gh_run_list_fallback_failure(self):
        run_data = [{"status": "completed", "conclusion": "failure"}]
        res = parse_gh_run_list(json.dumps(run_data))
        self.assertEqual(res["status"], CI_STATUS_FAILING)

    def test_gh_run_list_fallback_in_progress(self):
        run_data = [{"status": "in_progress", "conclusion": ""}]
        res = parse_gh_run_list(json.dumps(run_data))
        self.assertEqual(res["status"], CI_STATUS_PENDING)


class TestWireProtocolConformance(unittest.TestCase):
    """Tests JSON wire protocol formatting, packet boundaries, and round-trip parsing."""

    def setUp(self):
        self.agent_info = {
            "name": "Antigravity",
            "state": "running",
            "task": "Survey specs R1-R5",
            "active_agents": 3,
        }
        self.ci_info = {
            "repo": "vitruvian-core",
            "branch": "main",
            "dirty": True,
            "dirty_files": 2,
            "status": "passing",
            "pr": 2177,
            "passed": 54,
            "total": 54,
        }

    def test_payload_structure(self):
        payload = build_agent_ci_payload(self.agent_info, self.ci_info)
        self.assertEqual(payload["type"], "agent_ci")
        self.assertIn("agent", payload)
        self.assertIn("ci", payload)
        self.assertEqual(payload["agent"]["name"], "Antigravity")
        self.assertEqual(payload["agent"]["state"], "running")
        self.assertEqual(payload["ci"]["status"], "passing")
        self.assertEqual(payload["ci"]["passed"], 54)
        self.assertEqual(payload["ci"]["total"], 54)

    def test_wire_framing_newline(self):
        payload = build_agent_ci_payload(self.agent_info, self.ci_info)
        packet = serialize_agent_ci_packet(payload)
        self.assertTrue(packet.endswith("\n"), "Packet must end with newline delimiter")
        self.assertEqual(
            packet.count("\n"), 1, "Packet must not contain interior newlines"
        )

    def test_buffer_size_within_512_bytes(self):
        payload = build_agent_ci_payload(self.agent_info, self.ci_info)
        packet = serialize_agent_ci_packet(payload)
        encoded_len = len(packet.encode("utf-8"))
        self.assertLess(
            encoded_len,
            512,
            f"Wire packet size ({encoded_len} bytes) exceeds 512-byte limit",
        )

    def test_arduinojson_simulated_deserialization(self):
        """Simulates ArduinoJson v7 extraction logic implemented in main.cpp."""
        payload = build_agent_ci_payload(self.agent_info, self.ci_info)
        packet = serialize_agent_ci_packet(payload).strip()

        # Simulate deserializeJson(doc, packet)
        doc = json.loads(packet)
        self.assertEqual(doc.get("type"), "agent_ci")

        # Simulate agent extraction
        agent = doc.get("agent", {})
        a_name = agent.get("name", "Agent")
        a_state = agent.get("state", "idle")
        a_task = agent.get("task", agent.get("detail", "Idle"))
        active_agents = agent.get("active_agents", 0)

        self.assertEqual(a_name, "Antigravity")
        self.assertEqual(a_state, "running")
        self.assertEqual(a_task, "Survey specs R1-R5")
        self.assertEqual(active_agents, 3)

        # Simulate ci extraction
        ci = doc.get("ci", {})
        c_repo = ci.get("repo", "repo")
        c_branch = ci.get("branch", "main")
        c_status = ci.get("status", ci.get("state", "unknown"))
        passed = ci.get("passed", 0)
        total = ci.get("total", 0)
        dirty = ci.get("dirty", False)

        self.assertEqual(c_repo, "vitruvian-core")
        self.assertEqual(c_branch, "main")
        self.assertEqual(c_status, "passing")
        self.assertEqual(passed, 54)
        self.assertEqual(total, 54)
        self.assertTrue(dirty)

    def test_robustness_against_missing_and_null_fields(self):
        """Firmware must not crash on partial or malformed agent_ci packets."""
        partial_payload = {"type": "agent_ci", "agent": None, "ci": {}}
        packet = json.dumps(partial_payload)
        doc = json.loads(packet)

        # Agent fallback
        agent = doc.get("agent") or {}
        a_name = agent.get("name", "Agent")
        self.assertEqual(a_name, "Agent")

        # CI fallback
        ci = doc.get("ci") or {}
        c_status = ci.get("status", "unknown")
        self.assertEqual(c_status, "unknown")


class TestHostCommandDispatcher(unittest.TestCase):
    """Tests host daemon command dispatch for touch actions sent from ESP32."""

    def setUp(self):
        self.mock_monitor = MagicMock(spec=AgentCIMonitor)
        self.mock_monitor.workspace_dir = "/test/repo/vitruvian-core"
        self.mock_monitor.get_payload.return_value = {
            "type": "agent_ci",
            "agent": {
                "name": "TestAgent",
                "state": "idle",
                "task": "Idle",
                "active_agents": 0,
            },
            "ci": {
                "repo": "vitruvian-core",
                "branch": "main",
                "dirty": False,
                "dirty_files": 0,
                "status": "passing",
                "pr": 0,
                "passed": 1,
                "total": 1,
            },
        }

    @patch("subprocess.Popen")
    def test_dispatch_run_checks_command(self, mock_popen):
        handle_esp_command('{"cmd":"run_checks"}\n', self.mock_monitor)
        self.mock_monitor.trigger_refresh.assert_called_once()
        mock_popen.assert_called_once_with(
            ["gh", "pr", "checks"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            cwd=self.mock_monitor.workspace_dir,
        )

    @patch("subprocess.Popen")
    def test_dispatch_open_pr_with_active_pr(self, mock_popen):
        self.mock_monitor.get_payload.return_value = {
            "ci": {
                "repo": "vitruvian-core",
                "branch": "feat/test",
                "status": "passing",
                "pr": 42,
            }
        }
        handle_esp_command('{"cmd":"open_pr"}\n', self.mock_monitor)
        mock_popen.assert_called_once_with(
            ["gh", "pr", "view", "42", "--web"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            cwd=self.mock_monitor.workspace_dir,
        )

    @patch("subprocess.Popen")
    def test_dispatch_open_pr_without_active_pr(self, mock_popen):
        self.mock_monitor.get_payload.return_value = {
            "ci": {
                "repo": "vitruvian-core",
                "branch": "main",
                "status": "none",
                "pr": 0,
            }
        }
        handle_esp_command('{"cmd":"open_pr"}\n', self.mock_monitor)
        mock_popen.assert_called_once_with(
            ["gh", "repo", "view", "--web"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            cwd=self.mock_monitor.workspace_dir,
        )

    @patch("subprocess.Popen")
    def test_dispatch_refresh_command(self, mock_popen):
        handle_esp_command('{"cmd":"refresh"}\n', self.mock_monitor)
        self.mock_monitor.trigger_refresh.assert_called_once()
        mock_popen.assert_not_called()

    @patch("subprocess.Popen")
    def test_dispatch_command_aliases(self, mock_popen):
        # Test 'action' key instead of 'cmd' key, and 'refresh_ci' alias
        handle_esp_command('{"action":"refresh_ci"}\n', self.mock_monitor)
        self.mock_monitor.trigger_refresh.assert_called_once()
        mock_popen.assert_not_called()

        # Test 'open_ci' alias
        self.mock_monitor.get_payload.return_value = {"ci": {"pr": 10}}
        handle_esp_command('{"action":"open_ci"}\n', self.mock_monitor)
        mock_popen.assert_called_once_with(
            ["gh", "pr", "view", "10", "--web"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            cwd=self.mock_monitor.workspace_dir,
        )

    @patch("subprocess.Popen")
    def test_dispatch_focus_agent(self, mock_popen):
        handle_esp_command('{"cmd":"focus_agent"}\n', self.mock_monitor)
        mock_popen.assert_called_once_with(
            ["osascript", "-e", 'tell application "Antigravity" to activate'],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

    @patch("subprocess.Popen")
    def test_dispatch_invalid_commands_and_json(self, mock_popen):
        handle_esp_command("not-json-payload\n", self.mock_monitor)
        handle_esp_command("", self.mock_monitor)
        handle_esp_command("{}\n", self.mock_monitor)
        handle_esp_command('{"cmd":"some_unhandled_action"}\n', self.mock_monitor)
        mock_popen.assert_not_called()
        self.mock_monitor.trigger_refresh.assert_not_called()


class TestAgentCIMonitorThread(unittest.TestCase):
    """Tests background threading and thread-safe payload retrieval in AgentCIMonitor."""

    def test_monitor_init_payload(self):
        m = AgentCIMonitor(agent_interval=1.0, ci_interval=1.0)
        p = m.get_payload()
        self.assertEqual(p["type"], "agent_ci")
        self.assertIn("agent", p)
        self.assertIn("ci", p)

    @patch.object(
        AgentCIMonitor,
        "poll_agent",
        return_value={
            "name": "MockAgent",
            "state": "idle",
            "task": "Idle",
            "active_agents": 0,
        },
    )
    @patch.object(
        AgentCIMonitor,
        "poll_ci",
        return_value={
            "repo": "repo",
            "branch": "main",
            "dirty": False,
            "dirty_files": 0,
            "status": "passing",
            "pr": 0,
            "passed": 1,
            "total": 1,
        },
    )
    def test_monitor_start_stop(self, mock_ci, mock_agent):
        m = AgentCIMonitor(agent_interval=0.1, ci_interval=0.1)
        m.start()
        time.sleep(0.05)
        self.assertTrue(m._worker_thread.is_alive())
        m.stop(timeout=2.0)
        self.assertFalse(m._worker_thread.is_alive())

    def test_monitor_trigger_refresh(self):
        m = AgentCIMonitor(agent_interval=10.0, ci_interval=10.0)
        m.start()
        m.trigger_refresh()
        self.assertTrue(m._refresh_event.is_set())
        m.stop(timeout=1.0)


if __name__ == "__main__":
    unittest.main()
