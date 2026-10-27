// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

//! Rust migration of `test_orientation.py`:
//! QMI8658 IMU orientation detection, 300ms hysteresis debounce, CST816S touch coordinate
//! remapping across rotations 0..=3, NVS persistence, and portrait/landscape UI reflow.

use crate::XorShift64;
use std::collections::BTreeMap;

pub const LSB_PER_G: i32 = 8192;
pub const FLAT_AZ_LSB: i32 = 6553;
pub const FLAT_XY_LSB: i32 = 2867;
pub const ORIENT_TRIGGER_LSB: i32 = 4096;
pub const DEBOUNCE_MS: u32 = 300;

pub const ORIENT_PORTRAIT: u8 = 0;
pub const ORIENT_LANDSCAPE_CW: u8 = 1;
pub const ORIENT_PORTRAIT_INVERTED: u8 = 2;
pub const ORIENT_LANDSCAPE_CCW: u8 = 3;

pub const NATIVE_W: i32 = 240;
pub const NATIVE_H: i32 = 280;

pub fn classify_accel(ax: i32, ay: i32, az: i32, current_orient: u8) -> u8 {
    let abs_ax = ax.abs();
    let abs_ay = ay.abs();
    let abs_az = az.abs();

    if abs_az > FLAT_AZ_LSB && abs_ax < FLAT_XY_LSB && abs_ay < FLAT_XY_LSB {
        return current_orient;
    }

    if abs_ay >= abs_ax && abs_ay > ORIENT_TRIGGER_LSB {
        if ay < 0 {
            ORIENT_PORTRAIT
        } else {
            ORIENT_PORTRAIT_INVERTED
        }
    } else if abs_ax > abs_ay && abs_ax > ORIENT_TRIGGER_LSB {
        if ax > 0 {
            ORIENT_LANDSCAPE_CW
        } else {
            ORIENT_LANDSCAPE_CCW
        }
    } else {
        current_orient
    }
}

pub struct OrientationDebouncer {
    pub current: u8,
    pub candidate: u8,
    pub candidate_since_ms: u32,
    pub auto_rotate: bool,
}

impl OrientationDebouncer {
    pub fn new(initial: u8, auto_rotate: bool) -> Self {
        Self {
            current: initial,
            candidate: initial,
            candidate_since_ms: 0,
            auto_rotate,
        }
    }

    pub fn step(&mut self, ax: i32, ay: i32, az: i32, now_ms: u32) -> (u8, bool) {
        if !self.auto_rotate {
            return (self.current, false);
        }
        let detected = classify_accel(ax, ay, az, self.current);
        if detected != self.candidate {
            self.candidate = detected;
            self.candidate_since_ms = now_ms;
            return (self.current, false);
        }
        let elapsed = now_ms.wrapping_sub(self.candidate_since_ms);
        if self.candidate != self.current && elapsed >= DEBOUNCE_MS {
            self.current = self.candidate;
            return (self.current, true);
        }
        (self.current, false)
    }
}

pub fn touch_remap(raw_x: i32, raw_y: i32, rotation: u8) -> Option<(i32, i32)> {
    if !(0..NATIVE_W).contains(&raw_x) || !(0..NATIVE_H).contains(&raw_y) {
        return None;
    }
    match rotation {
        ORIENT_PORTRAIT => Some((raw_x, raw_y)),
        ORIENT_LANDSCAPE_CW => Some((raw_y, (NATIVE_W - 1) - raw_x)),
        ORIENT_PORTRAIT_INVERTED => Some(((NATIVE_W - 1) - raw_x, (NATIVE_H - 1) - raw_y)),
        ORIENT_LANDSCAPE_CCW => Some(((NATIVE_H - 1) - raw_y, raw_x)),
        _ => None,
    }
}

pub fn logical_dimensions(rotation: u8) -> (i32, i32) {
    if rotation == ORIENT_PORTRAIT || rotation == ORIENT_PORTRAIT_INVERTED {
        (NATIVE_W, NATIVE_H)
    } else {
        (NATIVE_H, NATIVE_W)
    }
}

pub struct MockNvs {
    pub store: BTreeMap<(String, String), u8>,
    pub write_count: usize,
}

impl MockNvs {
    pub fn new() -> Self {
        Self {
            store: BTreeMap::new(),
            write_count: 0,
        }
    }

    pub fn get_uchar(&self, ns: &str, key: &str, default: u8) -> u8 {
        *self
            .store
            .get(&(ns.to_string(), key.to_string()))
            .unwrap_or(&default)
    }

    pub fn put_uchar(&mut self, ns: &str, key: &str, val: u8) {
        let k = (ns.to_string(), key.to_string());
        if self.store.get(&k) != Some(&val) {
            self.store.insert(k, val);
            self.write_count += 1;
        }
    }
}

pub fn test_qmi8658_gravity_classification() {
    assert_eq!(
        classify_accel(0, -LSB_PER_G, 0, ORIENT_LANDSCAPE_CW),
        ORIENT_PORTRAIT
    );
    assert_eq!(
        classify_accel(0, LSB_PER_G, 0, ORIENT_PORTRAIT),
        ORIENT_PORTRAIT_INVERTED
    );
    assert_eq!(
        classify_accel(LSB_PER_G, 0, 0, ORIENT_PORTRAIT),
        ORIENT_LANDSCAPE_CW
    );
    assert_eq!(
        classify_accel(-LSB_PER_G, 0, 0, ORIENT_PORTRAIT),
        ORIENT_LANDSCAPE_CCW
    );

    let mut rng = XorShift64::new(7);
    for current in [
        ORIENT_PORTRAIT,
        ORIENT_LANDSCAPE_CW,
        ORIENT_PORTRAIT_INVERTED,
        ORIENT_LANDSCAPE_CCW,
    ] {
        for _ in 0..500 {
            let ax = rng.gen_range_i32(-2500, 2501);
            let ay = rng.gen_range_i32(-2500, 2501);
            let az = if (rng.next_u64() & 1) == 0 { 1 } else { -1 } * rng.gen_range_i32(6600, 9001);
            assert_eq!(classify_accel(ax, ay, az, current), current);
        }
    }
}

