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

//! The pieces of Go's standard library actionpins.go leans on, on bytes the
//! way Go strings are: UTF-8 decoding (an invalid byte is one RuneError),
//! `strconv.Quote` (what `%q` prints), `strings.TrimSpace`, `bufio.Scanner`
//! line splitting, `path/filepath`, `os.Getwd` and `*os.PathError` text.

use crate::goprint::{PRINTABLE, SPACE};
use std::io;
use std::path::Path;

const RUNE_ERROR: u32 = 0xFFFD;

fn in_table(table: &[(u32, u32)], r: u32) -> bool {
    table
        .binary_search_by(|&(lo, hi)| {
            if hi < r {
                std::cmp::Ordering::Less
            } else if lo > r {
                std::cmp::Ordering::Greater
            } else {
                std::cmp::Ordering::Equal
            }
        })
        .is_ok()
}

/// `utf8.DecodeRune`: the rune and its width; (RuneError, 1) when invalid.
pub fn decode_rune(s: &[u8]) -> (u32, usize) {
    let Some(&b0) = s.first() else {
        return (RUNE_ERROR, 0);
    };
    if b0 < 0x80 {
        return (b0 as u32, 1);
    }
    let cont = |i: usize, lo: u8, hi: u8| s.get(i).filter(|&&b| b >= lo && b <= hi).copied();
    match b0 {
        0xC2..=0xDF => match cont(1, 0x80, 0xBF) {
            Some(b1) => ((((b0 & 0x1F) as u32) << 6) | (b1 & 0x3F) as u32, 2),
            None => (RUNE_ERROR, 1),
        },
        0xE0..=0xEF => {
            let (lo, hi) = match b0 {
                0xE0 => (0xA0, 0xBF),
                0xED => (0x80, 0x9F),
                _ => (0x80, 0xBF),
            };
            match (cont(1, lo, hi), cont(2, 0x80, 0xBF)) {
                (Some(b1), Some(b2)) => (
                    (((b0 & 0x0F) as u32) << 12) | (((b1 & 0x3F) as u32) << 6) | (b2 & 0x3F) as u32,
                    3,
                ),
                _ => (RUNE_ERROR, 1),
            }
        }
        0xF0..=0xF4 => {
            let (lo, hi) = match b0 {
                0xF0 => (0x90, 0xBF),
                0xF4 => (0x80, 0x8F),
                _ => (0x80, 0xBF),
            };
            match (cont(1, lo, hi), cont(2, 0x80, 0xBF), cont(3, 0x80, 0xBF)) {
                (Some(b1), Some(b2), Some(b3)) => (
                    (((b0 & 0x07) as u32) << 18)
                        | (((b1 & 0x3F) as u32) << 12)
                        | (((b2 & 0x3F) as u32) << 6)
                        | (b3 & 0x3F) as u32,
                    4,
                ),
                _ => (RUNE_ERROR, 1),
            }
        }
        _ => (RUNE_ERROR, 1),
    }
}

/// `utf8.DecodeLastRune`.
pub fn decode_last_rune(s: &[u8]) -> (u32, usize) {
    let end = s.len();
    if end == 0 {
        return (RUNE_ERROR, 0);
    }
    let last = s[end - 1];
    if last < 0x80 {
        return (last as u32, 1);
    }
    let lim = end.saturating_sub(4);
    let mut start = end - 1;
    while start > lim {
        start -= 1;
        if s[start] & 0xC0 != 0x80 {
            break;
        }
    }
    let (r, size) = decode_rune(&s[start..end]);
    if start + size != end {
        return (RUNE_ERROR, 1);
    }
    (r, size)
}

pub fn is_print(r: u32) -> bool {
    in_table(PRINTABLE, r)
}

pub fn is_space(r: u32) -> bool {
    in_table(SPACE, r)
}

/// `strconv.Quote`.
pub fn quote(s: &[u8]) -> Vec<u8> {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let mut out = vec![b'"'];
    let mut i = 0;
    while i < s.len() {
        let (r, width) = decode_rune(&s[i..]);
        if width == 1 && r == RUNE_ERROR {
            out.extend_from_slice(b"\\x");
            out.push(HEX[(s[i] >> 4) as usize]);
            out.push(HEX[(s[i] & 0xF) as usize]);
            i += 1;
            continue;
        }
        let raw = &s[i..i + width];
        i += width;
        if r == '"' as u32 || r == '\\' as u32 {
            out.push(b'\\');
            out.extend_from_slice(raw);
        } else if is_print(r) {
            out.extend_from_slice(raw);
        } else {
            match r {
                0x07 => out.extend_from_slice(b"\\a"),
                0x08 => out.extend_from_slice(b"\\b"),
                0x0C => out.extend_from_slice(b"\\f"),
                0x0A => out.extend_from_slice(b"\\n"),
                0x0D => out.extend_from_slice(b"\\r"),
                0x09 => out.extend_from_slice(b"\\t"),
                0x0B => out.extend_from_slice(b"\\v"),
                r if r < 0x20 || r == 0x7F => {
                    out.extend_from_slice(format!("\\x{r:02x}").as_bytes());
                }
                r if r < 0x10000 => out.extend_from_slice(format!("\\u{r:04x}").as_bytes()),
                r => out.extend_from_slice(format!("\\U{r:08x}").as_bytes()),
            }
        }
    }
    out.push(b'"');
    out
}

