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

//! actionpins.go in Rust: the third-party GitHub Action pins manifest
//! (`.github/actions/pins/action.yml`), and the check that generated
//! workflows use exactly those pins (the Go package's
//! `TestGeneratedWorkflowsOnlyUseManifestPins`, as a command).
//!
//! Everything is bytes, as Go strings are, so a manifest with invalid UTF-8
//! or control characters reads and errors exactly as the Go one does.

pub mod cli;
pub mod goprint;
pub mod gostd;

use gostd::{join, path_error, quote, scan_lines, trim_space, ERR_TOO_LONG};
use std::collections::BTreeMap;

/// One parsed `uses:` line: the action and its pin (`action@sha # comment`).
#[derive(Debug, PartialEq)]
pub struct Pin {
    pub action: Vec<u8>,
    pub pin: Vec<u8>,
}

/// RE2's `\s`: ASCII only, and no vertical tab.
fn re_space(b: u8) -> bool {
    matches!(b, b'\t' | b'\n' | 0x0C | b'\r' | b' ')
}

fn skip_space(line: &[u8], mut i: usize) -> usize {
    while i < line.len() && re_space(line[i]) {
        i += 1;
    }
    i
}

/// `ParsePinLine`: `Ok(None)` when the line is not a `uses: action@ref` step.
///
/// The Go pattern is
/// `(?m)^\s*(?:-\s*)?uses:\s*([^\s@]+)@([^\s#]+)(?:\s*#\s*(.*))?$` on a line
/// with no newline in it, which comes to: the whole line must be that shape,
/// so a ref followed by blanks and no `#` comment is not a step at all.
pub fn parse_pin_line(line: &[u8]) -> Result<Option<Pin>, Vec<u8>> {
    let mut i = skip_space(line, 0);
    if line.get(i) == Some(&b'-') {
        i = skip_space(line, i + 1);
    }
    if !line[i..].starts_with(b"uses:") {
        return Ok(None);
    }
    i = skip_space(line, i + "uses:".len());
    let action_start = i;
    while i < line.len() && !re_space(line[i]) && line[i] != b'@' {
        i += 1;
    }
    if i == action_start || line.get(i) != Some(&b'@') {
        return Ok(None);
    }
    let action = &line[action_start..i];
    i += 1;
    let sha_start = i;
    while i < line.len() && !re_space(line[i]) && line[i] != b'#' {
        i += 1;
    }
    if i == sha_start {
        return Ok(None);
    }
    let sha = &line[sha_start..i];
    let comment: &[u8] = if i == line.len() {
        b""
    } else {
        let j = skip_space(line, i);
        if line.get(j) != Some(&b'#') {
            return Ok(None);
        }
        &line[skip_space(line, j + 1)..]
    };

    let is_sha = sha.len() == 40 && sha.iter().all(|b| matches!(b, b'0'..=b'9' | b'a'..=b'f'));
    if !is_sha {
        let mut err = b"action ".to_vec();
        err.extend(quote(action));
        err.extend_from_slice(b" has invalid ref ");
        err.extend(quote(sha));
        err.extend_from_slice(b": must be a 40-character hexadecimal commit SHA");
        return Err(err);
    }
    let mut pin = [action, b"@", sha].concat();
    let comment = trim_space(comment);
    if !comment.is_empty() {
        pin.extend_from_slice(b" # ");
        pin.extend_from_slice(comment);
    }
    Ok(Some(Pin {
        action: action.to_vec(),
        pin,
    }))
}

/// The loaded manifest: action name to its full pin.
#[derive(Debug)]
pub struct Pins {
    pins: BTreeMap<Vec<u8>, Vec<u8>>,
}

fn prefixed(path: &[u8], line_no: usize, msg: &[u8]) -> Vec<u8> {
    let mut out = path.to_vec();
    out.extend_from_slice(format!(":{line_no}: ").as_bytes());
    out.extend_from_slice(msg);
    out
}

/// `Load`: read and parse a manifest; the error text is the Go error's.
pub fn load(path: &[u8]) -> Result<Pins, Vec<u8>> {
    let wrap = |what: &str, err: Vec<u8>| {
        let mut out = format!("{what} action pins manifest ").into_bytes();
        out.extend_from_slice(path);
        out.extend_from_slice(b": ");
        out.extend(err);
        out
    };
    let os_path = gostd::as_path(path);
    let file =
        std::fs::File::open(os_path).map_err(|e| wrap("open", path_error("open", path, &e)))?;
    let data = {
        use std::io::Read;
        let mut data = Vec::new();
        let mut file = file;
        file.read_to_end(&mut data)
            .map_err(|e| wrap("read", path_error("read", path, &e)))?;
        data
    };
    let (lines, too_long) = scan_lines(&data);
    let mut pins = BTreeMap::new();
    for (n, line) in lines.iter().enumerate() {
        let line_no = n + 1;
        match parse_pin_line(line) {
            Err(err) => return Err(prefixed(path, line_no, &err)),
            Ok(None) => continue,
            Ok(Some(p)) => {
                if pins.contains_key(&p.action) {
                    let mut msg = b"duplicate action pin for ".to_vec();
                    msg.extend(quote(&p.action));
                    return Err(prefixed(path, line_no, &msg));
                }
                pins.insert(p.action, p.pin);
            }
        }
    }
    if too_long {
        return Err(wrap("read", ERR_TOO_LONG.as_bytes().to_vec()));
    }
    if pins.is_empty() {
        let mut out = b"action pins manifest ".to_vec();
        out.extend_from_slice(path);
        out.extend_from_slice(b" contained 0 valid pins");
        return Err(out);
    }
    Ok(Pins { pins })
}

