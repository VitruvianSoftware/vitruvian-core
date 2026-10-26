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

//! The third-party action pin manifest (.github/actions/pins/action.yml):
//! a port of //tools/ci/actionpins, kept inside this crate so the generator
//! depends on nothing outside its own package.
//!
//! Dependabot bumps that manifest natively; every `uses:` the generator
//! renders for a third-party action is looked up here, so a bump reaches the
//! generated workflows on the next regenerate with no code change.

use std::collections::HashMap;

use crate::gostd;

const REL_PATH: &str = ".github/actions/pins/action.yml";

/// bufio.Scanner's default token limit: a longer line stops the scan.
const MAX_TOKEN: usize = 64 * 1024;

#[derive(Clone, Debug, Default)]
pub struct Pins {
    pins: HashMap<String, String>,
}

fn is_re_space(c: char) -> bool {
    // RE2's \s: [\t\n\f\r ] (no \v).
    matches!(c, '\t' | '\n' | '\x0C' | '\r' | ' ')
}

/// usesPattern, `^\s*(?:-\s*)?uses:\s*([^\s@]+)@([^\s#]+)(?:\s*#\s*(.*))?$`,
/// over one line (the scanner has already split on '\n').
fn match_uses(line: &str) -> Option<(String, String, String)> {
    let mut s = line.trim_start_matches(is_re_space);
    if let Some(rest) = s.strip_prefix('-') {
        // `(?:-\s*)?` — but a leading '-' that is not followed by `uses:`
        // (after spaces) cannot match the other way either, since `uses`
        // does not start with '-'.
        s = rest.trim_start_matches(is_re_space);
    }
    let s = s.strip_prefix("uses:")?;
    let s = s.trim_start_matches(is_re_space);
    let at = s.find(|c: char| c == '@' || is_re_space(c))?;
    if at == 0 || !s[at..].starts_with('@') {
        return None;
    }
    let action = &s[..at];
    let s = &s[at + 1..];
    let end = s
        .find(|c: char| c == '#' || is_re_space(c))
        .unwrap_or(s.len());
    if end == 0 {
        return None;
    }
    let sha = &s[..end];
    let rest = &s[end..];
    if rest.is_empty() {
        return Some((action.into(), sha.into(), String::new()));
    }
    let t = rest.trim_start_matches(is_re_space);
    let t = t.strip_prefix('#')?;
    let t = t.trim_start_matches(is_re_space);
    if t.contains('\n') {
        return None;
    }
    Some((action.into(), sha.into(), t.into()))
}

fn is_sha(s: &str) -> bool {
    s.len() == 40
        && s.bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
}

/// ParsePinLine: (action, pin) for a `uses: action@sha` line, None for any
/// other line, Err for a non-SHA ref.
pub fn parse_pin_line(line: &str) -> Result<Option<(String, String)>, String> {
    let (action, sha, comment) = match match_uses(line) {
        Some(m) => m,
        None => return Ok(None),
    };
    if !is_sha(&sha) {
        return Err(format!(
            "action {} has invalid ref {}: must be a 40-character hexadecimal commit SHA",
            gostd::q(&action),
            gostd::q(&sha)
        ));
    }
    let comment = comment.trim();
    let mut pin = format!("{}@{}", action, sha);
    if !comment.is_empty() {
        pin = format!("{} # {}", pin, comment);
    }
    Ok(Some((action, pin)))
}

impl Pins {
    /// Load: read and parse a manifest.
    pub fn load(path: &str) -> Result<Pins, String> {
        let data = match std::fs::File::open(path) {
            Ok(mut f) => {
                use std::io::Read;
                let mut buf = Vec::new();
                match f.read_to_end(&mut buf) {
                    Ok(_) => Ok(buf),
                    Err(e) => Err(gostd::path_err("read", path, &e)),
                }
            }
            Err(e) => {
                return Err(format!(
                    "open action pins manifest {}: {}",
                    path,
                    gostd::path_err("open", path, &e)
                ));
            }
        };
        let mut pins = HashMap::new();
        // A read error surfaces only after the lines read before it; a
        // directory reads nothing at all.
        let (bytes, read_err) = match data {
            Ok(b) => (b, None),
            Err(e) => (Vec::new(), Some(e)),
        };
        let mut line_no = 0;
        let mut rest: &[u8] = &bytes;
        let mut scan_err: Option<String> = read_err;
        while !rest.is_empty() {
            let (raw, next) = match rest.iter().position(|&b| b == b'\n') {
                Some(i) => (&rest[..i], &rest[i + 1..]),
                None => (rest, &rest[rest.len()..]),
            };
            // The scanner's buffer holds MAX_TOKEN bytes and needs the line
            // and its terminator (a newline, or EOF observed with room to
            // spare) inside it: a line of MAX_TOKEN bytes or more is
            // ErrTooLong.
            if raw.len() >= MAX_TOKEN {
                scan_err = Some("bufio.Scanner: token too long".into());
                break;
            }
            let raw = raw.strip_suffix(b"\r").unwrap_or(raw);
            line_no += 1;
            let line = gostd::go_lossy(raw);
            match parse_pin_line(&line) {
                Err(e) => return Err(format!("{}:{}: {}", path, line_no, e)),
                Ok(None) => {}
                Ok(Some((action, pin))) => {
                    if pins.contains_key(&action) {
                        return Err(format!(
                            "{}:{}: duplicate action pin for {}",
                            path,
                            line_no,
                            gostd::q(&action)
                        ));
                    }
                    pins.insert(action, pin);
                }
            }
            rest = next;
        }
        if let Some(e) = scan_err {
            return Err(format!("read action pins manifest {}: {}", path, e));
        }
        if pins.is_empty() {
            return Err(format!(
                "action pins manifest {} contained 0 valid pins",
                path
            ));
        }
        Ok(Pins { pins })
    }

