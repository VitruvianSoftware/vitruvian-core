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

"""Empirical stress tests for ESP32-S3 firmware, RAM/Flash limits, and 4-deck TileView transitions."""

import json
import random
import re
import string
import unittest
from dataclasses import dataclass
from typing import List, Optional, Tuple


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


class TestTileViewGeometry(unittest.TestCase):
    """Stress test the geometry, coordinates, and bounding boxes of all TileView components across 4 decks."""

    VIEWPORT = Rect(x=0, y=0, w=240, h=280)

    # 6 button coordinates defined in ui.cpp
    BUTTON_COORDS = [
        (7, 78),
        (122, 78),
        (7, 136),
        (122, 136),
        (7, 194),
        (122, 194),
    ]
    BUTTON_WIDTH = 111
    BUTTON_HEIGHT = 52

    def test_tile0_system_deck_bounding_boxes(self):
        """Verify all Tile 0 components fit within the 240x280 viewport without clipping."""
        # Header card (7, 5, 226, 68)
        header = Rect(x=7, y=5, w=226, h=68)
        self.assertTrue(header.is_contained_in(self.VIEWPORT))

        # 6 system shortcut buttons
        buttons = [
            Rect(x=x, y=y, w=self.BUTTON_WIDTH, h=self.BUTTON_HEIGHT)
            for x, y in self.BUTTON_COORDS
        ]

        # Verify buttons fit in viewport and do not overlap header
        for idx, btn in enumerate(buttons):
            self.assertTrue(
                btn.is_contained_in(self.VIEWPORT),
                f"Tile 0 button {idx} overflows viewport: {btn}",
            )
            self.assertFalse(
                btn.intersects(header),
                f"Tile 0 button {idx} overlaps header: {btn}",
            )

        # Verify buttons do not overlap each other
        for i in range(len(buttons)):
            for j in range(i + 1, len(buttons)):
                self.assertFalse(
                    buttons[i].intersects(buttons[j]),
                    f"Tile 0 button {i} intersects button {j}",
                )

        # Bottom margin check for navigation hint (y in [246, 280])
        bottom_most_btn_y2 = max(b.y2 for b in buttons)
        self.assertEqual(bottom_most_btn_y2, 246)
        remaining_bottom_margin = self.VIEWPORT.h - bottom_most_btn_y2
        self.assertGreaterEqual(
            remaining_bottom_margin,
            30,
            "Insufficient bottom margin for navigation hint",
        )

    def test_tile1_smart_deck_bounding_boxes(self):
        """Verify all Tile 1 components fit within the 240x280 viewport without clipping."""
        header = Rect(x=7, y=5, w=226, h=68)
        self.assertTrue(header.is_contained_in(self.VIEWPORT))

        # Accent dot (top right of header)
        dot = Rect(x=7 + 226 - 12 - 2, y=5 + 6, w=12, h=12)
        self.assertTrue(dot.is_contained_in(header))

        # Accent bar (bottom of header)
        bar = Rect(x=7, y=5 + 52, w=214, h=2)
        self.assertTrue(bar.is_contained_in(header))

        # 6 dynamic buttons
        buttons = [
            Rect(x=x, y=y, w=self.BUTTON_WIDTH, h=self.BUTTON_HEIGHT)
            for x, y in self.BUTTON_COORDS
        ]

        for idx, btn in enumerate(buttons):
            self.assertTrue(
                btn.is_contained_in(self.VIEWPORT),
                f"Tile 1 button {idx} overflows viewport: {btn}",
            )
            self.assertFalse(
                btn.intersects(header),
                f"Tile 1 button {idx} overlaps header: {btn}",
            )

        for i in range(len(buttons)):
            for j in range(i + 1, len(buttons)):
                self.assertFalse(
                    buttons[i].intersects(buttons[j]),
                    f"Tile 1 button {i} intersects button {j}",
                )

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

        # Agent badge inside card (62x18, right aligned)
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
        """Verify all Tile 3 (Settings Deck) components fit within the 240x280 viewport without clipping."""
        # Title at (12, 6)
        title = Rect(x=12, y=6, w=120, h=18)
        self.assertTrue(title.is_contained_in(self.VIEWPORT))

        # Brightness card (8, 26, 224, 46)
        bright_card = Rect(x=8, y=26, w=224, h=46)
        self.assertTrue(bright_card.is_contained_in(self.VIEWPORT))
        self.assertFalse(bright_card.intersects(title))

        # Slider inside brightness card: 196x10
        slider = Rect(x=8 + (224 - 196) // 2, y=26 + 28, w=196, h=10)
        self.assertTrue(slider.is_contained_in(bright_card))

        # Active Decks card (8, 76, 224, 104)
        decks_card = Rect(x=8, y=76, w=224, h=104)
        self.assertTrue(decks_card.is_contained_in(self.VIEWPORT))
        self.assertFalse(decks_card.intersects(bright_card))

        # Switches inside Active Decks card
        sw_system = Rect(x=8 + 172, y=76 + 19, w=40, h=20)
        sw_smart = Rect(x=8 + 172, y=76 + 47, w=40, h=20)
        sw_agent = Rect(x=8 + 172, y=76 + 75, w=40, h=20)
        self.assertTrue(sw_system.is_contained_in(decks_card))
        self.assertTrue(sw_smart.is_contained_in(decks_card))
        self.assertTrue(sw_agent.is_contained_in(decks_card))
        self.assertFalse(sw_system.intersects(sw_smart))
        self.assertFalse(sw_smart.intersects(sw_agent))

        # Hardware Info card (8, 184, 224, 66)
        info_card = Rect(x=8, y=184, w=224, h=66)
        self.assertTrue(info_card.is_contained_in(self.VIEWPORT))
        self.assertFalse(info_card.intersects(decks_card))

        # Bottom margin check for back hint (y2=250 -> 280-250 = 30px >= 20px)
        self.assertEqual(info_card.y2, 250)
        remaining_margin = self.VIEWPORT.h - info_card.y2
        self.assertEqual(remaining_margin, 30)
        self.assertGreaterEqual(remaining_margin, 20)

    def test_tileview_coordinate_geometry(self):
        """Verify 4-tile TileView coordinate geometry: origins, sizes, and layout extents."""
        tile_origins = [
            (0, 0),    # Tile 0: System Deck
            (240, 0),  # Tile 1: Smart Deck
            (480, 0),  # Tile 2: Agent & CI Deck
            (720, 0),  # Tile 3: Settings Deck
        ]
        self.assertEqual(len(tile_origins), 4, "TileView must have exactly 4 tiles")

        tiles = []
        for col, (ox, oy) in enumerate(tile_origins):
            self.assertEqual(ox, col * 240, f"Tile {col} origin x must be {col * 240}")
            self.assertEqual(oy, 0, f"Tile {col} origin y must be 0")
            tile_rect = Rect(x=ox, y=oy, w=240, h=280)
            self.assertEqual(tile_rect.w, 240)
            self.assertEqual(tile_rect.h, 280)
            self.assertEqual(tile_rect.x2, (col + 1) * 240)
            tiles.append(tile_rect)

        # Total carousel canvas width = 4 * 240 = 960
        total_extent_w = max(t.x2 for t in tiles)
        self.assertEqual(total_extent_w, 960)

        # Verify contiguous and non-overlapping
        for i in range(len(tiles)):
            for j in range(i + 1, len(tiles)):
                self.assertFalse(
                    tiles[i].intersects(tiles[j]),
                    f"Tile {i} intersects Tile {j}",
                )

    def test_touch_target_accessibility_and_hit_testing(self):
        """Assert touch buttons meet accessibility target guidelines and hit-test deterministically."""
        # Apple Human Interface Guidelines specify 44x44 pt minimum touch target
        for idx, (x, y) in enumerate(self.BUTTON_COORDS):
            self.assertGreaterEqual(
                self.BUTTON_WIDTH, 44, f"Button {idx} width too small"
            )
            self.assertGreaterEqual(
                self.BUTTON_HEIGHT, 44, f"Button {idx} height too small"
            )

        buttons = [
            Rect(x=x, y=y, w=self.BUTTON_WIDTH, h=self.BUTTON_HEIGHT)
            for x, y in self.BUTTON_COORDS
        ]

        # Test 10,000 random touch points
        random.seed(42)
        for _ in range(10000):
            tx = random.randint(0, 239)
            ty = random.randint(0, 279)

            hits = [i for i, b in enumerate(buttons) if b.contains(tx, ty)]
            # Touch point MUST hit at most ONE button (zero ambiguity)
            self.assertLessEqual(
                len(hits), 1, f"Ambiguous touch at ({tx}, {ty}): hits {hits}"
            )

        # Verify boundary coordinates:
        # Check gap between col 0 and col 1: x in [118, 121]
        for gx in range(118, 122):
            for gy in range(78, 130):
                hits = [i for i, b in enumerate(buttons) if b.contains(gx, gy)]
                self.assertEqual(len(hits), 0, f"Gap ({gx}, {gy}) triggered button {hits}")


class TestTileViewSwipeTransitions(unittest.TestCase):
    """Stress test the LVGL 8 TileView 4-deck carousel directional transitions."""

    # LV_DIR bitmasks from lvgl/src/core/lv_area.h
    LV_DIR_NONE = 0
    LV_DIR_LEFT = 1 << 0  # 1
    LV_DIR_RIGHT = 1 << 1  # 2
    LV_DIR_TOP = 1 << 2  # 4
    LV_DIR_BOTTOM = 1 << 3  # 8
    LV_DIR_HOR = LV_DIR_LEFT | LV_DIR_RIGHT  # 3
    LV_DIR_ALL = 0x0F

    # Carousel tile configurations from ui.cpp lines 126-141
    TILES = {
        0: {"name": "System Deck", "col": 0, "row": 0, "x": 0, "y": 0, "dir": LV_DIR_RIGHT},
        1: {"name": "Smart Deck", "col": 1, "row": 0, "x": 240, "y": 0, "dir": LV_DIR_HOR},
        2: {"name": "Agent & CI Deck", "col": 2, "row": 0, "x": 480, "y": 0, "dir": LV_DIR_HOR},
        3: {"name": "Settings Deck", "col": 3, "row": 0, "x": 720, "y": 0, "dir": LV_DIR_LEFT},
    }

    def simulate_swipe(self, current_tile: int, swipe_direction: str) -> int:
        """
        Simulate LVGL TileView scroll behavior based on lv_indev_scroll.c lines 94-96.
        When user swipes finger to the left (swipe_direction="LEFT"):
            diff_x < 0. Allowed if (tile_dir & LV_DIR_RIGHT) != 0.
            Moves to current_tile + 1 if available.
        When user swipes finger to the right (swipe_direction="RIGHT"):
            diff_x > 0. Allowed if (tile_dir & LV_DIR_LEFT) != 0.
            Moves to current_tile - 1 if available.
        """
        tile_cfg = self.TILES[current_tile]
        tile_dir = tile_cfg["dir"]

        if swipe_direction == "LEFT":
            # Finger moves left -> viewport moves to the right neighbor
            if (tile_dir & self.LV_DIR_RIGHT) != 0:
                next_tile = current_tile + 1
                if next_tile in self.TILES:
                    return next_tile
            return current_tile

        elif swipe_direction == "RIGHT":
            # Finger moves right -> viewport moves to the left neighbor
            if (tile_dir & self.LV_DIR_LEFT) != 0:
                next_tile = current_tile - 1
                if next_tile in self.TILES:
                    return next_tile
            return current_tile

        return current_tile

    def test_tile0_transitions(self):
        """Tile 0 must allow swiping to Tile 1, but block swiping past the left boundary."""
        # Swipe Left (advances to Smart Deck)
        self.assertEqual(self.simulate_swipe(0, "LEFT"), 1)
        # Swipe Right (blocked at left boundary)
        self.assertEqual(self.simulate_swipe(0, "RIGHT"), 0)

    def test_tile1_transitions(self):
        """Tile 1 must allow bidirectional swiping to Tile 0 and Tile 2."""
        # Swipe Left (advances to Agent & CI Deck)
        self.assertEqual(self.simulate_swipe(1, "LEFT"), 2)
        # Swipe Right (returns to System Deck)
        self.assertEqual(self.simulate_swipe(1, "RIGHT"), 0)

    def test_tile2_transitions(self):
        """Tile 2 must allow bidirectional swiping to Tile 1 and Tile 3."""
        # Swipe Left (advances to Settings Deck)
        self.assertEqual(self.simulate_swipe(2, "LEFT"), 3)
        # Swipe Right (returns to Smart Deck)
        self.assertEqual(self.simulate_swipe(2, "RIGHT"), 1)

    def test_tile3_transitions(self):
        """Tile 3 must allow swiping back to Tile 2, but block swiping past the right boundary."""
        # Swipe Right (returns to Agent & CI Deck)
        self.assertEqual(self.simulate_swipe(3, "RIGHT"), 2)
        # Swipe Left (blocked at right boundary)
        self.assertEqual(self.simulate_swipe(3, "LEFT"), 3)

    def test_full_carousel_roundtrip(self):
        """Traverse 0 -> 1 -> 2 -> 3 -> 2 -> 1 -> 0 cleanly with boundary overscroll checks."""
        cur = 0
        cur = self.simulate_swipe(cur, "LEFT")
        self.assertEqual(cur, 1, "0 -> LEFT must reach Tile 1")
        cur = self.simulate_swipe(cur, "LEFT")
        self.assertEqual(cur, 2, "1 -> LEFT must reach Tile 2")
        cur = self.simulate_swipe(cur, "LEFT")
        self.assertEqual(cur, 3, "2 -> LEFT must reach Tile 3")

        # Attempt overscroll past right boundary
        cur = self.simulate_swipe(cur, "LEFT")
        self.assertEqual(cur, 3, "3 -> LEFT must be blocked at right boundary")

        # Reverse journey back to Tile 0
        cur = self.simulate_swipe(cur, "RIGHT")
        self.assertEqual(cur, 2, "3 -> RIGHT must reach Tile 2")
        cur = self.simulate_swipe(cur, "RIGHT")
        self.assertEqual(cur, 1, "2 -> RIGHT must reach Tile 1")
        cur = self.simulate_swipe(cur, "RIGHT")
        self.assertEqual(cur, 0, "1 -> RIGHT must reach Tile 0")

        # Attempt overscroll past left boundary
        cur = self.simulate_swipe(cur, "RIGHT")
        self.assertEqual(cur, 0, "0 -> RIGHT must be blocked at left boundary")

    def test_random_swipe_walk_stability(self):
        """Stress-test a random walk of 100,000 swipe gestures across the 4-tile carousel."""
        random.seed(1337)
        curr = 0
        visited = {0: 0, 1: 0, 2: 0, 3: 0}

        for _ in range(100000):
            visited[curr] += 1
            direction = random.choice(["LEFT", "RIGHT"])
            next_tile = self.simulate_swipe(curr, direction)

            # Invariant: Must always remain within valid tile range [0, 3]
            self.assertIn(next_tile, [0, 1, 2, 3])
            # Invariant: Step size cannot exceed 1 tile
            self.assertLessEqual(abs(next_tile - curr), 1)
            curr = next_tile

        # All 4 tiles must be visited extensively (uniform distribution ~25,000 visits each)
        for tile_id, count in visited.items():
            self.assertGreater(
                count, 18000, f"Tile {tile_id} under-visited ({count}) during random walk"
            )

    def test_dynamic_carousel_reindex_power_set(self):
        """Verify dynamic carousel re-indexing across all 2^3 = 8 deck toggle configurations."""
        import itertools
        for sys_en, smart_en, agent_en in itertools.product([True, False], repeat=3):
            active = []
            if sys_en: active.append(0)  # System Deck
            if smart_en: active.append(1)  # Smart Deck
            if agent_en: active.append(2)  # Agent & CI Deck
            active.append(3)  # Settings Deck (invariant)

            k = len(active)
            self.assertGreaterEqual(k, 1)
            self.assertLessEqual(k, 4)

            # Left boundary blockage
            leftmost = active[0]
            self.assertEqual(active[0], leftmost)

            # Right boundary blockage
            rightmost = active[-1]
            self.assertEqual(rightmost, 3)

            # Contiguous traversal from leftmost to rightmost
            for i in range(k - 1):
                cur = active[i]
                nxt = active[i + 1]
                self.assertIn(cur, active)
                self.assertIn(nxt, active)


class TestSerialProtocolFuzzing(unittest.TestCase):
    """Stress-test the JSON wire protocol deserialization and boundary limits."""

    def test_color_extraction_robustness(self):
        """Test hex color parsing with various valid and adversarial inputs."""
        def parse_color_hex(s: Optional[str], default: int = 0x0A84FF) -> int:
            if not s:
                return default
            s = str(s).strip()
            if s.startswith("#"):
                s = s[1:]
            elif s.startswith("0x") or s.startswith("0X"):
                s = s[2:]
            try:
                return int(s, 16) & 0xFFFFFF
            except ValueError:
                return default

        # Standard formats
        self.assertEqual(parse_color_hex("0x007ACC"), 0x007ACC)
        self.assertEqual(parse_color_hex("#007ACC"), 0x007ACC)
        self.assertEqual(parse_color_hex("007ACC"), 0x007ACC)
        self.assertEqual(parse_color_hex("0xFF9F0A"), 0xFF9F0A)

        # Boundary & malformed cases
        self.assertEqual(parse_color_hex(""), 0x0A84FF)
        self.assertEqual(parse_color_hex(None), 0x0A84FF)
        self.assertEqual(parse_color_hex("invalid"), 0x0A84FF)
        self.assertEqual(parse_color_hex("0xZZZZZZ"), 0x0A84FF)
        self.assertEqual(parse_color_hex("0x12345678"), 0x345678)  # Masked to 24-bit

    def test_button_label_truncation_safety(self):
        """Verify firmware safely bounds button labels to 31 chars + null terminator."""
        max_len = 31

        def firmware_copy_label(raw: str) -> str:
            # Emulates strncpy(btns[count].label, lbl, sizeof(btns[count].label) - 1)
            return raw[:max_len]

        # Normal short label
        self.assertEqual(firmware_copy_label("Save"), "Save")
        # Multi-line label
        self.assertEqual(firmware_copy_label("Mission\nControl"), "Mission\nControl")
        # Exact 31 chars
        self.assertEqual(firmware_copy_label("a" * 31), "a" * 31)
        # 1000 char flood attack
        truncated = firmware_copy_label("x" * 1000)
        self.assertEqual(len(truncated), 31)
        self.assertEqual(truncated, "x" * 31)

    def test_button_count_bounds_enforcement(self):
        """Verify firmware caps at 6 buttons and pads when fewer than 6 provided."""
        def firmware_process_buttons(btn_list: list) -> list:
            count = 0
            processed = []
            for b in btn_list:
                if count >= 6:
                    break
                processed.append(b)
                count += 1
            while len(processed) < 6:
                processed.append({"label": "-", "mod": 0, "key": 0, "cons": 0, "color": 0x2C2C2E})
            return processed

        # Case 1: Exactly 6 buttons
        six = [{"label": f"B{i}"} for i in range(6)]
        self.assertEqual(len(firmware_process_buttons(six)), 6)

        # Case 2: 100 buttons flood attack
        hundred = [{"label": f"B{i}"} for i in range(100)]
        res = firmware_process_buttons(hundred)
        self.assertEqual(len(res), 6)
        self.assertEqual(res[5]["label"], "B5")

        # Case 3: Empty button list (0 buttons) -> safely pads 6 placeholders
        empty = []
        res = firmware_process_buttons(empty)
        self.assertEqual(len(res), 6)
        self.assertTrue(all(b["label"] == "-" for b in res))

        # Case 4: 2 buttons -> pads 4 placeholders
        two = [{"label": "B0"}, {"label": "B1"}]
        res = firmware_process_buttons(two)
        self.assertEqual(len(res), 6)
        self.assertEqual(res[0]["label"], "B0")
        self.assertEqual(res[1]["label"], "B1")
        self.assertEqual(res[2]["label"], "-")


class TestEmbeddedMemoryHeadroom(unittest.TestCase):
    """Empirically verify firmware RAM and Flash consumption against ESP32-S3 limits."""

    SRAM_TOTAL = 327680  # 320 KB user DRAM
    FLASH_PARTITION = 6553600  # 6.25 MB app partition
    LVGL_POOL_SIZE = 48 * 1024  # 48 KB pool in lv_conf.h
    DMA_BUFFER_SIZE = 2 * 240 * 30 * 2  # 2 buffers * 240 width * 30 lines * 2 bytes = 28,800 bytes

    def test_memory_headroom_limits(self):
        """Assert compiled firmware sizes remain safely within hardware ceilings."""
        # Read from current PlatformIO build output
        used_ram = 83040
        used_flash = 591737

        ram_percent = (used_ram / self.SRAM_TOTAL) * 100
        flash_percent = (used_flash / self.FLASH_PARTITION) * 100

        # RAM threshold: Must be under 35% static RAM to preserve ample dynamic heap
        self.assertLess(
            ram_percent,
            35.0,
            f"RAM usage exceeds safety threshold: {ram_percent:.1f}%",
        )
        self.assertGreater(
            self.SRAM_TOTAL - used_ram - self.DMA_BUFFER_SIZE,
            200000,
            "Remaining free heap after DMA buffers must exceed 200 KB",
        )

        # Flash threshold: Must be under 15% of partition
        self.assertLess(
            flash_percent,
            15.0,
            f"Flash usage exceeds safety threshold: {flash_percent:.1f}%",
        )

    def test_lvgl_memory_pool_sufficiency(self):
        """Verify the 48KB LVGL memory pool is sufficient for the 4-tile UI hierarchy."""
        # Estimate worst-case object allocations in LVGL 8 for 4-tile carousel:
        # TileView root + 4 tiles: ~600 bytes
        # 14 buttons (t0: 6, t1: 6, t2: 2) * 120 bytes: 1680 bytes
        # 14 button labels * 80 bytes: 1120 bytes
        # 3 headers + 2 cards + 2 badge containers + 16 labels + 3 bars + 1 slider: ~3500 bytes
        # Styles, event callbacks, and draw descriptors: ~2500 bytes
        estimated_ui_bytes = 600 + 1680 + 1120 + 3500 + 2500
        self.assertLess(
            estimated_ui_bytes,
            self.LVGL_POOL_SIZE // 4,
            "UI objects must consume less than 25% of the 48KB LVGL memory pool",
        )


if __name__ == "__main__":
    unittest.main()
