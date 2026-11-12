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

//! Rust migration of `test_settings_toggles.py`:
//! Dynamic TileView deck toggles across all 2^3 = 8 power-set combinations,
//! 100k random-walk ergodicity, NVS persistence & flash wear deduplication, and navigation hints.

use crate::XorShift64;
use std::collections::{BTreeMap, BTreeSet};

pub const LV_DIR_LEFT: u8 = 1;
pub const LV_DIR_RIGHT: u8 = 2;
pub const LV_DIR_HOR: u8 = LV_DIR_LEFT | LV_DIR_RIGHT;

pub const DECK_SYSTEM: usize = 0;
pub const DECK_SMART: usize = 1;
pub const DECK_AGENT: usize = 2;
pub const DECK_SETTINGS: usize = 3;

const DECK_SHORT_NAMES: [&str; 4] = ["System", "Smart Deck", "Agent & CI", "Settings"];

pub struct DynamicTileViewCarousel {
    pub enabled: [bool; 4],
    pub active_col: usize,
}

impl DynamicTileViewCarousel {
    pub fn new(en_system: bool, en_smart: bool, en_agent: bool) -> Self {
        Self {
            enabled: [en_system, en_smart, en_agent, true],
            active_col: 0,
        }
    }

    pub fn active_decks(&self) -> Vec<usize> {
        let mut v: Vec<usize> = (0..3).filter(|&i| self.enabled[i]).collect();
        v.push(DECK_SETTINGS);
        v
    }

    pub fn num_active(&self) -> usize {
        self.active_decks().len()
    }

    pub fn current_deck_id(&self) -> usize {
        let decks = self.active_decks();
        let col = self.active_col.min(decks.len() - 1);
        decks[col]
    }

    pub fn tile_position(&self, deck_id: usize) -> Option<(usize, usize)> {
        self.active_decks()
            .iter()
            .position(|&d| d == deck_id)
            .map(|col| (col, 0))
    }

    pub fn allowed_dir(&self, col: usize) -> u8 {
        let n = self.num_active();
        if n <= 1 {
            0
        } else if col == 0 {
            LV_DIR_RIGHT
        } else if col == n - 1 {
            LV_DIR_LEFT
        } else {
            LV_DIR_HOR
        }
    }

    pub fn swipe(&mut self, direction: &str) -> usize {
        let dirs = self.allowed_dir(self.active_col);
        if direction == "NEXT" && (dirs & LV_DIR_RIGHT) != 0 {
            self.active_col += 1;
        } else if direction == "PREV" && (dirs & LV_DIR_LEFT) != 0 {
            self.active_col -= 1;
        }
        self.current_deck_id()
    }

    pub fn set_deck_enabled(&mut self, deck_id: usize, enable: bool) {
        assert_ne!(deck_id, DECK_SETTINGS, "Settings Deck cannot be disabled");
        let prev_deck = self.current_deck_id();
        self.enabled[deck_id] = enable;
        let decks = self.active_decks();
        if let Some(pos) = decks.iter().position(|&d| d == prev_deck) {
            self.active_col = pos;
        } else {
            self.active_col = decks.len() - 1;
        }
    }

    pub fn nav_hint_for_col(&self, col: usize) -> String {
        let decks = self.active_decks();
        let n = decks.len();
        if n == 1 {
            return "All optional decks hidden".to_string();
        }
        if col == 0 {
            let right_name = DECK_SHORT_NAMES[decks[1]];
            format!("Swipe left for {right_name}  -->")
        } else if col == n - 1 {
            let left_name = DECK_SHORT_NAMES[decks[n - 2]];
            format!("<--  Swipe right for {left_name}")
        } else {
            let left_name = DECK_SHORT_NAMES[decks[col - 1]];
            let right_name = DECK_SHORT_NAMES[decks[col + 1]];
            format!("<-- {left_name}  |  {right_name} -->")
        }
    }
}

pub struct MockPreferencesStorage {
    pub store: BTreeMap<(String, String), i32>,
    pub write_ops: usize,
}

