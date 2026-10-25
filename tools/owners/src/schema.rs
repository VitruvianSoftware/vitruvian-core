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

//! The OWNERS file schema and its two readings: YAML first, then the legacy
//! one-handle-per-line format when the YAML reading fails or declares nothing.

use crate::gostr;
use crate::yaml;
use serde::Deserialize;

/// What yaml.v3 decoded into the Go struct. A null field leaves the zero
/// value; a null list element never arrives (see yaml.rs).
#[derive(Debug, Default, Deserialize)]
struct RawConfig {
    #[serde(default)]
    approvers: Option<Vec<Option<String>>>,
    #[serde(default)]
    reviewers: Option<Vec<Option<String>>>,
    #[serde(default)]
    owners: Option<Vec<Option<String>>>,
    #[serde(default)]
    options: Option<RawOptions>,
    #[serde(default)]
    per_file: Option<Vec<Option<RawPerFile>>>,
}

#[derive(Debug, Default, Deserialize)]
struct RawOptions {
    #[serde(default)]
    no_parent_owners: Option<bool>,
}

#[derive(Debug, Default, Deserialize)]
struct RawPerFile {
    #[serde(default)]
    pattern: Option<String>,
    #[serde(default)]
    approvers: Option<Vec<Option<String>>>,
    #[serde(default)]
    reviewers: Option<Vec<Option<String>>>,
    #[serde(default)]
    owners: Option<Vec<Option<String>>>,
}

fn strings(v: Option<Vec<Option<String>>>) -> Vec<String> {
    v.unwrap_or_default()
        .into_iter()
        .map(Option::unwrap_or_default)
        .collect()
}

#[derive(Debug, Default, Clone, PartialEq)]
pub struct Options {
    pub no_parent_owners: bool,
}

#[derive(Debug, Default, Clone, PartialEq)]
pub struct PerFileRule {
    pub pattern: String,
    pub approvers: Vec<String>,
    pub reviewers: Vec<String>,
    pub owners: Vec<String>,
}

#[derive(Debug, Default, Clone, PartialEq)]
pub struct Config {
    pub approvers: Vec<String>,
    pub reviewers: Vec<String>,
    pub owners: Vec<String>,
    pub options: Options,
    pub per_file: Vec<PerFileRule>,
}

impl From<RawConfig> for Config {
    fn from(r: RawConfig) -> Self {
        Config {
            approvers: strings(r.approvers),
            reviewers: strings(r.reviewers),
            owners: strings(r.owners),
            options: Options {
                no_parent_owners: r.options.and_then(|o| o.no_parent_owners).unwrap_or(false),
            },
            per_file: r
                .per_file
                .unwrap_or_default()
                .into_iter()
                .map(|p| {
                    let p = p.unwrap_or_default();
                    PerFileRule {
                        pattern: p.pattern.unwrap_or_default(),
                        approvers: strings(p.approvers),
                        reviewers: strings(p.reviewers),
                        owners: strings(p.owners),
                    }
                })
                .collect(),
        }
    }
}

impl Config {
    /// All approvers, then all owners, without repeats or empty entries.
    pub fn effective_approvers(&self) -> Vec<String> {
        let mut out: Vec<String> = Vec::new();
        for a in self.approvers.iter().chain(self.owners.iter()) {
            if !a.is_empty() && !out.contains(a) {
                out.push(a.clone());
            }
        }
        out
    }
}

fn is_re2_space(b: u8) -> bool {
    matches!(b, b'\t' | b'\n' | 0x0c | b'\r' | b' ')
}

/// The Go tool's `(?m)^(\s*-\s+)(@[^\s#"']+)` -> `$1"$2"`: quotes an unquoted
/// `@handle` list item so YAML can read it.
pub fn quote_handles(data: &str) -> String {
    let b = data.as_bytes();
    let mut out = String::with_capacity(data.len() + 16);
    let mut copied = 0;
    let mut p = 0;
    while p <= b.len() {
        if p == 0 || b[p - 1] == b'\n' {
            if let Some((g1_end, end)) = match_handle_item(b, p) {
                out.push_str(&data[copied..g1_end]);
                out.push('"');
                out.push_str(&data[g1_end..end]);
                out.push('"');
                copied = end;
                p = end;
                continue;
            }
        }
        p += 1;
    }
    out.push_str(&data[copied..]);
    out
}

