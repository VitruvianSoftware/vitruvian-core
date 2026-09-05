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
mac-controller/tests/test_profiles.py
Automated unit test suite for Smart Deck application profiles, modifier bitmask,
frontmost app detection debounce, and USB serial JSON wire protocol conformance.
"""

import sys
import os
import json
import time
import unittest
from unittest.mock import patch

# Ensure host_companion is discoverable
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../host_companion")))

import app_profiles
from app_profiles import (
    MOD_NONE, MOD_CTRL, MOD_SHIFT, MOD_ALT, MOD_CMD,
    KEY_UP_ARROW, KEY_DOWN_ARROW, KEY_LEFT_ARROW, KEY_RIGHT_ARROW, KEY_F11,
    CONSUMER_CONTROL_MUTE,
    PROFILES, get_profile_for_app, get_profile_for_bundle,
    build_app_payload, build_app_wire_payload,
    FrontmostAppDetector,
)

class TestModifierBitmask(unittest.TestCase):
    """Verifies that the modifier bitmask adheres strictly to the canonical contract."""

    def test_bitmask_powers_of_two(self):
        self.assertEqual(MOD_NONE, 0)
        self.assertEqual(MOD_CTRL, 1)   # 1 << 0
        self.assertEqual(MOD_SHIFT, 2)  # 1 << 1
        self.assertEqual(MOD_ALT, 4)    # 1 << 2
        self.assertEqual(MOD_CMD, 8)    # 1 << 3

    def test_bitmask_orthogonal(self):
        """Ensure all modifiers occupy distinct bits."""
        mods = [MOD_CTRL, MOD_SHIFT, MOD_ALT, MOD_CMD]
        for i in range(len(mods)):
            for j in range(i + 1, len(mods)):
                self.assertEqual(mods[i] & mods[j], 0, f"Collision between {mods[i]} and {mods[j]}")

    def test_compound_modifiers(self):
        self.assertEqual(MOD_CMD | MOD_SHIFT, 10)
        self.assertEqual(MOD_CTRL | MOD_SHIFT, 3)
        self.assertEqual(MOD_SHIFT | MOD_ALT, 6)
        self.assertEqual(MOD_CMD | MOD_ALT, 12)
        self.assertEqual(MOD_CMD | MOD_CTRL, 9)
        self.assertEqual(MOD_CTRL | MOD_ALT | MOD_CMD, 13)
        self.assertEqual(MOD_CMD | MOD_ALT | MOD_SHIFT, 14)


class TestProfileResolution(unittest.TestCase):
    """Verifies matching of macOS bundle IDs and process names to profiles."""

    def test_vscode_resolution(self):
        self.assertEqual(get_profile_for_app("com.microsoft.VSCode")["app"], "VS Code")
        self.assertEqual(get_profile_for_app("com.vscodium")["app"], "VS Code")
        self.assertEqual(get_profile_for_app("", "Visual Studio Code")["app"], "VS Code")
        self.assertEqual(get_profile_for_bundle("com.microsoft.VSCodeInsiders")["app"], "VS Code")

    def test_chrome_resolution(self):
        self.assertEqual(get_profile_for_app("com.google.Chrome")["app"], "Chrome")
        self.assertEqual(get_profile_for_app("com.brave.Browser")["app"], "Chrome")
        self.assertEqual(get_profile_for_app("com.apple.Safari")["app"], "Chrome")
        self.assertEqual(get_profile_for_app("", "Google Chrome")["app"], "Chrome")

    def test_terminal_resolution(self):
        self.assertEqual(get_profile_for_app("com.apple.Terminal")["app"], "Terminal")
        self.assertEqual(get_profile_for_app("com.googlecode.iterm2")["app"], "Terminal")
        self.assertEqual(get_profile_for_app("dev.warp.Warp-Stable")["app"], "Terminal")
        self.assertEqual(get_profile_for_app("", "iTerm2")["app"], "Terminal")
        self.assertEqual(get_profile_for_app("com.mitchellh.ghostty")["app"], "Terminal")

    def test_slack_resolution(self):
        self.assertEqual(get_profile_for_app("com.tinyspeck.slackmacgap")["app"], "Slack")
        self.assertEqual(get_profile_for_app("", "Slack")["app"], "Slack")

    def test_default_fallback(self):
        self.assertEqual(get_profile_for_app("com.apple.finder")["app"], "Default")
        self.assertEqual(get_profile_for_app("com.unknown.arbitrary.app")["app"], "Default")
        self.assertEqual(get_profile_for_app("", "")["app"], "Default")


class TestProfileSchemaConformance(unittest.TestCase):
    """Verifies that all profiles strictly conform to the 6-button physical display layout."""

    def test_all_profiles_have_six_buttons(self):
        for name, profile in PROFILES.items():
            buttons = profile.get("buttons", [])
            self.assertEqual(len(buttons), 6, f"Profile '{name}' must have exactly 6 buttons (found {len(buttons)})")

    def test_button_attributes_and_ranges(self):
        for name, profile in PROFILES.items():
            self.assertIn("app", profile)
            self.assertIn("color", profile)
            self.assertTrue(profile["color"].startswith("0x") or profile["color"].startswith("#"))

            for idx, btn in enumerate(profile["buttons"]):
                self.assertIn("label", btn, f"Missing label in {name}[{idx}]")
                self.assertTrue(len(btn["label"]) > 0, f"Empty label in {name}[{idx}]")
                self.assertLessEqual(len(btn["label"]), 32, f"Label too long in {name}[{idx}]")

                self.assertIn("mod", btn)
                self.assertIsInstance(btn["mod"], int)
                self.assertTrue(0 <= btn["mod"] <= 15, f"mod out of range (0-15) in {name}[{idx}]: {btn['mod']}")

                self.assertIn("key", btn)
                self.assertIsInstance(btn["key"], int)
                self.assertTrue(0 <= btn["key"] <= 255, f"key out of range (0-255) in {name}[{idx}]: {btn['key']}")

                self.assertIn("cons", btn)
                self.assertIsInstance(btn["cons"], int)
                self.assertTrue(0 <= btn["cons"] <= 65535, f"cons out of range in {name}[{idx}]: {btn['cons']}")

                self.assertIn("color", btn)
                self.assertTrue(btn["color"].startswith("0x") or btn["color"].startswith("#"))

                # If cons is set, key should be 0
                if btn["cons"] != 0:
                    self.assertEqual(btn["key"], 0, f"Button {name}[{idx}] has both non-zero key and consumer code")


class TestWireProtocolPayload(unittest.TestCase):
    """Verifies JSON serialization, size constraints, and wire framing."""

    def test_payload_structure(self):
        for name, profile in PROFILES.items():
            payload = build_app_payload(profile)
            self.assertEqual(payload["type"], "app")
            self.assertEqual(payload["app"], profile["app"])
            self.assertEqual(payload["color"], profile["color"])
            self.assertEqual(len(payload["buttons"]), 6)

            # Test alias
            payload_alias = build_app_wire_payload(profile)
            self.assertEqual(payload, payload_alias)

    def test_json_roundtrip_and_size(self):
        for name, profile in PROFILES.items():
            payload = build_app_payload(profile)
            serialized = json.dumps(payload)
            deserialized = json.loads(serialized)
            self.assertEqual(payload, deserialized)

            # Wire framing requirement: single line (no embedded newlines in JSON outside escape)
            self.assertNotIn("\r", serialized)
            # ESP32 buffer limit: payload must be comfortably under 1024 bytes
            self.assertLess(len(serialized.encode("utf-8")), 1024)


class TestKeycodeSemantics(unittest.TestCase):
    """Verifies semantic correctness of specific shortcuts against macOS standards."""

    def test_vscode_semantics(self):
        p = PROFILES["vscode"]["buttons"]
        # Pal: Cmd + Shift + P
        self.assertEqual(p[0]["label"], "Pal")
        self.assertEqual(p[0]["mod"], MOD_CMD | MOD_SHIFT)
        self.assertEqual(p[0]["key"], ord('p'))

        # Quick Open: Cmd + P
        self.assertEqual(p[1]["label"], "File")
        self.assertEqual(p[1]["mod"], MOD_CMD)
        self.assertEqual(p[1]["key"], ord('p'))

        # Toggle Terminal: Ctrl + `
        self.assertEqual(p[2]["label"], "Term")
        self.assertEqual(p[2]["mod"], MOD_CTRL)
        self.assertEqual(p[2]["key"], ord('`'))

    def test_terminal_semantics(self):
        p = PROFILES["terminal"]["buttons"]
        # Clear: Cmd + K
        self.assertEqual(p[0]["label"], "Clear")
        self.assertEqual(p[0]["mod"], MOD_CMD)
        self.assertEqual(p[0]["key"], ord('k'))

        # Cancel: Ctrl + C
        self.assertEqual(p[4]["label"], "Cancel")
        self.assertEqual(p[4]["mod"], MOD_CTRL)
        self.assertEqual(p[4]["key"], ord('c'))

    def test_default_consumer_mute(self):
        p = PROFILES["default"]["buttons"]
        # Button 4 is Mute: cons = CONSUMER_CONTROL_MUTE (0x00E2)
        self.assertEqual(p[4]["label"], "Mute")
        self.assertEqual(p[4]["key"], 0)
        self.assertEqual(p[4]["cons"], CONSUMER_CONTROL_MUTE)


class TestFrontmostAppDetector(unittest.TestCase):
    """Verifies debounce logic and state machine transitions in FrontmostAppDetector."""

    def test_initial_connection_immediate(self):
        detector = FrontmostAppDetector(debounce_seconds=0.25)
        with patch.object(detector, "query_frontmost_raw", return_value=("com.microsoft.VSCode", "Code")):
            bundle = detector.update(force_immediate=True)
            self.assertEqual(bundle, "com.microsoft.VSCode")
            self.assertEqual(detector.confirmed_bundle_id, "com.microsoft.VSCode")
            self.assertEqual(detector.confirmed_app_name, "Code")

    def test_debounce_filtering(self):
        detector = FrontmostAppDetector(debounce_seconds=0.25)
        with patch.object(detector, "query_frontmost_raw", return_value=("com.apple.finder", "Finder")):
            # Initial establishment
            detector.update(force_immediate=True)

        # Candidate changes to Chrome at t = 100.0
        with patch.object(detector, "query_frontmost_raw", return_value=("com.google.Chrome", "Google Chrome")):
            with patch("time.monotonic", return_value=100.0):
                res1 = detector.update()
                self.assertIsNone(res1)  # Debouncing, should return None
                self.assertEqual(detector.pending_bundle_id, "com.google.Chrome")

            # Candidate still Chrome at t = 100.1 (< 0.25s)
            with patch("time.monotonic", return_value=100.1):
                res2 = detector.update()
                self.assertIsNone(res2)

            # Candidate still Chrome at t = 100.26 (>= 0.25s)
            with patch("time.monotonic", return_value=100.26):
                res3 = detector.update()
                self.assertEqual(res3, "com.google.Chrome")
                self.assertEqual(detector.confirmed_bundle_id, "com.google.Chrome")
                self.assertEqual(detector.confirmed_app_name, "Google Chrome")

    def test_transient_flicker_ignored(self):
        detector = FrontmostAppDetector(debounce_seconds=0.25)
        with patch.object(detector, "query_frontmost_raw", return_value=("com.apple.finder", "Finder")):
            detector.update(force_immediate=True)

        # Brief flicker to Slack at t = 100.0
        with patch.object(detector, "query_frontmost_raw", return_value=("com.tinyspeck.slackmacgap", "Slack")):
            with patch("time.monotonic", return_value=100.0):
                detector.update()

        # Reverts back to Finder at t = 100.1
        with patch.object(detector, "query_frontmost_raw", return_value=("com.apple.finder", "Finder")):
            with patch("time.monotonic", return_value=100.1):
                res = detector.update()
                self.assertIsNone(res)
                self.assertIsNone(detector.pending_bundle_id)
                self.assertEqual(detector.confirmed_bundle_id, "com.apple.finder")


if __name__ == "__main__":
    unittest.main()
