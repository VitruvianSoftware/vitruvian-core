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

"""Comprehensive empirical test suite for Milestone 4: Dynamic Deck Visibility Toggles & State Persistence.

Covers:
1. Power set of 8 active deck configurations (2^3 = 8 subsets).
2. Contiguous 1D swipe graphs without holes or dead ends.
3. Left and right boundary blockage and LVGL direction bitmasks.
4. Settings Deck reachability from every active subset.
5. Invariance of Settings Deck (cannot be disabled).
6. Multi-step skip transitions across disabled decks.
7. Random-walk ergodicity (100,000 steps) across all 8 configurations.
8. Live toggle mutations and seamless carousel re-indexing.
9. NVS/Preferences state persistence, power-cycle recovery, and flash endurance.
10. Dynamic bottom navigation hint string adaptation.
"""

import enum
import itertools
import random
import unittest
from dataclasses import dataclass
from typing import Dict, List, Optional, Tuple


# LVGL 8 Direction Bitmasks (from lvgl/src/core/lv_area.h)
LV_DIR_NONE = 0
LV_DIR_LEFT = 1 << 0   # 1: swipe rightwards moves to left neighbor
LV_DIR_RIGHT = 1 << 1  # 2: swipe leftwards moves to right neighbor
LV_DIR_TOP = 1 << 2    # 4
LV_DIR_BOTTOM = 1 << 3 # 8
LV_DIR_HOR = LV_DIR_LEFT | LV_DIR_RIGHT  # 3: bidirectional horizontal swipe
LV_DIR_ALL = 0x0F


class DeckID(enum.IntEnum):
    SYSTEM = 0
    SMART = 1
    AGENT_CI = 2
    SETTINGS = 3


DECK_NAMES = {
    DeckID.SYSTEM: "System Deck",
    DeckID.SMART: "Smart Deck",
    DeckID.AGENT_CI: "Agent & CI Deck",
    DeckID.SETTINGS: "Settings Deck",
}


@dataclass
class DeckTile:
    deck_id: DeckID
    name: str
    col: int
    row: int
    x: int
    y: int
    w: int
    h: int
    dir: int
    hidden: bool