fn ascii_space(b: u8) -> bool {
    matches!(b, b'\t' | b'\n' | 0x0B | 0x0C | b'\r' | b' ')
}

fn trim_left_func(mut s: &[u8]) -> &[u8] {
    while !s.is_empty() {
        let (r, w) = decode_rune(s);
        if !is_space(r) {
            break;
        }
        s = &s[w..];
    }
    s
}

fn trim_right_func(mut s: &[u8]) -> &[u8] {
    while !s.is_empty() {
        let (r, w) = decode_last_rune(s);
        if !is_space(r) {
            break;
        }
        s = &s[..s.len() - w];
    }
    s
}

/// `strings.TrimSpace`.
pub fn trim_space(s: &[u8]) -> &[u8] {
    let mut start = 0;
    while start < s.len() {
        let c = s[start];
        if c >= 0x80 {
            return trim_right_func(trim_left_func(&s[start..]));
        }
        if !ascii_space(c) {
            break;
        }
        start += 1;
    }
    let mut stop = s.len();
    while stop > start {
        let c = s[stop - 1];
        if c >= 0x80 {
            return trim_right_func(&s[start..stop]);
        }
        if !ascii_space(c) {
            break;
        }
        stop -= 1;
    }
    &s[start..stop]
}

/// bufio.Scanner's buffer cap: a line this long or longer stops the scan.
pub const MAX_SCAN_TOKEN: usize = 64 * 1024;

/// `bufio.Scanner` with `ScanLines`: the lines, and whether a line too long
/// for its buffer ended the scan early.
pub fn scan_lines(data: &[u8]) -> (Vec<&[u8]>, bool) {
    let mut lines = Vec::new();
    let mut rest = data;
    while !rest.is_empty() {
        let (raw, next, newline) = match rest.iter().position(|&b| b == b'\n') {
            Some(at) => (&rest[..at], &rest[at + 1..], true),
            None => (rest, &rest[rest.len()..], false),
        };
        if raw.len() + usize::from(newline) > MAX_SCAN_TOKEN || raw.len() >= MAX_SCAN_TOKEN {
            return (lines, true);
        }
        lines.push(raw.strip_suffix(b"\r").unwrap_or(raw));
        rest = next;
    }
    (lines, false)
}

pub const ERR_TOO_LONG: &str = "bufio.Scanner: token too long";

/// The text Go's syscall.Errno prints: the C library's, lower-cased first.
pub fn errno_text(err: &io::Error) -> String {
    let text = err.to_string();
    let text = match text.find(" (os error ") {
        Some(at) => &text[..at],
        None => &text,
    };
    let mut chars = text.chars();
    match chars.next() {
        Some(c) => c.to_lowercase().collect::<String>() + chars.as_str(),
        None => String::new(),
    }
}

/// `*os.PathError`'s text: `<op> <path>: <errno>`.
pub fn path_error(op: &str, path: &[u8], err: &io::Error) -> Vec<u8> {
    let mut out = op.as_bytes().to_vec();
    out.push(b' ');
    out.extend_from_slice(path);
    out.extend_from_slice(b": ");
    out.extend_from_slice(errno_text(err).as_bytes());
    out
}

/// `filepath.Clean`.
pub fn clean(path: &[u8]) -> Vec<u8> {
    if path.is_empty() {
        return b".".to_vec();
    }
    let rooted = path[0] == b'/';
    let n = path.len();
    let mut out: Vec<u8> = Vec::with_capacity(n);
    let (mut r, mut dotdot) = (0, 0);
    if rooted {
        out.push(b'/');
        r = 1;
        dotdot = 1;
    }
    while r < n {
        if path[r] == b'/' {
            r += 1;
        } else if path[r] == b'.' && (r + 1 == n || path[r + 1] == b'/') {
            r += 1;
        } else if path[r] == b'.'
            && path.get(r + 1) == Some(&b'.')
            && (r + 2 == n || path[r + 2] == b'/')
        {
            r += 2;
            if out.len() > dotdot {
                // Back up over the last element and the slash before it.
                let mut w = out.len() - 1;
                while w > dotdot && out[w] != b'/' {
                    w -= 1;
                }
                out.truncate(w);
            } else if !rooted {
                if !out.is_empty() {
                    out.push(b'/');
                }
                out.extend_from_slice(b"..");
                dotdot = out.len();
            }
        } else {
            if (rooted && out.len() != 1) || (!rooted && !out.is_empty()) {
                out.push(b'/');
            }
            while r < n && path[r] != b'/' {
                out.push(path[r]);
                r += 1;
            }
        }
    }
    if out.is_empty() {
        return b".".to_vec();
    }
    out
}

