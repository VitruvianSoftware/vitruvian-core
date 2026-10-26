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

//! The action pins the workflow is rendered with, read from
//! `.github/actions/pins/action.yml` exactly as //tools/ci/actionpins reads
//! it (that Go package is the source of truth; this is a copy of its
//! behaviour, kept here so the generator has no Go dependency).

use std::collections::HashMap;

use crate::gostr::{self, quote};

pub struct Pins {
    pins: HashMap<String, String>,
}

/// Go's RE2 `\s`: ASCII whitespace only.
fn is_re_space(c: u8) -> bool {
    matches!(c, b' ' | b'\t' | b'\n' | b'\x0c' | b'\r')
}

/// The match of
/// `^\s*(?:-\s*)?uses:\s*([^\s@]+)@([^\s#]+)(?:\s*#\s*(.*))?$` on one line:
/// (action, ref, comment). The pattern can only match one way, so this
/// reads it left to right.
fn match_uses(line: &[u8]) -> Option<(String, String, String)> {
    let n = line.len();
    let mut i = 0;
    while i < n && is_re_space(line[i]) {
        i += 1;
    }
    if i < n && line[i] == b'-' {
        i += 1;
        while i < n && is_re_space(line[i]) {
            i += 1;
        }
    }
    if !line[i..].starts_with(b"uses:") {
        return None;
    }
    i += 5;
    while i < n && is_re_space(line[i]) {
        i += 1;
    }
    let a0 = i;
    while i < n && !is_re_space(line[i]) && line[i] != b'@' {
        i += 1;
    }
    if i == a0 || i >= n || line[i] != b'@' {
        return None;
    }
    let action = &line[a0..i];
    i += 1;
    let r0 = i;
    while i < n && !is_re_space(line[i]) && line[i] != b'#' {
        i += 1;
    }
    if i == r0 {
        return None;
    }
    let sha = &line[r0..i];
    let mut comment: &[u8] = b"";
    if i < n {
        while i < n && is_re_space(line[i]) {
            i += 1;
        }
        if i >= n || line[i] != b'#' {
            return None;
        }
        i += 1;
        while i < n && is_re_space(line[i]) {
            i += 1;
        }
        // (.*) runs to the end of the line: Load splits on "\n", so there is
        // no newline for `.` to stop at.
        comment = &line[i..];
    }
    let s = |b: &[u8]| String::from_utf8_lossy(b).into_owned();
    Some((s(action), s(sha), s(comment)))
}

fn is_sha(s: &str) -> bool {
    s.len() == 40
        && s.bytes()
            .all(|c| c.is_ascii_digit() || (b'a'..=b'f').contains(&c))
}

/// Go's `ParsePinLine`: Ok(None) for a line that is not a pin.
pub fn parse_pin_line(line: &[u8]) -> Result<Option<(String, String)>, String> {
    let Some((action, sha, comment)) = match_uses(line) else {
        return Ok(None);
    };
    if !is_sha(&sha) {
        return Err(format!(
            "action {} has invalid ref {}: must be a 40-character hexadecimal commit SHA",
            quote(&action),
            quote(&sha)
        ));
    }
    let comment = gostr::trim_space(&comment);
    let mut pin = format!("{action}@{sha}");
    if !comment.is_empty() {
        pin = format!("{pin} # {comment}");
    }
    Ok(Some((action, pin)))
}

/// bufio.Scanner's default limit: a line longer than this is an error.
const MAX_SCAN_TOKEN: usize = 64 * 1024;

