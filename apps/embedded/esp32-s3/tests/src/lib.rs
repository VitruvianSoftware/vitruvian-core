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
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

use std::env;
use std::fs;
use std::path::{Path, PathBuf};

pub mod test_agent_ci;
pub mod test_catalog;
pub mod test_challenger_m2;
pub mod test_challenger_m3;
pub mod test_challenger_m3_firmware;
pub mod test_cloud_ci;
pub mod test_net_telemetry;
pub mod test_orientation;
pub mod test_power_battery;
pub mod test_profiles;
pub mod test_settings_toggles;
pub mod test_stress_firmware;
pub mod test_wifi_provisioning;

/// Resolves the `apps/embedded/esp32-s3` component directory hermetically inside
/// Bazel test sandboxes (`TEST_SRCDIR`), `bazel run` (`BUILD_WORKSPACE_DIRECTORY`),
/// or direct execution from the repository/package root.
pub fn component_dir() -> PathBuf {
    let candidates = [PathBuf::from("apps/embedded/esp32-s3"), PathBuf::from(".")];
    for c in &candidates {
        if c.join("platformio.ini").is_file() && c.join("src").is_dir() {
            return c.clone();
        }
    }
    if let Ok(srcdir) = env::var("TEST_SRCDIR") {
        let workspace = env::var("TEST_WORKSPACE").unwrap_or_else(|_| "_main".to_string());
        let p = Path::new(&srcdir)
            .join(&workspace)
            .join("apps/embedded/esp32-s3");
        if p.join("platformio.ini").is_file() {
            return p;
        }
    }
    if let Ok(ws) = env::var("BUILD_WORKSPACE_DIRECTORY") {
        let p = Path::new(&ws).join("apps/embedded/esp32-s3");
        if p.join("platformio.ini").is_file() {
            return p;
        }
    }
    PathBuf::from("apps/embedded/esp32-s3")
}

/// Resolves the repository root directory (following Bazel runfile symlinks when possible).
pub fn repo_root() -> PathBuf {
    if let Ok(ws) = env::var("BUILD_WORKSPACE_DIRECTORY") {
        let p = PathBuf::from(ws);
        if p.exists() {
            return p;
        }
    }
    let comp = component_dir();
    if let Ok(canon) = fs::canonicalize(comp.join("platformio.ini")) {
        // <repo>/apps/embedded/esp32-s3/platformio.ini -> 4 parents up is <repo>
        if let Some(root) = canon
            .parent()
            .and_then(|p| p.parent())
            .and_then(|p| p.parent())
            .and_then(|p| p.parent())
        {
            return root.to_path_buf();
        }
    }
    if let Ok(cwd) = env::current_dir() {
        return cwd;
    }
    PathBuf::from(".")
}

/// Reads a file inside `apps/embedded/esp32-s3/<rel_path>` verbatim.
pub fn read_component_file(rel_path: &str) -> String {
    let path = component_dir().join(rel_path);
    fs::read_to_string(&path).unwrap_or_else(|e| panic!("failed to read {}: {}", path.display(), e))
}

/// Deterministic, zero-dependency PRNG (xorshift64*) for high-speed Monte Carlo
/// touch hit-testing and 100,000-step carousel random-walk ergodicity checks.
#[derive(Clone, Debug)]
pub struct XorShift64 {
    state: u64,
}

impl XorShift64 {
    pub fn new(seed: u64) -> Self {
        Self {
            state: if seed == 0 {
                0xCAFE_BABE_1337_0001
            } else {
                seed
            },
        }
    }

    pub fn next_u64(&mut self) -> u64 {
        let mut x = self.state;
        x ^= x >> 12;
        x ^= x << 25;
        x ^= x >> 27;
        self.state = x;
        x.wrapping_mul(0x2545_F491_4F6C_DD1D)
    }

    pub fn next_range(&mut self, min_inclusive: i32, max_inclusive: i32) -> i32 {
        let span = (max_inclusive - min_inclusive + 1) as u64;
        min_inclusive + (self.next_u64() % span) as i32
    }

    pub fn gen_range_i32(&mut self, min_inclusive: i32, max_exclusive: i32) -> i32 {
        if max_exclusive <= min_inclusive {
            return min_inclusive;
        }
        let span = (max_exclusive - min_inclusive) as u64;
        min_inclusive + (self.next_u64() % span) as i32
    }

    pub fn next_bool(&mut self) -> bool {
        (self.next_u64() & 1) == 0
    }
}

