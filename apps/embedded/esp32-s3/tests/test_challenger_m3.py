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
mac-controller/tests/test_challenger_m3.py
Empirical Challenger Adversarial Stress Suite for Milestone 3 (AI Agent & CI/CD Pipeline Deck).

Empirically tests and reproduces:
1. Agent Process Detection (pgrep edge cases, noise, multiple agent types, timeouts).
2. Workspace & progress.md Resilience (corrupt files, non-UTF8, 10MB file, null bytes, non-existent paths).
3. Lifecycle State Machine Stress (clock skew, future mtime, exact boundary thresholds).
4. Git Status & Detached HEAD (detached HEAD variations, upstream tracking, large dirty trees).
5. CI/CD Status Parsing (offline/timeouts, skipped checks, non-standard states, malformed JSON).
6. Concurrent Thread Safety & Lifecycle (background worker thread, race condition stress).
7. Verified Empirical Bug Reproductions:
   - Bug A: parse_gh_run_list crashes on [null] or [123] with uncaught AttributeError.
   - Bug B: parse_git_status truncates branch names containing dots (e.g. release/v1.0.0 -> release/v1).
   - Bug C: build_agent_ci_payload crashes on non-numeric active_agents/passed with ValueError.
   - Bug D: Benign error mentions in progress.md ("0 errors, all passed") trigger false-positive AGENT_STATE_ERROR.
   - Bug E: Non-deterministic agent state depending on os.listdir order across multiple agent directories.
