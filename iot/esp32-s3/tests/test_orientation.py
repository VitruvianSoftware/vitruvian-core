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

"""Empirical test suite for Milestone 7: QMI8658 IMU Auto-Rotate.

Faithful Python models of the firmware logic in src/qmi8658.cpp,
src/touch_cst816t.cpp and src/ui.cpp:

1. Accelerometer vector classification (portrait vs inverted portrait vs hold).
2. Flat-on-desk deadband suppression (|Az| > 0.8g with quiet in-plane axes).
3. The 300ms debounce state machine, sampled at the firmware's 100ms cadence.
4. Touch coordinate remapping for rotations 0 and 2 with bounds guarantees.
5. Settings Deck NVS persistence (namespace 'settings', key 'auto_rotate').
"""

import itertools
import random
import unittest
from typing import Dict, Optional

# ---------------------------------------------------------------------------
# Constants mirrored from src/qmi8658.h -- keep in lockstep with the firmware.
# ---------------------------------------------------------------------------
LSB_PER_G = 8192            # +-4g full scale on a 16-bit accelerometer
FLAT_AZ_LSB = 6553          # 0.8g: dominant Z means the device lies flat
FLAT_XY_LSB = 2867          # 0.35g in-plane deadband while flat
ORIENT_TRIGGER_LSB = 4096   # 0.5g gravity projection required on Y
DEBOUNCE_MS = 300

ORIENT_PORTRAIT = 0         # USB connector down
ORIENT_INVERTED = 2         # USB connector up

LCD_WIDTH = 240
LCD_HEIGHT = 280

POLL_PERIOD_MS = 100        # main.cpp polls the classifier every 100ms


def classify_sample(ax: int, ay: int, az: int) -> Optional[int]:
    """Mirror of classify_sample() in qmi8658.cpp.

    Returns ORIENT_PORTRAIT / ORIENT_INVERTED, or None for "hold current"
    (flat on the desk, or gravity not clearly on the panel's long axis).
    """
    aax, aay, aaz = abs(ax), abs(ay), abs(az)

    # Flat-table suppression
    if aaz > FLAT_AZ_LSB and aax < FLAT_XY_LSB and aay < FLAT_XY_LSB:
        return None

    # Y must clear the trigger threshold AND dominate X
    if aay < ORIENT_TRIGGER_LSB or aay <= aax:
        return None

    return ORIENT_PORTRAIT if ay > 0 else ORIENT_INVERTED


class OrientationDebouncer:
    """Mirror of the qmi8658_get_orientation() state machine."""

    def __init__(self, initial: int = ORIENT_PORTRAIT):
        self.stable = initial
        self.tracking = False
        self.candidate = initial
        self.candidate_since_ms = 0

    def update(self, ax: int, ay: int, az: int, now_ms: int) -> int:
        candidate = classify_sample(ax, ay, az)
        if candidate is None or candidate == self.stable:
            # Flat/indeterminate samples and confirmations of the current
            # state both restart the debounce from scratch.
            self.tracking = False
            return self.stable

        if not self.tracking or self.candidate != candidate:
            self.tracking = True
            self.candidate = candidate
            self.candidate_since_ms = now_ms
            return self.stable

        if now_ms - self.candidate_since_ms >= DEBOUNCE_MS:
            self.stable = self.candidate
            self.tracking = False
        return self.stable


def touch_remap(raw_x: int, raw_y: int, rotation: int) -> Optional[tuple]:
    """Mirror of the rotation remap in touch_read() (touch_cst816t.cpp).

    Returns mapped (x, y), or None when the raw sample is rejected.
    """
    if raw_x >= LCD_WIDTH or raw_y >= LCD_HEIGHT or raw_x < 0 or raw_y < 0:
        return None

    mx, my = raw_x, raw_y
    if rotation == 2:
        mx = LCD_WIDTH - 1 - raw_x
        my = LCD_HEIGHT - 1 - raw_y

    # Defensive clamp (mirrors the firmware's belt-and-braces bound)
    mx = min(mx, LCD_WIDTH - 1)
    my = min(my, LCD_HEIGHT - 1)
    return (mx, my)


