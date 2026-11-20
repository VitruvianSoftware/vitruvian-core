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

//! Shared Go standard-library helpers whose exact output or semantics Rust
//! ports depend on: `utf8.DecodeRune`, Unix `path`/`filepath` `Clean` and
//! `Join`, `syscall.Errno.Error()`, and `*os.PathError` formatting.

use std::io;

/// `utf8.DecodeRune`: the rune at the start of `b` and its width, or
/// `(None, 1)` for an invalid or truncated sequence — Go replaces each such
/// byte with U+FFFD, whereas Rust's `from_utf8_lossy` replaces a maximal
/// invalid prefix. Returns `(None, 0)` for an empty slice.
pub fn decode_rune(b: &[u8]) -> (Option<char>, usize) {
    if b.is_empty() {
        return (None, 0);
    }
    let b0 = b[0];
    if b0 < 0x80 {
        return (Some(b0 as char), 1);
    }
    let cont = |i: usize, lo: u8, hi: u8| -> bool { i < b.len() && b[i] >= lo && b[i] <= hi };
    let (n, lo, hi) = match b0 {
        0xC2..=0xDF => (2, 0x80, 0xBF),
        0xE0 => (3, 0xA0, 0xBF),
        0xE1..=0xEC | 0xEE..=0xEF => (3, 0x80, 0xBF),
        0xED => (3, 0x80, 0x9F),
        0xF0 => (4, 0x90, 0xBF),
        0xF1..=0xF3 => (4, 0x80, 0xBF),
        0xF4 => (4, 0x80, 0x8F),
        _ => return (None, 1),
    };
    if !cont(1, lo, hi) {
        return (None, 1);
    }
    for i in 2..n {
        if !cont(i, 0x80, 0xBF) {
            return (None, 1);
        }
    }
    match std::str::from_utf8(&b[..n]) {
        Ok(s) => (s.chars().next(), n),
        Err(_) => (None, 1),
    }
}

/// `filepath.Clean` / `path.Clean` (Unix).
pub fn clean(path: &str) -> String {
    // `goexec::clean` only splits and joins on ASCII `/` and `.`, so valid
    // UTF-8 input always produces valid UTF-8 output.
    String::from_utf8(crate::goexec::clean(path.as_bytes())).expect("clean preserves valid UTF-8")
}

/// `filepath.Join` / `path.Join` (Unix).
pub fn join(parts: &[&str]) -> String {
    let nonempty: Vec<&str> = parts.iter().copied().filter(|p| !p.is_empty()).collect();
    if nonempty.is_empty() {
        return String::new();
    }
    clean(&nonempty.join("/"))
}

/// `syscall.Errno.Error()`: Go's per-OS tables are `strerror(3)` with the
/// first letter lowered, derived from Rust's own error text by stripping
/// any trailing `" (os error N)"` suffix.
pub fn errno_text(e: &io::Error) -> String {
    let full = e.to_string();
    let msg = match full.rfind(" (os error ") {
        Some(i) => &full[..i],
        None => full.as_str(),
    };
    let mut cs = msg.chars();
    match cs.next() {
        Some(f) => f.to_lowercase().collect::<String>() + cs.as_str(),
        None => String::new(),
    }
}

