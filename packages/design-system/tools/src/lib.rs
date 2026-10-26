// Copyright (c) 2026 VitruvianSoftware
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

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

// ---------------------------------------------------------------------------
// Minimal std-only JSON parser
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, PartialEq)]
pub enum JsonValue {
    Null,
    Bool(bool),
    Number(f64),
    Str(String),
    Array(Vec<JsonValue>),
    Object(BTreeMap<String, JsonValue>),
}

impl JsonValue {
    pub fn as_object(&self) -> Option<&BTreeMap<String, JsonValue>> {
        match self {
            JsonValue::Object(m) => Some(m),
            _ => None,
        }
    }

    pub fn as_str(&self) -> Option<&str> {
        match self {
            JsonValue::Str(s) => Some(s),
            _ => None,
        }
    }

    pub fn as_array(&self) -> Option<&Vec<JsonValue>> {
        match self {
            JsonValue::Array(a) => Some(a),
            _ => None,
        }
    }

    pub fn get(&self, key: &str) -> Option<&JsonValue> {
        self.as_object().and_then(|m| m.get(key))
    }
}

struct Parser<'a> {
    input: &'a [u8],
    pos: usize,
}

impl<'a> Parser<'a> {
    fn new(input: &'a str) -> Self {
        Self {
            input: input.as_bytes(),
            pos: 0,
        }
    }

    fn skip_ws(&mut self) {
        while self.pos < self.input.len() {
            match self.input[self.pos] {
                b' ' | b'\t' | b'\n' | b'\r' => self.pos += 1,
                _ => break,
            }
        }
    }

    fn peek(&self) -> Option<u8> {
        self.input.get(self.pos).copied()
    }

    fn next_byte(&mut self) -> Result<u8, String> {
        if self.pos < self.input.len() {
            let b = self.input[self.pos];
            self.pos += 1;
            Ok(b)
        } else {
            Err("unexpected end of input".into())
        }
    }

    fn expect(&mut self, b: u8) -> Result<(), String> {
        let got = self.next_byte()?;
        if got == b {
            Ok(())
        } else {
            Err(format!(
                "expected '{}' at position {}, got '{}'",
                b as char,
                self.pos - 1,
                got as char
            ))
        }
    }

    fn parse_value(&mut self) -> Result<JsonValue, String> {
        self.skip_ws();
        match self.peek() {
            Some(b'"') => self.parse_string().map(JsonValue::Str),
            Some(b'{') => self.parse_object(),
            Some(b'[') => self.parse_array(),
            Some(b't') => self.parse_literal("true", JsonValue::Bool(true)),
            Some(b'f') => self.parse_literal("false", JsonValue::Bool(false)),
            Some(b'n') => self.parse_literal("null", JsonValue::Null),
            Some(b'-') | Some(b'0'..=b'9') => self.parse_number(),
            Some(c) => Err(format!(
                "unexpected character '{}' at position {}",
                c as char, self.pos
            )),
            None => Err("unexpected end of input".into()),
        }
    }

    fn parse_literal(&mut self, lit: &str, val: JsonValue) -> Result<JsonValue, String> {
        for expected in lit.bytes() {
            let got = self.next_byte()?;
            if got != expected {
                return Err(format!("invalid literal at position {}", self.pos - 1));
            }
        }
        Ok(val)
    }

    fn parse_number(&mut self) -> Result<JsonValue, String> {
        let start = self.pos;
        if self.peek() == Some(b'-') {
            self.pos += 1;
        }
        while self.pos < self.input.len() && self.input[self.pos].is_ascii_digit() {
            self.pos += 1;
        }
        if self.pos < self.input.len() && self.input[self.pos] == b'.' {
            self.pos += 1;
            while self.pos < self.input.len() && self.input[self.pos].is_ascii_digit() {
                self.pos += 1;
            }
        }
        if self.pos < self.input.len()
            && (self.input[self.pos] == b'e' || self.input[self.pos] == b'E')
        {
            self.pos += 1;
            if self.pos < self.input.len()
                && (self.input[self.pos] == b'+' || self.input[self.pos] == b'-')
            {
                self.pos += 1;
            }
            while self.pos < self.input.len() && self.input[self.pos].is_ascii_digit() {
                self.pos += 1;
            }
        }
        let s = std::str::from_utf8(&self.input[start..self.pos])
            .map_err(|e| format!("invalid UTF-8 in number: {e}"))?;
        let n: f64 = s
            .parse()
            .map_err(|e| format!("invalid number '{s}': {e}"))?;
        Ok(JsonValue::Number(n))
    }

    fn parse_string(&mut self) -> Result<String, String> {
        self.expect(b'"')?;
        let mut s = String::new();
        loop {
            let b = self.next_byte()?;
            match b {
                b'"' => return Ok(s),
                b'\\' => {
                    let esc = self.next_byte()?;
                    match esc {
                        b'"' => s.push('"'),
                        b'\\' => s.push('\\'),
                        b'/' => s.push('/'),
                        b'b' => s.push('\u{0008}'),
                        b'f' => s.push('\u{000C}'),
                        b'n' => s.push('\n'),
                        b'r' => s.push('\r'),
                        b't' => s.push('\t'),
                        b'u' => {
                            let mut hex = String::with_capacity(4);
                            for _ in 0..4 {
                                hex.push(self.next_byte()? as char);
                            }
                            let cp = u32::from_str_radix(&hex, 16)
                                .map_err(|_| format!("invalid unicode escape \\u{hex}"))?;
                            if let Some(c) = char::from_u32(cp) {
                                s.push(c);
                            } else if (0xD800..=0xDBFF).contains(&cp) {
                                // high surrogate — expect \uXXXX low surrogate
                                self.expect(b'\\')?;
                                self.expect(b'u')?;
                                let mut hex2 = String::with_capacity(4);
                                for _ in 0..4 {
                                    hex2.push(self.next_byte()? as char);
                                }
                                let cp2 = u32::from_str_radix(&hex2, 16)
                                    .map_err(|_| format!("invalid unicode escape \\u{hex2}"))?;
                                let full = 0x10000 + ((cp - 0xD800) << 10) + (cp2 - 0xDC00);
                                if let Some(c) = char::from_u32(full) {
                                    s.push(c);
                                }
                            }
                        }
                        _ => {
                            s.push('\\');
                            s.push(esc as char);
                        }
                    }
                }
                _ => s.push(b as char),
            }
        }
    }

    fn parse_object(&mut self) -> Result<JsonValue, String> {
        self.expect(b'{')?;
        self.skip_ws();
        let mut map = BTreeMap::new();
        if self.peek() == Some(b'}') {
            self.pos += 1;
            return Ok(JsonValue::Object(map));
        }
        loop {
            self.skip_ws();
            let key = self.parse_string()?;
            self.skip_ws();
            self.expect(b':')?;
            let val = self.parse_value()?;
            map.insert(key, val);
            self.skip_ws();
            match self.peek() {
                Some(b',') => {
                    self.pos += 1;
                }
                Some(b'}') => {
                    self.pos += 1;
                    return Ok(JsonValue::Object(map));
                }
                _ => return Err(format!("expected ',' or '}}' at position {}", self.pos)),
            }
        }
    }

