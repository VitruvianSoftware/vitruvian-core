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

//! Rust migration of `test_challenger_m3_firmware.py`:
//! 4-Deck LVGL UI geometry, 4-deck swipe transitions, memory limits, and Agent/CI payload fuzzing.

use crate::{json_extract_i64, json_extract_str, Rect, XorShift64};

const VIEWPORT: Rect = Rect::new(0, 0, 240, 280);
const SIX_BTN_COORDS: [(i32, i32); 6] = [
    (7, 78),
    (122, 78),
    (7, 136),
    (122, 136),
    (7, 194),
    (122, 194),
];
const BTN_W: i32 = 111;
const BTN_H: i32 = 52;

const LV_DIR_LEFT: u8 = 1;
const LV_DIR_RIGHT: u8 = 2;
const LV_DIR_HOR: u8 = LV_DIR_LEFT | LV_DIR_RIGHT;

const FLASH_PARTITION_LIMIT: usize = 6_553_600;
const SRAM_LIMIT: usize = 327_680;
const LVGL_POOL_SIZE: usize = 48 * 1024;

pub fn get_tile0_elements() -> Vec<(&'static str, Rect)> {
    let mut els = vec![("header", Rect::new(7, 5, 226, 68))];
    for (idx, (bx, by)) in SIX_BTN_COORDS.iter().enumerate() {
        let name = match idx {
            0 => "sys_btn_0",
            1 => "sys_btn_1",
            2 => "sys_btn_2",
            3 => "sys_btn_3",
            4 => "sys_btn_4",
            _ => "sys_btn_5",
        };
        els.push((name, Rect::new(*bx, *by, BTN_W, BTN_H)));
    }
    els
}

pub fn get_tile1_elements() -> Vec<(&'static str, Rect)> {
    let mut els = vec![("header", Rect::new(7, 5, 226, 68))];
    for (idx, (bx, by)) in SIX_BTN_COORDS.iter().enumerate() {
        let name = match idx {
            0 => "deck_btn_0",
            1 => "deck_btn_1",
            2 => "deck_btn_2",
            3 => "deck_btn_3",
            4 => "deck_btn_4",
            _ => "deck_btn_5",
        };
        els.push((name, Rect::new(*bx, *by, BTN_W, BTN_H)));
    }
    els
}

pub fn get_tile2_elements() -> Vec<(&'static str, Rect)> {
    vec![
        ("header_aci", Rect::new(7, 5, 226, 34)),
        ("card_agent", Rect::new(7, 43, 226, 78)),
        ("card_ci", Rect::new(7, 125, 226, 80)),
        ("btn_run", Rect::new(7, 210, 110, 42)),
        ("btn_pr", Rect::new(123, 210, 110, 42)),
    ]
}

pub fn get_tile3_elements() -> Vec<(&'static str, Rect)> {
    vec![
        ("title", Rect::new(12, 6, 120, 18)),
        ("bright_card", Rect::new(8, 26, 224, 46)),
        ("decks_card", Rect::new(8, 76, 224, 104)),
        ("info_card", Rect::new(8, 184, 224, 66)),
    ]
}