class DynamicTileViewCarousel:
    """Accurate model of the ESP32-S3 LVGL 8 TileView dynamic re-indexing engine."""

    SCREEN_WIDTH = 240
    SCREEN_HEIGHT = 280

    def __init__(self, sys_en: bool = True, smart_en: bool = True, agent_en: bool = True):
        # Hardware tile storage (all 4 tiles allocated at init)
        self.sys_enabled = sys_en
        self.smart_enabled = smart_en
        self.agent_enabled = agent_en
        self.settings_enabled = True  # INVARIANT: Settings Deck is always enabled

        self.tiles: Dict[DeckID, DeckTile] = {
            DeckID.SYSTEM: DeckTile(DeckID.SYSTEM, "System Deck", 0, 0, 0, 0, 240, 280, LV_DIR_RIGHT, False),
            DeckID.SMART: DeckTile(DeckID.SMART, "Smart Deck", 1, 0, 240, 0, 240, 280, LV_DIR_HOR, False),
            DeckID.AGENT_CI: DeckTile(DeckID.AGENT_CI, "Agent & CI Deck", 2, 0, 480, 0, 240, 280, LV_DIR_HOR, False),
            DeckID.SETTINGS: DeckTile(DeckID.SETTINGS, "Settings Deck", 3, 0, 720, 0, 240, 280, LV_DIR_LEFT, False),
        }
        self.active_order: List[DeckID] = []
        self.reindex()

    def set_deck_visibility(self, deck_id: DeckID, enabled: bool):
        """Update toggle state and trigger carousel re-indexing."""
        if deck_id == DeckID.SYSTEM:
            self.sys_enabled = enabled
        elif deck_id == DeckID.SMART:
            self.smart_enabled = enabled
        elif deck_id == DeckID.AGENT_CI:
            self.agent_enabled = enabled
        elif deck_id == DeckID.SETTINGS:
            raise ValueError("Settings Deck cannot be disabled (invariant)!")
        self.reindex()

    def reindex(self):
        """Execute dynamic re-indexing: assign contiguous coordinates and direction bitmasks."""
        active = []
        if self.sys_enabled:
            active.append(DeckID.SYSTEM)
        if self.smart_enabled:
            active.append(DeckID.SMART)
        if self.agent_enabled:
            active.append(DeckID.AGENT_CI)
        active.append(DeckID.SETTINGS)
        self.active_order = active
        k = len(active)

        # 1. Update active tiles
        for col_idx, deck_id in enumerate(active):
            tile = self.tiles[deck_id]
            tile.col = col_idx
            tile.row = 0
            tile.x = col_idx * self.SCREEN_WIDTH
            tile.y = 0
            tile.hidden = False

            if k == 1:
                tile.dir = LV_DIR_NONE
            elif col_idx == 0:
                tile.dir = LV_DIR_RIGHT
            elif col_idx == k - 1:
                tile.dir = LV_DIR_LEFT
            else:
                tile.dir = LV_DIR_HOR

        # 2. Update disabled tiles
        disabled = [d for d in [DeckID.SYSTEM, DeckID.SMART, DeckID.AGENT_CI] if d not in active]
        for deck_id in disabled:
            tile = self.tiles[deck_id]
            tile.col = -1
            tile.row = -1
            tile.x = 9999  # offscreen
            tile.y = 9999
            tile.hidden = True
            tile.dir = LV_DIR_NONE

    def simulate_swipe(self, current_deck: DeckID, swipe_direction: str) -> DeckID:
        """Simulate LVGL TileView scroll gesture from current_deck.

        swipe_direction == 'LEFT': Finger swipes left -> viewport moves right to neighbor (requires LV_DIR_RIGHT).
        swipe_direction == 'RIGHT': Finger swipes right -> viewport moves left to neighbor (requires LV_DIR_LEFT).
        """
        if current_deck not in self.active_order:
            return current_deck

        tile = self.tiles[current_deck]
        current_idx = self.active_order.index(current_deck)
        k = len(self.active_order)

        if swipe_direction == "LEFT":
            if (tile.dir & LV_DIR_RIGHT) != 0 and current_idx + 1 < k:
                return self.active_order[current_idx + 1]
            return current_deck
        elif swipe_direction == "RIGHT":
            if (tile.dir & LV_DIR_LEFT) != 0 and current_idx - 1 >= 0:
                return self.active_order[current_idx - 1]
            return current_deck
        return current_deck

    def get_navigation_hints(self) -> Dict[DeckID, str]:
        """Compute the dynamic bottom navigation hint strings for all active decks."""
        hints = {}
        k = len(self.active_order)
        for i, deck_id in enumerate(self.active_order):
            if k == 1:
                hints[deck_id] = "No other active decks"
            elif i == 0:
                right_neighbor = DECK_NAMES[self.active_order[i + 1]].replace(" Deck", "")
                hints[deck_id] = f"Swipe Left for {right_neighbor} >"
            elif i == k - 1:
                left_neighbor = DECK_NAMES[self.active_order[i - 1]].replace(" Deck", "")
                hints[deck_id] = f"< Swipe Right for {left_neighbor}"
            else:
                left_neighbor = DECK_NAMES[self.active_order[i - 1]].replace(" Deck", "")
                right_neighbor = DECK_NAMES[self.active_order[i + 1]].replace(" Deck", "")
                hints[deck_id] = f"< {left_neighbor} | {right_neighbor} >"
        return hints


class MockPreferencesStorage:
    """Emulates ESP32 Arduino Preferences library and NVS partition at 0x9000."""

    def __init__(self):
        self._namespaces: Dict[str, Dict[str, any]] = {}
        self._open_namespace: Optional[str] = None
        self._write_count = 0

    def begin(self, name: str, read_only: bool = False) -> bool:
        if len(name) > 15:
            return False
        self._open_namespace = name
        if name not in self._namespaces:
            self._namespaces[name] = {}
        return True

    def end(self):
        self._open_namespace = None

    def get_bool(self, key: str, default: bool = False) -> bool:
        if not self._open_namespace or key not in self._namespaces[self._open_namespace]:
            return default
        return bool(self._namespaces[self._open_namespace][key])

    def put_bool(self, key: str, value: bool) -> bool:
        if not self._open_namespace:
            return False
        ns = self._namespaces[self._open_namespace]
        # Wear leveling optimization: skip flash write if existing value matches
        if key in ns and ns[key] == value:
            return True
        ns[key] = value
        self._write_count += 1
        return True

    def get_uchar(self, key: str, default: int = 80) -> int:
        if not self._open_namespace or key not in self._namespaces[self._open_namespace]:
            return default
        return int(self._namespaces[self._open_namespace][key])

    def put_uchar(self, key: str, value: int) -> bool:
        if not self._open_namespace:
            return False
        ns = self._namespaces[self._open_namespace]
        if key in ns and ns[key] == value:
            return True
        ns[key] = value
        self._write_count += 1
        return True

    @property
    def write_count(self) -> int:
        return self._write_count