    /// FindDefaultPath: the workspace (bazel run), the runfiles (bazel test),
    /// then every directory up from the cwd.
    pub fn find_default_path() -> Result<String, String> {
        let exists = |p: &str| std::fs::metadata(p).is_ok();
        if let Some(ws) = std::env::var_os("BUILD_WORKSPACE_DIRECTORY") {
            let ws = ws.to_string_lossy();
            if !ws.is_empty() {
                let c = gostd::join(&[&ws, REL_PATH]);
                if exists(&c) {
                    return Ok(c);
                }
            }
        }
        if let Some(src) = std::env::var_os("TEST_SRCDIR") {
            let src = src.to_string_lossy();
            if !src.is_empty() {
                let ws = std::env::var("TEST_WORKSPACE")
                    .ok()
                    .filter(|s| !s.is_empty())
                    .unwrap_or_else(|| "_main".into());
                for c in [
                    gostd::join(&[&src, &ws, REL_PATH]),
                    gostd::join(&[&src, REL_PATH]),
                ] {
                    if exists(&c) {
                        return Ok(c);
                    }
                }
            }
        }
        if let Some(mut d) = gostd::getwd() {
            loop {
                let c = gostd::join(&[&d, REL_PATH]);
                if exists(&c) {
                    return Ok(c);
                }
                let parent = gostd::dir(&d);
                if parent == d {
                    break;
                }
                d = parent;
            }
        }
        Err(format!("could not locate {}", REL_PATH))
    }

    /// MustLoadDefault, with the panic turned into the message Go panicked
    /// with (the caller decides how to die).
    pub fn load_default() -> Result<Pins, String> {
        let path = Self::find_default_path()
            .map_err(|e| format!("actionpins: failed to find pin manifest: {}", e))?;
        Self::load(&path).map_err(|e| format!("actionpins: failed to load pin manifest: {}", e))
    }

    /// Lookup.
    pub fn lookup(&self, action: &str) -> Result<String, String> {
        self.pins.get(action).cloned().ok_or_else(|| {
            format!(
                "actionpins: unpinned action {} (must be added to .github/actions/pins/action.yml)",
                gostd::q(action)
            )
        })
    }

    pub fn len(&self) -> usize {
        self.pins.len()
    }

    pub fn is_empty(&self) -> bool {
        self.pins.is_empty()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const SHA: &str = "3d3c42e5aac5ba805825da76410c181273ba90b1";

    #[test]
    fn parses_pin_lines_like_the_go_regex() {
        let ok = |l: &str| parse_pin_line(l).unwrap().map(|(_, p)| p);
        assert_eq!(
            ok(&format!("  - uses: actions/checkout@{} # v7.0.1", SHA)),
            Some(format!("actions/checkout@{} # v7.0.1", SHA))
        );
        assert_eq!(
            ok(&format!("uses: a/b@{}", SHA)),
            Some(format!("a/b@{}", SHA))
        );
        assert_eq!(
            ok(&format!("uses: a/b@{}#c  ", SHA)),
            Some(format!("a/b@{} # c", SHA))
        );
        assert_eq!(ok(&format!("uses: a/b@{} trailing", SHA)), None);
        assert_eq!(ok("name: x"), None);
        assert!(parse_pin_line("uses: a/b@v4").is_err());
    }

    #[test]
    fn load_rejects_empty_and_duplicates() {
        let dir = std::env::temp_dir().join(format!("pins-test-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let p = dir.join("a.yml");
        std::fs::write(&p, "name: x\n").unwrap();
        assert!(Pins::load(p.to_str().unwrap())
            .unwrap_err()
            .contains("contained 0 valid pins"));
        std::fs::write(&p, format!("uses: a/b@{}\nuses: a/b@{}\n", SHA, SHA)).unwrap();
        assert!(Pins::load(p.to_str().unwrap())
            .unwrap_err()
            .contains(":2: duplicate action pin for \"a/b\""));
        std::fs::remove_dir_all(&dir).unwrap();
    }
}
