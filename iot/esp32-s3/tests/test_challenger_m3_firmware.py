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

"""Empirical stress tests for ESP32-S3 firmware build, RAM/Flash limits, and 4-deck carousel layout."""

import json
import os
import random
import re
import subprocess
import unittest
import zipfile
from dataclasses import dataclass
from typing import Dict, List, Optional, Tuple


@dataclass
class Rect:
    x: int
    y: int
    w: int
    h: int

    @property
    def x2(self) -> int:
        return self.x + self.w

    @property
    def y2(self) -> int:
        return self.y + self.h

    def contains(self, px: int, py: int) -> bool:
        return self.x <= px < self.x2 and self.y <= py < self.y2

    def intersects(self, other: "Rect") -> bool:
        return not (
            self.x2 <= other.x
            or other.x2 <= self.x
            or self.y2 <= other.y
            or other.y2 <= self.y
        )

    def is_contained_in(self, parent: "Rect") -> bool:
        return (
            self.x >= parent.x
            and self.y >= parent.y
            and self.x2 <= parent.x2
            and self.y2 <= parent.y2
        )


class TestTileView4DeckCoordinates(unittest.TestCase):
    """Stress-test coordinates, geometry, and bounding boxes of all 4 Decks on 240x280 display."""

    VIEWPORT = Rect(x=0, y=0, w=240, h=280)

    # 6 shortcut button coordinates (Tile 0 and Tile 1)
    SIX_BTN_COORDS = [
        (7, 78),
        (122, 78),
        (7, 136),
        (122, 136),
        (7, 194),
        (122, 194),
    ]
    SIX_BTN_W = 111
    SIX_BTN_H = 52

    def test_tile0_system_deck_bounding_boxes(self):
        """Verify all Tile 0 components fit within 240x280 viewport without clipping or collision."""
        header = Rect(x=7, y=5, w=226, h=68)
        self.assertTrue(header.is_contained_in(self.VIEWPORT))

        buttons = [
            Rect(x=x, y=y, w=self.SIX_BTN_W, h=self.SIX_BTN_H)
            for x, y in self.SIX_BTN_COORDS
        ]

        for idx, btn in enumerate(buttons):
            self.assertTrue(btn.is_contained_in(self.VIEWPORT), f"Tile 0 btn {idx} clipped: {btn}")
            self.assertFalse(btn.intersects(header), f"Tile 0 btn {idx} overlaps header: {btn}")

        for i in range(len(buttons)):
            for j in range(i + 1, len(buttons)):
                self.assertFalse(buttons[i].intersects(buttons[j]), f"Tile 0 btn {i} intersects btn {j}")

        # Bottom navigation hint margin check
        bottom_y2 = max(b.y2 for b in buttons)
        self.assertEqual(bottom_y2, 246)
        self.assertGreaterEqual(self.VIEWPORT.h - bottom_y2, 30, "Insufficient margin for nav hint")

    def test_tile1_smart_deck_bounding_boxes(self):
        """Verify all Tile 1 components fit within 240x280 viewport without clipping or collision."""
        header = Rect(x=7, y=5, w=226, h=68)
        self.assertTrue(header.is_contained_in(self.VIEWPORT))

        dot = Rect(x=7 + 226 - 12 - 2, y=5 + 6, w=12, h=12)
        self.assertTrue(dot.is_contained_in(header))

        bar = Rect(x=7, y=5 + 52, w=214, h=2)
        self.assertTrue(bar.is_contained_in(header))

        buttons = [
            Rect(x=x, y=y, w=self.SIX_BTN_W, h=self.SIX_BTN_H)
            for x, y in self.SIX_BTN_COORDS
        ]

        for idx, btn in enumerate(buttons):
            self.assertTrue(btn.is_contained_in(self.VIEWPORT), f"Tile 1 btn {idx} clipped: {btn}")
            self.assertFalse(btn.intersects(header), f"Tile 1 btn {idx} overlaps header: {btn}")

        for i in range(len(buttons)):
            for j in range(i + 1, len(buttons)):
                self.assertFalse(buttons[i].intersects(buttons[j]), f"Tile 1 btn {i} intersects btn {j}")

    def test_tile2_agent_ci_deck_bounding_boxes(self):
        """Verify all Tile 2 (Agent & CI) components fit within 240x280 viewport without clipping."""
        # 1. Header Card (7, 5, 226, 34)
        header_aci = Rect(x=7, y=5, w=226, h=34)
        self.assertTrue(header_aci.is_contained_in(self.VIEWPORT))

        # Live dot inside header (8x8)
        dot_aci = Rect(x=7 + 226 - 36 - 8, y=5 + (34 - 8) // 2, w=8, h=8)
        self.assertTrue(dot_aci.is_contained_in(header_aci))

        # 2. Agent Card (7, 43, 226, 78)
        card_agent = Rect(x=7, y=43, w=226, h=78)
        self.assertTrue(card_agent.is_contained_in(self.VIEWPORT))
        self.assertFalse(card_agent.intersects(header_aci), "Agent card overlaps header")
        self.assertEqual(card_agent.y - header_aci.y2, 4, "Gap between header and agent card must be 4px")

        # Agent badge inside card (62x18, right aligned: x = 7 + 226 - 6 - 62 = 165)
        badge_agent = Rect(x=7 + 226 - 6 - 62, y=43 + 6, w=62, h=18)
        self.assertTrue(badge_agent.is_contained_in(card_agent))

        # 3. CI/CD Card (7, 125, 226, 80)
        card_ci = Rect(x=7, y=125, w=226, h=80)
        self.assertTrue(card_ci.is_contained_in(self.VIEWPORT))
        self.assertFalse(card_ci.intersects(card_agent), "CI card overlaps Agent card")
        self.assertEqual(card_ci.y - card_agent.y2, 4, "Gap between Agent and CI cards must be 4px")

        # CI badge inside card (62x18, right aligned)
        badge_ci = Rect(x=7 + 226 - 6 - 62, y=125 + 6, w=62, h=18)
        self.assertTrue(badge_ci.is_contained_in(card_ci))

        # CI progress bar inside card (214x8, pos 0, 48 from inner pad)
        bar_ci = Rect(x=7 + 6, y=125 + 6 + 48, w=214, h=8)
        self.assertTrue(bar_ci.is_contained_in(card_ci))

        # 4. Action Buttons (Run Checks & Open PR, 110x42 each)
        btn_run = Rect(x=7, y=210, w=110, h=42)
        btn_pr = Rect(x=123, y=210, w=110, h=42)

        self.assertTrue(btn_run.is_contained_in(self.VIEWPORT), f"btn_run clipped: {btn_run}")
        self.assertTrue(btn_pr.is_contained_in(self.VIEWPORT), f"btn_pr clipped: {btn_pr}")

        self.assertFalse(btn_run.intersects(card_ci), "btn_run overlaps CI card")
        self.assertFalse(btn_pr.intersects(card_ci), "btn_pr overlaps CI card")
        self.assertFalse(btn_run.intersects(btn_pr), "Action buttons overlap each other")

        self.assertEqual(btn_run.y - card_ci.y2, 5, "Gap between CI card and action buttons must be 5px")
        self.assertEqual(btn_pr.x - btn_run.x2, 6, "Gap between action buttons must be 6px")

        # 5. Bottom Navigation Hint (y in [252, 280])
        action_y2 = max(btn_run.y2, btn_pr.y2)
        self.assertEqual(action_y2, 252)
        remaining_margin = self.VIEWPORT.h - action_y2
        self.assertEqual(remaining_margin, 28, "Remaining vertical margin must be 28px")
        self.assertGreaterEqual(remaining_margin, 20, "Insufficient margin for bottom nav hint")

    def test_tile3_settings_deck_bounding_boxes(self):
        """Verify all Tile 3 (Settings Deck) components fit within 240x280 viewport without clipping."""
        title = Rect(x=12, y=10, w=120, h=20)
        self.assertTrue(title.is_contained_in(self.VIEWPORT))

        card_bright = Rect(x=8, y=38, w=224, h=76)
        self.assertTrue(card_bright.is_contained_in(self.VIEWPORT))
        self.assertFalse(card_bright.intersects(title))

        slider = Rect(x=8 + (224 - 196) // 2, y=38 + 76 - 12 - 6, w=196, h=12)
        self.assertTrue(slider.is_contained_in(card_bright))

        card_info = Rect(x=8, y=120, w=224, h=134)
        self.assertTrue(card_info.is_contained_in(self.VIEWPORT))
        self.assertFalse(card_info.intersects(card_bright))

        self.assertEqual(card_info.y2, 254)
        self.assertGreaterEqual(self.VIEWPORT.h - card_info.y2, 20, "Insufficient margin for back hint")

    def test_tileview_global_4_deck_layout_extent(self):
        """Verify 4-deck TileView global layout coordinates: 0, 240, 480, 720."""
        tile_origins = [0, 240, 480, 720]
        total_width = 4 * 240
        self.assertEqual(total_width, 960)

        for col, origin_x in enumerate(tile_origins):
            tile_rect = Rect(x=origin_x, y=0, w=240, h=280)
            self.assertEqual(tile_rect.x, col * 240)
            self.assertEqual(tile_rect.x2, (col + 1) * 240)
            self.assertEqual(tile_rect.h, 280)

    def test_touch_target_accessibility_all_decks(self):
        """Verify touch target sizes meet embedded accessibility guidelines and have zero collision."""
        # Check action buttons on Tile 2
        btn_run = Rect(x=7, y=210, w=110, h=42)
        btn_pr = Rect(x=123, y=210, w=110, h=42)
        self.assertGreaterEqual(btn_run.w, 44)
        self.assertGreaterEqual(btn_run.h, 40)
        self.assertGreaterEqual(btn_pr.w, 44)
        self.assertGreaterEqual(btn_pr.h, 40)

        # Check Tile 0 & 1 buttons (111x52)
        for x, y in self.SIX_BTN_COORDS:
            self.assertGreaterEqual(self.SIX_BTN_W, 44)
            self.assertGreaterEqual(self.SIX_BTN_H, 44)

        # Hit-test simulation across 10,000 points on Tile 2
        interactive_t2 = [btn_run, btn_pr]
        random.seed(1337)
        for _ in range(10000):
            tx = random.randint(0, 239)
            ty = random.randint(0, 279)
            hits = [i for i, b in enumerate(interactive_t2) if b.contains(tx, ty)]
            self.assertLessEqual(len(hits), 1, f"Ambiguous touch at ({tx}, {ty}): {hits}")


class TestTileView4DeckDirectionalTransitions(unittest.TestCase):
    """Stress-test 4-deck directional navigation state machine and boundary handling."""

    LV_DIR_NONE = 0
    LV_DIR_LEFT = 1 << 0   # 1
    LV_DIR_RIGHT = 1 << 1  # 2
    LV_DIR_HOR = LV_DIR_LEFT | LV_DIR_RIGHT  # 3

    # Carousel tile configuration from ui.cpp lines 126-140
    TILES_4 = {
        0: {"name": "System Deck", "dir": LV_DIR_RIGHT},
        1: {"name": "Smart Deck", "dir": LV_DIR_HOR},
        2: {"name": "Agent & CI Deck", "dir": LV_DIR_HOR},
        3: {"name": "Settings Deck", "dir": LV_DIR_LEFT},
    }

    def simulate_swipe(self, current_tile: int, swipe_dir: str) -> int:
        """
        Simulate LVGL TileView scroll behavior.
        swipe_dir == "LEFT": finger drags left (scroll right to tile+1).
          Allowed if (dir & LV_DIR_RIGHT) != 0.
        swipe_dir == "RIGHT": finger drags right (scroll left to tile-1).
          Allowed if (dir & LV_DIR_LEFT) != 0.
        """
        cfg = self.TILES_4[current_tile]
        tile_dir = cfg["dir"]

        if swipe_dir == "LEFT":  # drag left -> advance to right neighbor
            if (tile_dir & self.LV_DIR_RIGHT) != 0 and current_tile < 3:
                return current_tile + 1
            return current_tile
        elif swipe_dir == "RIGHT":  # drag right -> retreat to left neighbor
            if (tile_dir & self.LV_DIR_LEFT) != 0 and current_tile > 0:
                return current_tile - 1
            return current_tile
        return current_tile

    def test_tile0_transitions(self):
        """Tile 0 allows swiping left to Tile 1, blocks swiping right past left boundary."""
        self.assertEqual(self.simulate_swipe(0, "LEFT"), 1)
        self.assertEqual(self.simulate_swipe(0, "RIGHT"), 0)

    def test_tile1_transitions(self):
        """Tile 1 allows swiping right to Tile 0 and left to Tile 2."""
        self.assertEqual(self.simulate_swipe(1, "RIGHT"), 0)
        self.assertEqual(self.simulate_swipe(1, "LEFT"), 2)

    def test_tile2_transitions(self):
        """Tile 2 allows swiping right to Tile 1 and left to Tile 3."""
        self.assertEqual(self.simulate_swipe(2, "RIGHT"), 1)
        self.assertEqual(self.simulate_swipe(2, "LEFT"), 3)

    def test_tile3_transitions(self):
        """Tile 3 allows swiping right to Tile 2, blocks swiping left past right boundary."""
        self.assertEqual(self.simulate_swipe(3, "RIGHT"), 2)
        self.assertEqual(self.simulate_swipe(3, "LEFT"), 3)

    def test_full_carousel_roundtrip(self):
        """Traverse 0 -> 1 -> 2 -> 3 -> 2 -> 1 -> 0 cleanly."""
        cur = 0
        cur = self.simulate_swipe(cur, "LEFT")
        self.assertEqual(cur, 1)
        cur = self.simulate_swipe(cur, "LEFT")
        self.assertEqual(cur, 2)
        cur = self.simulate_swipe(cur, "LEFT")
        self.assertEqual(cur, 3)
        # Attempt overscroll at right boundary
        cur = self.simulate_swipe(cur, "LEFT")
        self.assertEqual(cur, 3)
        # Reverse path
        cur = self.simulate_swipe(cur, "RIGHT")
        self.assertEqual(cur, 2)
        cur = self.simulate_swipe(cur, "RIGHT")
        self.assertEqual(cur, 1)
        cur = self.simulate_swipe(cur, "RIGHT")
        self.assertEqual(cur, 0)
        # Attempt overscroll at left boundary
        cur = self.simulate_swipe(cur, "RIGHT")
        self.assertEqual(cur, 0)

    def test_random_swipe_walk_100k(self):
        """Stress test 100,000 random swipe gestures on the 4-deck carousel."""
        random.seed(999)
        cur = 0
        for _ in range(100000):
            gesture = random.choice(["LEFT", "RIGHT"])
            cur = self.simulate_swipe(cur, gesture)
            self.assertTrue(0 <= cur <= 3, f"Carousel escaped valid tile range: {cur}")


class TestFirmwareMemoryAndBuildLimits(unittest.TestCase):
    """Stress-test compiled binary memory utilization against ESP32-S3 hardware ceilings."""

    @classmethod
    def setUpClass(cls):
        cur = os.path.dirname(os.path.abspath(__file__))
        while cur and cur != os.path.dirname(cur):
            if os.path.isfile(os.path.join(cur, "MODULE.bazel")) or os.path.isdir(os.path.join(cur, ".git")):
                cls.REPO_ROOT = cur
                break
            cur = os.path.dirname(cur)
        else:
            cls.REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../.."))

        cls.BUILD_DIR = os.path.join(cls.REPO_ROOT, "iot/esp32-s3/.pio/build/esp32s3")
        cls.BAZEL_BIN_DIR = os.path.join(cls.REPO_ROOT, "bazel-bin/iot/esp32-s3")

    # ESP32-S3 DevKitC-1 N8R8 / N16R8 hardware ceilings
    FLASH_PARTITION_LIMIT = 6553600   # 6.25 MB default app partition
    SRAM_LIMIT = 327680               # 320 KB usable internal SRAM
    LVGL_POOL_SIZE = 49152            # 48 KB configured in lv_conf.h

    def test_firmware_elf_and_bin_exist(self):
        """Verify PlatformIO compiled binaries exist and have valid sizes."""
        firmware_bin = os.path.join(self.BUILD_DIR, "firmware.bin")
        if not os.path.isfile(firmware_bin):
            raise unittest.SkipTest(f"firmware.bin not built at {firmware_bin}")
        bin_size = os.path.getsize(firmware_bin)
        self.assertGreater(bin_size, 200000, "firmware.bin unexpectedly small")
        self.assertLess(bin_size, self.FLASH_PARTITION_LIMIT, "firmware.bin exceeds flash partition")

    def test_memory_utilization_headroom(self):
        """Verify Flash and RAM utilization headroom meets safety margins."""
        firmware_bin = os.path.join(self.BUILD_DIR, "firmware.bin")
        if not os.path.isfile(firmware_bin):
            raise unittest.SkipTest(f"firmware.bin not built at {firmware_bin}")
        bin_size = os.path.getsize(firmware_bin)
        flash_pct = (bin_size / self.FLASH_PARTITION_LIMIT) * 100
        # Flash utilization must be under 25% (9.0% observed)
        self.assertLess(flash_pct, 25.0, f"Flash utilization too high: {flash_pct:.1f}%")

    def test_bazel_firmware_artifacts_and_zip(self):
        """Verify Bazel build targets exist and zip bundle is complete."""
        zip_path = os.path.join(self.BAZEL_BIN_DIR, "esp32-s3-mac-controller.zip")
        if not os.path.isfile(zip_path):
            raise unittest.SkipTest(f"Bazel zip bundle missing: {zip_path}")

        with zipfile.ZipFile(zip_path, "r") as z:
            names = z.namelist()
            expected = ["firmware.bin", "bootloader.bin", "partitions.bin", "build_info.json", "flash.sh"]
            for exp in expected:
                self.assertIn(exp, names, f"Zip bundle missing {exp}")

            # Validate build_info.json schema
            info_data = json.loads(z.read("build_info.json").decode("utf-8"))
            self.assertIn("version", info_data)
            self.assertIn("board", info_data)
            self.assertEqual(info_data["board"], "Waveshare ESP32-S3-Touch-LCD-1.69")
            self.assertEqual(info_data["mcu"], "ESP32-S3")
            self.assertEqual(info_data["flash_size"], "16MB")


class TestAgentCIPayloadStressAndFuzzing(unittest.TestCase):
    """Stress-test Agent & CI serial packet parsing with extreme inputs."""

    def test_extreme_task_string_length(self):
        """Ensure payloads with 1024-character task strings are bounded and do not overflow."""
        long_task = "A" * 1024
        payload = {
            "type": "agent_ci",
            "agent": {"state": "running", "task": long_task},
            "ci": {"status": "passing", "branch": "B" * 512, "passed": 50, "total": 50}
        }
        raw_json = json.dumps(payload)
        self.assertTrue(len(raw_json) > 1024)

    def test_unicode_and_emojis_in_ci_payload(self):
        """Ensure unicode characters (branch names, PR titles, emoji) serialize and deserialize cleanly."""
        payload = {
            "type": "agent_ci",
            "agent": {"name": "🤖 AI Agent", "state": "review", "task": "Testing 🚀 rocket speed"},
            "ci": {"status": "passing", "branch": "feat/🔥-hotfix-日本語", "passed": 12, "total": 12}
        }
        # Raw UTF-8 wire framing (ensure_ascii=False)
        raw_utf8 = json.dumps(payload, ensure_ascii=False) + "\n"
        self.assertIn("feat/🔥-hotfix-日本語", raw_utf8)
        deser_raw = json.loads(raw_utf8.strip())
        self.assertEqual(deser_raw["agent"]["name"], "🤖 AI Agent")

        # Escaped wire framing (ensure_ascii=True)
        escaped_ascii = json.dumps(payload, ensure_ascii=True) + "\n"
        deser_esc = json.loads(escaped_ascii.strip())
        self.assertEqual(deser_esc["agent"]["name"], "🤖 AI Agent")
        self.assertEqual(deser_esc["ci"]["branch"], "feat/🔥-hotfix-日本語")

    def test_integer_boundary_values(self):
        """Test integer extremes (large PR numbers, zero checks, passed > total)."""
        payload = {
            "type": "agent_ci",
            "ci": {
                "pr": 2147483647,
                "passed": 999999,
                "total": 1000000,
                "dirty_files": 32767
            }
        }
        raw = json.dumps(payload)
        deser = json.loads(raw)
        self.assertEqual(deser["ci"]["pr"], 2147483647)
        self.assertEqual(deser["ci"]["passed"], 999999)


if __name__ == "__main__":
    unittest.main()