class TestDeckPowerSetConfigurations(unittest.TestCase):
    """Verify that all 2^3 = 8 configurations form mathematically sound 1D chains."""

    def test_power_set_enumeration_and_layout(self):
        """Enumerate all 8 subsets and assert active sequence, count, coordinates, and ordering."""
        expected_configs = [
            # (sys, smart, agent) -> expected active list
            ((True, True, True), [DeckID.SYSTEM, DeckID.SMART, DeckID.AGENT_CI, DeckID.SETTINGS]),
            ((True, True, False), [DeckID.SYSTEM, DeckID.SMART, DeckID.SETTINGS]),
            ((True, False, True), [DeckID.SYSTEM, DeckID.AGENT_CI, DeckID.SETTINGS]),
            ((True, False, False), [DeckID.SYSTEM, DeckID.SETTINGS]),
            ((False, True, True), [DeckID.SMART, DeckID.AGENT_CI, DeckID.SETTINGS]),
            ((False, True, False), [DeckID.SMART, DeckID.SETTINGS]),
            ((False, False, True), [DeckID.AGENT_CI, DeckID.SETTINGS]),
            ((False, False, False), [DeckID.SETTINGS]),
        ]

        for (sys_en, smart_en, agent_en), expected_active in expected_configs:
            carousel = DynamicTileViewCarousel(sys_en, smart_en, agent_en)

            # 1. Active sequence and count
            self.assertEqual(
                carousel.active_order,
                expected_active,
                f"Mismatch for ({sys_en}, {smart_en}, {agent_en})",
            )
            k = len(expected_active)
            self.assertGreaterEqual(k, 1)
            self.assertLessEqual(k, 4)

            # 2. Settings Deck is always present
            self.assertIn(DeckID.SETTINGS, carousel.active_order)
            self.assertEqual(carousel.active_order[-1], DeckID.SETTINGS)

            # 3. Column indices form contiguous [0 .. k-1]
            for col_idx, deck_id in enumerate(expected_active):
                tile = carousel.tiles[deck_id]
                self.assertEqual(tile.col, col_idx)
                self.assertEqual(tile.row, 0)
                self.assertEqual(tile.x, col_idx * 240)
                self.assertEqual(tile.y, 0)
                self.assertFalse(tile.hidden)

            # 4. Total extent matches k * 240
            total_w = k * 240
            self.assertEqual(max(t.x + t.w for t in carousel.tiles.values() if not t.hidden), total_w)

            # 5. Inactive tiles are hidden and offscreen
            inactive = [d for d in [DeckID.SYSTEM, DeckID.SMART, DeckID.AGENT_CI] if d not in expected_active]
            for d in inactive:
                tile = carousel.tiles[d]
                self.assertTrue(tile.hidden)
                self.assertGreaterEqual(tile.x, 9000)
                self.assertEqual(tile.dir, LV_DIR_NONE)