/// Axis-aligned bounding rectangle used by UI layout and hit-test suites.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Rect {
    pub x: i32,
    pub y: i32,
    pub w: i32,
    pub h: i32,
}

impl Rect {
    pub const fn new(x: i32, y: i32, w: i32, h: i32) -> Self {
        Self { x, y, w, h }
    }

    pub const fn x2(&self) -> i32 {
        self.x + self.w
    }

    pub const fn y2(&self) -> i32 {
        self.y + self.h
    }

    pub const fn contains(&self, px: i32, py: i32) -> bool {
        self.x <= px && px < self.x2() && self.y <= py && py < self.y2()
    }

    pub const fn contains_rect(&self, child: &Rect) -> bool {
        child.is_contained_in(self)
    }

    pub const fn intersects(&self, other: &Rect) -> bool {
        !(self.x2() <= other.x
            || other.x2() <= self.x
            || self.y2() <= other.y
            || other.y2() <= self.y)
    }

    pub const fn is_contained_in(&self, parent: &Rect) -> bool {
        self.x >= parent.x
            && self.y >= parent.y
            && self.x2() <= parent.x2()
            && self.y2() <= parent.y2()
    }
}

/// Escapes a string for JSON string serialization.
pub fn json_escape_str(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for ch in s.chars() {
        match ch {
            '\\' => out.push_str("\\\\"),
            '"' => out.push_str("\\\""),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c => out.push(c),
        }
    }
    out
}

/// Extracts a JSON string value for a given key from a flat or nested JSON object snippet.
pub fn json_extract_str(json: &str, key: &str) -> Option<String> {
    let needle = format!("\"{}\"", key);
    let mut search_from = 0;
    while let Some(rel_pos) = json[search_from..].find(&needle) {
        let pos = search_from + rel_pos;
        let after_key = &json[pos + needle.len()..];
        let trimmed = after_key.trim_start();
        if let Some(after_colon) = trimmed.strip_prefix(':') {
            let val_trimmed = after_colon.trim_start();
            if let Some(rest) = val_trimmed.strip_prefix('"') {
                let mut result = String::new();
                let mut chars = rest.chars();
                while let Some(c) = chars.next() {
                    if c == '\\' {
                        if let Some(esc) = chars.next() {
                            match esc {
                                'n' => result.push('\n'),
                                'r' => result.push('\r'),
                                't' => result.push('\t'),
                                '"' => result.push('"'),
                                '\\' => result.push('\\'),
                                '/' => result.push('/'),
                                other => {
                                    result.push('\\');
                                    result.push(other);
                                }
                            }
                        }
                    } else if c == '"' {
                        return Some(result);
                    } else {
                        result.push(c);
                    }
                }
            } else if val_trimmed.starts_with("null") {
                return None;
            }
        }
        search_from = pos + needle.len();
    }
    None
}

/// Extracts an integer field for a given key from a JSON snippet.
pub fn json_extract_i64(json: &str, key: &str) -> Option<i64> {
    let needle = format!("\"{}\"", key);
    let mut search_from = 0;
    while let Some(rel_pos) = json[search_from..].find(&needle) {
        let pos = search_from + rel_pos;
        let after_key = &json[pos + needle.len()..];
        let trimmed = after_key.trim_start();
        if let Some(after_colon) = trimmed.strip_prefix(':') {
            let val_trimmed = after_colon.trim_start();
            let num_str: String = val_trimmed
                .chars()
                .take_while(|c| c.is_ascii_digit() || *c == '-')
                .collect();
            if !num_str.is_empty() && num_str != "-" {
                if let Ok(v) = num_str.parse::<i64>() {
                    return Some(v);
                }
            }
        }
        search_from = pos + needle.len();
    }
    None
}

/// Extracts a boolean field for a given key from a JSON snippet.
pub fn json_extract_bool(json: &str, key: &str) -> Option<bool> {
    let needle = format!("\"{}\"", key);
    let mut search_from = 0;
    while let Some(rel_pos) = json[search_from..].find(&needle) {
        let pos = search_from + rel_pos;
        let after_key = &json[pos + needle.len()..];
        let trimmed = after_key.trim_start();
        if let Some(after_colon) = trimmed.strip_prefix(':') {
            let val_trimmed = after_colon.trim_start();
            if val_trimmed.starts_with("true") {
                return Some(true);
            } else if val_trimmed.starts_with("false") {
                return Some(false);
            }
        }
        search_from = pos + needle.len();
    }
    None
}