class MockPreferencesStorage:
    """Emulates the ESP32 Arduino Preferences library / NVS partition."""

    def __init__(self):
        self._namespaces: Dict[str, Dict[str, object]] = {}
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
        ns = self._namespaces.get(self._open_namespace or "", {})
        if key not in ns:
            return default
        return bool(ns[key])

    def put_bool(self, key: str, value: bool) -> bool:
        if not self._open_namespace:
            return False
        ns = self._namespaces[self._open_namespace]
        # Wear leveling: identical writes never touch flash
        if key in ns and ns[key] == value:
            return True
        ns[key] = value
        self._write_count += 1
        return True

    @property
    def write_count(self) -> int:
        return self._write_count


class AutoRotateSettingsCard:
    """Model of the DISPLAY ORIENTATION card's toggle logic (ui.cpp)."""

    NAMESPACE = "settings"
    KEY = "auto_rotate"

    def __init__(self, storage: MockPreferencesStorage):
        self.storage = storage
        self.display_rotation = ORIENT_PORTRAIT
        # ui_load_deck_preferences(): default OFF -> locked portrait
        self.storage.begin(self.NAMESPACE, read_only=True)
        self.enabled = self.storage.get_bool(self.KEY, default=False)
        self.storage.end()

    def toggle(self, checked: bool):
        self.enabled = checked
        self.storage.begin(self.NAMESPACE, read_only=False)
        self.storage.put_bool(self.KEY, checked)
        self.storage.end()
        if not checked:
            # sw_auto_rotate_toggle_cb: restore default rotation immediately
            self.display_rotation = ORIENT_PORTRAIT

    def status_label(self, imu_present: bool = True) -> str:
        if not self.enabled:
            return "Locked: Portrait (0°)"
        if not imu_present:
            return "Auto-Rotate: IMU not detected"
        return "Auto-Rotate: Enabled (QMI8658)"


# Convenience gravity vectors (raw LSB at +-4g)
G = LSB_PER_G
USB_DOWN = (0, G, 0)          # upright portrait: +Y reads +1g
USB_UP = (0, -G, 0)           # inverted portrait
FLAT_FACE_UP = (0, 0, G)      # lying on the desk, screen up
FLAT_FACE_DOWN = (0, 0, -G)   # screen down
LANDSCAPE = (G, 0, 0)         # on its side: X dominates, must hold


class TestVectorClassification(unittest.TestCase):
    """1. Pure accelerometer vector classification."""

    def test_cardinal_orientations(self):
        self.assertEqual(classify_sample(*USB_DOWN), ORIENT_PORTRAIT)
        self.assertEqual(classify_sample(*USB_UP), ORIENT_INVERTED)
        self.assertIsNone(classify_sample(*FLAT_FACE_UP))
        self.assertIsNone(classify_sample(*FLAT_FACE_DOWN))
        self.assertIsNone(classify_sample(*LANDSCAPE))
        self.assertIsNone(classify_sample(-G, 0, 0))

    def test_tilted_desk_stand_angles(self):
        """A 35-45° desk stand still reads as upright portrait."""
        # 40° tilt: Ay = g*cos(40°) ~ 0.766g, Az = g*sin(40°) ~ 0.643g
        ay = int(0.766 * G)
        az = int(0.643 * G)
        self.assertEqual(classify_sample(0, ay, az), ORIENT_PORTRAIT)
        self.assertEqual(classify_sample(0, -ay, az), ORIENT_INVERTED)

    def test_trigger_threshold_boundary(self):
        """Y projection below 0.5g never produces a candidate."""
        self.assertIsNone(classify_sample(0, ORIENT_TRIGGER_LSB - 1, 0))
        self.assertEqual(
            classify_sample(0, ORIENT_TRIGGER_LSB, 0), ORIENT_PORTRAIT
        )
        self.assertEqual(
            classify_sample(0, -ORIENT_TRIGGER_LSB, 0), ORIENT_INVERTED
        )

    def test_x_dominance_guard(self):
        """When X pull >= Y pull (diagonal/landscape lean), hold."""
        self.assertIsNone(classify_sample(6000, 5000, 0))
        self.assertEqual(classify_sample(4000, 5000, 0), ORIENT_PORTRAIT)
        self.assertIsNone(classify_sample(5000, -5000, 0))
        self.assertEqual(classify_sample(-4000, -5000, 0), ORIENT_INVERTED)

    def test_zero_and_noise_vectors(self):
        """Free-fall / noise-floor samples never classify."""
        self.assertIsNone(classify_sample(0, 0, 0))
        self.assertIsNone(classify_sample(100, -80, 120))