impl Pins {
    /// `Lookup`.
    pub fn lookup(&self, action: &[u8]) -> Result<&[u8], Vec<u8>> {
        match self.pins.get(action) {
            Some(pin) => Ok(pin),
            None => {
                let mut err = b"actionpins: unpinned action ".to_vec();
                err.extend(quote(action));
                err.extend_from_slice(b" (must be added to .github/actions/pins/action.yml)");
                Err(err)
            }
        }
    }

    /// `All`, sorted by action.
    pub fn all(&self) -> &BTreeMap<Vec<u8>, Vec<u8>> {
        &self.pins
    }
}

fn exists(path: &[u8]) -> bool {
    std::fs::metadata(gostd::as_path(path)).is_ok()
}

fn is_dir(path: &[u8]) -> bool {
    std::fs::metadata(gostd::as_path(path))
        .map(|m| m.is_dir())
        .unwrap_or(false)
}

fn env_bytes(name: &str) -> Vec<u8> {
    use std::os::unix::ffi::OsStrExt;
    std::env::var_os(name)
        .map(|v| v.as_bytes().to_vec())
        .unwrap_or_default()
}

/// Look for `rel` the way the Go code does: under BUILD_WORKSPACE_DIRECTORY,
/// in the test runfiles, then up from the working directory. `runfiles_first`
/// is the Go test's order for the workflows directory.
fn find(rel: &[u8], want_dir: bool, runfiles_first: bool) -> Option<Vec<u8>> {
    let ok = |p: &[u8]| if want_dir { is_dir(p) } else { exists(p) };
    let workspace = || {
        let ws = env_bytes("BUILD_WORKSPACE_DIRECTORY");
        if ws.is_empty() {
            return None;
        }
        let candidate = join(&[&ws, rel]);
        ok(&candidate).then_some(candidate)
    };
    let runfiles = || {
        let srcdir = env_bytes("TEST_SRCDIR");
        if srcdir.is_empty() {
            return None;
        }
        let mut ws = env_bytes("TEST_WORKSPACE");
        if ws.is_empty() {
            ws = b"_main".to_vec();
        }
        [join(&[&srcdir, &ws, rel]), join(&[&srcdir, rel])]
            .into_iter()
            .find(|c| ok(c))
    };
    let found = if runfiles_first {
        runfiles().or_else(workspace)
    } else {
        workspace().or_else(runfiles)
    };
    if found.is_some() {
        return found;
    }
    let mut dir = gostd::getwd()?;
    loop {
        let candidate = join(&[&dir, rel]);
        if ok(&candidate) {
            return Some(candidate);
        }
        let parent = gostd::dir(&dir);
        if parent == dir {
            return None;
        }
        dir = parent;
    }
}

pub const MANIFEST: &[u8] = b".github/actions/pins/action.yml";

/// `FindDefaultPath`.
pub fn find_default_path() -> Result<Vec<u8>, Vec<u8>> {
    find(MANIFEST, false, false).ok_or_else(|| {
        let mut err = b"could not locate ".to_vec();
        err.extend_from_slice(MANIFEST);
        err
    })
}

/// The Go test's `findWorkflowsDir`.
pub fn find_workflows_dir() -> Option<Vec<u8>> {
    find(b".github/workflows", true, true)
}

/// One workflow file's problems, as the Go test words them.
pub fn check_workflow(name: &[u8], text: &[u8], pins: &Pins) -> Vec<Vec<u8>> {
    let mut problems = Vec::new();
    // The Go test never asks the scanner for its error: a line too long for
    // it quietly ends the file's check, and so it does here.
    let (lines, _) = scan_lines(text);
    for (n, line) in lines.iter().enumerate() {
        let at = prefixed(name, n + 1, b"");
        match parse_pin_line(line) {
            Err(err) => {
                let mut msg = at;
                msg.extend_from_slice(b"invalid action pin syntax: ");
                msg.extend(err);
                problems.push(msg);
            }
            Ok(None) => {}
            Ok(Some(p)) => {
                if p.action.starts_with(b".") || p.action.starts_with(b"/") {
                    continue;
                }
                match pins.all().get(&p.action) {
                    None => {
                        let mut msg = at;
                        msg.extend_from_slice(b"unpinned third-party action ");
                        msg.extend(quote(&p.action));
                        msg.extend_from_slice(
                            b" in generated workflow (must be added to .github/actions/pins/action.yml)",
                        );
                        problems.push(msg);
                    }
                    Some(want) if *want != p.pin => {
                        let mut msg = at;
                        msg.extend_from_slice(b"mismatched pin for action ");
                        msg.extend(quote(&p.action));
                        msg.extend_from_slice(b" in ");
                        msg.extend_from_slice(name);
                        msg.extend_from_slice(b":\n  got:  ");
                        msg.extend_from_slice(&p.pin);
                        msg.extend_from_slice(b"\n  want: ");
                        msg.extend_from_slice(want);
                        problems.push(msg);
                    }
                    Some(_) => {}
                }
            }
        }
    }
    problems
}