pub fn test_debounce_hysteresis_and_wraparound() {
    let mut d = OrientationDebouncer::new(ORIENT_PORTRAIT, true);
    for t in (0..300).step_by(20) {
        let (orient, changed) = d.step(LSB_PER_G, 0, 0, t);
        assert_eq!(orient, ORIENT_PORTRAIT);
        assert!(!changed);
    }
    let (orient, changed) = d.step(LSB_PER_G, 0, 0, 300);
    assert_eq!(orient, ORIENT_LANDSCAPE_CW);
    assert!(changed);

    // 32-bit millis() wraparound
    let mut dw = OrientationDebouncer::new(ORIENT_PORTRAIT, true);
    let t_start: u32 = 0xFFFF_FF50;
    let (_, ch1) = dw.step(LSB_PER_G, 0, 0, t_start);
    assert!(!ch1);
    let t_end = t_start.wrapping_add(DEBOUNCE_MS);
    let (orient_w, ch2) = dw.step(LSB_PER_G, 0, 0, t_end);
    assert!(ch2);
    assert_eq!(orient_w, ORIENT_LANDSCAPE_CW);
}

pub fn test_touch_coordinate_remapping() {
    for x in (0..NATIVE_W).step_by(17) {
        for y in (0..NATIVE_H).step_by(19) {
            assert_eq!(touch_remap(x, y, ORIENT_PORTRAIT), Some((x, y)));
            let (ix, iy) = touch_remap(x, y, ORIENT_PORTRAIT_INVERTED).unwrap();
            assert_eq!(touch_remap(ix, iy, ORIENT_PORTRAIT_INVERTED), Some((x, y)));
        }
    }
    assert_eq!(touch_remap(0, 0, ORIENT_LANDSCAPE_CW), Some((0, 239)));
    assert_eq!(touch_remap(239, 0, ORIENT_LANDSCAPE_CW), Some((0, 0)));
    assert_eq!(touch_remap(0, 279, ORIENT_LANDSCAPE_CW), Some((279, 239)));
    assert_eq!(touch_remap(239, 279, ORIENT_LANDSCAPE_CW), Some((279, 0)));

    assert_eq!(touch_remap(0, 0, ORIENT_LANDSCAPE_CCW), Some((279, 0)));
    assert_eq!(touch_remap(239, 279, ORIENT_LANDSCAPE_CCW), Some((0, 239)));

    assert!(touch_remap(-1, 10, ORIENT_PORTRAIT).is_none());
    assert!(touch_remap(240, 10, ORIENT_PORTRAIT).is_none());
    assert!(touch_remap(10, 280, ORIENT_PORTRAIT).is_none());
    assert!(touch_remap(10, 10, 4).is_none());

    assert_eq!(logical_dimensions(ORIENT_PORTRAIT), (240, 280));
    assert_eq!(logical_dimensions(ORIENT_LANDSCAPE_CW), (280, 240));
}

pub fn test_nvs_persistence_and_wear_dedup() {
    let mut nvs = MockNvs::new();
    assert_eq!(nvs.get_uchar("deck_cfg", "auto_rot", 1), 1);
    nvs.put_uchar("deck_cfg", "auto_rot", 0);
    nvs.put_uchar("deck_cfg", "auto_rot", 0);
    assert_eq!(nvs.write_count, 1);
    assert_eq!(nvs.get_uchar("deck_cfg", "auto_rot", 1), 0);

    // Coexistence with chimes_muted in settings namespace
    nvs.put_uchar("settings", "chimes_muted", 1);
    nvs.put_uchar("settings", "auto_rotate", 0);
    assert_eq!(nvs.get_uchar("settings", "chimes_muted", 0), 1);
    assert_eq!(nvs.get_uchar("settings", "auto_rotate", 1), 0);

    // Auto-Rotate Settings card status label states
    let status_text = |auto_rotate: bool, imu_ready: bool| -> &'static str {
        if !auto_rotate {
            "Locked: Portrait (0°)"
        } else if imu_ready {
            "Auto-Rotate: Enabled (QMI8658)"
        } else {
            "Auto-Rotate: IMU not detected"
        }
    };
    assert_eq!(status_text(true, true), "Auto-Rotate: Enabled (QMI8658)");
    assert_eq!(status_text(true, false), "Auto-Rotate: IMU not detected");
    assert_eq!(status_text(false, true), "Locked: Portrait (0°)");

    // Landscape 3x2 grid symmetry and settings card centering
    let bw = 84;
    let xs = [7, 98, 189];
    let margin_left = xs[0];
    let gap01 = xs[1] - (xs[0] + bw);
    let gap12 = xs[2] - (xs[1] + bw);
    let margin_right = 280 - (xs[2] + bw);
    assert_eq!(margin_left, 7);
    assert_eq!(gap01, 7);
    assert_eq!(gap12, 7);
    assert_eq!(margin_right, 7);

    let card_x = |scr_w: i32| (scr_w - 224).max(16) / 2;
    assert_eq!(card_x(240), 8);
    assert_eq!(card_x(280), 28);
}

pub fn run_suite() -> usize {
    test_qmi8658_gravity_classification();
    test_debounce_hysteresis_and_wraparound();
    test_touch_coordinate_remapping();
    test_nvs_persistence_and_wear_dedup();
    4
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn orientation_suite() {
        assert_eq!(run_suite(), 4);
    }
}
