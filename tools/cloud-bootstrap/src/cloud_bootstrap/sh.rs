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

//! The few shell behaviours the bootstrap leans on: `${VAR:-default}`,
//! `command -v`, `$(...)` capture, bash `printf %q` (session.env is sourced by
//! every Bash tool call, so it must stay bash syntax), reading such a file back
//! the way `. file` would, and files written with a fixed mode.
//!
//! Kept inside this crate rather than taken from //tools/shell-compat so the
//! crate builds with one plain `rustc` call: it runs in a bare cloud VM before
//! Bazel is installed (it is what installs Bazel).

use std::ffi::{OsStr, OsString};
use std::fs;
use std::io::{self, Write};
use std::os::unix::ffi::{OsStrExt, OsStringExt};
use std::os::unix::fs::{DirBuilderExt, OpenOptionsExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

/// `$NAME` as bytes; None when unset.
pub fn env(name: &str) -> Option<Vec<u8>> {
    std::env::var_os(name).map(OsString::into_vec)
}

/// `${NAME:-}`.
pub fn env_or_empty(name: &str) -> Vec<u8> {
    env(name).unwrap_or_default()
}

/// `${NAME:-default}`: the value when set and non-empty, else `default`.
pub fn env_or(name: &str, default: &str) -> Vec<u8> {
    match env(name) {
        Some(v) if !v.is_empty() => v,
        _ => default.as_bytes().to_vec(),
    }
}

/// `${NAME:-default}` as a String (for names, versions, account ids).
pub fn env_str(name: &str, default: &str) -> String {
    String::from_utf8_lossy(&env_or(name, default)).into_owned()
}

pub fn os(b: &[u8]) -> &OsStr {
    OsStr::from_bytes(b)
}

pub fn path(b: &[u8]) -> PathBuf {
    PathBuf::from(os(b))
}

pub fn lossy(b: &[u8]) -> String {
    String::from_utf8_lossy(b).into_owned()
}

pub fn path_str(p: &Path) -> String {
    p.to_string_lossy().into_owned()
}

/// `${#var}`: characters when the value is UTF-8 (bash in a UTF-8 locale),
/// bytes otherwise.
pub fn char_len(v: &[u8]) -> usize {
    match std::str::from_utf8(v) {
        Ok(s) => s.chars().count(),
        Err(_) => v.len(),
    }
}

fn is_executable_file(p: &Path) -> bool {
    match fs::metadata(p) {
        Ok(m) => m.is_file() && m.permissions().mode() & 0o111 != 0,
        Err(_) => false,
    }
}

/// `[ -x path ]`.
pub fn is_executable(p: &Path) -> bool {
    match fs::metadata(p) {
        Ok(m) => m.permissions().mode() & 0o111 != 0,
        Err(_) => false,
    }
}

/// `command -v NAME` for an external command: a name with a `/` is checked as
/// it stands, any other is looked up on $PATH.
pub fn which(name: &OsStr) -> Option<PathBuf> {
    let b = name.as_bytes();
    if b.is_empty() {
        return None;
    }
    if b.contains(&b'/') {
        let p = PathBuf::from(name);
        return if is_executable_file(&p) {
            Some(p)
        } else {
            None
        };
    }
    let path_var = env_or_empty("PATH");
    for dir in path_var.split(|&c| c == b':') {
        let d: &[u8] = if dir.is_empty() { b"." } else { dir };
        let cand = path(d).join(name);
        if is_executable_file(&cand) {
            return Some(cand);
        }
    }
    None
}

pub fn has(name: &str) -> bool {
    which(OsStr::new(name)).is_some()
}

/// What `$(...)` makes of output: NULs dropped, trailing newlines removed.
pub fn subst(mut v: Vec<u8>) -> Vec<u8> {
    v.retain(|&c| c != 0);
    while v.last() == Some(&b'\n') {
        v.pop();
    }
    v
}

/// A finished child: whether it exited 0, and what it printed.
pub struct Ran {
    pub ok: bool,
    pub stdout: Vec<u8>,
    pub stderr: Vec<u8>,
}

/// Run with stdout and stderr captured. A command that cannot start is a
/// failure, its reason in `stderr` (as bash would have put it in the 2> file).
pub fn capture(cmd: &mut Command) -> Ran {
    cmd.stdout(Stdio::piped()).stderr(Stdio::piped());
    match cmd.output() {
        Ok(o) => Ran {
            ok: o.status.success(),
            stdout: o.stdout,
            stderr: o.stderr,
        },
        Err(e) => Ran {
            ok: false,
            stdout: Vec::new(),
            stderr: spawn_error(cmd, &e).into_bytes(),
        },
    }
}

/// Run with stdin fed from `input`, stdout and stderr captured (stdin closed
/// after writing, so the child sees EOF).
pub fn capture_with_input(cmd: &mut Command, input: &[u8]) -> Ran {
    cmd.stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    let mut child = match cmd.spawn() {
        Ok(c) => c,
        Err(e) => {
            return Ran {
                ok: false,
                stdout: Vec::new(),
                stderr: spawn_error(cmd, &e).into_bytes(),
            }
        }
    };
    if let Some(mut sin) = child.stdin.take() {
        // A child that exits without reading is its own failure, seen below.
        let _ = sin.write_all(input);
    }
    match child.wait_with_output() {
        Ok(o) => Ran {
            ok: o.status.success(),
            stdout: o.stdout,
            stderr: o.stderr,
        },
        Err(_) => Ran {
            ok: false,
            stdout: Vec::new(),
            stderr: Vec::new(),
        },
    }
}

/// Run to completion with stdout and stderr discarded (`>/dev/null 2>&1`).
pub fn quiet(cmd: &mut Command) -> bool {
    cmd.stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

/// Run to completion with inherited stdio. A command that cannot start is
/// reported on stderr, as bash reports it.
pub fn run(cmd: &mut Command) -> bool {
    match cmd.status() {
        Ok(s) => s.success(),
        Err(e) => {
            eprint!("{}", spawn_error(cmd, &e));
            false
        }
    }
}

fn spawn_error(cmd: &Command, e: &io::Error) -> String {
    let prog = cmd.get_program().to_string_lossy();
    if e.kind() == io::ErrorKind::NotFound {
        format!("cloud-bootstrap: {prog}: command not found\n")
    } else {
        format!("cloud-bootstrap: {prog}: {e}\n")
    }
}

/// `sed 's/^/<prefix>/'`.
pub fn indent(text: &[u8], prefix: &str) -> Vec<u8> {
    let mut out = Vec::new();
    let mut at_line_start = true;
    for &c in text {
        if at_line_start {
            out.extend_from_slice(prefix.as_bytes());
        }
        out.push(c);
        at_line_start = c == b'\n';
    }
    out
}

/// Lines of `text`, as awk/grep read them: split on '\n', no trailing empty
/// record for a final newline.
pub fn lines(text: &[u8]) -> Vec<&[u8]> {
    if text.is_empty() {
        return Vec::new();
    }
    let body = text.strip_suffix(b"\n").unwrap_or(text);
    body.split(|&c| c == b'\n').collect()
}

pub fn contains(hay: &[u8], needle: &[u8]) -> bool {
    needle.is_empty() || hay.windows(needle.len()).any(|w| w == needle)
}

/// `grep -qs <fixed> file`: false when the file is missing or unreadable.
pub fn file_contains(p: &Path, needle: &[u8]) -> bool {
    fs::read(p).map(|t| contains(&t, needle)).unwrap_or(false)
}

/// `[ -f p ]`.
pub fn is_file(p: &Path) -> bool {
    fs::metadata(p).map(|m| m.is_file()).unwrap_or(false)
}

/// `[ -s p ]`: exists and is not empty.
pub fn non_empty(p: &Path) -> bool {
    fs::metadata(p).map(|m| m.len() > 0).unwrap_or(false)
}

/// `mkdir -p dir && chmod 700 dir`, the directories created 0700 (the
/// `umask 077` the script scoped around its writes).
pub fn private_dir(dir: &Path) -> io::Result<()> {
    fs::DirBuilder::new()
        .recursive(true)
        .mode(0o700)
        .create(dir)?;
    let _ = fs::set_permissions(dir, fs::Permissions::from_mode(0o700));
    Ok(())
}

/// Write `data` to `p`, mode 0600 whether or not it existed (`(umask 077;
/// printf ... >p); chmod 600 p`). An existing file is emptied and made 0600
/// BEFORE the secret is written, so it is never readable with a wider mode.
pub fn write_private(p: &Path, data: &[u8]) -> io::Result<()> {
    let mut f = fs::OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .mode(0o600)
        .open(p)?;
    f.set_permissions(fs::Permissions::from_mode(0o600))?;
    f.write_all(data)
}

/// `printf ... >>p`: create (mode from the umask, as the shell did) and append.
pub fn append(p: &Path, data: &[u8]) -> io::Result<()> {
    let mut f = fs::OpenOptions::new().create(true).append(true).open(p)?;
    f.write_all(data)
}

// ---------------------------------------------------------------------------
// bash quoting: what `printf %q` writes, and what `. file` reads back
// ---------------------------------------------------------------------------

fn safe_unquoted(c: u8) -> bool {
    c.is_ascii_alphanumeric() || b"_./:@%+=-,~#".contains(&c)
}

/// bash `printf %q`: a word that, read back by bash, is exactly `v`. Empty is
/// `''`; plain words are left bare; printable ASCII is backslash-escaped; any
/// control byte switches to `$'...'`. (Tests source the result with real bash.)
pub fn shell_quote(v: &[u8]) -> Vec<u8> {
    if v.is_empty() {
        return b"''".to_vec();
    }
    let has_control = v.iter().any(|&c| c < 0x20 || c == 0x7f);
    if has_control {
        let mut out = b"$'".to_vec();
        for &c in v {
            match c {
                b'\n' => out.extend_from_slice(b"\\n"),
                b'\t' => out.extend_from_slice(b"\\t"),
                b'\r' => out.extend_from_slice(b"\\r"),
                b'\\' => out.extend_from_slice(b"\\\\"),
                b'\'' => out.extend_from_slice(b"\\'"),
                c if c < 0x20 || c == 0x7f => {
                    out.extend_from_slice(format!("\\{:03o}", c).as_bytes())
                }
                c => out.push(c),
            }
        }
        out.push(b'\'');
        return out;
    }
    let mut out = Vec::with_capacity(v.len());
    for (i, &c) in v.iter().enumerate() {
        // `~` and `#` only mean something at the start of a word.
        let leading_special = i == 0 && (c == b'~' || c == b'#');
        if (safe_unquoted(c) || c >= 0x80) && !leading_special {
            out.push(c);
        } else {
            out.push(b'\\');
            out.push(c);
        }
    }
    out
}

/// One shell word, as bash reads it: bare text with backslash escapes, '...',
/// "..." and $'...'. Enough for anything `printf %q` (bash 3.2 or 5) writes,
/// which is all session.env ever holds. Expansions are not performed.
pub fn shell_unquote(w: &[u8]) -> Vec<u8> {
    let mut out = Vec::new();
    let mut i = 0;
    while i < w.len() {
        let c = w[i];
        if c == b'\\' {
            if i + 1 < w.len() {
                if w[i + 1] != b'\n' {
                    out.push(w[i + 1]);
                }
                i += 2;
            } else {
                i += 1;
            }
        } else if c == b'\'' {
            i += 1;
            while i < w.len() && w[i] != b'\'' {
                out.push(w[i]);
                i += 1;
            }
            i += 1;
        } else if c == b'$' && w.get(i + 1) == Some(&b'\'') {
            i += 2;
            while i < w.len() && w[i] != b'\'' {
                if w[i] == b'\\' && i + 1 < w.len() {
                    i += 1;
                    let e = w[i];
                    match e {
                        b'n' => out.push(b'\n'),
                        b't' => out.push(b'\t'),
                        b'r' => out.push(b'\r'),
                        b'a' => out.push(0x07),
                        b'b' => out.push(0x08),
                        b'e' | b'E' => out.push(0x1b),
                        b'f' => out.push(0x0c),
                        b'v' => out.push(0x0b),
                        b'x' => {
                            let mut n: u32 = 0;
                            let mut k = 0;
                            while k < 2 && i + 1 < w.len() && (w[i + 1] as char).is_ascii_hexdigit()
                            {
                                i += 1;
                                n = n * 16 + (w[i] as char).to_digit(16).unwrap_or(0);
                                k += 1;
                            }
                            if k == 0 {
                                out.extend_from_slice(b"\\x");
                            } else {
                                out.push(n as u8);
                            }
                        }
                        b'0'..=b'7' => {
                            let mut n: u32 = (e - b'0') as u32;
                            let mut k = 1;
                            while k < 3 && i + 1 < w.len() && (b'0'..=b'7').contains(&w[i + 1]) {
                                i += 1;
                                n = n * 8 + (w[i] - b'0') as u32;
                                k += 1;
                            }
                            out.push(n as u8);
                        }
                        b'\\' | b'\'' | b'"' | b'?' => out.push(e),
                        other => {
                            out.push(b'\\');
                            out.push(other);
                        }
                    }
                    i += 1;
                } else {
                    out.push(w[i]);
                    i += 1;
                }
            }
            i += 1;
        } else if c == b'"' {
            i += 1;
            while i < w.len() && w[i] != b'"' {
                if w[i] == b'\\'
                    && i + 1 < w.len()
                    && matches!(w[i + 1], b'\\' | b'"' | b'$' | b'`' | b'\n')
                {
                    if w[i + 1] != b'\n' {
                        out.push(w[i + 1]);
                    }
                    i += 2;
                } else {
                    out.push(w[i]);
                    i += 1;
                }
            }
            i += 1;
        } else {
            out.push(c);
            i += 1;
        }
    }
    out
}

/// The `export NAME=word` lines of a session.env, in order, as `. file`
/// would apply them. Anything else in the file is ignored.
pub fn parse_exports(text: &[u8]) -> Vec<(String, Vec<u8>)> {
    let mut out = Vec::new();
    for line in lines(text) {
        let Some(rest) = line.strip_prefix(b"export ") else {
            continue;
        };
        let Some(eq) = rest.iter().position(|&c| c == b'=') else {
            continue;
        };
        let name = &rest[..eq];
        let valid = !name.is_empty()
            && !name[0].is_ascii_digit()
            && name.iter().all(|&c| c.is_ascii_alphanumeric() || c == b'_');
        if !valid {
            continue;
        }
        out.push((lossy(name), shell_unquote(&rest[eq + 1..])));
    }
    out
}

/// `. file` for a session.env: export every value into this process, so what
/// runs next (and every child) sees them.
pub fn source_exports(p: &Path) {
    if let Ok(text) = fs::read(p) {
        for (name, value) in parse_exports(&text) {
            std::env::set_var(name, os(&value));
        }
    }
}

// ---------------------------------------------------------------------------
// base64 -d
// ---------------------------------------------------------------------------

/// `base64 -d`: decodes up to the first byte that is not base64 (or the
/// padding), so malformed input yields a prefix, as coreutils does.
pub fn base64_decode(input: &[u8]) -> Vec<u8> {
    let mut out = Vec::new();
    let mut acc: u32 = 0;
    let mut bits = 0;
    for &c in input {
        let v = match c {
            b'A'..=b'Z' => c - b'A',
            b'a'..=b'z' => c - b'a' + 26,
            b'0'..=b'9' => c - b'0' + 52,
            b'+' => 62,
            b'/' => 63,
            _ => break,
        } as u32;
        acc = (acc << 6) | v;
        bits += 6;
        if bits >= 8 {
            bits -= 8;
            out.push((acc >> bits) as u8);
            acc &= (1 << bits) - 1;
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn quote_round_trips() {
        for v in [
            &b""[..],
            b"abc",
            b"a b",
            b"a'b\"c$d`e\\f",
            b"~home",
            b"#hash",
            b"line1\nline2",
            b"tab\there",
            "é-unicode".as_bytes(),
            b"\x01ctl",
            b"a=b,c:d@e%f+g/h.i-j_k",
        ] {
            assert_eq!(shell_unquote(&shell_quote(v)), v, "{:?}", lossy(v));
        }
    }

    #[test]
    fn reads_bash_32_and_5_forms() {
        assert_eq!(shell_unquote(b"a\\ b"), b"a b");
        assert_eq!(shell_unquote(b"$'a\\nb'"), b"a\nb");
        assert_eq!(shell_unquote(b"$'\\001'"), b"\x01");
        assert_eq!(shell_unquote(b"$'\\x41'"), b"A");
        assert_eq!(shell_unquote(b"''"), b"");
        assert_eq!(shell_unquote(b"'it'\\''s'"), b"it's");
    }

    #[test]
    fn exports_are_parsed_in_order() {
        let got = parse_exports(b"export A=1\n# x\nexport B=''\nexport 9X=n\nexport A=a\\ b\n");
        assert_eq!(
            got,
            vec![
                ("A".to_string(), b"1".to_vec()),
                ("B".to_string(), b"".to_vec()),
                ("A".to_string(), b"a b".to_vec()),
            ]
        );
    }

    #[test]
    fn base64_matches_coreutils() {
        assert_eq!(base64_decode(b"eyJhIjoxfQ=="), b"{\"a\":1}");
        assert_eq!(base64_decode(b"eyJhIjoxfQ"), b"{\"a\":1}");
        assert!(base64_decode(b"base64:{}").len() < 6);
    }
}
