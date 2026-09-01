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

"""Unit tests for Antigravity & Claude Code Session Exporter daemon."""

import json
import os
import tempfile
import unittest
from session_exporter import TranscriptScanner


class TestTranscriptScanner(unittest.TestCase):
    """Test suite for incremental transcript parsing and offset management."""

    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.brain_dir = os.path.join(self.temp_dir.name, "brain")
        self.claude_dir = os.path.join(self.temp_dir.name, "claude_projects")
        self.state_file = os.path.join(self.temp_dir.name, "telemetry_state.json")
        os.makedirs(self.brain_dir, exist_ok=True)
        os.makedirs(self.claude_dir, exist_ok=True)

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_incremental_antigravity_scan(self):
        convo_id = "test-convo-123"
        log_dir = os.path.join(self.brain_dir, convo_id, ".system_generated", "logs")
        os.makedirs(log_dir, exist_ok=True)
        transcript_path = os.path.join(log_dir, "transcript.jsonl")

        step1 = {"step_index": 1, "type": "USER_INPUT", "content": "Hello"}
        step2 = {
            "step_index": 2,
            "type": "PLANNER_RESPONSE",
            "tool_calls": [{"name": "run_command"}, {"name": "view_file"}],
        }

        with open(transcript_path, "w", encoding="utf-8") as f:
            f.write(json.dumps(step1) + "\n")
            f.write(json.dumps(step2) + "\n")

        scanner = TranscriptScanner(
            brain_dir=self.brain_dir,
            claude_dir=self.claude_dir,
            state_file=self.state_file,
            endpoint="http://127.0.0.1:9999",
            host="test-host",
        )

        events_count = scanner.scan_once()
        self.assertEqual(events_count, 1)
        self.assertGreater(scanner.offsets[transcript_path], 0)

        step3 = {
            "step_index": 3,
            "type": "PLANNER_RESPONSE",
            "tool_calls": [{"name": "invoke_subagent"}],
        }
        with open(transcript_path, "a", encoding="utf-8") as f:
            f.write(json.dumps(step3) + "\n")

        events_count2 = scanner.scan_once()
        self.assertEqual(events_count2, 1)

    def test_incremental_claude_scan(self):
        project_dir = os.path.join(self.claude_dir, "test-project")
        os.makedirs(project_dir, exist_ok=True)
        session_file = os.path.join(project_dir, "session-1.jsonl")

        msg1 = {
            "type": "assistant",
            "message": {
                "role": "assistant",
                "model": "claude-opus-5",
                "usage": {
                    "input_tokens": 100,
                    "output_tokens": 50,
                    "cache_read_input_tokens": 200,
                    "cache_creation_input_tokens": 300,
                },
                "content": [
                    {"type": "tool_use", "name": "Bash"},
                    {"type": "tool_use", "name": "Read"},
                ],
            },
        }

        with open(session_file, "w", encoding="utf-8") as f:
            f.write(json.dumps(msg1) + "\n")

        scanner = TranscriptScanner(
            brain_dir=self.brain_dir,
            claude_dir=self.claude_dir,
            state_file=self.state_file,
            endpoint="http://127.0.0.1:9999",
            host="test-host",
        )

        events = scanner.scan_once()
        self.assertEqual(events, 1)
        self.assertGreater(scanner.offsets[session_file], 0)

        msg2 = {
            "type": "assistant",
            "message": {
                "role": "assistant",
                "model": "claude-opus-5",
                "usage": {"input_tokens": 10, "output_tokens": 20},
                "content": [{"type": "tool_use", "name": "Agent"}],
            },
        }

        with open(session_file, "a", encoding="utf-8") as f:
            f.write(json.dumps(msg2) + "\n")

        events2 = scanner.scan_once()
        self.assertEqual(events2, 1)


if __name__ == "__main__":
    unittest.main()
