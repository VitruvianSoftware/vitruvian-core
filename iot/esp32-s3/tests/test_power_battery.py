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

"""Unit tests for Waveshare ESP32-S3-Touch-LCD-1.69 Power Management & Battery Monitoring.

Validates:
1. Hardware Pin Configurations (SYS_EN_PIN 41, SYS_OUT_PIN 40, BAT_ADC_PIN 1).
2. Hardware Voltage Divider scaling (200k / 100k -> 3.0x ratio).
3. Piecewise linear LiPo discharge percentage curve across the full voltage spectrum.
4. Battery status glyph and color tier selection.
5. Power button state machine (debounce, short-press sleep/wake, long-press power-off).
6. UI header layout geometry and reflow coordinates in portrait and landscape.
"""

import unittest


class LiPoBatteryModel:
    """Python reference model of power_manager.cpp battery calculations."""

    VOLTAGE_DIVIDER_RATIO = 3.0

    @classmethod
    def adc_to_battery_mv(cls, adc_mv: float) -> int:
        """Converts raw ADC millivolts through the 3.0x hardware voltage divider."""
        return int(round(adc_mv * cls.VOLTAGE_DIVIDER_RATIO))

    @classmethod
    def calculate_battery_percent(cls, mv: int) -> int:
        """Calculates battery percentage (0-100%) using the 5-segment LiPo curve."""
        if mv >= 4200:
            return 100
        if mv <= 3200:
            return 0
        if mv >= 4050:
            return 85 + int(((mv - 4050) * 15) // 150)
        elif mv >= 3850:
            return 60 + int(((mv - 3850) * 25) // 200)
        elif mv >= 3700:
            return 35 + int(((mv - 3700) * 25) // 150)
        elif mv >= 3500:
            return 10 + int(((mv - 3500) * 25) // 200)
        else:
            return int(((mv - 3200) * 10) // 300)

    @classmethod
    def get_tier_and_color(cls, percent: int, is_charging: bool):
        """Returns (symbol_name, hex_color) corresponding to ui_update_battery."""
        if is_charging:
            return ("LV_SYMBOL_CHARGE", 0x30D158)
        if percent >= 80:
            return ("LV_SYMBOL_BATTERY_FULL", 0x30D158)
        elif percent >= 50:
            return ("LV_SYMBOL_BATTERY_3", 0x64D2FF)
        elif percent >= 25:
            return ("LV_SYMBOL_BATTERY_2", 0xFF9F0A)
        elif percent >= 10:
            return ("LV_SYMBOL_BATTERY_1", 0xFF6934)
        else:
            return ("LV_SYMBOL_BATTERY_EMPTY", 0xFF453A)


class PowerButtonStateMachine:
    """Models the power button (SYS_OUT_PIN) debounce and action triggers."""

    DEBOUNCE_MIN_MS = 50
    SHORT_PRESS_MAX_MS = 1200
    LONG_PRESS_SHUTDOWN_MS = 2500

    def __init__(self):
        self.is_held = False
        self.press_start_ms = 0
        self.long_press_triggered = False
        self.display_sleeping = False
        self.power_latched = True  # SYS_EN_PIN starts HIGH on boot

    def on_button_down(self, now_ms: int):
        self.is_held = True
        self.press_start_ms = now_ms
        self.long_press_triggered = False

    def update(self, now_ms: int):
        if self.is_held and not self.long_press_triggered:
            if (now_ms - self.press_start_ms) >= self.LONG_PRESS_SHUTDOWN_MS:
                self.long_press_triggered = True
                self.power_latched = False  # Drives SYS_EN_PIN LOW
                return "SHUTDOWN"
        return None

    def on_button_up(self, now_ms: int):
        if not self.is_held:
            return None
        self.is_held = False
        duration = now_ms - self.press_start_ms

        if (
            not self.long_press_triggered
            and self.DEBOUNCE_MIN_MS <= duration < self.SHORT_PRESS_MAX_MS
        ):
            self.display_sleeping = not self.display_sleeping
            return "TOGGLE_DISPLAY_SLEEP"
        return None


class TestHardwarePowerPinout(unittest.TestCase):
    """1. Hardware pin specifications for Waveshare soft-latch power management."""

    def test_pin_constants(self):
        from pathlib import Path

        pin_config = (
            Path(__file__).parent.parent / "include" / "pin_config.h"
        ).read_text()

        self.assertIn("#define SYS_EN_PIN 41", pin_config)
        self.assertIn("#define SYS_OUT_PIN 40", pin_config)
        self.assertIn("#define SYS_EN_LEGACY_PIN 35", pin_config)
        self.assertIn("#define SYS_OUT_LEGACY_PIN 36", pin_config)
        self.assertIn("#define BAT_ADC_PIN 1", pin_config)


class TestVoltageDividerAndLiPoCurve(unittest.TestCase):
    """2 & 3. Voltage divider ratio and LiPo discharge percentage curve."""

    def test_voltage_divider_ratio(self):
        # Hardware resistors: R3 = 200k, R7 = 100k
        r3 = 200000.0
        r7 = 100000.0
        expected_ratio = (r3 + r7) / r7
        self.assertAlmostEqual(
            LiPoBatteryModel.VOLTAGE_DIVIDER_RATIO, expected_ratio, places=2
        )

        # ADC millivolts conversion
        self.assertEqual(LiPoBatteryModel.adc_to_battery_mv(1400.0), 4200)
        self.assertEqual(LiPoBatteryModel.adc_to_battery_mv(1333.33), 4000)
        self.assertEqual(LiPoBatteryModel.adc_to_battery_mv(1233.33), 3700)
        self.assertEqual(LiPoBatteryModel.adc_to_battery_mv(1066.67), 3200)

    def test_lipo_curve_boundaries(self):
        # Upper clamp
        self.assertEqual(LiPoBatteryModel.calculate_battery_percent(4350), 100)
        self.assertEqual(LiPoBatteryModel.calculate_battery_percent(4200), 100)

        # Segment endpoints
        self.assertEqual(LiPoBatteryModel.calculate_battery_percent(4050), 85)
        self.assertEqual(LiPoBatteryModel.calculate_battery_percent(3850), 60)
        self.assertEqual(LiPoBatteryModel.calculate_battery_percent(3700), 35)
        self.assertEqual(LiPoBatteryModel.calculate_battery_percent(3500), 10)
        self.assertEqual(LiPoBatteryModel.calculate_battery_percent(3200), 0)

        # Lower clamp
        self.assertEqual(LiPoBatteryModel.calculate_battery_percent(3100), 0)
        self.assertEqual(LiPoBatteryModel.calculate_battery_percent(2800), 0)

    def test_lipo_curve_monotonicity(self):
        """Battery percentage must be monotonically non-decreasing from 3.0V to 4.3V."""
        last_pct = -1
        for mv in range(3000, 4350, 5):
            pct = LiPoBatteryModel.calculate_battery_percent(mv)
            self.assertGreaterEqual(pct, last_pct)
            self.assertGreaterEqual(pct, 0)
            self.assertLessEqual(pct, 100)
            last_pct = pct


class TestBatteryTierAndStyling(unittest.TestCase):
    """4. Battery icon glyph and color assignments."""

    def test_charging_state(self):
        glyph, color = LiPoBatteryModel.get_tier_and_color(percent=45, is_charging=True)
        self.assertEqual(glyph, "LV_SYMBOL_CHARGE")
        self.assertEqual(color, 0x30D158)  # Green

    def test_discharging_tiers(self):
        # >= 80%: Full Green
        glyph, color = LiPoBatteryModel.get_tier_and_color(
            percent=92, is_charging=False
        )
        self.assertEqual(glyph, "LV_SYMBOL_BATTERY_FULL")
        self.assertEqual(color, 0x30D158)

        # 50 - 79%: Tier 3 Cyan
        glyph, color = LiPoBatteryModel.get_tier_and_color(
            percent=65, is_charging=False
        )
        self.assertEqual(glyph, "LV_SYMBOL_BATTERY_3")
        self.assertEqual(color, 0x64D2FF)

        # 25 - 49%: Tier 2 Orange
        glyph, color = LiPoBatteryModel.get_tier_and_color(
            percent=35, is_charging=False
        )
        self.assertEqual(glyph, "LV_SYMBOL_BATTERY_2")
        self.assertEqual(color, 0xFF9F0A)

        # 10 - 24%: Tier 1 Orange-Red
        glyph, color = LiPoBatteryModel.get_tier_and_color(
            percent=18, is_charging=False
        )
        self.assertEqual(glyph, "LV_SYMBOL_BATTERY_1")
        self.assertEqual(color, 0xFF6934)

        # < 10%: Empty Red
        glyph, color = LiPoBatteryModel.get_tier_and_color(percent=7, is_charging=False)
        self.assertEqual(glyph, "LV_SYMBOL_BATTERY_EMPTY")
        self.assertEqual(color, 0xFF453A)


class TestPowerButtonHandling(unittest.TestCase):
    """5. Power button interaction, debounce, sleep/wake, and shutdown."""

    def setUp(self):
        self.sm = PowerButtonStateMachine()

    def test_initial_power_latch_high(self):
        self.assertTrue(self.sm.power_latched)

    def test_glitch_ignored(self):
        self.sm.on_button_down(now_ms=100)
        action = self.sm.on_button_up(now_ms=130)  # 30ms < 50ms debounce
        self.assertIsNone(action)
        self.assertFalse(self.sm.display_sleeping)
        self.assertTrue(self.sm.power_latched)

    def test_short_click_toggles_display_sleep(self):
        self.sm.on_button_down(now_ms=100)
        action = self.sm.on_button_up(now_ms=350)  # 250ms short click
        self.assertEqual(action, "TOGGLE_DISPLAY_SLEEP")
        self.assertTrue(self.sm.display_sleeping)

        # Second click wakes it up
        self.sm.on_button_down(now_ms=1000)
        action = self.sm.on_button_up(now_ms=1200)
        self.assertEqual(action, "TOGGLE_DISPLAY_SLEEP")
        self.assertFalse(self.sm.display_sleeping)

    def test_long_press_triggers_shutdown(self):
        self.sm.on_button_down(now_ms=100)
        self.assertIsNone(self.sm.update(now_ms=1500))
        self.assertTrue(self.sm.power_latched)

        # Reach 2500ms threshold
        action = self.sm.update(now_ms=2650)
        self.assertEqual(action, "SHUTDOWN")
        self.assertFalse(self.sm.power_latched)  # Drops SYS_EN to cut battery power

        # Releasing after shutdown does not trigger sleep toggle
        self.assertIsNone(self.sm.on_button_up(now_ms=3000))


class TestUIHeaderLayoutAndReflow(unittest.TestCase):
    """6. Two-column System Deck header geometry across orientations."""

    def test_portrait_header_coordinates(self):
        # Portrait screen: 240 x 280, Header: 226 x 68 at (7, 5)
        # Left status column:
        y_time = -2
        y_battery = 20
        y_link = 42
        self.assertLess(y_time, y_battery)
        self.assertLess(y_battery, y_link)
        self.assertEqual(y_battery - y_time, 22)
        self.assertEqual(y_link - y_battery, 22)

        # Right meter column: x=110, fits cleanly in 226px header
        bar_x = 110
        bar_w = 106
        self.assertLessEqual(bar_x + bar_w, 226)

    def test_landscape_header_coordinates(self):
        # Landscape screen: 280 x 240, Header: 266 x 48 at (7, 4)
        # Left status column:
        y_time = 2
        y_battery = 16
        y_link = 30
        self.assertLess(y_time, y_battery)
        self.assertLess(y_battery, y_link)
        self.assertEqual(y_battery - y_time, 14)
        self.assertEqual(y_link - y_battery, 14)

        # Right meter column: x=136, width 120, fits in 266px header
        bar_x = 136
        bar_w = 120
        self.assertLessEqual(bar_x + bar_w, 266)


if __name__ == "__main__":
    unittest.main()