fn match_handle_item(b: &[u8], start: usize) -> Option<(usize, usize)> {
    let mut i = start;
    while i < b.len() && is_re2_space(b[i]) {
        i += 1;
    }
    if i >= b.len() || b[i] != b'-' {
        return None;
    }
    i += 1;
    let ws = i;
    while i < b.len() && is_re2_space(b[i]) {
        i += 1;
    }
    if i == ws || i >= b.len() || b[i] != b'@' {
        return None;
    }
    let g1_end = i;
    i += 1;
    let body = i;
    while i < b.len() && !is_re2_space(b[i]) && !matches!(b[i], b'#' | b'"' | b'\'') {
        i += 1;
    }
    if i == body {
        return None;
    }
    Some((g1_end, i))
}

/// Go's `ParseConfig`.
pub fn parse_config(data: &[u8]) -> Result<Config, String> {
    let text = String::from_utf8_lossy(data);
    if gostr::trim_space(&text).is_empty() {
        return Err("OWNERS file is empty".to_string());
    }

    let sanitized = quote_handles(&text);
    if let Ok(node) = yaml::parse(&sanitized) {
        if let Ok(raw) = RawConfig::deserialize(&node) {
            let cfg = Config::from(raw);
            if !cfg.approvers.is_empty()
                || !cfg.owners.is_empty()
                || !cfg.reviewers.is_empty()
                || !cfg.per_file.is_empty()
                || cfg.options.no_parent_owners
            {
                return Ok(cfg);
            }
        }
    }

    let mut cfg = Config::default();
    let mut lines: Vec<&str> = text.split('\n').collect();
    if lines.last() == Some(&"") {
        lines.pop();
    }
    for raw in lines {
        let line = gostr::trim_space(raw.strip_suffix('\r').unwrap_or(raw));
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        if line == "set noparent" || line.contains("no_parent_owners: true") {
            cfg.options.no_parent_owners = true;
            continue;
        }
        for f in gostr::fields(line) {
            let f = f.trim_matches(|c| matches!(c, '-' | ',' | '"' | '\'' | ':'));
            if f.starts_with('@') || f.contains('/') {
                cfg.approvers.push(f.to_string());
            }
        }
    }
    if cfg.approvers.is_empty() && cfg.owners.is_empty() && !cfg.options.no_parent_owners {
        return Err("no valid owners/approvers declared".to_string());
    }
    Ok(cfg)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_config_cases() {
        let c = parse_config(b"\napprovers:\n  - @VitruvianSoftware/devx-team\n  - @alice\noptions:\n  no_parent_owners: true\n").unwrap();
        assert_eq!(c.effective_approvers().len(), 2);
        assert!(c.options.no_parent_owners);

        let c = parse_config(b"\nset noparent\n@VitruvianSoftware/platform-team\n@bob\n").unwrap();
        assert_eq!(c.effective_approvers().len(), 2);
        assert!(c.options.no_parent_owners);

        assert_eq!(
            parse_config(b"   \n  ").unwrap_err(),
            "OWNERS file is empty"
        );
        assert_eq!(
            parse_config(b"# nothing\nfoo bar\n").unwrap_err(),
            "no valid owners/approvers declared"
        );
    }

    #[test]
    fn quote_handles_matches_the_go_regex() {
        assert_eq!(
            quote_handles("a:\n  - @x/y\n  - \"@q\"\n- @z # c"),
            "a:\n  - \"@x/y\"\n  - \"@q\"\n- \"@z\" # c"
        );
        assert_eq!(quote_handles("-@x\n- @"), "-@x\n- @");
        assert_eq!(quote_handles("\n\n  -\n @x"), "\n\n  -\n \"@x\"");
    }

    #[test]
    fn yaml_types_fall_back_to_lines() {
        // A scalar where a list belongs is a yaml.v3 type error, so the line
        // reading is what counts.
        let c = parse_config(b"approvers: @a\n").unwrap();
        assert_eq!(c.approvers, vec!["@a"]);
        let c = parse_config(b"approvers: [~, x, '']\n").unwrap();
        assert_eq!(c.approvers, vec!["x", ""]);
        let c = parse_config(b"options:\n  no_parent_owners: yes\n").unwrap();
        assert!(c.options.no_parent_owners);
    }
}