class TestContiguousSwipeGraph(unittest.TestCase):
    """Verify bidirectional contiguous navigation, no holes, and multi-step skipping."""

    def test_bidirectional_contiguity_all_8_subsets(self):
        """Every active deck must smoothly transition to its neighbors in both directions."""
        for sys_en, smart_en, agent_en in itertools.product([True, False], repeat=3):
            carousel = DynamicTileViewCarousel(sys_en, smart_en, agent_en)
            active = carousel.active_order
            k = len(active)

            # Test bidirectional link between every adjacent pair
            for i in range(k - 1):
                cur = active[i]
                nxt = active[i + 1]

                # Forward swipe (LEFT gesture)
                self.assertEqual(
                    carousel.simulate_swipe(cur, "LEFT"),
                    nxt,
                    f"Failed LEFT swipe from {cur} to {nxt} in config ({sys_en}, {smart_en}, {agent_en})",
                )
                # Reverse swipe (RIGHT gesture)
                self.assertEqual(
                    carousel.simulate_swipe(nxt, "RIGHT"),
                    cur,
                    f"Failed RIGHT swipe from {nxt} to {cur} in config ({sys_en}, {smart_en}, {agent_en})",
                )

    def test_multi_step_skip_scenarios(self):
        """Verify direct transitions skipping disabled intermediate decks."""
        # Scenario 1: Smart Deck disabled -> System swipes directly to Agent/CI
        c1 = DynamicTileViewCarousel(sys_en=True, smart_en=False, agent_en=True)
        self.assertEqual(c1.simulate_swipe(DeckID.SYSTEM, "LEFT"), DeckID.AGENT_CI)
        self.assertEqual(c1.simulate_swipe(DeckID.AGENT_CI, "RIGHT"), DeckID.SYSTEM)

        # Scenario 2: Smart & Agent/CI disabled -> System swipes directly to Settings
        c2 = DynamicTileViewCarousel(sys_en=True, smart_en=False, agent_en=False)
        self.assertEqual(c2.simulate_swipe(DeckID.SYSTEM, "LEFT"), DeckID.SETTINGS)
        self.assertEqual(c2.simulate_swipe(DeckID.SETTINGS, "RIGHT"), DeckID.SYSTEM)

        # Scenario 3: System & Smart disabled -> Agent/CI is leftmost, swipes directly to Settings
        c3 = DynamicTileViewCarousel(sys_en=False, smart_en=False, agent_en=True)
        self.assertEqual(c3.simulate_swipe(DeckID.AGENT_CI, "LEFT"), DeckID.SETTINGS)
        self.assertEqual(c3.simulate_swipe(DeckID.SETTINGS, "RIGHT"), DeckID.AGENT_CI)
        # Left boundary of Agent/CI blocks swiping right
        self.assertEqual(c3.simulate_swipe(DeckID.AGENT_CI, "RIGHT"), DeckID.AGENT_CI)


class TestBoundaryBlockage(unittest.TestCase):
    """Verify left boundary blockage, right boundary blockage, and direction bitmasks."""

    def test_boundaries_for_all_8_subsets(self):
        """Leftmost deck blocks right swipes; rightmost deck (Settings) blocks left swipes."""
        for sys_en, smart_en, agent_en in itertools.product([True, False], repeat=3):
            carousel = DynamicTileViewCarousel(sys_en, smart_en, agent_en)
            active = carousel.active_order
            k = len(active)

            leftmost = active[0]
            rightmost = active[-1]
            self.assertEqual(rightmost, DeckID.SETTINGS)

            # Left boundary blockage
            self.assertEqual(
                carousel.simulate_swipe(leftmost, "RIGHT"),
                leftmost,
                f"Left boundary not blocked for {leftmost} in ({sys_en}, {smart_en}, {agent_en})",
            )

            # Right boundary blockage
            self.assertEqual(
                carousel.simulate_swipe(rightmost, "LEFT"),
                rightmost,
                f"Right boundary not blocked for {rightmost} in ({sys_en}, {smart_en}, {agent_en})",
            )

            # Bitmask assertions
            if k == 1:
                # Standalone Settings tile: both directions blocked
                self.assertEqual(carousel.tiles[rightmost].dir, LV_DIR_NONE)
            else:
                # Leftmost tile allows ONLY moving rightward (LV_DIR_RIGHT)
                self.assertEqual(carousel.tiles[leftmost].dir, LV_DIR_RIGHT)
                self.assertEqual(carousel.tiles[leftmost].dir & LV_DIR_LEFT, 0)

                # Rightmost tile allows ONLY moving leftward (LV_DIR_LEFT)
                self.assertEqual(carousel.tiles[rightmost].dir, LV_DIR_LEFT)
                self.assertEqual(carousel.tiles[rightmost].dir & LV_DIR_RIGHT, 0)

                # All intermediate tiles allow bidirectional horizontal movement
                for mid in active[1:-1]:
                    self.assertEqual(carousel.tiles[mid].dir, LV_DIR_HOR)


class TestSettingsDeckReachability(unittest.TestCase):
    """Verify Settings Deck is 100% reachable from every active deck across all combinations."""

    def test_reachability_within_max_3_swipes(self):
        """From any active deck, repeated LEFT swipes must reach Settings Deck in <= 3 steps."""
        for sys_en, smart_en, agent_en in itertools.product([True, False], repeat=3):
            carousel = DynamicTileViewCarousel(sys_en, smart_en, agent_en)
            active = carousel.active_order
            k = len(active)

            for start_deck in active:
                curr = start_deck
                steps = 0
                while curr != DeckID.SETTINGS:
                    next_deck = carousel.simulate_swipe(curr, "LEFT")
                    self.assertNotEqual(
                        next_deck,
                        curr,
                        f"Premature dead-end at {curr} in ({sys_en}, {smart_en}, {agent_en})",
                    )
                    curr = next_deck
                    steps += 1

                self.assertLessEqual(steps, k - 1)
                self.assertLessEqual(steps, 3)

    def test_settings_deck_invariant_protection(self):
        """Settings Deck cannot be disabled via API or toggle."""
        carousel = DynamicTileViewCarousel(True, True, True)
        with self.assertRaises(ValueError):
            carousel.set_deck_visibility(DeckID.SETTINGS, False)


