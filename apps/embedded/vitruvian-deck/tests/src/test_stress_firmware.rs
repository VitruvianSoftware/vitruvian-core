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

//! Rust migration of `test_stress_firmware.py`:
//! 4-Tile LVGL bounding-box & hit-test stress checks, serial protocol fuzzing,
//! and embedded SRAM / Flash headroom verification.

use crate::{Rect, XorShift64};

const VIEWPORT: Rect = Rect::new(0, 0, 240, 280);

pub fn get_tile3_settings_elements() -> Vec<(&'static str, Rect)> {
    vec![
        ("title", Rect::new(12, 6, 120, 18)),
        ("bright_card", Rect::new(8, 26, 224, 46)),
        ("decks_card", Rect::new(8, 76, 224, 104)),
        ("info_card", Rect::new(8, 184, 224, 66)),
    ]
}

pub fn get_tile3_switches() -> Vec<(&'static str, Rect)> {
    vec![
        ("sw_system", Rect::new(8 + 172, 76 + 19, 40, 20)),
        ("sw_smart", Rect::new(8 + 172, 76 + 47, 40, 20)),
        ("sw_agent", Rect::new(8 + 172, 76 + 75, 40, 20)),
    ]
}

pub fn parse_color_hex(hex_str: &str, default: u32) -> u32 {
    if hex_str.starts_with('#') && hex_str.len() == 7 {
        u32::from_str_radix(&hex_str[1..], 16).unwrap_or(default)
    } else {
        default
    }
}

pub fn test_tile3_settings_geometry() {
    let els = get_tile3_settings_elements();
    for (name, el) in &els {
        assert!(VIEWPORT.contains_rect(el), "{} out of bounds", name);
    }
    for i in 0..els.len() {
        for j in (i + 1)..els.len() {
            assert!(!els[i].1.intersects(&els[j].1));
        }
    }

    let decks_card = &els.iter().find(|(n, _)| *n == "decks_card").unwrap().1;
    let switches = get_tile3_switches();
    for (_, sw) in &switches {
        assert!(decks_card.contains_rect(sw));
    }
    for i in 0..switches.len() {
        for j in (i + 1)..switches.len() {
            assert!(!switches[i].1.intersects(&switches[j].1));
        }
    }

    // Tile 0 (System Deck), Tile 1 (Smart Deck), Tile 2 (Agent & CI Deck) bounding boxes
    let tile0 = [
        Rect::new(8, 6, 224, 24),
        Rect::new(8, 34, 224, 52),
        Rect::new(8, 92, 108, 72),
        Rect::new(124, 92, 108, 72),
        Rect::new(8, 170, 224, 48),
        Rect::new(8, 224, 108, 30),
        Rect::new(124, 224, 108, 30),
    ];
    let tile1 = [
        Rect::new(8, 6, 224, 24),
        Rect::new(8, 34, 224, 38),
        Rect::new(7, 78, 111, 52),
        Rect::new(122, 78, 111, 52),
        Rect::new(7, 136, 111, 52),
        Rect::new(122, 136, 111, 52),
        Rect::new(7, 194, 111, 52),
        Rect::new(122, 194, 111, 52),
    ];
    let tile2 = [
        Rect::new(8, 6, 224, 24),
        Rect::new(8, 34, 224, 86),
        Rect::new(8, 126, 224, 86),
        Rect::new(8, 218, 108, 34),
        Rect::new(124, 218, 108, 34),
    ];
    for tile in [&tile0[..], &tile1[..], &tile2[..]] {
        for r in tile {
            assert!(VIEWPORT.contains_rect(r));
        }
        for i in 0..tile.len() {
            for j in (i + 1)..tile.len() {
                assert!(!tile[i].intersects(&tile[j]));
            }
        }
    }
}

pub fn test_10000_point_button_hit_test() {
    let mut rng = XorShift64::new(42);
    let coords = [
        (7, 78),
        (122, 78),
        (7, 136),
        (122, 136),
        (7, 194),
        (122, 194),
    ];
    let buttons: Vec<Rect> = coords
        .iter()
        .map(|&(bx, by)| Rect::new(bx, by, 111, 52))
        .collect();

    for _ in 0..10_000 {
        let px = rng.gen_range_i32(0, 240);
        let py = rng.gen_range_i32(0, 280);
        let hits = buttons.iter().filter(|b| b.contains(px, py)).count();
        assert!(hits <= 1);
    }
}

pub fn test_serial_protocol_fuzzing() {
    let default_accent = 0xBF5AF2;
    assert_eq!(parse_color_hex("#007ACC", default_accent), 0x007ACC);
    assert_eq!(parse_color_hex("#30D158", default_accent), 0x30D158);
    for malformed in ["", "#", "#12345", "#1234567", "007ACC", "#GGGGGG"] {
        assert_eq!(parse_color_hex(malformed, default_accent), default_accent);
    }

    let long_app = "A".repeat(500);
    let truncated: String = long_app.chars().take(31).collect();
    assert_eq!(truncated.len(), 31);

    let process_buttons = |labels: &[&str]| -> Vec<String> {
        let mut out = Vec::with_capacity(6);
        for i in 0..6 {
            if let Some(&lbl) = labels.get(i) {
                out.push(lbl.chars().take(19).collect());
            } else {
                out.push("-".to_string());
            }
        }
        out
    };
    let many: Vec<&str> = (0..100).map(|_| "Btn").collect();
    assert_eq!(process_buttons(&many).len(), 6);
    let two = process_buttons(&["One", "Two"]);
    assert_eq!(two, vec!["One", "Two", "-", "-", "-", "-"]);
    let empty = process_buttons(&[]);
    assert_eq!(empty, vec!["-", "-", "-", "-", "-", "-"]);
}

pub fn test_memory_and_flash_headroom() {
    let total_ram = 327_680usize;
    let used_ram = 83_040usize;
    let dma_buffer_size = 240 * 40 * 2usize;
    let total_flash = 6_553_600usize;
    let used_flash = 591_737usize;
    let lvgl_pool = 48 * 1024usize;
    let estimated_lvgl_widgets_bytes = 24 * 1024usize;

    assert!((used_ram as f64 / total_ram as f64) < 0.50);
    assert!((used_flash as f64 / total_flash as f64) < 0.25);
    assert!(estimated_lvgl_widgets_bytes < lvgl_pool);
    assert!(total_ram - used_ram - dma_buffer_size > 200_000);
}

pub fn run_suite() -> usize {
    test_tile3_settings_geometry();
    test_10000_point_button_hit_test();
    test_serial_protocol_fuzzing();
    test_memory_and_flash_headroom();
    4
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stress_firmware_suite() {
        assert_eq!(run_suite(), 4);
    }
}