    fn parse_array(&mut self) -> Result<JsonValue, String> {
        self.expect(b'[')?;
        self.skip_ws();
        let mut arr = Vec::new();
        if self.peek() == Some(b']') {
            self.pos += 1;
            return Ok(JsonValue::Array(arr));
        }
        loop {
            let val = self.parse_value()?;
            arr.push(val);
            self.skip_ws();
            match self.peek() {
                Some(b',') => {
                    self.pos += 1;
                }
                Some(b']') => {
                    self.pos += 1;
                    return Ok(JsonValue::Array(arr));
                }
                _ => return Err(format!("expected ',' or ']' at position {}", self.pos)),
            }
        }
    }
}

pub fn parse_json(input: &str) -> Result<JsonValue, String> {
    let mut parser = Parser::new(input);
    let val = parser.parse_value()?;
    parser.skip_ws();
    if parser.pos != parser.input.len() {
        return Err(format!("trailing content at position {}", parser.pos));
    }
    Ok(val)
}

// ---------------------------------------------------------------------------
// Package directory resolution
// ---------------------------------------------------------------------------

fn has_tokens_json(dir: &Path) -> bool {
    dir.join("src").join("tokens.json").is_file()
}

pub fn find_pkg_dir() -> Result<PathBuf, String> {
    // 1. BUILD_WORKSPACE_DIRECTORY
    if let Ok(ws) = std::env::var("BUILD_WORKSPACE_DIRECTORY") {
        let candidate = PathBuf::from(&ws).join("packages").join("design-system");
        if has_tokens_json(&candidate) {
            return Ok(candidate);
        }
    }

    // 2. TEST_SRCDIR / RUNFILES_DIR
    let runfiles = std::env::var("TEST_SRCDIR")
        .or_else(|_| std::env::var("RUNFILES_DIR"))
        .ok();
    if let Some(rf) = runfiles {
        let base = PathBuf::from(&rf);
        for prefix in &[
            "_main/packages/design-system",
            "vitruvian_core/packages/design-system",
            "packages/design-system",
            ".",
        ] {
            let candidate = base.join(prefix);
            if has_tokens_json(&candidate) {
                return Ok(candidate);
            }
        }
    }

    // 3. current_exe() parent chain
    if let Ok(exe) = std::env::current_exe() {
        let exe = exe.canonicalize().unwrap_or(exe);
        let mut cur = exe.parent();
        while let Some(p) = cur {
            if has_tokens_json(p) {
                return Ok(p.to_path_buf());
            }
            let ws_candidate = p.join("packages").join("design-system");
            if has_tokens_json(&ws_candidate) {
                return Ok(ws_candidate);
            }
            cur = p.parent();
        }
    }

    // 4. current_dir() chain
    if let Ok(cwd) = std::env::current_dir() {
        let mut cur = Some(cwd.as_path());
        while let Some(p) = cur {
            if has_tokens_json(p) {
                return Ok(p.to_path_buf());
            }
            let ws_candidate = p.join("packages").join("design-system");
            if has_tokens_json(&ws_candidate) {
                return Ok(ws_candidate);
            }
            cur = p.parent();
        }
    }

    Err("Could not locate packages/design-system/src/tokens.json".into())
}

// ---------------------------------------------------------------------------
// Check functions — each returns Ok(()) or Err(vec of error messages)
// ---------------------------------------------------------------------------

pub fn check_no_remote_font_import(tokens_css: &str) -> Result<(), Vec<String>> {
    if tokens_css.contains("fonts.googleapis.com") {
        Err(vec![
            "tokens.css must not use remote Google Fonts @import (stripped by Vite/lightningcss)"
                .into(),
        ])
    } else {
        Ok(())
    }
}

pub fn check_all_font_face_urls_exist_on_disk(
    tokens_css: &str,
    src_dir: &Path,
) -> Result<(), Vec<String>> {
    let mut errors = Vec::new();
    let urls = extract_font_urls(tokens_css);
    if urls.len() < 12 {
        errors.push(format!(
            "Expected 12 woff2 @font-face declarations, found {}",
            urls.len()
        ));
    }
    for fname in &urls {
        let fpath = src_dir.join("fonts").join(fname);
        if !fpath.is_file() {
            errors.push(format!("Missing vendored font file: {}", fpath.display()));
        }
    }
    if !src_dir.join("fonts").join("OFL.txt").is_file() {
        errors.push("Missing SIL Open Font License (OFL.txt) in src/fonts/".into());
    }
    if errors.is_empty() {
        Ok(())
    } else {
        Err(errors)
    }
}

fn extract_font_urls(css: &str) -> Vec<String> {
    let mut urls = Vec::new();
    let patterns: &[&str] = &["url(\"./fonts/", "url('./fonts/"];
    for pat in patterns {
        let mut start = 0;
        while let Some(idx) = css[start..].find(pat) {
            let abs = start + idx + pat.len();
            let close_chars: &[char] = &['"', '\''];
            if let Some(end) = css[abs..].find(close_chars) {
                urls.push(css[abs..abs + end].to_string());
            }
            start = abs;
        }
    }
    urls
}

pub fn check_color_ramps_match_between_json_css_and_ts(
    tokens_json: &JsonValue,
    tokens_css: &str,
    tokens_ts: &str,
) -> Result<(), Vec<String>> {
    let mut errors = Vec::new();
    let ramps: &[(&str, &str)] = &[
        ("accent", "--color-accent-"),
        ("sanguine", "--color-sanguine-"),
        ("neutral", "--color-neutral-"),
    ];
    let steps = [
        "100", "200", "300", "400", "500", "600", "700", "800", "900",
    ];
    let css_lower = tokens_css.to_lowercase();
    let ts_lower = tokens_ts.to_lowercase();

    let color_obj = tokens_json.get("color");
    for &(ramp_name, css_prefix) in ramps {
        let ramp = color_obj.and_then(|c| c.get(ramp_name));
        for step in &steps {
            let val = ramp
                .and_then(|r| r.get(step))
                .and_then(|s| s.get("$value"))
                .and_then(|v| v.as_str());
            match val {
                None => {
                    errors.push(format!("Missing color.{ramp_name}.{step} in tokens.json"));
                }
                Some(hex_raw) => {
                    let hex = hex_raw.to_lowercase();
                    let expected_css = format!("{css_prefix}{step}: {hex};");
                    if !css_lower.contains(&expected_css) {
                        errors.push(format!(
                            "Missing or mismatched '{expected_css}' in tokens.css"
                        ));
                    }
                    if !ts_lower.contains(&hex) {
                        errors.push(format!("Missing '{hex}' ({ramp_name}.{step}) in tokens.ts"));
                    }
                }
            }
        }
    }
    if errors.is_empty() {
        Ok(())
    } else {
        Err(errors)
    }
}

