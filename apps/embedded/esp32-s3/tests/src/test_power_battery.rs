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

//! Rust migration of `test_power_battery.py`:
//! ETA6098 + GPIO1 ADC LiPo battery curve, GPIO41 power latch & GPIO40 button state machine,
//! and status header layout geometry.

use crate::{read_component_file, Rect};

pub const SYS_EN_PIN: i32 = 41;
pub const SYS_OUT_PIN: i32 = 40;
pub const BAT_ADC_PIN: i32 = 1;

pub const BAT_DIVIDER_RATIO: f64 = 3.0;
pub const BAT_EMPTY_MV: i32 = 3200;
pub const BAT_LOW_WARN_MV: i32 = 3450;
pub const BAT_NOMINAL_MV: i32 = 3700;
pub const BAT_FULL_MV: i32 = 4200;

pub const PWR_DEBOUNCE_MS: u32 = 50;
pub const PWR_SHORT_PRESS_MAX_MS: u32 = 1200;
pub const PWR_LONG_PRESS_MS: u32 = 2500;

pub const COLOR_GREEN: u32 = 0x30D158;
pub const COLOR_ORANGE: u32 = 0xFF9F0A;
pub const COLOR_RED: u32 = 0xFF453A;
pub const COLOR_MUTED: u32 = 0x8E8E93;

pub fn adc_mv_to_battery_mv(adc_pin_mv: i32) -> i32 {
    if adc_pin_mv < 100 {
        return 0;
    }
    ((adc_pin_mv as f64) * BAT_DIVIDER_RATIO).round() as i32
}

pub fn battery_mv_to_percent(bat_mv: i32) -> i32 {
    if bat_mv <= 0 {
        return -1;
    }
    if bat_mv <= BAT_EMPTY_MV {
        return 0;
    }
    if bat_mv >= BAT_FULL_MV {
        return 100;
    }
    let curve = [
        (3200, 0),
        (3500, 15),
        (3680, 50),
        (3850, 75),
        (4050, 92),
        (4200, 100),
    ];
    for i in 0..(curve.len() - 1) {
        let (v0, p0) = curve[i];
        let (v1, p1) = curve[i + 1];
        if bat_mv >= v0 && bat_mv <= v1 {
            let frac = (bat_mv - v0) as f64 / (v1 - v0) as f64;
            return (p0 as f64 + frac * (p1 - p0) as f64).round() as i32;
        }
    }
    0
}

pub fn battery_status_color(pct: i32) -> u32 {
    if pct < 0 {
        COLOR_MUTED
    } else if pct <= 15 {
        COLOR_RED
    } else if pct <= 35 {
        COLOR_ORANGE
    } else {
        COLOR_GREEN
    }
}

pub fn format_battery_badge(pct: i32, bat_mv: i32) -> String {
    if pct < 0 || bat_mv < 2500 {
        return "USB".to_string();
    }
    format!("{pct}%")
}

pub struct PowerButtonStateMachine {
    pub latch_high: bool,
    pub display_sleeping: bool,
    pub saved_brightness: u8,
    pub current_brightness: u8,
    pub btn_down: bool,
    pub press_start_ms: u32,
    pub long_press_fired: bool,
    pub events: Vec<String>,
}

impl Default for PowerButtonStateMachine {
    fn default() -> Self {
        Self::new()
    }
}

impl PowerButtonStateMachine {
    pub fn new() -> Self {
        Self {
            latch_high: true,
            display_sleeping: false,
            saved_brightness: 204,
            current_brightness: 204,
            btn_down: false,
            press_start_ms: 0,
            long_press_fired: false,
            events: Vec::new(),
        }
    }