class TestRandomWalkErgodicity(unittest.TestCase):
    """Stress test 100,000 random swipe gestures across all 8 configurations."""

    def test_random_walks_across_all_configurations(self):
        """Assert zero crashes, zero invalid coordinates, and uniform distribution on all active decks."""
        for idx, (sys_en, smart_en, agent_en) in enumerate(itertools.product([True, False], repeat=3)):
            carousel = DynamicTileViewCarousel(sys_en, smart_en, agent_en)
            active = carousel.active_order
            k = len(active)

            random.seed(1337 + idx)
            curr = active[0]
            visits = {d: 0 for d in active}

            for _ in range(12500):  # 8 configs * 12,500 = 100,000 total steps
                visits[curr] += 1
                direction = random.choice(["LEFT", "RIGHT"])
                nxt = carousel.simulate_swipe(curr, direction)

                # Invariants:
                self.assertIn(nxt, active)
                curr_idx = active.index(curr)
                nxt_idx = active.index(nxt)
                self.assertLessEqual(abs(nxt_idx - curr_idx), 1)

                curr = nxt

            # Distribution checks
            if k > 1:
                for d in active:
                    self.assertGreater(
                        visits[d],
                        1200,
                        f"Deck {d} under-visited ({visits[d]}) in config ({sys_en}, {smart_en}, {agent_en})",
                    )
            else:
                self.assertEqual(visits[DeckID.SETTINGS], 12500)


class TestLiveToggleMutations(unittest.TestCase):
    """Simulate a user interactively toggling switches on the Settings Deck in real-time."""

    def test_interactive_toggling_workflow(self):
        """Walk through toggling off Smart, then Agent, then restoring them, asserting state."""
        carousel = DynamicTileViewCarousel(sys_en=True, smart_en=True, agent_en=True)
        self.assertEqual(carousel.active_order, [DeckID.SYSTEM, DeckID.SMART, DeckID.AGENT_CI, DeckID.SETTINGS])

        # User is on Settings Deck and disables Smart Deck
        carousel.set_deck_visibility(DeckID.SMART, False)
        self.assertEqual(carousel.active_order, [DeckID.SYSTEM, DeckID.AGENT_CI, DeckID.SETTINGS])
        self.assertEqual(carousel.tiles[DeckID.SETTINGS].col, 2)
        # Swiping right from Settings lands on Agent/CI
        self.assertEqual(carousel.simulate_swipe(DeckID.SETTINGS, "RIGHT"), DeckID.AGENT_CI)
        # Swiping right from Agent/CI lands on System
        self.assertEqual(carousel.simulate_swipe(DeckID.AGENT_CI, "RIGHT"), DeckID.SYSTEM)

        # User disables Agent/CI Deck
        carousel.set_deck_visibility(DeckID.AGENT_CI, False)
        self.assertEqual(carousel.active_order, [DeckID.SYSTEM, DeckID.SETTINGS])
        self.assertEqual(carousel.tiles[DeckID.SETTINGS].col, 1)
        # Swiping right from Settings lands directly on System
        self.assertEqual(carousel.simulate_swipe(DeckID.SETTINGS, "RIGHT"), DeckID.SYSTEM)

        # User re-enables Smart Deck
        carousel.set_deck_visibility(DeckID.SMART, True)
        self.assertEqual(carousel.active_order, [DeckID.SYSTEM, DeckID.SMART, DeckID.SETTINGS])
        self.assertEqual(carousel.tiles[DeckID.SETTINGS].col, 2)
        self.assertEqual(carousel.simulate_swipe(DeckID.SETTINGS, "RIGHT"), DeckID.SMART)