impl MockPreferencesStorage {
    pub fn new() -> Self {
        Self {
            store: BTreeMap::new(),
            write_ops: 0,
        }
    }

    pub fn put_val(&mut self, ns: &str, key: &str, val: i32) {
        let k = (ns.to_string(), key.to_string());
        if self.store.get(&k) != Some(&val) {
            self.store.insert(k, val);
            self.write_ops += 1;
        }
    }

    pub fn get_val(&self, ns: &str, key: &str, default: i32) -> i32 {
        *self
            .store
            .get(&(ns.to_string(), key.to_string()))
            .unwrap_or(&default)
    }
}

pub fn test_all_8_powerset_configurations() {
    for mask in 0..8u8 {
        let s0 = (mask & 1) != 0;
        let s1 = (mask & 2) != 0;
        let s2 = (mask & 4) != 0;
        let mut c = DynamicTileViewCarousel::new(s0, s1, s2);
        let active = c.active_decks();
        assert_eq!(*active.last().unwrap(), DECK_SETTINGS);

        let cols: Vec<usize> = active
            .iter()
            .map(|&d| c.tile_position(d).unwrap().0)
            .collect();
        let expected_cols: Vec<usize> = (0..active.len()).collect();
        assert_eq!(cols, expected_cols);

        // Forward traversal reaches Settings in <= 3 swipes
        let mut visited_fwd = vec![c.current_deck_id()];
        for _ in 0..(active.len() - 1) {
            visited_fwd.push(c.swipe("NEXT"));
        }
        assert_eq!(visited_fwd, active);
        assert_eq!(c.swipe("NEXT"), *active.last().unwrap());

        // Backward traversal returns to first active deck
        let mut visited_bwd = vec![c.current_deck_id()];
        for _ in 0..(active.len() - 1) {
            visited_bwd.push(c.swipe("PREV"));
        }
        let mut rev = active.clone();
        rev.reverse();
        assert_eq!(visited_bwd, rev);
    }
}

pub fn test_random_walk_100k_ergodicity() {
    let mut rng = XorShift64::new(2026);
    for mask in 0..8u8 {
        let s0 = (mask & 1) != 0;
        let s1 = (mask & 2) != 0;
        let s2 = (mask & 4) != 0;
        let mut c = DynamicTileViewCarousel::new(s0, s1, s2);
        let expected: BTreeSet<usize> = c.active_decks().into_iter().collect();
        let mut visited = BTreeSet::new();
        visited.insert(c.current_deck_id());

        for _ in 0..12_500 {
            let dir = if (rng.next_u64() & 1) == 0 {
                "NEXT"
            } else {
                "PREV"
            };
            let d = c.swipe(dir);
            assert!(expected.contains(&d));
            visited.insert(d);
        }
        assert_eq!(visited, expected);
    }
}

pub fn test_live_toggle_and_nvs_persistence() {
    let mut c = DynamicTileViewCarousel::new(true, true, true);
    c.swipe("NEXT");
    c.swipe("NEXT");
    c.swipe("NEXT");
    assert_eq!(c.current_deck_id(), DECK_SETTINGS);

    c.set_deck_enabled(DECK_SMART, false);
    assert_eq!(c.current_deck_id(), DECK_SETTINGS);
    assert_eq!(c.active_col, 2);

    c.set_deck_enabled(DECK_SYSTEM, false);
    c.set_deck_enabled(DECK_AGENT, false);
    assert_eq!(c.active_decks(), vec![DECK_SETTINGS]);
    assert_eq!(c.nav_hint_for_col(0), "All optional decks hidden");

    let mut nvs = MockPreferencesStorage::new();
    nvs.put_val("deck_cfg", "brightness", 180);
    nvs.put_val("deck_cfg", "brightness", 180);
    assert_eq!(nvs.write_ops, 1);
    assert_eq!(nvs.get_val("deck_cfg", "brightness", 204), 180);
}

pub fn run_suite() -> usize {
    test_all_8_powerset_configurations();
    test_random_walk_100k_ergodicity();
    test_live_toggle_and_nvs_persistence();
    3
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn settings_toggles_suite() {
        assert_eq!(run_suite(), 3);
    }
}
