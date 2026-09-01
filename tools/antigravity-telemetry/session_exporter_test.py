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

"""Unit tests for Antigravity Session Exporter daemon."""

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
        self.state_file = os.path.join(self.temp_dir.name, "telemetry_state.json")
        os.makedirs(self.brain_dir, exist_ok=True)

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_incremental_scan(self):
        convo_id = "test-convo-123"
        log_dir = os.path.join(self.brain_dir, convo_id, ".system_generated", "logs")
        os.makedirs(log_dir, exist_ok=True)
        transcript_path = os.path.join(log_dir, "transcript.jsonl")

        # Write initial steps
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
            state_file=self.state_file,
            endpoint="http://127.0.0.1:9999",
            host="test-host",
        )

        events_count = scanner.scan_once()
        self.assertEqual(events_count, 1)  # 1 planner response
        self.assertGreater(scanner.offsets[transcript_path], 0)

        # Append new step
        step3 = {
            "step_index": 3,
            "type": "PLANNER_RESPONSE",
            "tool_calls": [{"name": "invoke_subagent"}],
        }
        with open(transcript_path, "a", encoding="utf-8") as f:
            f.write(json.dumps(step3) + "\n")

        # Second scan should only process step 3
        events_count2 = scanner.scan_once()
        self.assertEqual(events_count2, 1)


if __name__ == "__main__":
    unittest.main()