pub fn check_fibonacci_spacing_and_zero_radius(
    tokens_json: &JsonValue,
    tokens_css: &str,
) -> Result<(), Vec<String>> {
    let mut errors = Vec::new();
    let expected_fib: &[(&str, &str)] = &[
        ("1", "3px"),
        ("2", "5px"),
        ("3", "8px"),
        ("4", "13px"),
        ("5", "21px"),
        ("6", "34px"),
        ("7", "55px"),
        ("8", "89px"),
    ];
    for &(k, v) in expected_fib {
        let json_val = tokens_json
            .get("space")
            .and_then(|s| s.get(k))
            .and_then(|s| s.get("$value"))
            .and_then(|s| s.as_str());
        match json_val {
            Some(jv) if jv == v => {}
            Some(jv) => errors.push(format!(
                "space.{k} in tokens.json is '{jv}', expected '{v}'"
            )),
            None => errors.push(format!("Missing space.{k} in tokens.json")),
        }
        let css_needle = format!("--space-{k}: {v};");
        if !tokens_css.contains(&css_needle) {
            errors.push(format!("Missing '{css_needle}' in tokens.css"));
        }
    }

    for r in &["sm", "md", "lg"] {
        let json_val = tokens_json
            .get("radius")
            .and_then(|s| s.get(*r))
            .and_then(|s| s.get("$value"))
            .and_then(|s| s.as_str());
        match json_val {
            Some("0px") => {}
            Some(jv) => errors.push(format!(
                "radius.{r} must be 0px (Vitruvian square geometry), got '{jv}'"
            )),
            None => errors.push(format!("Missing radius.{r} in tokens.json")),
        }
        let css_needle = format!("--radius-{r}: 0px;");
        if !tokens_css.contains(&css_needle) {
            errors.push(format!("Missing '{css_needle}' in tokens.css"));
        }
    }

    if errors.is_empty() {
        Ok(())
    } else {
        Err(errors)
    }
}

fn is_word_boundary(c: u8) -> bool {
    !(c.is_ascii_alphanumeric() || c == b'_')
}

fn contains_word(text: &str, word: &str) -> bool {
    let haystack = text.as_bytes();
    let needle = word.as_bytes();
    if needle.is_empty() {
        return true;
    }
    let mut start = 0;
    while start + needle.len() <= haystack.len() {
        if let Some(idx) = text[start..].find(word) {
            let abs = start + idx;
            let before_ok = abs == 0 || is_word_boundary(haystack[abs - 1]);
            let after_pos = abs + needle.len();
            let after_ok = after_pos >= haystack.len() || is_word_boundary(haystack[after_pos]);
            if before_ok && after_ok {
                return true;
            }
            start = abs + 1;
        } else {
            break;
        }
    }
    false
}

pub fn check_index_exports_complete_component_surface(
    index_ts: &str,
    src_dir: &Path,
) -> Result<(), Vec<String>> {
    let mut errors = Vec::new();
    let required_exports: &[&str] = &[
        "VitruvianTokens",
        "tokens",
        "Plate",
        "RegistrationMarks",
        "VMark",
        "BrandMark",
        "BrandLogo",
        "BrandMedallion",
        "Rule",
        "Glass",
        "Button",
        "Tag",
        "Label",
        "Kbd",
        "Card",
        "Field",
        "Input",
        "Textarea",
        "Select",
        "Checkbox",
        "Radio",
        "Switch",
        "Segmented",
        "Slider",
        "CopyButton",
        "Nav",
        "Tabs",
        "Shell",
        "SideGroup",
        "SideItem",
        "Crumbs",
        "HostChip",
        "TopBar",
        "TabBar",
        "Rail",
        "SectionHeader",
        "Section",
        "MobileShell",
        "Pagination",
        "Avatar",
        "Status",
        "Metric",
        "Meter",
        "SegBar",
        "Spark",
        "BarChart",
        "LogStream",
        "Table",
        "Terminal",
        "Code",
        "BlinkingCursor",
        "Dialog",
        "Banner",
        "Menu",
        "MenuItem",
        "MenuDivider",
        "BottomSheet",
        "Tooltip",
        "Popover",
        "Toast",
        "Drawer",
        "CommandPalette",
        "EmptyState",
        "Skeleton",
        "Spinner",
        "VIcon",
        "VitruvianIcons",
        "ListItem",
        "AutoGrid",
        "KeyValue",
        "Accordion",
        "VitruvianPlate",
        "PlateFigure",
        "VitruvianStockImages",
        "DuotoneImage",
    ];
    for sym in required_exports {
        if !contains_word(index_ts, sym) {
            errors.push(format!(
                "Missing export '{sym}' in packages/design-system/src/index.ts"
            ));
        }
    }
    if !src_dir
        .join("brand")
        .join("vitruvian-medallion.png")
        .is_file()
    {
        errors.push(
            "Missing official brand medallion PNG in src/brand/vitruvian-medallion.png".into(),
        );
    }
    if !src_dir.join("brand").join("vitruvian-mark.svg").is_file() {
        errors.push("Missing official vector brand mark in src/brand/vitruvian-mark.svg".into());
    }
    if errors.is_empty() {
        Ok(())
    } else {
        Err(errors)
    }
}

pub fn check_dark_light_theme_parity(
    tokens_json: &JsonValue,
    tokens_css: &str,
    tokens_ts: &str,
) -> Result<(), Vec<String>> {
    let mut errors = Vec::new();

    // JSON: light.color must exist with required overrides
    let light_color = tokens_json.get("light").and_then(|l| l.get("color"));
    let required_light_keys: &[&str] = &[
        "bg",
        "surface",
        "surface-2",
        "text",
        "text-dim",
        "divider",
        "line",
        "accent-text",
        "accent-quiet",
        "on-accent",
        "sanguine-text",
        "ok",
        "warn",
    ];
    match light_color {
        None => {
            errors.push("Missing light.color overrides in tokens.json".into());
        }
        Some(lc) => {
            if let Some(obj) = lc.as_object() {
                for key in required_light_keys {
                    if !obj.contains_key(*key) {
                        errors.push(format!("Missing light.color.{key} override in tokens.json"));
                    }
                }
            } else {
                errors.push("light.color in tokens.json is not an object".into());
            }
        }
    }

    // CSS: [data-theme="light"] section must exist
    if !tokens_css.contains("[data-theme=\"light\"]") {
        errors.push("Missing [data-theme=\"light\"] section in tokens.css".into());
    }

    // TS: color.dark and color.light must both be present
    if !tokens_ts.contains("dark:") && !tokens_ts.contains("dark :") {
        errors.push("Missing color.dark theme object in tokens.ts".into());
    }
    if !tokens_ts.contains("light:") && !tokens_ts.contains("light :") {
        errors.push("Missing color.light theme object in tokens.ts".into());
    }

    if errors.is_empty() {
        Ok(())
    } else {
        Err(errors)
    }
}