/// `filepath.Join`.
pub fn join(parts: &[&[u8]]) -> Vec<u8> {
    let kept: Vec<&[u8]> = parts.iter().copied().filter(|p| !p.is_empty()).collect();
    if kept.is_empty() {
        return Vec::new();
    }
    clean(&kept.join(&b'/'))
}

/// `filepath.Dir`.
pub fn dir(path: &[u8]) -> Vec<u8> {
    let cut = path
        .iter()
        .rposition(|&b| b == b'/')
        .map(|i| i + 1)
        .unwrap_or(0);
    clean(&path[..cut])
}

/// `filepath.Base`.
pub fn base(path: &[u8]) -> Vec<u8> {
    if path.is_empty() {
        return b".".to_vec();
    }
    let mut p = path;
    while p.len() > 1 && p.ends_with(b"/") {
        p = &p[..p.len() - 1];
    }
    if p == b"/" {
        return b"/".to_vec();
    }
    match p.iter().rposition(|&b| b == b'/') {
        Some(i) => p[i + 1..].to_vec(),
        None => p.to_vec(),
    }
}

pub fn as_path(bytes: &[u8]) -> &Path {
    use std::os::unix::ffi::OsStrExt;
    Path::new(std::ffi::OsStr::from_bytes(bytes))
}

/// `os.Getwd`: $PWD when it names the working directory, else getcwd.
pub fn getwd() -> Option<Vec<u8>> {
    use std::os::unix::ffi::OsStrExt;
    use std::os::unix::fs::MetadataExt;
    let dot = std::fs::metadata(".").ok()?;
    if let Some(pwd) = std::env::var_os("PWD") {
        let bytes = pwd.as_bytes();
        if bytes.first() == Some(&b'/') {
            if let Ok(meta) = std::fs::metadata(&pwd) {
                if meta.dev() == dot.dev() && meta.ino() == dot.ino() {
                    return Some(bytes.to_vec());
                }
            }
        }
    }
    std::env::current_dir()
        .ok()
        .map(|p| p.as_os_str().as_bytes().to_vec())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn quote_matches_go() {
        assert_eq!(quote(b"actions/checkout"), b"\"actions/checkout\"");
        assert_eq!(quote(b"a\"b\\c"), b"\"a\\\"b\\\\c\"");
        assert_eq!(quote(b"\x07\x0b\x01\x7f"), b"\"\\a\\v\\x01\\x7f\"");
        assert_eq!(quote(b"\xff\xc3"), b"\"\\xff\\xc3\"");
        assert_eq!(quote("é✓".as_bytes()), "\"é✓\"".as_bytes());
        assert_eq!(
            quote("\u{a0}\u{200b}\u{e0001}".as_bytes()),
            b"\"\\u00a0\\u200b\\U000e0001\""
        );
        assert_eq!(quote(b"\xed\xa0\x80"), b"\"\\xed\\xa0\\x80\"");
    }

    #[test]
    fn trim_space_matches_go() {
        assert_eq!(trim_space(b"  v7.0.1 \t"), b"v7.0.1");
        assert_eq!(trim_space("\u{a0}v1\u{3000}".as_bytes()), b"v1");
        assert_eq!(trim_space(b"\x0bv1\x0b"), b"v1");
        assert_eq!(trim_space(b"\xffv1 "), b"\xffv1");
        assert_eq!(trim_space(b""), b"");
    }

    #[test]
    fn scanner_lines() {
        assert_eq!(
            scan_lines(b"a\r\nb\n\nc").0,
            vec![&b"a"[..], b"b", b"", b"c"]
        );
        assert_eq!(scan_lines(b"a\n").0, vec![&b"a"[..]]);
        assert_eq!(scan_lines(b"a\r\r\n").0, vec![&b"a\r"[..]]);
        let ok = vec![b'x'; MAX_SCAN_TOKEN - 1];
        assert!(!scan_lines(&ok).1);
        let long = vec![b'x'; MAX_SCAN_TOKEN];
        assert!(scan_lines(&long).1);
    }

    #[test]
    fn paths_match_go() {
        assert_eq!(clean(b"a//b/../c/."), b"a/c");
        assert_eq!(clean(b"/../a"), b"/a");
        assert_eq!(clean(b"../../a"), b"../../a");
        assert_eq!(clean(b"a/b/.."), b"a");
        assert_eq!(clean(b"/a/.."), b"/");
        assert_eq!(clean(b"a/../.."), b"..");
        assert_eq!(clean(b"/x/./y//z/../w/"), b"/x/y/w");
        assert_eq!(clean(b""), b".");
        assert_eq!(
            join(&[b"/ws/", b".github/workflows"]),
            b"/ws/.github/workflows"
        );
        assert_eq!(join(&[b"", b""]), b"");
        assert_eq!(dir(b"/a/b"), b"/a");
        assert_eq!(dir(b"/"), b"/");
        assert_eq!(dir(b"a"), b".");
        assert_eq!(base(b"/a/b/"), b"b");
        assert_eq!(base(b"/"), b"/");
    }
}