class TestFlatTableDeadband(unittest.TestCase):
    """2. Flat-on-desk suppression: |Az| > 0.8g with quiet in-plane axes."""

    def test_flat_thresholds(self):
        # Exactly at the Az threshold: NOT flat (strict >), but Y is quiet so
        # the sample is indeterminate either way -> hold.
        self.assertIsNone(classify_sample(0, 0, FLAT_AZ_LSB))
        self.assertIsNone(classify_sample(0, 0, FLAT_AZ_LSB + 1))
        self.assertIsNone(classify_sample(0, 0, -(FLAT_AZ_LSB + 1)))

    def test_flat_with_in_plane_noise_holds_current(self):
        """Small Ax/Ay jitter while flat must never flip orientation."""
        deb = OrientationDebouncer(initial=ORIENT_INVERTED)
        rng = random.Random(26145)
        now = 0
        for _ in range(500):
            now += POLL_PERIOD_MS
            ay = rng.randint(-(FLAT_XY_LSB - 1), FLAT_XY_LSB - 1)
            ax = rng.randint(-(FLAT_XY_LSB - 1), FLAT_XY_LSB - 1)
            az = rng.choice([1, -1]) * rng.randint(FLAT_AZ_LSB + 1, G)
            self.assertEqual(deb.update(ax, ay, az, now), ORIENT_INVERTED)

    def test_strong_y_beats_flat_deadband(self):
        """A firm Y pull outside the deadband classifies even with big Az."""
        # Steep-but-not-flat: Ay 0.55g, Az 0.83g -> Az dominant but Ay is
        # outside the in-plane deadband, so the flat suppression does not
        # apply and Y still classifies.
        ay = int(0.55 * G)
        az = int(0.83 * G)
        self.assertEqual(classify_sample(0, ay, az), ORIENT_PORTRAIT)

    def test_pick_up_from_desk_then_rotate(self):
        """Flat -> picked up USB-up -> orientation flips after debounce."""
        deb = OrientationDebouncer(initial=ORIENT_PORTRAIT)
        now = 0
        for _ in range(20):  # 2s flat on the desk
            now += POLL_PERIOD_MS
            self.assertEqual(deb.update(*FLAT_FACE_UP, now), ORIENT_PORTRAIT)
        for _ in range(3):   # 300ms of USB-up: t+100..t+300
            now += POLL_PERIOD_MS
            deb.update(*USB_UP, now)
        # 4th consecutive sample crosses the 300ms window
        now += POLL_PERIOD_MS
        self.assertEqual(deb.update(*USB_UP, now), ORIENT_INVERTED)