/// Go's `Load`.
pub fn load(path: &str) -> Result<Pins, String> {
    let mut f = std::fs::File::open(path).map_err(|e| {
        format!(
            "open action pins manifest {path}: {}",
            gostr::path_error("open", path, &e)
        )
    })?;
    let mut data = Vec::new();
    let read_err = std::io::Read::read_to_end(&mut f, &mut data)
        .err()
        .map(|e| {
            format!(
                "read action pins manifest {path}: {}",
                gostr::path_error("read", path, &e)
            )
        });

    let mut pins = HashMap::new();
    let mut line_no = 0;
    let mut rest: &[u8] = &data;
    while !rest.is_empty() {
        let (mut line, next, had_nl) = match rest.iter().position(|&c| c == b'\n') {
            Some(i) => (&rest[..i], &rest[i + 1..], true),
            None => (rest, &rest[rest.len()..], false),
        };
        let token_len = line.len() + usize::from(had_nl);
        if token_len > MAX_SCAN_TOKEN || (!had_nl && line.len() >= MAX_SCAN_TOKEN) {
            return Err(format!(
                "read action pins manifest {path}: bufio.Scanner: token too long"
            ));
        }
        rest = next;
        if line.last() == Some(&b'\r') {
            line = &line[..line.len() - 1];
        }
        line_no += 1;
        match parse_pin_line(line).map_err(|e| format!("{path}:{line_no}: {e}"))? {
            None => continue,
            Some((action, pin)) => {
                if pins.contains_key(&action) {
                    return Err(format!(
                        "{path}:{line_no}: duplicate action pin for {}",
                        quote(&action)
                    ));
                }
                pins.insert(action, pin);
            }
        }
    }
    if let Some(e) = read_err {
        return Err(e);
    }
    if pins.is_empty() {
        return Err(format!(
            "action pins manifest {path} contained 0 valid pins"
        ));
    }
    Ok(Pins { pins })
}

/// Go's `FindDefaultPath`.
pub fn find_default_path() -> Result<String, String> {
    let rel = ".github/actions/pins/action.yml";
    if let Ok(ws) = std::env::var("BUILD_WORKSPACE_DIRECTORY") {
        if !ws.is_empty() {
            let c = gostr::join(&ws, rel);
            if gostr::stat_ok(&c) {
                return Ok(c);
            }
        }
    }
    if let Ok(srcdir) = std::env::var("TEST_SRCDIR") {
        if !srcdir.is_empty() {
            let ws = std::env::var("TEST_WORKSPACE")
                .ok()
                .filter(|w| !w.is_empty());
            let ws = ws.unwrap_or_else(|| "_main".to_string());
            for c in [
                gostr::join(&gostr::join(&srcdir, &ws), rel),
                gostr::join(&srcdir, rel),
            ] {
                if gostr::stat_ok(&c) {
                    return Ok(c);
                }
            }
        }
    }
    if let Ok(mut dir) = gostr::getwd() {
        loop {
            let c = gostr::join(&dir, rel);
            if gostr::stat_ok(&c) {
                return Ok(c);
            }
            let parent = gostr::dir(&dir);
            if parent == dir {
                break;
            }
            dir = parent;
        }
    }
    Err(format!("could not locate {rel}"))
}

/// Go's `MustLoadDefault`, with the panic text as the error (the caller
/// prints it the way the Go runtime did).
pub fn load_default() -> Result<Pins, String> {
    let path =
        find_default_path().map_err(|e| format!("actionpins: failed to find pin manifest: {e}"))?;
    load(&path).map_err(|e| format!("actionpins: failed to load pin manifest: {e}"))
}

impl Pins {
    /// Go's `Lookup`; the error is what `Resolve` panics with.
    pub fn lookup(&self, action: &str) -> Result<String, String> {
        self.pins.get(action).cloned().ok_or_else(|| {
            format!(
                "actionpins: unpinned action {} (must be added to .github/actions/pins/action.yml)",
                quote(action)
            )
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const SHA: &str = "3d3c42e5aac5ba805825da76410c181273ba90b1";

    #[test]
    fn pin_lines() {
        let line = format!("      - uses: actions/checkout@{SHA} # v7.0.1  ");
        assert_eq!(
            parse_pin_line(line.as_bytes()).unwrap(),
            Some((
                "actions/checkout".into(),
                format!("actions/checkout@{SHA} # v7.0.1")
            ))
        );
        let bare = format!("uses: a/b@{SHA}");
        assert_eq!(
            parse_pin_line(bare.as_bytes()).unwrap().unwrap().1,
            format!("a/b@{SHA}")
        );
        // Trailing whitespace with no comment: the pattern's `$` cannot match.
        assert_eq!(
            parse_pin_line(format!("uses: a/b@{SHA} ").as_bytes()).unwrap(),
            None
        );
        assert_eq!(parse_pin_line(b"name: x").unwrap(), None);
        assert_eq!(
            parse_pin_line(b"uses: a/b@v1").unwrap_err(),
            "action \"a/b\" has invalid ref \"v1\": must be a 40-character hexadecimal commit SHA"
        );
    }
}