/// Whether a workflow is one a generator wrote (only those are checked).
pub fn is_generated(text: &[u8]) -> bool {
    text.windows(b"# GENERATED by".len())
        .any(|w| w == b"# GENERATED by")
}

#[cfg(test)]
mod tests {
    use super::*;

    const SHA: &str = "3d3c42e5aac5ba805825da76410c181273ba90b1";

    fn parse(line: &str) -> Result<Option<(String, String)>, String> {
        parse_pin_line(line.as_bytes())
            .map(|p| {
                p.map(|p| {
                    (
                        String::from_utf8(p.action).unwrap(),
                        String::from_utf8(p.pin).unwrap(),
                    )
                })
            })
            .map_err(|e| String::from_utf8(e).unwrap())
    }

    fn pin(action: &str, pin: &str) -> Result<Option<(String, String)>, String> {
        Ok(Some((action.into(), pin.into())))
    }

    #[test]
    fn parse_lines_like_the_go_pattern() {
        let want = format!("actions/checkout@{SHA} # v7.0.1");
        assert_eq!(
            parse(&format!("    - uses: actions/checkout@{SHA} # v7.0.1")),
            pin("actions/checkout", &want)
        );
        assert_eq!(
            parse(&format!("uses: actions/checkout@{SHA}#v7.0.1  ")),
            pin("actions/checkout", &want)
        );
        assert_eq!(
            parse(&format!("-uses:a@{SHA}")),
            pin("a", &format!("a@{SHA}"))
        );
        assert_eq!(
            parse(&format!("  uses: a@{SHA} #   ")),
            pin("a", &format!("a@{SHA}"))
        );
        // A ref then blanks with no comment is not a step at all.
        assert_eq!(parse(&format!("uses: a@{SHA} ")), Ok(None));
        assert_eq!(parse(&format!("uses: a@{SHA} trailing")), Ok(None));
        assert_eq!(parse("name: x"), Ok(None));
        assert_eq!(parse("uses: @x"), Ok(None));
        assert_eq!(parse("uses: a b@c"), Ok(None));
        // \v is not RE2's \s.
        assert_eq!(parse(&format!("\x0buses: a@{SHA}")), Ok(None));
        assert_eq!(
            parse("  - uses: actions/checkout@v4 # tag"),
            Err("action \"actions/checkout\" has invalid ref \"v4\": must be a 40-character hexadecimal commit SHA".into())
        );
        assert_eq!(
            parse("uses: a@b@c"),
            Err("action \"a\" has invalid ref \"b@c\": must be a 40-character hexadecimal commit SHA".into())
        );
    }

    #[test]
    fn the_go_tests_manifests() {
        let dir = std::env::temp_dir().join(format!("actionpins-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("action.yml");
        let write = |text: &str| std::fs::write(&path, text).unwrap();
        let p = path.to_str().unwrap().as_bytes();

        write(&format!("steps:\n    - uses: actions/checkout@{SHA} # v7.0.1\n    - uses: astral-sh/setup-uv@1c37ad07a6a961277cf70c0d37d6f313000f5884 # v10.3.0\n"));
        let pins = load(p).unwrap();
        assert_eq!(
            pins.lookup(b"actions/checkout").unwrap(),
            format!("actions/checkout@{SHA} # v7.0.1").as_bytes()
        );
        assert!(pins.lookup(b"unknown/action").is_err());

        write("runs:\n  steps: []\n");
        assert!(String::from_utf8(load(p).unwrap_err())
            .unwrap()
            .ends_with("contained 0 valid pins"));
        write(&format!("- uses: a@{SHA}\n- uses: a@{SHA}\n"));
        assert!(String::from_utf8(load(p).unwrap_err())
            .unwrap()
            .contains(":2: duplicate action pin for \"a\""));
        write("- uses: actions/checkout@v4 # tag not SHA\n");
        assert!(load(p).is_err());
        std::fs::remove_dir_all(&dir).unwrap();
        let missing = load(b"/nonexistent/action.yml").unwrap_err();
        assert_eq!(
            String::from_utf8(missing).unwrap(),
            "open action pins manifest /nonexistent/action.yml: open /nonexistent/action.yml: no such file or directory"
        );
    }

    #[test]
    fn generated_marker() {
        assert!(is_generated(b"# GENERATED by tools/pipeline/gen\n"));
        assert!(!is_generated(b"# Generated by hand\n"));
    }
}