pub fn check_tailwind_theme_sync(vitruvian_css: &str) -> Result<(), Vec<String>> {
    let mut errors = Vec::new();

    if !vitruvian_css.contains("@theme inline") {
        errors.push("Missing @theme inline block in vitruvian.css".into());
    }

    // Check for a non-inline @theme block. Look for "@theme" that is NOT followed by " inline"
    let has_bare_theme = {
        let mut found = false;
        let mut search_start = 0;
        while let Some(idx) = vitruvian_css[search_start..].find("@theme") {
            let abs = search_start + idx;
            let after = &vitruvian_css[abs + 6..];
            if !after.starts_with(" inline") {
                found = true;
                break;
            }
            search_start = abs + 6;
        }
        found
    };
    if !has_bare_theme {
        errors.push("Missing @theme block (non-inline) in vitruvian.css".into());
    }

    // Fibonacci spacing in @theme block
    let expected_spacing: &[(&str, &str)] = &[
        ("1", "3px"),
        ("2", "5px"),
        ("3", "8px"),
        ("4", "13px"),
        ("5", "21px"),
        ("6", "34px"),
        ("7", "55px"),
        ("8", "89px"),
    ];
    for &(k, v) in expected_spacing {
        let needle = format!("--spacing-{k}: {v}");
        if !vitruvian_css.contains(&needle) {
            errors.push(format!(
                "Missing or mismatched --spacing-{k}: {v} in vitruvian.css @theme block"
            ));
        }
    }

    // Zero radius in @theme block
    for r in &["sm", "md", "lg"] {
        let needle = format!("--radius-{r}: 0px");
        if !vitruvian_css.contains(&needle) {
            errors.push(format!(
                "Missing or mismatched --radius-{r}: 0px in vitruvian.css @theme block"
            ));
        }
    }

    if errors.is_empty() {
        Ok(())
    } else {
        Err(errors)
    }
}

// ---------------------------------------------------------------------------
// Top-level runner
// ---------------------------------------------------------------------------