class TestDebounceStateMachine(unittest.TestCase):
    """3. The 300ms debounce, sampled on the firmware's 100ms poll grid."""

    def _feed(self, deb, sample, count, start_ms):
        now = start_ms
        result = deb.stable
        for _ in range(count):
            now += POLL_PERIOD_MS
            result = deb.update(*sample, now)
        return result, now

    def test_short_transient_is_ignored(self):
        """USB-up held < 300ms then back: no flip."""
        deb = OrientationDebouncer()
        result, now = self._feed(deb, USB_UP, 3, 0)  # spans 200ms of tracking
        self.assertEqual(result, ORIENT_PORTRAIT)
        result, _ = self._feed(deb, USB_DOWN, 5, now)
        self.assertEqual(result, ORIENT_PORTRAIT)

    def test_sustained_candidate_flips_after_300ms(self):
        deb = OrientationDebouncer()
        # Samples at t=100..300: tracking starts at 100, 300-100=200 < 300
        result, now = self._feed(deb, USB_UP, 3, 0)
        self.assertEqual(result, ORIENT_PORTRAIT)
        # t=400: 400-100=300 >= 300 -> flip
        result, now = self._feed(deb, USB_UP, 1, now)
        self.assertEqual(result, ORIENT_INVERTED)
        # And back again
        result, now = self._feed(deb, USB_DOWN, 4, now)
        self.assertEqual(result, ORIENT_PORTRAIT)

    def test_interruption_resets_the_window(self):
        """Candidate -> hold sample -> candidate must restart the 300ms."""
        deb = OrientationDebouncer()
        _, now = self._feed(deb, USB_UP, 2, 0)
        _, now = self._feed(deb, FLAT_FACE_UP, 1, now)  # resets tracking
        result, now = self._feed(deb, USB_UP, 3, now)
        self.assertEqual(result, ORIENT_PORTRAIT)  # only 200ms since restart
        result, now = self._feed(deb, USB_UP, 1, now)
        self.assertEqual(result, ORIENT_INVERTED)

    def test_confirming_current_orientation_resets_tracking(self):
        deb = OrientationDebouncer()
        _, now = self._feed(deb, USB_UP, 3, 0)
        _, now = self._feed(deb, USB_DOWN, 1, now)  # confirms current
        result, now = self._feed(deb, USB_UP, 3, now)
        self.assertEqual(result, ORIENT_PORTRAIT)
        result, _ = self._feed(deb, USB_UP, 1, now)
        self.assertEqual(result, ORIENT_INVERTED)

    def test_oscillating_noise_never_flips(self):
        """Alternating candidates each restart tracking: no flip, ever."""
        deb = OrientationDebouncer()
        now = 0
        for i in range(1000):
            now += POLL_PERIOD_MS
            sample = USB_UP if i % 2 == 0 else USB_DOWN
            self.assertEqual(deb.update(*sample, now), ORIENT_PORTRAIT)

    def test_slow_poll_still_debounces(self):
        """Even at a degraded 250ms cadence the window math holds."""
        deb = OrientationDebouncer()
        self.assertEqual(deb.update(*USB_UP, 250), ORIENT_PORTRAIT)
        self.assertEqual(deb.update(*USB_UP, 500), ORIENT_PORTRAIT)  # 250 < 300
        self.assertEqual(deb.update(*USB_UP, 750), ORIENT_INVERTED)  # 500 >= 300

    def test_millis_wraparound_safe_semantics(self):
        """Unsigned elapsed-time subtraction survives near-wrap timestamps."""
        # The firmware computes (now - since) in unsigned arithmetic; the
        # model uses Python ints, so emulate the wrap by masking to 32 bits.
        u32 = 0xFFFFFFFF
        since = u32 - 100  # 100ms before the 32-bit millis() wrap
        for elapsed, expect_flip in ((200, False), (300, True)):
            now = (since + elapsed) & u32
            self.assertEqual(
                ((now - since) & u32) >= DEBOUNCE_MS,
                expect_flip,
                f"elapsed={elapsed}",
            )


class TestTouchCoordinateRemap(unittest.TestCase):
    """4. Touch transform math for rotations 0 and 2."""

    def test_rotation0_is_identity(self):
        for x, y in [(0, 0), (239, 279), (120, 140), (17, 233)]:
            self.assertEqual(touch_remap(x, y, 0), (x, y))

    def test_rotation2_mirrors_both_axes(self):
        self.assertEqual(touch_remap(0, 0, 2), (239, 279))
        self.assertEqual(touch_remap(239, 279, 2), (0, 0))
        self.assertEqual(touch_remap(120, 140, 2), (119, 139))
        self.assertEqual(touch_remap(10, 260, 2), (229, 19))

    def test_rotation2_is_an_involution(self):
        """Applying the 180° map twice returns the original point."""
        for x, y in itertools.product(range(0, 240, 7), range(0, 280, 9)):
            mx, my = touch_remap(x, y, 2)
            self.assertEqual(touch_remap(mx, my, 2), (x, y))

    def test_bounds_all_valid_inputs_stay_onscreen(self):
        for rotation in (0, 2):
            for x, y in itertools.product(range(0, 240, 13), range(0, 280, 11)):
                mx, my = touch_remap(x, y, rotation)
                self.assertTrue(0 <= mx < LCD_WIDTH)
                self.assertTrue(0 <= my < LCD_HEIGHT)

    def test_out_of_range_raw_rejected_before_remap(self):
        self.assertIsNone(touch_remap(240, 0, 2))
        self.assertIsNone(touch_remap(0, 280, 2))
        self.assertIsNone(touch_remap(4095, 4095, 0))