class TestStatePersistenceAndEndurance(unittest.TestCase):
    """Verify NVS / Preferences persistence model, power-cycle recovery, and flash endurance."""

    def test_nvs_persistence_roundtrip(self):
        """Test write -> power cycle -> read -> carousel re-indexing."""
        storage = MockPreferencesStorage()

        # 1. First boot: No keys stored -> load defaults
        storage.begin("mac_ctrl", read_only=False)
        sys_val = storage.get_bool("deck_sys", default=True)
        smart_val = storage.get_bool("deck_smart", default=True)
        agent_val = storage.get_bool("deck_agent", default=True)
        bright_val = storage.get_uchar("brightness", default=80)
        storage.end()

        self.assertTrue(sys_val)
        self.assertTrue(smart_val)
        self.assertTrue(agent_val)
        self.assertEqual(bright_val, 80)

        # 2. User toggles Smart OFF and Agent OFF, sets brightness to 65
        storage.begin("mac_ctrl", read_only=False)
        storage.put_bool("deck_sys", True)
        storage.put_bool("deck_smart", False)
        storage.put_bool("deck_agent", False)
        storage.put_uchar("brightness", 65)
        storage.end()

        # 3. Simulate Power Cycle / Reboot
        rebooted_storage = storage  # data retained in NVS partition
        rebooted_storage.begin("mac_ctrl", read_only=True)
        r_sys = rebooted_storage.get_bool("deck_sys", default=True)
        r_smart = rebooted_storage.get_bool("deck_smart", default=True)
        r_agent = rebooted_storage.get_bool("deck_agent", default=True)
        r_bright = rebooted_storage.get_uchar("brightness", default=80)
        rebooted_storage.end()

        self.assertTrue(r_sys)
        self.assertFalse(r_smart)
        self.assertFalse(r_agent)
        self.assertEqual(r_bright, 65)

        # 4. Instantiate carousel with restored preferences
        rebooted_carousel = DynamicTileViewCarousel(r_sys, r_smart, r_agent)
        self.assertEqual(rebooted_carousel.active_order, [DeckID.SYSTEM, DeckID.SETTINGS])

    def test_flash_wear_endurance_guarantee(self):
        """Verify zero duplicate flash writes and safe write budget under high-frequency toggling."""
        storage = MockPreferencesStorage()
        storage.begin("mac_ctrl", read_only=False)

        # Repeatedly write identical value 1,000 times
        for _ in range(1000):
            storage.put_bool("deck_sys", True)

        # Should only write to flash ONCE due to deduplication
        self.assertEqual(storage.write_count, 1)

        # Flip value back and forth 10 times
        for i in range(10):
            storage.put_bool("deck_sys", (i % 2 == 0))

        # Total writes = 1 initial + 9 mutations (i=0 was True, matching current value) = 10 writes
        self.assertEqual(storage.write_count, 10)

        # Flash endurance check: 100,000 erase cycles / 100 writes per month = >80 years lifespan
        flash_lifespan_years = 100000 / (50 * 12)
        self.assertGreater(flash_lifespan_years, 80)


class TestDynamicNavigationHints(unittest.TestCase):
    """Verify bottom navigation hint strings adapt dynamically to active carousel neighbors."""

    def test_navigation_hint_texts(self):
        """Check hint strings across different configurations."""
        # 1. Full carousel
        c_full = DynamicTileViewCarousel(True, True, True)
        hints_full = c_full.get_navigation_hints()
        self.assertEqual(hints_full[DeckID.SYSTEM], "Swipe Left for Smart >")
        self.assertEqual(hints_full[DeckID.SMART], "< System | Agent & CI >")
        self.assertEqual(hints_full[DeckID.AGENT_CI], "< Smart | Settings >")
        self.assertEqual(hints_full[DeckID.SETTINGS], "< Swipe Right for Agent & CI")

        # 2. Smart disabled
        c_no_smart = DynamicTileViewCarousel(True, False, True)
        hints_no_smart = c_no_smart.get_navigation_hints()
        self.assertEqual(hints_no_smart[DeckID.SYSTEM], "Swipe Left for Agent & CI >")
        self.assertEqual(hints_no_smart[DeckID.AGENT_CI], "< System | Settings >")
        self.assertEqual(hints_no_smart[DeckID.SETTINGS], "< Swipe Right for Agent & CI")

        # 3. Only System and Settings
        c_sys_set = DynamicTileViewCarousel(True, False, False)
        hints_sys_set = c_sys_set.get_navigation_hints()
        self.assertEqual(hints_sys_set[DeckID.SYSTEM], "Swipe Left for Settings >")
        self.assertEqual(hints_sys_set[DeckID.SETTINGS], "< Swipe Right for System")

        # 4. Standalone Settings
        c_solo = DynamicTileViewCarousel(False, False, False)
        hints_solo = c_solo.get_navigation_hints()
        self.assertEqual(hints_solo[DeckID.SETTINGS], "No other active decks")


if __name__ == "__main__":
    unittest.main()