"""

import os
import sys
import json
import time
import tempfile
import shutil
import subprocess
import threading
import unittest
from unittest.mock import patch, MagicMock

# Add host_companion to sys.path
sys.path.insert(
    0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../host_companion"))
)

import agent_ci_monitor
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


class TestAgentProcessDetectionStress(unittest.TestCase):
    """Stress tests process detection against noise, high volume, and corner cases."""

    def test_mixed_multiple_agent_processes(self):
        """Simultaneous multiple Antigravity and Claude Code processes should yield 'Teamwork'."""
        pgrep_output = (
            "101 /usr/local/bin/antigravity --worker\n"
            "102 /usr/local/bin/antigravity --worker\n"
            "103 /opt/homebrew/bin/claude\n"
            "104 /opt/homebrew/bin/claude --print\n"
            "105 /usr/local/bin/agy\n"
        )
        name, count = parse_agent_processes(pgrep_output)
        self.assertEqual(name, "Teamwork")
        self.assertEqual(count, 5)

    def test_noise_and_mcp_filtering(self):
        """Processes related to MCP servers, Claude Helper, or grep must be filtered by poll_agent."""
        pgrep_output = (
            "201 node /Users/user/.npm/bin/mcp-server-git\n"
            "202 node /Users/user/.npm/bin/mcp-remote\n"
            "203 /Applications/Claude.app/Contents/Frameworks/Claude Helper (Renderer).app\n"
            "204 grep -i antigravity\n"
            "205 pgrep -fl claude\n"
            "206 /opt/homebrew/bin/python3 -m antigravity\n"
        )
        monitor = AgentCIMonitor(workspace_dir="/tmp")
        with patch("subprocess.check_output", return_value=pgrep_output):
            res = monitor.poll_agent()
        self.assertEqual(res["name"], "Antigravity")
        self.assertEqual(res["active_agents"], 1)

        # Architectural Observation: parse_agent_processes by itself only filters 'pgrep' and 'grep',
        # leaving 'Claude Helper' to match regex \bclaude\b if not pre-filtered by poll_agent.
        raw_name, raw_count = parse_agent_processes(pgrep_output)
        self.assertEqual(raw_name, "Teamwork")  # Matched line 203 as claude
        self.assertEqual(raw_count, 2)

    def test_case_insensitivity_and_spacing(self):
        """Whitespace padding and varied casing in process names."""
        pgrep_output = "   999    /bin/CLAUDE-CODE   --verbose   \n"
        name, count = parse_agent_processes(pgrep_output)
        self.assertEqual(name, "Claude Code")
        self.assertEqual(count, 1)

    def test_pgrep_timeout_and_error_handling(self):
        """AgentCIMonitor.poll_agent must survive pgrep failures and timeouts."""
        monitor = AgentCIMonitor(workspace_dir="/tmp")
        with patch(
            "subprocess.check_output",
            side_effect=subprocess.TimeoutExpired(["pgrep"], 1.5),
        ):
            res = monitor.poll_agent()
            self.assertEqual(res["name"], "None")
            self.assertEqual(res["active_agents"], 0)

        with patch(
            "subprocess.check_output", side_effect=FileNotFoundError("pgrep not found")
        ):
            res = monitor.poll_agent()
            self.assertEqual(res["name"], "None")
            self.assertEqual(res["active_agents"], 0)


class TestWorkspaceProgressStress(unittest.TestCase):
    """Stress tests workspace .agents and progress.md parsing against corruption and scale."""

    def setUp(self):
        self.test_dir = tempfile.mkdtemp(prefix="agent_stress_")
        self.agents_dir = os.path.join(self.test_dir, ".agents")
        os.makedirs(self.agents_dir, exist_ok=True)

    def tearDown(self):
        shutil.rmtree(self.test_dir, ignore_errors=True)

    def test_corrupt_and_binary_progress_file(self):
        """progress.md containing raw binary bytes and null characters must not crash the parser."""
        agent_dir = os.path.join(self.agents_dir, "corrupt_agent")
        os.makedirs(agent_dir, exist_ok=True)
        prog_path = os.path.join(agent_dir, "progress.md")

        with open(prog_path, "wb") as f:
            f.write(
                b"\x00\xff\xfe\x80\x01\x02\x03Some text\x00- [/] Active binary task\xff\xfe"
            )

        monitor = AgentCIMonitor(workspace_dir=self.test_dir)
        with patch("subprocess.check_output", return_value="123 /bin/antigravity\n"):
            res = monitor.poll_agent()
            self.assertEqual(res["name"], "Antigravity")
            self.assertIn(res["state"], (AGENT_STATE_RUNNING, AGENT_STATE_REVIEW))

    def test_massive_progress_file_bounded_read(self):
        """A 10MB progress.md must be safely bounded to 2048 bytes without memory exhaustion."""
        agent_dir = os.path.join(self.agents_dir, "large_agent")
        os.makedirs(agent_dir, exist_ok=True)
        prog_path = os.path.join(agent_dir, "progress.md")

        with open(prog_path, "w") as f:
            f.write("- [/] Fast parsed task\n")
            f.write("A" * (10 * 1024 * 1024))  # 10MB

        monitor = AgentCIMonitor(workspace_dir=self.test_dir)
        start_t = time.monotonic()
        with patch("subprocess.check_output", return_value="123 /bin/antigravity\n"):
            res = monitor.poll_agent()
        duration = time.monotonic() - start_t

        self.assertLess(
            duration, 0.5, "Parsing huge progress.md must take < 0.5s via bounded read"
        )
        self.assertEqual(res["task"], "Fast parsed task")

    def test_empty_and_whitespace_progress_file(self):
        """Empty progress.md should default to 'Ready' or 'Idle'."""
        agent_dir = os.path.join(self.agents_dir, "empty_agent")
        os.makedirs(agent_dir, exist_ok=True)
        prog_path = os.path.join(agent_dir, "progress.md")
        with open(prog_path, "w") as f:
            f.write("   \n\n   ")

        monitor = AgentCIMonitor(workspace_dir=self.test_dir)
        with patch("subprocess.check_output", return_value=""):
            res = monitor.poll_agent()
            self.assertEqual(res["task"], "Ready")

    def test_nonexistent_workspace_dir(self):
        """Nonexistent workspace directories must degrade gracefully to defaults."""
        monitor = AgentCIMonitor(
            workspace_dir="/nonexistent/path/that/cannot/exist/99999"
        )
        with patch("subprocess.check_output", return_value=""):
            res = monitor.poll_agent()
            self.assertEqual(res["name"], "None")
            self.assertEqual(res["state"], AGENT_STATE_IDLE)
            self.assertEqual(res["task"], "Ready")

    def test_task_string_truncation(self):
        """Task descriptions exceeding 48 characters must be safely truncated."""
        prog = "- [/] " + ("A" * 100)
        parsed = parse_agent_progress(prog)
        self.assertEqual(len(parsed["task"]), 100)

        # In poll_agent, line 494 truncates to 48 chars
        agent_dir = os.path.join(self.agents_dir, "long_task_agent")
        os.makedirs(agent_dir, exist_ok=True)
        with open(os.path.join(agent_dir, "progress.md"), "w") as f:
            f.write(prog)

        monitor = AgentCIMonitor(workspace_dir=self.test_dir)
        with patch("subprocess.check_output", return_value=""):
            res = monitor.poll_agent()
            self.assertEqual(len(res["task"]), 48)
            self.assertEqual(res["task"], "A" * 48)


class TestAgentLifecycleStateMachine(unittest.TestCase):
    """Stress tests lifecycle state transitions and timing boundaries."""

    def test_boundary_timing_transitions(self):
        """Verify exact timing boundaries (45s, 300s)."""
        now = 1000.0
        # Exactly 44.9s elapsed -> RUNNING
        self.assertEqual(
            determine_agent_state(True, now - 44.9, now), AGENT_STATE_RUNNING
        )
        # Exactly 45.1s elapsed -> REVIEW
        self.assertEqual(
            determine_agent_state(True, now - 45.1, now), AGENT_STATE_REVIEW
        )
        # Exactly 299.9s elapsed -> REVIEW
        self.assertEqual(
            determine_agent_state(True, now - 299.9, now), AGENT_STATE_REVIEW
        )
        # Exactly 300.1s elapsed -> IDLE
        self.assertEqual(
            determine_agent_state(True, now - 300.1, now), AGENT_STATE_IDLE
        )

    def test_future_clock_skew(self):
        """If mtime is in the future (NTP jump), elapsed is clamped to 0.0 -> RUNNING."""
        now = 1000.0
        future_mtime = now + 500.0
        self.assertEqual(
            determine_agent_state(True, future_mtime, now), AGENT_STATE_RUNNING
        )

    def test_missing_or_zero_mtime(self):
        """mtime <= 0 enters grace period -> RUNNING if process is running."""
        now = 1000.0
        self.assertEqual(determine_agent_state(True, 0.0, now), AGENT_STATE_RUNNING)
        self.assertEqual(determine_agent_state(True, -10.0, now), AGENT_STATE_RUNNING)
        self.assertEqual(determine_agent_state(False, 0.0, now), AGENT_STATE_IDLE)


class TestGitStatusAndDetachedHeadStress(unittest.TestCase):
    """Stress tests git status porcelain parsing, detached HEAD, and branch tracking."""

    def test_detached_head_variants(self):
        """All detached HEAD porcelain formats must extract 'HEAD' without error."""
        # Standard detached HEAD
        branch, dirty, count = parse_git_status("## HEAD (no branch)\n")
        self.assertEqual(branch, "HEAD")
        self.assertFalse(dirty)
        self.assertEqual(count, 0)

        # Detached HEAD with uncommitted changes
        porcelain = "## HEAD (no branch)\n M src/main.cpp\n?? newfile.py\n"
        branch, dirty, count = parse_git_status(porcelain)
        self.assertEqual(branch, "HEAD")
        self.assertTrue(dirty)
        self.assertEqual(count, 2)

        # Detached at commit SHA
        branch, _, _ = parse_git_status("## HEAD (detached at 7a8b9c0)\n")
        self.assertEqual(branch, "HEAD")

        # Detached from tag
        branch, _, _ = parse_git_status("## HEAD (detached from v1.2.0)\n")
        self.assertEqual(branch, "HEAD")

    def test_tracking_upstream_and_divergence(self):
        """Branches with upstream tracking details must extract branch name cleanly."""
        porcelain = "## feat/my-branch...origin/feat/my-branch [ahead 3, behind 1]\n"
        branch, dirty, count = parse_git_status(porcelain)
        self.assertEqual(branch, "feat/my-branch")
        self.assertFalse(dirty)

    def test_massive_dirty_tree(self):
        """Repository with 1,000 uncommitted files."""
        lines = ["## main...origin/main"]
        lines.extend([f" M file_{i}.py" for i in range(1000)])
        porcelain = "\n".join(lines) + "\n"

        branch, dirty, count = parse_git_status(porcelain)
        self.assertEqual(branch, "main")
        self.assertTrue(dirty)
        self.assertEqual(count, 1000)

    def test_unborn_branch_and_initial_commit(self):
        """Unborn branch before initial commit."""
        branch, _, _ = parse_git_status("## Initial commit on feature-init\n")
        self.assertEqual(branch, "feature-init")

        branch, _, _ = parse_git_status("## No commits yet on dev\n")
        self.assertEqual(branch, "dev")


class TestGitHubChecksAndRunsStress(unittest.TestCase):
    """Stress tests GitHub CI checks parsing under edge cases and error conditions."""

    def test_offline_or_gh_cli_missing(self):
        """AgentCIMonitor.poll_ci must handle complete network disconnect or missing gh binary."""
        monitor = AgentCIMonitor(workspace_dir="/tmp")
        with patch(
            "subprocess.check_output",
            side_effect=subprocess.TimeoutExpired(["gh"], 3.0),
        ):
            res = monitor.poll_ci()
            self.assertEqual(res["status"], CI_STATUS_NONE)
            self.assertEqual(res["pr"], 0)

        with patch(
            "subprocess.check_output", side_effect=FileNotFoundError("gh not found")
        ):
            res = monitor.poll_ci()
            self.assertEqual(res["status"], CI_STATUS_NONE)

    def test_skipped_and_neutral_checks(self):
        """Skipped checks in gh pr checks should not mark CI as failing."""
        checks = [
            {"name": "build", "state": "SUCCESS", "bucket": "pass"},
            {"name": "optional-lint", "state": "SKIPPED", "bucket": "skipping"},
            {"name": "deploy-preview", "state": "NEUTRAL", "bucket": "neutral"},
        ]
        res = parse_gh_pr_checks(json.dumps(checks))
        # 1 passed out of 3, 0 failing, 0 pending -> passing because passed > 0
        self.assertEqual(res["status"], CI_STATUS_PASSING)
        self.assertEqual(res["passed"], 1)
        self.assertEqual(res["total"], 3)

    def test_all_skipped_checks(self):
        """If all checks are skipped (0 passed, 0 failed, 0 pending), status is unknown."""
        checks = [
            {"name": "optional-1", "state": "SKIPPED", "bucket": "skipping"},
            {"name": "optional-2", "state": "SKIPPED", "bucket": "skipping"},
        ]
        res = parse_gh_pr_checks(json.dumps(checks))
        self.assertEqual(res["status"], CI_STATUS_UNKNOWN)
        self.assertEqual(res["passed"], 0)
        self.assertEqual(res["total"], 2)

    def test_corrupt_json_in_pr_checks(self):
        """Malformed JSON strings must safely return default unknown/none dicts."""
        res_empty = parse_gh_pr_checks("")
        self.assertEqual(res_empty["status"], CI_STATUS_NONE)

        res_malformed = parse_gh_pr_checks("{not-valid-json")
        self.assertEqual(res_malformed["status"], CI_STATUS_UNKNOWN)

        res_dict = parse_gh_pr_checks('{"error": "API rate limit exceeded"}')
        self.assertEqual(res_dict["status"], CI_STATUS_UNKNOWN)

    def test_checks_list_with_non_dict_elements(self):
        """JSON list containing non-dict elements (e.g. null, ints, strings) must be skipped safely."""
        checks = [
            None,
            1234,
            "error_string",
            {"name": "valid-check", "state": "SUCCESS", "bucket": "pass"},
        ]
        res = parse_gh_pr_checks(json.dumps(checks))
        self.assertEqual(res["passed"], 1)
        self.assertEqual(res["total"], 4)
        self.assertEqual(res["status"], CI_STATUS_PASSING)


class TestThreadSafetyAndLifecycleStress(unittest.TestCase):
    """Stress tests background worker thread lifecycle, concurrency, and shutdown."""

    def test_concurrent_payload_reads_under_active_polling(self):
        """High-frequency concurrent reads from multiple threads while monitor is running."""
        monitor = AgentCIMonitor(
            workspace_dir="/tmp", agent_interval=0.05, ci_interval=0.05
        )
        monitor.start()

        errors = []

        def reader():
            for _ in range(100):
                try:
                    p = monitor.get_payload()
                    self.assertIn("type", p)
                    self.assertEqual(p["type"], "agent_ci")
                    self.assertIn("agent", p)
                    self.assertIn("ci", p)
                except Exception as e:
                    errors.append(e)
                time.sleep(0.002)

        threads = [threading.Thread(target=reader) for _ in range(10)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()

        monitor.stop(timeout=2.0)
        self.assertEqual(len(errors), 0, f"Thread errors encountered: {errors}")

    def test_rapid_start_stop_restart(self):
        """Verify monitor starts and stops cleanly without hanging."""
        monitor = AgentCIMonitor(
            workspace_dir="/tmp", agent_interval=1.0, ci_interval=1.0
        )
        monitor.start()
        self.assertTrue(monitor._worker_thread.is_alive())
        monitor.trigger_refresh()
        monitor.stop(timeout=1.0)
        self.assertFalse(monitor._worker_thread.is_alive())


# ===========================================================================
# Empirical Bug Reproductions (Documented Findings)
# ===========================================================================
class TestEmpiricalBugReproductions(unittest.TestCase):
    """
    Empirical tests validating remediations for edge case bugs (Bugs A-E).
    Each test asserts the correct, robust behavior under previously failing conditions.
    """

    def test_bug_a_parse_gh_run_list_attribute_error_on_null_elements(self):
        """Remediated: parse_gh_run_list safely handles [null] and [123] without AttributeError."""
        res_null = parse_gh_run_list("[null]")
        self.assertEqual(res_null["status"], CI_STATUS_UNKNOWN)
        self.assertEqual(res_null["passed"], 0)

        res_int = parse_gh_run_list("[123]")
        self.assertEqual(res_int["status"], CI_STATUS_UNKNOWN)
        self.assertEqual(res_int["passed"], 0)

    def test_bug_b_parse_git_status_truncates_branch_names_with_dots(self):
        """Remediated: parse_git_status preserves branch names containing dots."""
        branch_v1, dirty, _ = parse_git_status(
            "## release/v1.0.0...origin/release/v1.0.0\n"
        )
        self.assertEqual(branch_v1, "release/v1.0.0")
        self.assertFalse(dirty)

        branch_dot, _, _ = parse_git_status("## feat.v2\n")
        self.assertEqual(branch_dot, "feat.v2")

    def test_bug_c_build_agent_ci_payload_value_error_on_non_int(self):
        """Remediated: build_agent_ci_payload safely handles non-integer and malformed values."""
        payload_1 = build_agent_ci_payload({"active_agents": "two"}, {})
        self.assertEqual(payload_1["agent"]["active_agents"], 0)

        payload_2 = build_agent_ci_payload({}, {"passed": "all", "total": "none"})
        self.assertEqual(payload_2["ci"]["passed"], 0)
        self.assertEqual(payload_2["ci"]["total"], 0)

    def test_bug_d_false_positive_agent_error_on_benign_text(self):
        """Remediated: poll_agent does not flag benign phrases as errors."""
        benign_content = (
            "## Status\nBuild successful. No errors encountered. 0 failed tests."
        )
        with tempfile.TemporaryDirectory() as td:
            agent_dir = os.path.join(td, ".agents", "worker")
            os.makedirs(agent_dir)
            with open(os.path.join(agent_dir, "progress.md"), "w") as f:
                f.write(benign_content)
            monitor = AgentCIMonitor(workspace_dir=td)
            with patch(
                "subprocess.check_output", return_value="123 /bin/antigravity\n"
            ):
                res = monitor.poll_agent()
            self.assertEqual(res["state"], AGENT_STATE_RUNNING)

    def test_bug_e_non_deterministic_agent_error_from_directory_traversal_order(self):
        """Remediated: poll_agent evaluates state deterministically based on highest mtime."""
        with tempfile.TemporaryDirectory() as td:
            agents_dir = os.path.join(td, ".agents")
            os.makedirs(os.path.join(agents_dir, "old_failed"))
            os.makedirs(os.path.join(agents_dir, "new_active"))

            with open(os.path.join(agents_dir, "old_failed", "progress.md"), "w") as f:
                f.write("ERROR: failed compilation step")
            os.utime(
                os.path.join(agents_dir, "old_failed", "progress.md"), (1000, 1000)
            )

            with open(os.path.join(agents_dir, "new_active", "progress.md"), "w") as f:
                f.write("- [/] Active feature development\nAll good.")
            now = time.time()
            os.utime(os.path.join(agents_dir, "new_active", "progress.md"), (now, now))

            monitor = AgentCIMonitor(workspace_dir=td)

            with patch(
                "subprocess.check_output", return_value="123 /bin/antigravity\n"
            ):
                with patch("os.listdir", return_value=["old_failed", "new_active"]):
                    res_old_first = monitor.poll_agent()
                with patch("os.listdir", return_value=["new_active", "old_failed"]):
                    res_new_first = monitor.poll_agent()

            self.assertEqual(res_old_first["state"], AGENT_STATE_RUNNING)
            self.assertEqual(res_new_first["state"], AGENT_STATE_RUNNING)
            self.assertEqual(res_old_first["state"], res_new_first["state"])


if __name__ == "__main__":
    unittest.main()