class TestSettingsPersistence(unittest.TestCase):
    """5. Settings Deck NVS persistence: namespace 'settings', key 'auto_rotate'."""

    def test_default_is_locked_portrait(self):
        card = AutoRotateSettingsCard(MockPreferencesStorage())
        self.assertFalse(card.enabled)
        self.assertEqual(card.status_label(), "Locked: Portrait (0°)")

    def test_roundtrip_survives_power_cycle(self):
        storage = MockPreferencesStorage()
        card = AutoRotateSettingsCard(storage)
        card.toggle(True)
        self.assertEqual(card.status_label(), "Auto-Rotate: Enabled (QMI8658)")

        # Power cycle: same NVS partition, fresh UI state
        rebooted = AutoRotateSettingsCard(storage)
        self.assertTrue(rebooted.enabled)

        rebooted.toggle(False)
        rebooted_again = AutoRotateSettingsCard(storage)
        self.assertFalse(rebooted_again.enabled)

    def test_toggle_off_restores_portrait_immediately(self):
        card = AutoRotateSettingsCard(MockPreferencesStorage())
        card.toggle(True)
        card.display_rotation = ORIENT_INVERTED  # IMU rotated the panel
        card.toggle(False)
        self.assertEqual(card.display_rotation, ORIENT_PORTRAIT)

    def test_missing_imu_label(self):
        card = AutoRotateSettingsCard(MockPreferencesStorage())
        card.toggle(True)
        self.assertEqual(
            card.status_label(imu_present=False), "Auto-Rotate: IMU not detected"
        )

    def test_namespace_and_key_do_not_collide(self):
        """auto_rotate shares 'settings' with chimes_muted without clashes."""
        storage = MockPreferencesStorage()
        storage.begin("settings")
        storage.put_bool("chimes_muted", True)
        storage.end()

        card = AutoRotateSettingsCard(storage)
        card.toggle(True)

        storage.begin("settings", read_only=True)
        self.assertTrue(storage.get_bool("chimes_muted"))
        self.assertTrue(storage.get_bool("auto_rotate"))
        storage.end()

    def test_flash_wear_dedup(self):
        storage = MockPreferencesStorage()
        card = AutoRotateSettingsCard(storage)
        for _ in range(100):
            card.toggle(True)  # 99 duplicate writes deduplicated
        self.assertEqual(storage.write_count, 1)
        card.toggle(False)
        self.assertEqual(storage.write_count, 2)


class TestEndToEndRotationFlow(unittest.TestCase):
    """Integration: settings toggle + debouncer + touch remap in one walk."""

    def test_full_flip_and_lock_scenario(self):
        storage = MockPreferencesStorage()
        card = AutoRotateSettingsCard(storage)
        deb = OrientationDebouncer()
        now = 0

        def poll(sample):
            nonlocal now
            now += POLL_PERIOD_MS
            if card.enabled:  # main.cpp gates the poll on the toggle
                card.display_rotation = deb.update(*sample, now)

        # Auto-rotate off: physically inverting the device changes nothing
        for _ in range(10):
            poll(USB_UP)
        self.assertEqual(card.display_rotation, ORIENT_PORTRAIT)

        # Enable, still held USB-up: flips after the debounce window
        card.toggle(True)
        deb = OrientationDebouncer()  # firmware state machine, fresh candidate
        for _ in range(4):
            poll(USB_UP)
        self.assertEqual(card.display_rotation, ORIENT_INVERTED)

        # Touch now runs through the inverted map
        self.assertEqual(touch_remap(0, 0, card.display_rotation), (239, 279))

        # Lay it flat: orientation is retained
        for _ in range(50):
            poll(FLAT_FACE_UP)
        self.assertEqual(card.display_rotation, ORIENT_INVERTED)

        # Toggle off -> instant portrait lock regardless of the IMU
        card.toggle(False)
        self.assertEqual(card.display_rotation, ORIENT_PORTRAIT)
        self.assertEqual(touch_remap(0, 0, card.display_rotation), (0, 0))


if __name__ == "__main__":
    unittest.main()