/// `*os.PathError`'s text: `"<op> <path>: <errno>"`.
pub fn path_error(op: &str, path: &str, e: &io::Error) -> String {
    format!("{} {}: {}", op, path, errno_text(e))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ref_clean(path: &str) -> String {
        if path.is_empty() {
            return ".".into();
        }
        let rooted = path.starts_with('/');
        let mut out: Vec<&str> = Vec::new();
        for part in path.split('/') {
            match part {
                "" | "." => {}
                ".." => {
                    if let Some(last) = out.last() {
                        if *last != ".." {
                            out.pop();
                            continue;
                        }
                    }
                    if !rooted {
                        out.push("..");
                    }
                }
                p => out.push(p),
            }
        }
        let body = out.join("/");
        if rooted {
            format!("/{}", body)
        } else if body.is_empty() {
            ".".into()
        } else {
            body
        }
    }

    fn actionpins_decode_rune(s: &[u8]) -> (u32, usize) {
        const RUNE_ERROR: u32 = 0xFFFD;
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
                        (((b0 & 0x0F) as u32) << 12)
                            | (((b1 & 0x3F) as u32) << 6)
                            | (b2 & 0x3F) as u32,
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

    #[test]
    fn clean_matches_go() {
        for (input, want) in [
            ("", "."),
            ("/", "/"),
            ("//", "/"),
            (".", "."),
            ("..", ".."),
            ("...", "..."),
            (".a", ".a"),
            ("..a", "..a"),
            ("/..", "/"),
            ("a/..", "."),
            ("/a/..", "/"),
            ("a/../..", ".."),
            ("../a/..", ".."),
            ("a/../../b", "../b"),
            ("../..", "../.."),
            ("a/b/../..", "."),
            ("a/b/..", "a"),
            ("a/../b/./c//", "b/c"),
            ("a//b/./c/..", "a/b"),
            ("/../x", "/x"),
            ("/../a", "/a"),
            ("../../x", "../../x"),
            ("../../a", "../../a"),
            ("/x/./y//z/../w/", "/x/y/w"),
            ("/é/ñ/../ü", "/é/ü"),
        ] {
            assert_eq!(clean(input), want, "clean({input:?})");
            assert_eq!(clean(input), ref_clean(input), "ref parity for {input:?}");
        }
    }

    #[test]
    fn clean_matches_reference_on_generated_inputs() {
        const ALPHABET: [char; 4] = ['a', '/', '.', 'é'];
        let mut state: u64 = 0x5EED_CAFE_BABE_1234;
        let mut next = || -> u64 {
            state = state
                .wrapping_mul(6_364_136_223_846_793_005)
                .wrapping_add(1_442_695_040_888_963_407);
            state
        };

        let mut input = String::with_capacity(24);
        for _ in 0..25_000 {
            let len = ((next() >> 32) % 13) as usize;
            input.clear();
            for _ in 0..len {
                let idx = ((next() >> 32) & 3) as usize;
                input.push(ALPHABET[idx]);
            }
            assert_eq!(clean(&input), ref_clean(&input), "clean({input:?})");
        }
    }

    #[test]
    fn join_matches_go() {
        assert_eq!(join(&[]), "");
        assert_eq!(join(&["", ""]), "");
        assert_eq!(join(&["", "a", "", "b"]), "a/b");
        assert_eq!(
            join(&["repo//x", "y.delivery.json"]),
            "repo/x/y.delivery.json"
        );
        assert_eq!(
            join(&["/ws/", ".github/workflows"]),
            "/ws/.github/workflows"
        );
        assert_eq!(join(&["a", "..", "b"]), "b");
        assert_eq!(join(&["a", ".."]), ".");
    }

    #[test]
    fn errno_text_is_go_shaped() {
        let e = io::Error::from_raw_os_error(2);
        assert_eq!(errno_text(&e), "no such file or directory");

        let with_suffix = io::Error::other("Permission denied (os error 13)");
        assert_eq!(errno_text(&with_suffix), "permission denied");

        let without_suffix = io::Error::other("Broken pipe");
        assert_eq!(errno_text(&without_suffix), "broken pipe");

        let empty = io::Error::other("");
        assert_eq!(errno_text(&empty), "");

        // When the marker appears more than once, strip from the last occurrence
        // (`rfind`), matching delivery/gen and delivery/orchestrate rather than
        // first-match (`find`).
        let double_marker =
            io::Error::other("Wrapped (os error 1): Permission denied (os error 13)");
        assert_eq!(
            errno_text(&double_marker),
            "wrapped (os error 1): Permission denied"
        );
    }

    #[test]
    fn path_error_matches_go() {
        let e = io::Error::from_raw_os_error(2);
        assert_eq!(
            path_error("open", "/nonexistent", &e),
            "open /nonexistent: no such file or directory"
        );

        let custom = io::Error::other("Permission denied (os error 13)");
        assert_eq!(
            path_error("chdir", "/tmp/secret", &custom),
            "chdir /tmp/secret: permission denied"
        );
    }

    #[test]
    fn decode_rune_matches_go() {
        // Every valid Unicode scalar value encodes and decodes identically.
        let mut buf = [0u8; 4];
        for cp in 0u32..=0x10FFFF {
            if let Some(c) = char::from_u32(cp) {
                let encoded = c.encode_utf8(&mut buf).as_bytes();
                assert_eq!(
                    decode_rune(encoded),
                    (Some(c), encoded.len()),
                    "decode_rune U+{cp:04X}"
                );
                assert_eq!(
                    actionpins_decode_rune(encoded),
                    (c as u32, encoded.len()),
                    "actionpins parity U+{cp:04X}"
                );
            }
        }

        // Empty input.
        assert_eq!(decode_rune(b""), (None, 0));
        assert_eq!(actionpins_decode_rune(b""), (0xFFFD, 0));

        // Literal U+FFFD is valid 3-byte UTF-8 (distinct from invalid 1-byte errors).
        assert_eq!(decode_rune(b"\xef\xbf\xbd"), (Some('\u{FFFD}'), 3));
        assert_eq!(actionpins_decode_rune(b"\xef\xbf\xbd"), (0xFFFD, 3));

        // Invalid lead bytes.
        for lead in (0x80u8..=0xC1).chain(0xF5..=0xFF) {
            assert_eq!(decode_rune(&[lead, 0x80, 0x80, 0x80]), (None, 1));
            assert_eq!(
                actionpins_decode_rune(&[lead, 0x80, 0x80, 0x80]),
                (0xFFFD, 1)
            );
        }

        // Truncated, overlong, surrogate, and >U+10FFFF sequences.
        for bad in [
            &b"\xc2"[..],
            b"\xe2\x82",
            b"\xe2\x82a",
            b"\xf0\x90\x80",
            b"\xc0\x80",
            b"\xc1\xbf",
            b"\xe0\x9f\xbf",
            b"\xf0\x8f\xbf\xbf",
            b"\xed\xa0\x80",
            b"\xed\xbf\xbf",
            b"\xf4\x90\x80\x80",
        ] {
            assert_eq!(decode_rune(bad), (None, 1), "bad={bad:02x?}");
            assert_eq!(actionpins_decode_rune(bad), (0xFFFD, 1), "bad={bad:02x?}");
        }

        // Byte-by-byte Go-style lossy progression from delivery/gen.
        let mut out = String::new();
        let bytes = b"\xe2\x82a";
        let mut i = 0;
        while i < bytes.len() {
            let (r, n) = decode_rune(&bytes[i..]);
            out.push(r.unwrap_or('\u{FFFD}'));
            i += n;
        }
        assert_eq!(out, "\u{FFFD}\u{FFFD}a");
    }
}
