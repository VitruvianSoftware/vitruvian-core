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

//! Go string helpers the port needs: UTF-8 decoding with Go's error rules,
//! strconv.Quote (with Go's IsPrint table), and filepath.Join.

use crate::unicode_tables::PRINT;

/// utf8.DecodeRune: the rune (None for an invalid encoding) and its width.
pub fn decode_rune(s: &[u8]) -> (Option<char>, usize) {
    let b0 = s[0];
    if b0 < 0x80 {
        return (Some(b0 as char), 1);
    }
    let (n, min, init) = match b0 {
        0xC2..=0xDF => (2, 0x80, (b0 & 0x1F) as u32),
        0xE0..=0xEF => (3, 0x800, (b0 & 0x0F) as u32),
        0xF0..=0xF4 => (4, 0x10000, (b0 & 0x07) as u32),
        _ => return (None, 1),
    };
    if s.len() < n {
        return (None, 1);
    }
    let mut cp = init;
    for &b in &s[1..n] {
        if b & 0xC0 != 0x80 {
            return (None, 1);
        }
        cp = (cp << 6) | (b & 0x3F) as u32;
    }
    if cp < min || cp > 0x10FFFF || (0xD800..=0xDFFF).contains(&cp) {
        return (None, 1);
    }
    (char::from_u32(cp), n)
}

/// strconv.IsPrint.
pub fn is_print(c: char) -> bool {
    let cp = c as u32;
    PRINT
        .binary_search_by(|&(lo, hi)| {
            if hi < cp {
                std::cmp::Ordering::Less
            } else if lo > cp {
                std::cmp::Ordering::Greater
            } else {
                std::cmp::Ordering::Equal
            }
        })
        .is_ok()
}

const HEX: &[u8; 16] = b"0123456789abcdef";

/// strconv.Quote (also what fmt's %q prints for a string).
pub fn quote(s: &[u8]) -> Vec<u8> {
    let mut buf = Vec::with_capacity(s.len() + 2);
    buf.push(b'"');
    let mut i = 0;
    while i < s.len() {
        let (r, w) = decode_rune(&s[i..]);
        match r {
            None => {
                buf.extend_from_slice(b"\\x");
                buf.push(HEX[(s[i] >> 4) as usize]);
                buf.push(HEX[(s[i] & 15) as usize]);
            }
            Some(c) => escape_rune(&mut buf, c, b'"'),
        }
        i += w;
    }
    buf.push(b'"');
    buf
}

/// strconv's appendEscapedRune (not ASCII-only, not graphic-only).
pub fn escape_rune(buf: &mut Vec<u8>, c: char, quote: u8) {
    if c as u32 == quote as u32 || c == '\\' {
        buf.push(b'\\');
        buf.push(c as u8);
        return;
    }
    if is_print(c) {
        let mut tmp = [0u8; 4];
        buf.extend_from_slice(c.encode_utf8(&mut tmp).as_bytes());
        return;
    }
    match c {
        '\u{07}' => buf.extend_from_slice(b"\\a"),
        '\u{08}' => buf.extend_from_slice(b"\\b"),
        '\u{0C}' => buf.extend_from_slice(b"\\f"),
        '\n' => buf.extend_from_slice(b"\\n"),
        '\r' => buf.extend_from_slice(b"\\r"),
        '\t' => buf.extend_from_slice(b"\\t"),
        '\u{0B}' => buf.extend_from_slice(b"\\v"),
        _ => {
            let r = c as u32;
            if r < 0x20 || r == 0x7f {
                buf.extend_from_slice(b"\\x");
                buf.push(HEX[(r >> 4) as usize & 15]);
                buf.push(HEX[r as usize & 15]);
            } else if r < 0x10000 {
                buf.extend_from_slice(b"\\u");
                for sh in [12, 8, 4, 0] {
                    buf.push(HEX[((r >> sh) & 15) as usize]);
                }
            } else {
                buf.extend_from_slice(b"\\U");
                for sh in [28, 24, 20, 16, 12, 8, 4, 0] {
                    buf.push(HEX[((r >> sh) & 15) as usize]);
                }
            }
        }
    }
}

/// filepath.Join: the non-empty elements joined by "/", then Clean.
pub fn join(elems: &[&[u8]]) -> Vec<u8> {
    let mut out: Vec<u8> = Vec::new();
    let mut any = false;
    for e in elems {
        if e.is_empty() {
            continue;
        }
        if any {
            out.push(b'/');
        }
        out.extend_from_slice(e);
        any = true;
    }
    if !any {
        return Vec::new();
    }
    crate::goexec::clean(&out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn quote_matches_go() {
        assert_eq!(quote(b"12x"), b"\"12x\"");
        assert_eq!(quote(b"a\"b\\c"), b"\"a\\\"b\\\\c\"");
        assert_eq!(quote(b"\n\t\x01\x7f"), b"\"\\n\\t\\x01\\x7f\"");
        assert_eq!(quote(b"\xff"), b"\"\\xff\"");
        assert_eq!(
            quote("é\u{AD}\u{200B}😀".as_bytes()),
            "\"é\\u00ad\\u200b😀\"".as_bytes()
        );
        assert_eq!(quote("\u{E0001}".as_bytes()), b"\"\\U000e0001\"");
    }

    #[test]
    fn join_matches_go() {
        assert_eq!(join(&[b"", b"tools", b"copybara"]), b"tools/copybara");
        assert_eq!(join(&[b"/ws/", b"tools"]), b"/ws/tools");
        assert_eq!(join(&[b"", b""]), b"");
    }
}
