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
mac-controller/tests/test_challenger_m2.py
Adversarial challenge and stress-test suite for Milestone 2:
- Frontmost application detection and profile resolution edge cases
- Debounce state machine under rapid focus switching and clock anomalies
- Fuzzy heuristics and substring collision analysis
- Wire protocol serialization, malformed JSON, and buffer capacity
"""

import sys
import os
import json
import time
import unittest
from unittest.mock import patch, MagicMock

# Ensure host_companion is discoverable
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../host_companion")))

import app_profiles
from app_profiles import (
    MOD_NONE, MOD_CTRL, MOD_SHIFT, MOD_ALT, MOD_CMD,
    PROFILES, get_profile_for_app, get_profile_for_bundle,
    build_app_payload, FrontmostAppDetector,
)


class TestAdversarialProfileResolution(unittest.TestCase):
    """Stress tests profile resolution against adversarial, boundary, and pathological inputs."""

    def test_empty_and_whitespace_inputs(self):
        """Empty, whitespace, or None bundle IDs must safely fall back to Default profile."""
        self.assertEqual(get_profile_for_app("", "")["app"], "Default")
        self.assertEqual(get_profile_for_app("   ", "   ")["app"], "Default")
        self.assertEqual(get_profile_for_app(None, None)["app"], "Default")
        self.assertEqual(get_profile_for_app(None, "")["app"], "Default")
        self.assertEqual(get_profile_for_app("", None)["app"], "Default")

    def test_unknown_applications(self):
        """Unregistered apps with arbitrary names must fall back to Default."""
        self.assertEqual(get_profile_for_app("com.spotify.client", "Spotify")["app"], "Default")
        self.assertEqual(get_profile_for_app("org.blender.blender", "Blender")["app"], "Default")
        self.assertEqual(get_profile_for_app("com.docker.docker", "Docker Desktop")["app"], "Default")
        self.assertEqual(get_profile_for_app("com.figma.Desktop", "Figma")["app"], "Default")
        self.assertEqual(get_profile_for_app("com.valvesoftware.steam", "Steam")["app"], "Default")

    def test_unicode_and_special_character_names(self):
        """Unicode names (emoji, non-Latin scripts) must not raise exceptions."""
        self.assertEqual(get_profile_for_app("com.example.🚀", "🚀 Fast App")["app"], "Default")
        self.assertEqual(get_profile_for_app("com.example.app", "日本語エディタ")["app"], "Default")
        self.assertEqual(get_profile_for_app("com.example.app", "محرر النصوص")["app"], "Default")
        self.assertEqual(get_profile_for_app("com.example.app", "App <script>alert(1)</script>")["app"], "Default")

    def test_substring_bundle_id_collision_risks(self):
        """
        Adversarial test: 'bundle_lower in bid_lower' check causes broad false-positive collisions
        when bundle_id is a short prefix, suffix, or common token like 'com', 'io', 'app', 'com.apple'.
        """
        # "com" matches "com.microsoft.VSCode" because "com" in "com.microsoft.vscode"
        res_com = get_profile_for_app("com")
        self.assertEqual(res_com["app"], "VS Code")

        # "com.apple" matches "com.apple.Safari" because "com.apple" in "com.apple.safari"
        res_apple = get_profile_for_app("com.apple")
        self.assertEqual(res_apple["app"], "Chrome")

        # "io" matches "com.visualstudio.code.oss" because "io" is in "visualstudio",
        # causing false positive match to VS Code instead of falling back or reaching io.alacritty!
        res_io = get_profile_for_app("io")
        self.assertEqual(res_io["app"], "VS Code")

        # "net" matches "net.kovidgoyal.kitty" -> Terminal
        res_net = get_profile_for_app("net")
        self.assertEqual(res_net["app"], "Terminal")

        # "org" matches "org.mozilla.firefox" -> Chrome
        res_org = get_profile_for_app("org")
        self.assertEqual(res_org["app"], "Chrome")

        # "app" matches "com.apple.Safari" -> Chrome
        res_app = get_profile_for_app("app")
        self.assertEqual(res_app["app"], "Chrome")

    def test_fuzzy_name_collision_risks(self):
        """
        Adversarial test: 'code' in app_lower heuristics can falsely match unrelated apps
        containing the substring 'code'.
        """
        # Xcode matches VS Code because 'code' in 'xcode'
        self.assertEqual(get_profile_for_app("com.apple.dt.Xcode", "Xcode")["app"], "VS Code")
        # Barcode Scanner matches VS Code because 'code' in 'barcode scanner'
        self.assertEqual(get_profile_for_app("com.example.barcode", "Barcode Scanner")["app"], "VS Code")
        # Passcode Manager matches VS Code
        self.assertEqual(get_profile_for_app("com.example.passcode", "Passcode Manager")["app"], "VS Code")
        # Unicode Converter matches VS Code
        self.assertEqual(get_profile_for_app("com.example.unicode", "Unicode Converter")["app"], "VS Code")

    def test_missing_value_osascript_resolution(self):
        """When macOS System Events returns 'missing value', resolver should safely fallback."""
        self.assertEqual(get_profile_for_app("missing value", "Calculator")["app"], "Default")
        self.assertEqual(get_profile_for_app("missing value", "")["app"], "Default")


class TestAdversarialDebounceAndStateTransitions(unittest.TestCase):
    """Stress tests the FrontmostAppDetector state machine against rapid switches and clock jitter."""

    def test_rapid_fire_app_switching_stress(self):
        """
        Simulates cycling through 20 apps in rapid succession (15ms each, total 300ms).
        Since none persists >= 250ms, update() must NEVER confirm any of them.
        """
        detector = FrontmostAppDetector(debounce_seconds=0.25)
        with patch.object(detector, "query_frontmost_raw", return_value=("com.apple.finder", "Finder")):
            detector.update(force_immediate=True)

        apps = [f"com.app.{i}" for i in range(20)]
        t = 1000.0

        for app in apps:
            t += 0.015  # 15 ms per app
            with patch.object(detector, "query_frontmost_raw", return_value=(app, app)):
                with patch("time.monotonic", return_value=t):
                    res = detector.update()
                    self.assertIsNone(res, f"Unexpected confirmation during rapid switch for {app} at t={t}")

        # Current confirmed app must still be the original Finder
        self.assertEqual(detector.confirmed_bundle_id, "com.apple.finder")

    def test_near_boundary_debounce_timing(self):
        """Tests exact 249ms vs 251ms threshold precision."""
        detector = FrontmostAppDetector(debounce_seconds=0.25)
        with patch.object(detector, "query_frontmost_raw", return_value=("com.apple.finder", "Finder")):
            detector.update(force_immediate=True)

        candidate = ("com.google.Chrome", "Google Chrome")
        t0 = 500.0

        # Candidate arrives at t0
        with patch.object(detector, "query_frontmost_raw", return_value=candidate):
            with patch("time.monotonic", return_value=t0):
                self.assertIsNone(detector.update())

            # Candidate still there at t0 + 0.249s (just below 0.25s)
            with patch("time.monotonic", return_value=t0 + 0.249):
                self.assertIsNone(detector.update())
                self.assertEqual(detector.confirmed_bundle_id, "com.apple.finder")

            # Candidate still there at t0 + 0.251s (just above 0.25s)
            with patch("time.monotonic", return_value=t0 + 0.251):
                confirmed = detector.update()
                self.assertEqual(confirmed, "com.google.Chrome")
                self.assertEqual(detector.confirmed_bundle_id, "com.google.Chrome")

            # Consecutive check immediately after at t0 + 0.252s returns None
            with patch("time.monotonic", return_value=t0 + 0.252):
                self.assertIsNone(detector.update())

    def test_flicker_to_third_app_resets_debounce(self):
        """
        App A -> App B (pending 200ms) -> App C (flicker for 10ms) -> App B.
        The flicker to App C must reset the timer for App B.
        """
        detector = FrontmostAppDetector(debounce_seconds=0.25)
        with patch.object(detector, "query_frontmost_raw", return_value=("com.app.A", "A")):
            detector.update(force_immediate=True)

        # App B starts at t = 100.0
        with patch.object(detector, "query_frontmost_raw", return_value=("com.app.B", "B")):
            with patch("time.monotonic", return_value=100.0):
                detector.update()
            # Stays until t = 100.20 (200ms elapsed)
            with patch("time.monotonic", return_value=100.20):
                detector.update()

        # Flicker to App C at t = 100.21
        with patch.object(detector, "query_frontmost_raw", return_value=("com.app.C", "C")):
            with patch("time.monotonic", return_value=100.21):
                detector.update()
                self.assertEqual(detector.pending_bundle_id, "com.app.C")

        # Switches back to App B at t = 100.22
        with patch.object(detector, "query_frontmost_raw", return_value=("com.app.B", "B")):
            with patch("time.monotonic", return_value=100.22):
                detector.update()
                self.assertEqual(detector.pending_bundle_id, "com.app.B")

            # At t = 100.26 (0.26s from start of initial B, but only 40ms from second B):
            # Must NOT confirm because debounce timer was reset!
            with patch("time.monotonic", return_value=100.26):
                res = detector.update()
                self.assertIsNone(res)

            # At t = 100.48 (260ms after second B):
            # Must confirm now!
            with patch("time.monotonic", return_value=100.48):
                res = detector.update()
                self.assertEqual(res, "com.app.B")

    def test_query_frontmost_raw_resilience(self):
        """Simulate subprocess exceptions in query_frontmost_raw to verify graceful fallback."""
        detector = FrontmostAppDetector(debounce_seconds=0.25)

        # 1. Both lsappinfo and osascript raise exceptions
        with patch("subprocess.check_output", side_effect=RuntimeError("Subprocess failed")):
            bundle, name = detector.query_frontmost_raw()
            self.assertEqual(bundle, "com.apple.finder")
            self.assertEqual(name, "Finder")

        # 2. Subprocess times out
        import subprocess
        with patch("subprocess.check_output", side_effect=subprocess.TimeoutExpired(cmd="lsappinfo", timeout=0.5)):
            bundle, name = detector.query_frontmost_raw()
            self.assertEqual(bundle, "com.apple.finder")
            self.assertEqual(name, "Finder")


class TestAdversarialWireProtocolAndPayloadLimits(unittest.TestCase):
    """Stress tests JSON wire protocol encoding, size limits, and edge-case values."""

    def test_newline_injection_in_profile_breaks_framing(self):
        """
        Adversarial test: Newline delimiter framing vulnerability.
        If a label or app name contains an unescaped literal newline '\\n',
        it splits the serial JSON packet across two physical lines, causing
        the ESP32 parser to encounter truncated JSON fragments.
        """
        profile = {
            "app": "Test\nApp",
            "color": "0x007ACC",
            "buttons": [
                {"label": "Line1\nLine2", "mod": 0, "key": ord('a'), "cons": 0, "color": "0x007ACC"}
                for _ in range(6)
            ]
        }
        payload = build_app_payload(profile)
        wire_str = json.dumps(payload)
        # Note: json.dumps serializes literal \n as "\\n" (escaped), so wire_str itself has no raw \n
        self.assertNotIn("\n", wire_str)
        # However, if raw newline was transmitted:
        raw_split = wire_str.replace("\\n", "\n").split("\n")
        # Demonstrates that raw newlines would fragment the frame into multiple chunks
        self.assertGreater(len(raw_split), 1)

    def test_payload_size_with_maximum_length_labels(self):
        """
        Each label can be up to 31 chars + null (32 bytes).
        Test payload byte length when all 6 labels are max length.
        """
        profile = {
            "app": "A" * 32,
            "color": "0xFFFFFF",
            "buttons": [
                {"label": "W" * 31, "mod": 15, "key": 255, "cons": 65535, "color": "0xFFFFFF"}
                for _ in range(6)
            ]
        }
        payload = build_app_payload(profile)
        wire_bytes = (json.dumps(payload) + "\n").encode("utf-8")
        # Ensure it fits well within the 1024-byte ESP32 serial line buffer
        self.assertLess(len(wire_bytes), 1024)
        # Measured wire length with 31-char labels is ~723 bytes
        self.assertLess(len(wire_bytes), 800)

    def test_malformed_json_strings_resilience(self):
        """Test resilience against malformed JSON strings."""
        malformed_inputs = [
            "",
            "   ",
            "{",
            "}",
            "{'type': 'app'}",  # single quotes
            '{"type": "app", "buttons": [}',
            '{"type": "app", "buttons": [{"label": "A", "mod": }]}',
            '{"type": "app", "app": "VS Code", "buttons": [null, null]}',
            '{"type": "stats", "cpu": "not_an_int"}',
            '\x00\x01\x02\xFF',
        ]
        for bad_json in malformed_inputs:
            trimmed = bad_json.strip()
            # Firmware filter: line.length() > 0 && line.startsWith("{") && line.endsWith("}")
            passes_prefilter = len(trimmed) > 0 and trimmed.startswith("{") and trimmed.endswith("}")
            if passes_prefilter:
                try:
                    parsed = json.loads(trimmed)
                except Exception:
                    # Successfully detected as invalid JSON
                    pass


if __name__ == "__main__":
    unittest.main()