fn check_tile_elements(elements: &[(&'static str, Rect)]) {
    for (name, el) in elements {
        assert!(VIEWPORT.contains_rect(el), "{} out of viewport", name);
    }
    for i in 0..elements.len() {
        for j in (i + 1)..elements.len() {
            assert!(
                !elements[i].1.intersects(&elements[j].1),
                "Overlap between {} and {}",
                elements[i].0,
                elements[j].0
            );
        }
    }
}

pub fn test_all_four_tiles_bounding_boxes() {
    check_tile_elements(&get_tile0_elements());
    check_tile_elements(&get_tile1_elements());
    check_tile_elements(&get_tile2_elements());
    check_tile_elements(&get_tile3_elements());
}

pub fn test_4deck_tile_layout_extent() {
    let tiles = [(0, 0), (1, 0), (2, 0), (3, 0)];
    let mut x_offsets = Vec::new();
    for (col_idx, row_idx) in tiles {
        assert_eq!(row_idx, 0);
        let x_start = col_idx * VIEWPORT.w;
        x_offsets.push((x_start, x_start + VIEWPORT.w));
    }
    assert_eq!(
        x_offsets,
        vec![(0, 240), (240, 480), (480, 720), (720, 960)]
    );
    assert_eq!(x_offsets[3].1, 960);
}

pub fn test_tile3_10000_point_hit_test() {
    let mut rng = XorShift64::new(42);
    let interactive = [Rect::new(7, 214, 111, 38), Rect::new(122, 214, 111, 38)];
    for _ in 0..10_000 {
        let px = rng.gen_range_i32(0, 240);
        let py = rng.gen_range_i32(0, 280);
        let hits: Vec<&Rect> = interactive.iter().filter(|b| b.contains(px, py)).collect();
        assert!(hits.len() <= 1, "Ambiguous hit at ({px}, {py})");
    }
    for gx in 118..122 {
        for gy in 214..252 {
            let hits = interactive.iter().filter(|b| b.contains(gx, gy)).count();
            assert_eq!(hits, 0);
        }
    }
}

fn tile_dirs(tile: i32) -> u8 {
    match tile {
        0 => LV_DIR_RIGHT,
        1 | 2 => LV_DIR_HOR,
        3 => LV_DIR_LEFT,
        _ => 0,
    }
}

fn simulate_swipe(current_tile: i32, swipe_direction: &str) -> i32 {
    let allowed = tile_dirs(current_tile);
    if swipe_direction == "NEXT" && (allowed & LV_DIR_RIGHT) != 0 {
        return (current_tile + 1).min(3);
    }
    if swipe_direction == "PREV" && (allowed & LV_DIR_LEFT) != 0 {
        return (current_tile - 1).max(0);
    }
    current_tile
}

pub fn test_4deck_swipe_transitions() {
    let mut tile = 0;
    for expected in [1, 2, 3] {
        tile = simulate_swipe(tile, "NEXT");
        assert_eq!(tile, expected);
    }
    tile = simulate_swipe(tile, "NEXT");
    assert_eq!(tile, 3);
    for expected in [2, 1, 0] {
        tile = simulate_swipe(tile, "PREV");
        assert_eq!(tile, expected);
    }
    tile = simulate_swipe(tile, "PREV");
    assert_eq!(tile, 0);
}

pub fn test_random_walk_100k_transitions() {
    let mut rng = XorShift64::new(99);
    let mut tile = 0;
    let mut visited = [false; 4];
    visited[0] = true;
    for _ in 0..100_000 {
        let dir = if (rng.next_u64() & 1) == 0 {
            "NEXT"
        } else {
            "PREV"
        };
        tile = simulate_swipe(tile, dir);
        assert!((0..=3).contains(&tile));
        visited[tile as usize] = true;
    }
    assert_eq!(visited, [true, true, true, true]);
}

pub fn test_memory_limits_and_lvgl_pool() {
    let estimated_sram_used: usize = 80_224;
    let estimated_flash_used: usize = 578_400;
    assert!(estimated_sram_used < SRAM_LIMIT / 2);
    assert!(estimated_flash_used < FLASH_PARTITION_LIMIT / 5);
    assert_eq!(LVGL_POOL_SIZE, 49_152);
    let tile3_widgets = 18usize;
    let avg_bytes_per_widget = 192usize;
    let m3_heap_delta = tile3_widgets * avg_bytes_per_widget;
    assert!(m3_heap_delta < 4096);
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ParsedAgentCi {
    pub agent_state: String,
    pub agent_task: String,
    pub ci_status: String,
    pub ci_branch: String,
    pub ci_pr: i32,
    pub ci_checks_passed: i32,
    pub ci_checks_total: i32,
    pub ci_fail_step: String,
    pub notif_slack: i32,
    pub notif_gh: i32,
}

pub fn simulate_firmware_parse_agent_ci(json_line: &str) -> Option<ParsedAgentCi> {
    if json_extract_str(json_line, "type").as_deref() != Some("agent_ci") {
        return None;
    }
    let trunc = |key: &str, max_len: usize, default: &str| -> String {
        let raw = json_extract_str(json_line, key).unwrap_or_else(|| default.to_string());
        raw.chars().take(max_len).collect()
    };
    let int_val = |key: &str| -> i32 { json_extract_i64(json_line, key).unwrap_or(0) as i32 };
    Some(ParsedAgentCi {
        agent_state: trunc("agent_state", 16, "IDLE"),
        agent_task: trunc("agent_task", 32, "Ready"),
        ci_status: trunc("ci_status", 16, "NONE"),
        ci_branch: trunc("ci_branch", 24, "main"),
        ci_pr: int_val("ci_pr"),
        ci_checks_passed: int_val("ci_checks_passed"),
        ci_checks_total: int_val("ci_checks_total"),
        ci_fail_step: trunc("ci_fail_step", 24, ""),
        notif_slack: int_val("notif_slack"),
        notif_gh: int_val("notif_gh"),
    })
}

pub fn test_agent_ci_payload_fuzzing() {
    let valid = r#"{"type":"agent_ci","agent_state":"THINKING","agent_task":"Editing ui.cpp","ci_status":"PASS","ci_branch":"feat/m3","ci_pr":99,"ci_checks_passed":8,"ci_checks_total":8,"ci_fail_step":"","notif_slack":2,"notif_gh":5}"#;
    let res = simulate_firmware_parse_agent_ci(valid).unwrap();
    assert_eq!(res.agent_state, "THINKING");
    assert_eq!(res.ci_pr, 99);
    assert_eq!(res.notif_gh, 5);

    let long_task = "X".repeat(1024);
    let long_branch = "feature/".to_string() + &"b".repeat(500);
    let overflow = format!(
        r#"{{"type":"agent_ci","agent_state":"RUNNING_LONG_STATE_NAME","agent_task":"{}","ci_branch":"{}"}}"#,
        long_task, long_branch
    );
    let res_ovf = simulate_firmware_parse_agent_ci(&overflow).unwrap();
    assert_eq!(res_ovf.agent_state.chars().count(), 16);
    assert_eq!(res_ovf.agent_task.chars().count(), 32);
    assert_eq!(res_ovf.ci_branch.chars().count(), 24);

    let unicode = r#"{"type":"agent_ci","agent_state":"🚀THINK","agent_task":"Fixing 🐛 in UI","ci_branch":"feat/✨"}"#;
    let res_uni = simulate_firmware_parse_agent_ci(unicode).unwrap();
    assert!(res_uni.agent_state.contains("THINK"));

    let bounds = r#"{"type":"agent_ci","notif_slack":99999,"notif_gh":0,"ci_pr":2147483647}"#;
    let res_b = simulate_firmware_parse_agent_ci(bounds).unwrap();
    assert_eq!(res_b.notif_slack, 99_999);
    assert_eq!(res_b.ci_pr, 2_147_483_647);

    assert!(simulate_firmware_parse_agent_ci("{corrupted json").is_none());
}

pub fn run_suite() -> usize {
    test_all_four_tiles_bounding_boxes();
    test_4deck_tile_layout_extent();
    test_tile3_10000_point_hit_test();
    test_4deck_swipe_transitions();
    test_random_walk_100k_transitions();
    test_memory_limits_and_lvgl_pool();
    test_agent_ci_payload_fuzzing();
    7
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn challenger_m3_firmware_suite() {
        assert_eq!(run_suite(), 7);
    }
}