    pub fn step(&mut self, now_ms: u32, gpio40_low: bool) {
        if gpio40_low {
            if !self.btn_down {
                self.btn_down = true;
                self.press_start_ms = now_ms;
                self.long_press_fired = false;
            } else {
                let held_ms = now_ms.saturating_sub(self.press_start_ms);
                if held_ms >= PWR_LONG_PRESS_MS && !self.long_press_fired {
                    self.long_press_fired = true;
                    self.current_brightness = 0;
                    self.latch_high = false;
                    self.events.push("POWER_OFF".to_string());
                }
            }
        } else if self.btn_down {
            let held_ms = now_ms.saturating_sub(self.press_start_ms);
            self.btn_down = false;
            if !self.long_press_fired
                && (PWR_DEBOUNCE_MS..=PWR_SHORT_PRESS_MAX_MS).contains(&held_ms)
            {
                if self.display_sleeping {
                    self.display_sleeping = false;
                    self.current_brightness = self.saved_brightness;
                    self.events.push("WAKE_DISPLAY".to_string());
                } else {
                    self.saved_brightness = self.current_brightness;
                    self.display_sleeping = true;
                    self.current_brightness = 0;
                    self.events.push("SLEEP_DISPLAY".to_string());
                }
            }
        }
    }
}

pub fn test_pin_config_and_battery_curve() {
    let pin_cfg = read_component_file("include/pin_config.h");
    assert!(pin_cfg.contains("#define SYS_EN_PIN 41"));
    assert!(pin_cfg.contains("#define SYS_OUT_PIN 40"));
    assert!(pin_cfg.contains("#define BAT_ADC_PIN 1"));

    assert_eq!(adc_mv_to_battery_mv(1400), 4200);
    assert_eq!(adc_mv_to_battery_mv(1233), 3699);
    assert_eq!(adc_mv_to_battery_mv(0), 0);
    assert_eq!(battery_mv_to_percent(0), -1);

    let mut prev_pct = 0;
    for mv in (3000..=4350).step_by(5) {
        let pct = battery_mv_to_percent(mv);
        assert!((0..=100).contains(&pct));
        assert!(pct >= prev_pct);
        prev_pct = pct;
    }

    assert_eq!(battery_status_color(-1), COLOR_MUTED);
    assert_eq!(battery_status_color(10), COLOR_RED);
    assert_eq!(battery_status_color(25), COLOR_ORANGE);
    assert_eq!(battery_status_color(80), COLOR_GREEN);
    assert_eq!(format_battery_badge(87, 4010), "87%");
    assert_eq!(format_battery_badge(-1, 0), "USB");
}

pub fn test_power_button_state_machine() {
    let mut fsm = PowerButtonStateMachine::new();
    assert!(fsm.latch_high);

    fsm.step(100, true);
    fsm.step(130, false);
    assert!(fsm.events.is_empty());

    fsm.step(200, true);
    fsm.step(400, false);
    assert!(fsm.display_sleeping);
    assert_eq!(fsm.current_brightness, 0);
    fsm.step(1000, true);
    fsm.step(1250, false);
    assert!(!fsm.display_sleeping);
    assert_eq!(fsm.current_brightness, 204);

    fsm.step(2000, true);
    fsm.step(4500, true);
    assert!(!fsm.latch_high);
    assert_eq!(fsm.events.last().unwrap(), "POWER_OFF");
}

pub fn test_header_battery_badge_geometry() {
    let vp_portrait = Rect::new(0, 0, 240, 280);
    let hdr_p = Rect::new(8, 8, 172, 20);
    let bat_p = Rect::new(184, 8, 48, 20);
    assert!(vp_portrait.contains_rect(&hdr_p));
    assert!(vp_portrait.contains_rect(&bat_p));
    assert!(!hdr_p.intersects(&bat_p));

    let vp_landscape = Rect::new(0, 0, 280, 240);
    let hdr_l = Rect::new(8, 8, 212, 20);
    let bat_l = Rect::new(224, 8, 48, 20);
    assert!(vp_landscape.contains_rect(&hdr_l));
    assert!(vp_landscape.contains_rect(&bat_l));
    assert!(!hdr_l.intersects(&bat_l));
}

pub fn run_suite() -> usize {
    test_pin_config_and_battery_curve();
    test_power_button_state_machine();
    test_header_battery_badge_geometry();
    3
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn power_battery_suite() {
        assert_eq!(run_suite(), 3);
    }
}