pub fn run_all_checks(pkg_dir: &Path) -> Result<(), Vec<String>> {
    let src_dir = pkg_dir.join("src");
    let tokens_json_text =
        std::fs::read_to_string(src_dir.join("tokens.json")).map_err(|e| vec![e.to_string()])?;
    let tokens_css =
        std::fs::read_to_string(src_dir.join("tokens.css")).map_err(|e| vec![e.to_string()])?;
    let tokens_ts =
        std::fs::read_to_string(src_dir.join("tokens.ts")).map_err(|e| vec![e.to_string()])?;
    let index_ts =
        std::fs::read_to_string(src_dir.join("index.ts")).map_err(|e| vec![e.to_string()])?;
    let vitruvian_css =
        std::fs::read_to_string(src_dir.join("vitruvian.css")).map_err(|e| vec![e.to_string()])?;

    let tokens_json = parse_json(&tokens_json_text).map_err(|e| vec![e])?;

    let mut all_errors = Vec::new();

    if let Err(mut e) = check_no_remote_font_import(&tokens_css) {
        all_errors.append(&mut e);
    }
    if let Err(mut e) = check_all_font_face_urls_exist_on_disk(&tokens_css, &src_dir) {
        all_errors.append(&mut e);
    }
    if let Err(mut e) =
        check_color_ramps_match_between_json_css_and_ts(&tokens_json, &tokens_css, &tokens_ts)
    {
        all_errors.append(&mut e);
    }
    if let Err(mut e) = check_fibonacci_spacing_and_zero_radius(&tokens_json, &tokens_css) {
        all_errors.append(&mut e);
    }
    if let Err(mut e) = check_index_exports_complete_component_surface(&index_ts, &src_dir) {
        all_errors.append(&mut e);
    }
    if let Err(mut e) = check_dark_light_theme_parity(&tokens_json, &tokens_css, &tokens_ts) {
        all_errors.append(&mut e);
    }
    if let Err(mut e) = check_tailwind_theme_sync(&vitruvian_css) {
        all_errors.append(&mut e);
    }

    if all_errors.is_empty() {
        Ok(())
    } else {
        Err(all_errors)
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    // Helper: load real files from runfiles for integration tests.
    fn load_real_files() -> (PathBuf, JsonValue, String, String, String, String) {
        let pkg_dir = find_pkg_dir().expect("find_pkg_dir should locate design-system");
        let src = pkg_dir.join("src");
        let json_text = fs::read_to_string(src.join("tokens.json")).unwrap();
        let tokens_json = parse_json(&json_text).unwrap();
        let tokens_css = fs::read_to_string(src.join("tokens.css")).unwrap();
        let tokens_ts = fs::read_to_string(src.join("tokens.ts")).unwrap();
        let index_ts = fs::read_to_string(src.join("index.ts")).unwrap();
        let vitruvian_css = fs::read_to_string(src.join("vitruvian.css")).unwrap();
        (
            pkg_dir,
            tokens_json,
            tokens_css,
            tokens_ts,
            index_ts,
            vitruvian_css,
        )
    }

    // ── (a) Real-file validation ──────────────────────────────────────────

    #[test]
    fn test_real_no_remote_font_import() {
        let (_, _, css, _, _, _) = load_real_files();
        assert!(check_no_remote_font_import(&css).is_ok());
    }

    #[test]
    fn test_real_font_face_urls_exist() {
        let (pkg, _, css, _, _, _) = load_real_files();
        assert!(check_all_font_face_urls_exist_on_disk(&css, &pkg.join("src")).is_ok());
    }

    #[test]
    fn test_real_color_ramps_match() {
        let (_, json, css, ts, _, _) = load_real_files();
        assert!(check_color_ramps_match_between_json_css_and_ts(&json, &css, &ts).is_ok());
    }

    #[test]
    fn test_real_fibonacci_spacing_and_zero_radius() {
        let (_, json, css, _, _, _) = load_real_files();
        assert!(check_fibonacci_spacing_and_zero_radius(&json, &css).is_ok());
    }

    #[test]
    fn test_real_index_exports() {
        let (pkg, _, _, _, idx, _) = load_real_files();
        assert!(check_index_exports_complete_component_surface(&idx, &pkg.join("src")).is_ok());
    }

    #[test]
    fn test_real_dark_light_theme_parity() {
        let (_, json, css, ts, _, _) = load_real_files();
        assert!(check_dark_light_theme_parity(&json, &css, &ts).is_ok());
    }

    #[test]
    fn test_real_tailwind_theme_sync() {
        let (_, _, _, _, _, vcss) = load_real_files();
        assert!(check_tailwind_theme_sync(&vcss).is_ok());
    }

    #[test]
    fn test_real_run_all_checks() {
        let pkg_dir = find_pkg_dir().unwrap();
        assert!(run_all_checks(&pkg_dir).is_ok());
    }

    // ── (b) Synthetic drift/failure tests ─────────────────────────────────

    #[test]
    fn test_reject_remote_font_import() {
        let css = "@import url('https://fonts.googleapis.com/css2?family=Roboto');";
        let errs = check_no_remote_font_import(css).unwrap_err();
        assert!(errs[0].contains("Google Fonts @import"));
    }

    #[test]
    fn test_reject_missing_font_file() {
        let css = r#"
            url("./fonts/real-1.woff2") url("./fonts/real-2.woff2")
            url("./fonts/real-3.woff2") url("./fonts/real-4.woff2")
            url("./fonts/real-5.woff2") url("./fonts/real-6.woff2")
            url("./fonts/real-7.woff2") url("./fonts/real-8.woff2")
            url("./fonts/real-9.woff2") url("./fonts/real-10.woff2")
            url("./fonts/real-11.woff2") url("./fonts/real-12.woff2")
            url("./fonts/nonexistent-font.woff2")
        "#;
        let tmp = std::env::temp_dir().join("ds-test-missing-font");
        let _ = fs::remove_dir_all(&tmp);
        fs::create_dir_all(tmp.join("fonts")).unwrap();
        fs::write(tmp.join("fonts").join("OFL.txt"), "license").unwrap();
        let errs = check_all_font_face_urls_exist_on_disk(css, &tmp).unwrap_err();
        assert!(errs
            .iter()
            .any(|e| e.contains("Missing vendored font file")));
        let _ = fs::remove_dir_all(&tmp);
    }

    #[test]
    fn test_reject_missing_ofl() {
        let css = r#"
            url("./fonts/a.woff2") url("./fonts/b.woff2")
            url("./fonts/c.woff2") url("./fonts/d.woff2")
            url("./fonts/e.woff2") url("./fonts/f.woff2")
            url("./fonts/g.woff2") url("./fonts/h.woff2")
            url("./fonts/i.woff2") url("./fonts/j.woff2")
            url("./fonts/k.woff2") url("./fonts/l.woff2")
        "#;
        let tmp = std::env::temp_dir().join("ds-test-missing-ofl");
        let _ = fs::remove_dir_all(&tmp);
        fs::create_dir_all(tmp.join("fonts")).unwrap();
        for name in &[
            "a.woff2", "b.woff2", "c.woff2", "d.woff2", "e.woff2", "f.woff2", "g.woff2", "h.woff2",
            "i.woff2", "j.woff2", "k.woff2", "l.woff2",
        ] {
            fs::write(tmp.join("fonts").join(name), b"font").unwrap();
        }
        // No OFL.txt
        let errs = check_all_font_face_urls_exist_on_disk(css, &tmp).unwrap_err();
        assert!(errs.iter().any(|e| e.contains("OFL.txt")));
        let _ = fs::remove_dir_all(&tmp);
    }

    #[test]
    fn test_reject_color_ramp_drift_json() {
        // JSON missing accent.300
        let json_text = r##"{
            "color": {
                "accent": {
                    "100": {"$type":"color","$value":"#eff4f9"},
                    "200": {"$type":"color","$value":"#d8e4ee"},
                    "400": {"$type":"color","$value":"#93b0ca"},
                    "500": {"$type":"color","$value":"#5980a6"},
                    "600": {"$type":"color","$value":"#4a6d90"},
                    "700": {"$type":"color","$value":"#3b5776"},
                    "800": {"$type":"color","$value":"#2c405a"},
                    "900": {"$type":"color","$value":"#1e2c3d"}
                },
                "sanguine": {
                    "100": {"$type":"color","$value":"#faeeea"},
                    "200": {"$type":"color","$value":"#f2d8cf"},
                    "300": {"$type":"color","$value":"#e5b8a8"},
                    "400": {"$type":"color","$value":"#d2907b"},
                    "500": {"$type":"color","$value":"#b4553c"},
                    "600": {"$type":"color","$value":"#9c4832"},
                    "700": {"$type":"color","$value":"#7e3a29"},
                    "800": {"$type":"color","$value":"#5c2c20"},
                    "900": {"$type":"color","$value":"#3d1f17"}
                },
                "neutral": {
                    "100": {"$type":"color","$value":"#f2f3f4"},
                    "200": {"$type":"color","$value":"#dee1e3"},
                    "300": {"$type":"color","$value":"#c2c7cb"},
                    "400": {"$type":"color","$value":"#9ca4aa"},
                    "500": {"$type":"color","$value":"#778087"},
                    "600": {"$type":"color","$value":"#5a6369"},
                    "700": {"$type":"color","$value":"#40474c"},
                    "800": {"$type":"color","$value":"#2a3035"},
                    "900": {"$type":"color","$value":"#151a1e"}
                }
            }
        }"##;
        let json = parse_json(json_text).unwrap();
        let css = "--color-accent-100: #eff4f9; --color-accent-200: #d8e4ee; --color-accent-300: #bacfe0; --color-accent-400: #93b0ca; --color-accent-500: #5980a6; --color-accent-600: #4a6d90; --color-accent-700: #3b5776; --color-accent-800: #2c405a; --color-accent-900: #1e2c3d; --color-sanguine-100: #faeeea; --color-sanguine-200: #f2d8cf; --color-sanguine-300: #e5b8a8; --color-sanguine-400: #d2907b; --color-sanguine-500: #b4553c; --color-sanguine-600: #9c4832; --color-sanguine-700: #7e3a29; --color-sanguine-800: #5c2c20; --color-sanguine-900: #3d1f17; --color-neutral-100: #f2f3f4; --color-neutral-200: #dee1e3; --color-neutral-300: #c2c7cb; --color-neutral-400: #9ca4aa; --color-neutral-500: #778087; --color-neutral-600: #5a6369; --color-neutral-700: #40474c; --color-neutral-800: #2a3035; --color-neutral-900: #151a1e;";
        let ts = "#eff4f9 #d8e4ee #bacfe0 #93b0ca #5980a6 #4a6d90 #3b5776 #2c405a #1e2c3d #faeeea #f2d8cf #e5b8a8 #d2907b #b4553c #9c4832 #7e3a29 #5c2c20 #3d1f17 #f2f3f4 #dee1e3 #c2c7cb #9ca4aa #778087 #5a6369 #40474c #2a3035 #151a1e";
        let errs = check_color_ramps_match_between_json_css_and_ts(&json, css, ts).unwrap_err();
        assert!(errs.iter().any(|e| e.contains("accent.300")));
    }

    #[test]
    fn test_reject_color_ramp_drift_css() {
        let json_text = r##"{
            "color": {
                "accent": {
                    "100": {"$type":"color","$value":"#eff4f9"},
                    "200": {"$type":"color","$value":"#d8e4ee"},
                    "300": {"$type":"color","$value":"#bacfe0"},
                    "400": {"$type":"color","$value":"#93b0ca"},
                    "500": {"$type":"color","$value":"#5980a6"},
                    "600": {"$type":"color","$value":"#4a6d90"},
                    "700": {"$type":"color","$value":"#3b5776"},
                    "800": {"$type":"color","$value":"#2c405a"},
                    "900": {"$type":"color","$value":"#1e2c3d"}
                },
                "sanguine": {
                    "100": {"$type":"color","$value":"#faeeea"},
                    "200": {"$type":"color","$value":"#f2d8cf"},
                    "300": {"$type":"color","$value":"#e5b8a8"},
                    "400": {"$type":"color","$value":"#d2907b"},
                    "500": {"$type":"color","$value":"#b4553c"},
                    "600": {"$type":"color","$value":"#9c4832"},
                    "700": {"$type":"color","$value":"#7e3a29"},
                    "800": {"$type":"color","$value":"#5c2c20"},
                    "900": {"$type":"color","$value":"#3d1f17"}
                },
                "neutral": {
                    "100": {"$type":"color","$value":"#f2f3f4"},
                    "200": {"$type":"color","$value":"#dee1e3"},
                    "300": {"$type":"color","$value":"#c2c7cb"},
                    "400": {"$type":"color","$value":"#9ca4aa"},
                    "500": {"$type":"color","$value":"#778087"},
                    "600": {"$type":"color","$value":"#5a6369"},
                    "700": {"$type":"color","$value":"#40474c"},
                    "800": {"$type":"color","$value":"#2a3035"},
                    "900": {"$type":"color","$value":"#151a1e"}
                }
            }
        }"##;
        let json = parse_json(json_text).unwrap();
        // accent-200 has WRONG hex
        let css = "--color-accent-100: #eff4f9; --color-accent-200: #ffffff; --color-accent-300: #bacfe0; --color-accent-400: #93b0ca; --color-accent-500: #5980a6; --color-accent-600: #4a6d90; --color-accent-700: #3b5776; --color-accent-800: #2c405a; --color-accent-900: #1e2c3d; --color-sanguine-100: #faeeea; --color-sanguine-200: #f2d8cf; --color-sanguine-300: #e5b8a8; --color-sanguine-400: #d2907b; --color-sanguine-500: #b4553c; --color-sanguine-600: #9c4832; --color-sanguine-700: #7e3a29; --color-sanguine-800: #5c2c20; --color-sanguine-900: #3d1f17; --color-neutral-100: #f2f3f4; --color-neutral-200: #dee1e3; --color-neutral-300: #c2c7cb; --color-neutral-400: #9ca4aa; --color-neutral-500: #778087; --color-neutral-600: #5a6369; --color-neutral-700: #40474c; --color-neutral-800: #2a3035; --color-neutral-900: #151a1e;";
        let ts = "#eff4f9 #d8e4ee #bacfe0 #93b0ca #5980a6 #4a6d90 #3b5776 #2c405a #1e2c3d #faeeea #f2d8cf #e5b8a8 #d2907b #b4553c #9c4832 #7e3a29 #5c2c20 #3d1f17 #f2f3f4 #dee1e3 #c2c7cb #9ca4aa #778087 #5a6369 #40474c #2a3035 #151a1e";
        let errs = check_color_ramps_match_between_json_css_and_ts(&json, css, ts).unwrap_err();
        assert!(errs
            .iter()
            .any(|e| e.contains("accent-200") && e.contains("tokens.css")));
    }

    #[test]
    fn test_reject_color_ramp_drift_ts() {
        let json_text = r##"{
            "color": {
                "accent": {
                    "100": {"$type":"color","$value":"#eff4f9"},
                    "200": {"$type":"color","$value":"#d8e4ee"},
                    "300": {"$type":"color","$value":"#bacfe0"},
                    "400": {"$type":"color","$value":"#93b0ca"},
                    "500": {"$type":"color","$value":"#5980a6"},
                    "600": {"$type":"color","$value":"#4a6d90"},
                    "700": {"$type":"color","$value":"#3b5776"},
                    "800": {"$type":"color","$value":"#2c405a"},
                    "900": {"$type":"color","$value":"#1e2c3d"}
                },
                "sanguine": {
                    "100": {"$type":"color","$value":"#faeeea"},
                    "200": {"$type":"color","$value":"#f2d8cf"},
                    "300": {"$type":"color","$value":"#e5b8a8"},
                    "400": {"$type":"color","$value":"#d2907b"},
                    "500": {"$type":"color","$value":"#b4553c"},
                    "600": {"$type":"color","$value":"#9c4832"},
                    "700": {"$type":"color","$value":"#7e3a29"},
                    "800": {"$type":"color","$value":"#5c2c20"},
                    "900": {"$type":"color","$value":"#3d1f17"}
                },
                "neutral": {
                    "100": {"$type":"color","$value":"#f2f3f4"},
                    "200": {"$type":"color","$value":"#dee1e3"},
                    "300": {"$type":"color","$value":"#c2c7cb"},
                    "400": {"$type":"color","$value":"#9ca4aa"},
                    "500": {"$type":"color","$value":"#778087"},
                    "600": {"$type":"color","$value":"#5a6369"},
                    "700": {"$type":"color","$value":"#40474c"},
                    "800": {"$type":"color","$value":"#2a3035"},
                    "900": {"$type":"color","$value":"#151a1e"}
                }
            }
        }"##;
        let json = parse_json(json_text).unwrap();
        let css = "--color-accent-100: #eff4f9; --color-accent-200: #d8e4ee; --color-accent-300: #bacfe0; --color-accent-400: #93b0ca; --color-accent-500: #5980a6; --color-accent-600: #4a6d90; --color-accent-700: #3b5776; --color-accent-800: #2c405a; --color-accent-900: #1e2c3d; --color-sanguine-100: #faeeea; --color-sanguine-200: #f2d8cf; --color-sanguine-300: #e5b8a8; --color-sanguine-400: #d2907b; --color-sanguine-500: #b4553c; --color-sanguine-600: #9c4832; --color-sanguine-700: #7e3a29; --color-sanguine-800: #5c2c20; --color-sanguine-900: #3d1f17; --color-neutral-100: #f2f3f4; --color-neutral-200: #dee1e3; --color-neutral-300: #c2c7cb; --color-neutral-400: #9ca4aa; --color-neutral-500: #778087; --color-neutral-600: #5a6369; --color-neutral-700: #40474c; --color-neutral-800: #2a3035; --color-neutral-900: #151a1e;";
        // TS is missing #bacfe0 (accent.300)
        let ts = "#eff4f9 #d8e4ee #93b0ca #5980a6 #4a6d90 #3b5776 #2c405a #1e2c3d #faeeea #f2d8cf #e5b8a8 #d2907b #b4553c #9c4832 #7e3a29 #5c2c20 #3d1f17 #f2f3f4 #dee1e3 #c2c7cb #9ca4aa #778087 #5a6369 #40474c #2a3035 #151a1e";
        let errs = check_color_ramps_match_between_json_css_and_ts(&json, css, ts).unwrap_err();
        assert!(errs
            .iter()
            .any(|e| e.contains("#bacfe0") && e.contains("tokens.ts")));
    }

    #[test]
    fn test_reject_wrong_spacing() {
        let json_text = r#"{
            "space": {
                "1": {"$type":"dimension","$value":"4px"},
                "2": {"$type":"dimension","$value":"5px"},
                "3": {"$type":"dimension","$value":"8px"},
                "4": {"$type":"dimension","$value":"13px"},
                "5": {"$type":"dimension","$value":"21px"},
                "6": {"$type":"dimension","$value":"34px"},
                "7": {"$type":"dimension","$value":"55px"},
                "8": {"$type":"dimension","$value":"89px"}
            },
            "radius": {
                "sm": {"$type":"dimension","$value":"0px"},
                "md": {"$type":"dimension","$value":"0px"},
                "lg": {"$type":"dimension","$value":"0px"}
            }
        }"#;
        let json = parse_json(json_text).unwrap();
        let css = "--space-1: 4px; --space-2: 5px; --space-3: 8px; --space-4: 13px; --space-5: 21px; --space-6: 34px; --space-7: 55px; --space-8: 89px; --radius-sm: 0px; --radius-md: 0px; --radius-lg: 0px;";
        let errs = check_fibonacci_spacing_and_zero_radius(&json, css).unwrap_err();
        assert!(errs.iter().any(|e| e.contains("space.1")));
    }

    #[test]
    fn test_reject_nonzero_radius() {
        let json_text = r#"{
            "space": {
                "1": {"$type":"dimension","$value":"3px"},
                "2": {"$type":"dimension","$value":"5px"},
                "3": {"$type":"dimension","$value":"8px"},
                "4": {"$type":"dimension","$value":"13px"},
                "5": {"$type":"dimension","$value":"21px"},
                "6": {"$type":"dimension","$value":"34px"},
                "7": {"$type":"dimension","$value":"55px"},
                "8": {"$type":"dimension","$value":"89px"}
            },
            "radius": {
                "sm": {"$type":"dimension","$value":"4px"},
                "md": {"$type":"dimension","$value":"0px"},
                "lg": {"$type":"dimension","$value":"0px"}
            }
        }"#;
        let json = parse_json(json_text).unwrap();
        let css = "--space-1: 3px; --space-2: 5px; --space-3: 8px; --space-4: 13px; --space-5: 21px; --space-6: 34px; --space-7: 55px; --space-8: 89px; --radius-sm: 4px; --radius-md: 0px; --radius-lg: 0px;";
        let errs = check_fibonacci_spacing_and_zero_radius(&json, css).unwrap_err();
        assert!(errs
            .iter()
            .any(|e| e.contains("radius.sm") && e.contains("0px")));
    }

    #[test]
    fn test_reject_missing_export() {
        let index = "export { Button } from './Button.js';";
        let tmp = std::env::temp_dir().join("ds-test-missing-export");
        let _ = fs::remove_dir_all(&tmp);
        fs::create_dir_all(tmp.join("brand")).unwrap();
        fs::write(tmp.join("brand").join("vitruvian-medallion.png"), b"png").unwrap();
        fs::write(tmp.join("brand").join("vitruvian-mark.svg"), b"svg").unwrap();
        let errs = check_index_exports_complete_component_surface(index, &tmp).unwrap_err();
        // Should be missing most exports
        assert!(errs.iter().any(|e| e.contains("VitruvianTokens")));
        let _ = fs::remove_dir_all(&tmp);
    }

    #[test]
    fn test_reject_missing_brand_assets() {
        let (_, _, _, _, idx, _) = load_real_files();
        let tmp = std::env::temp_dir().join("ds-test-missing-brand");
        let _ = fs::remove_dir_all(&tmp);
        fs::create_dir_all(tmp.join("brand")).unwrap();
        // No medallion or mark files
        let errs = check_index_exports_complete_component_surface(&idx, &tmp).unwrap_err();
        assert!(errs.iter().any(|e| e.contains("vitruvian-medallion.png")));
        assert!(errs.iter().any(|e| e.contains("vitruvian-mark.svg")));
        let _ = fs::remove_dir_all(&tmp);
    }

    #[test]
    fn test_reject_missing_light_theme_json() {
        let json_text = r#"{"color": {"accent": {}}}"#;
        let json = parse_json(json_text).unwrap();
        let css = r#"[data-theme="light"] { --color-bg: #eeebe4; }"#;
        let ts = "color: { dark: { bg: '#0e1317' }, light: { bg: '#eeebe4' } }";
        let errs = check_dark_light_theme_parity(&json, css, ts).unwrap_err();
        assert!(errs.iter().any(|e| e.contains("light.color")));
    }

    #[test]
    fn test_reject_missing_light_theme_css() {
        let json_text = r##"{
            "light": {
                "color": {
                    "bg": {"$type":"color","$value":"#eeebe4"},
                    "surface": {"$type":"color","$value":"#f5f3ee"},
                    "surface-2": {"$type":"color","$value":"#e5e1d8"},
                    "text": {"$type":"color","$value":"#1a2024"},
                    "text-dim": {"$type":"color","$value":"#5c666d"},
                    "divider": {"$type":"color","$value":"#1a20242e"},
                    "line": {"$type":"color","$value":"#1a202414"},
                    "accent-text": {"$type":"color","$value":"#3b5776"},
                    "accent-quiet": {"$type":"color","$value":"#5980a629"},
                    "on-accent": {"$type":"color","$value":"#f5f3ee"},
                    "sanguine-text": {"$type":"color","$value":"#7e3a29"},
                    "ok": {"$type":"color","$value":"#3f7a5b"},
                    "warn": {"$type":"color","$value":"#94702a"}
                }
            }
        }"##;
        let json = parse_json(json_text).unwrap();
        // CSS has NO [data-theme="light"]
        let css = ":root { --color-bg: #0e1317; }";
        let ts = "color: { dark: { bg: '#0e1317' }, light: { bg: '#eeebe4' } }";
        let errs = check_dark_light_theme_parity(&json, css, ts).unwrap_err();
        assert!(errs
            .iter()
            .any(|e| e.contains("data-theme") && e.contains("light")));
    }

    #[test]
    fn test_reject_tailwind_spacing_drift() {
        let css = r#"
@theme inline {
  --font-display: var(--font-display);
}
@theme {
  --spacing-0: 0px;
  --spacing-1: 4px;
  --spacing-2: 5px;
  --spacing-3: 8px;
  --spacing-4: 13px;
  --spacing-5: 21px;
  --spacing-6: 34px;
  --spacing-7: 55px;
  --spacing-8: 89px;
  --radius-sm: 0px;
  --radius-md: 0px;
  --radius-lg: 0px;
}
"#;
        let errs = check_tailwind_theme_sync(css).unwrap_err();
        assert!(errs.iter().any(|e| e.contains("--spacing-1: 3px")));
    }

    #[test]
    fn test_reject_tailwind_radius_drift() {
        let css = r#"
@theme inline {
  --font-display: var(--font-display);
}
@theme {
  --spacing-0: 0px;
  --spacing-1: 3px;
  --spacing-2: 5px;
  --spacing-3: 8px;
  --spacing-4: 13px;
  --spacing-5: 21px;
  --spacing-6: 34px;
  --spacing-7: 55px;
  --spacing-8: 89px;
  --radius-sm: 4px;
  --radius-md: 0px;
  --radius-lg: 0px;
}
"#;
        let errs = check_tailwind_theme_sync(css).unwrap_err();
        assert!(errs.iter().any(|e| e.contains("--radius-sm: 0px")));
    }

    // ── (c) Python parity test ────────────────────────────────────────────

    #[test]
    fn test_python_parity() {
        use std::process::Command;

        let python = match Command::new("python3").arg("--version").output() {
            Ok(o) if o.status.success() => "python3",
            _ => {
                eprintln!("python3 not available, skipping parity test");
                return;
            }
        };

        let pkg_dir = match find_pkg_dir() {
            Ok(d) => d,
            Err(_) => {
                eprintln!("design-system not found, skipping parity test");
                return;
            }
        };

        let test_py = pkg_dir.join("tools").join("tokens_sync_test.py");
        if !test_py.is_file() {
            eprintln!("tokens_sync_test.py not found, skipping parity test");
            return;
        }

        // Both should pass on real files
        let py_result = Command::new(python)
            .arg(&test_py)
            .env("PYTHONDONTWRITEBYTECODE", "1")
            .current_dir(&pkg_dir)
            .output()
            .expect("failed to run python3");
        let rust_result = run_all_checks(&pkg_dir);

        assert!(
            py_result.status.success(),
            "Python test failed on real files: {}",
            String::from_utf8_lossy(&py_result.stderr)
        );
        assert!(
            rust_result.is_ok(),
            "Rust check failed on real files: {:?}",
            rust_result
        );

        // Create a broken temp dir: tokens.json missing accent.300
        let tmp = std::env::temp_dir().join("ds-parity-test");
        let _ = fs::remove_dir_all(&tmp);
        let tmp_src = tmp.join("src");
        fs::create_dir_all(&tmp_src).unwrap();
        fs::create_dir_all(tmp_src.join("fonts")).unwrap();
        fs::create_dir_all(tmp_src.join("brand")).unwrap();

        // Copy real files
        let real_src = pkg_dir.join("src");
        for name in &["tokens.css", "tokens.ts", "index.ts", "vitruvian.css"] {
            fs::copy(real_src.join(name), tmp_src.join(name)).unwrap();
        }

        // Copy brand assets
        if real_src
            .join("brand")
            .join("vitruvian-medallion.png")
            .is_file()
        {
            fs::copy(
                real_src.join("brand").join("vitruvian-medallion.png"),
                tmp_src.join("brand").join("vitruvian-medallion.png"),
            )
            .unwrap();
        }
        if real_src.join("brand").join("vitruvian-mark.svg").is_file() {
            fs::copy(
                real_src.join("brand").join("vitruvian-mark.svg"),
                tmp_src.join("brand").join("vitruvian-mark.svg"),
            )
            .unwrap();
        }

        // Copy font files
        if let Ok(entries) = fs::read_dir(real_src.join("fonts")) {
            for entry in entries.flatten() {
                let dest = tmp_src.join("fonts").join(entry.file_name());
                let _ = fs::copy(entry.path(), dest);
            }
        }

        // Write broken tokens.json (missing accent.300)
        let broken_json = r##"{
  "$schema": "https://tr.designtokens.org/format/",
  "color": {
    "accent": {
      "100": {"$type":"color","$value":"#eff4f9"},
      "200": {"$type":"color","$value":"#d8e4ee"},
      "400": {"$type":"color","$value":"#93b0ca"},
      "500": {"$type":"color","$value":"#5980a6"},
      "600": {"$type":"color","$value":"#4a6d90"},
      "700": {"$type":"color","$value":"#3b5776"},
      "800": {"$type":"color","$value":"#2c405a"},
      "900": {"$type":"color","$value":"#1e2c3d"}
    },
    "sanguine": {
      "100": {"$type":"color","$value":"#faeeea"},
      "200": {"$type":"color","$value":"#f2d8cf"},
      "300": {"$type":"color","$value":"#e5b8a8"},
      "400": {"$type":"color","$value":"#d2907b"},
      "500": {"$type":"color","$value":"#b4553c"},
      "600": {"$type":"color","$value":"#9c4832"},
      "700": {"$type":"color","$value":"#7e3a29"},
      "800": {"$type":"color","$value":"#5c2c20"},
      "900": {"$type":"color","$value":"#3d1f17"}
    },
    "neutral": {
      "100": {"$type":"color","$value":"#f2f3f4"},
      "200": {"$type":"color","$value":"#dee1e3"},
      "300": {"$type":"color","$value":"#c2c7cb"},
      "400": {"$type":"color","$value":"#9ca4aa"},
      "500": {"$type":"color","$value":"#778087"},
      "600": {"$type":"color","$value":"#5a6369"},
      "700": {"$type":"color","$value":"#40474c"},
      "800": {"$type":"color","$value":"#2a3035"},
      "900": {"$type":"color","$value":"#151a1e"}
    }
  },
  "space": {
    "1": {"$type":"dimension","$value":"3px"},
    "2": {"$type":"dimension","$value":"5px"},
    "3": {"$type":"dimension","$value":"8px"},
    "4": {"$type":"dimension","$value":"13px"},
    "5": {"$type":"dimension","$value":"21px"},
    "6": {"$type":"dimension","$value":"34px"},
    "7": {"$type":"dimension","$value":"55px"},
    "8": {"$type":"dimension","$value":"89px"}
  },
  "radius": {
    "sm": {"$type":"dimension","$value":"0px"},
    "md": {"$type":"dimension","$value":"0px"},
    "lg": {"$type":"dimension","$value":"0px"}
  }
}"##;
        fs::write(tmp_src.join("tokens.json"), broken_json).unwrap();

        // Copy the test script
        let tmp_tools = tmp.join("tools");
        fs::create_dir_all(&tmp_tools).unwrap();
        fs::copy(&test_py, tmp_tools.join("tokens_sync_test.py")).unwrap();

        let py_broken = Command::new(python)
            .arg(tmp_tools.join("tokens_sync_test.py"))
            .env("PYTHONDONTWRITEBYTECODE", "1")
            .current_dir(&tmp)
            .output()
            .expect("failed to run python3 on broken dir");
        let rust_broken = run_all_checks(&tmp);

        assert!(
            !py_broken.status.success(),
            "Python should fail on broken tokens.json"
        );
        assert!(
            rust_broken.is_err(),
            "Rust should fail on broken tokens.json"
        );

        let _ = fs::remove_dir_all(&tmp);
    }

    // ── JSON parser ───────────────────────────────────────────────────────

    #[test]
    fn test_json_parse_basic_types() {
        assert_eq!(parse_json("null").unwrap(), JsonValue::Null);
        assert_eq!(parse_json("true").unwrap(), JsonValue::Bool(true));
        assert_eq!(parse_json("false").unwrap(), JsonValue::Bool(false));
        assert_eq!(parse_json("42").unwrap(), JsonValue::Number(42.0));
        assert_eq!(parse_json("-3.14").unwrap(), JsonValue::Number(-3.14));
        assert_eq!(
            parse_json("\"hello\"").unwrap(),
            JsonValue::Str("hello".into())
        );
    }

    #[test]
    fn test_json_parse_object() {
        let val = parse_json(r#"{"a": 1, "b": "two"}"#).unwrap();
        assert_eq!(val.get("a"), Some(&JsonValue::Number(1.0)));
        assert_eq!(val.get("b").unwrap().as_str(), Some("two"));
    }

    #[test]
    fn test_json_parse_array() {
        let val = parse_json("[1, 2, 3]").unwrap();
        assert_eq!(val.as_array().unwrap().len(), 3);
    }

    #[test]
    fn test_json_parse_nested() {
        let val = parse_json(r#"{"a": {"b": [1, "x"]}}"#).unwrap();
        let inner = val.get("a").unwrap().get("b").unwrap().as_array().unwrap();
        assert_eq!(inner.len(), 2);
    }

    #[test]
    fn test_json_parse_escape() {
        let val = parse_json(r#""hello\nworld""#).unwrap();
        assert_eq!(val.as_str(), Some("hello\nworld"));
    }

    #[test]
    fn test_word_boundary_check() {
        assert!(contains_word("export { Button } from", "Button"));
        assert!(!contains_word("export { CopyButton } from", "Button"));
        assert!(contains_word("Button,", "Button"));
        assert!(contains_word("{Button}", "Button"));
        assert!(!contains_word("ButtonProps", "Button"));
    }

    #[test]
    fn test_font_url_extraction() {
        let css = r#"src: url("./fonts/ibm-plex-sans-400-latin.woff2") format("woff2");
src: url('./fonts/jetbrains-mono-400-latin.woff2') format("woff2");"#;
        let urls = extract_font_urls(css);
        assert_eq!(urls.len(), 2);
        assert_eq!(urls[0], "ibm-plex-sans-400-latin.woff2");
        assert_eq!(urls[1], "jetbrains-mono-400-latin.woff2");
    }
}
