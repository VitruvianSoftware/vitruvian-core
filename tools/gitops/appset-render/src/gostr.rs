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

//! Go string semantics the port needs, on raw bytes as Go strings are:
//! UTF-8 decoding with Go's error rules, the unicode/strconv predicates (from
//! generated tables), strconv's quoting and unquoting, and bytes.TrimSpace.

use crate::unicode_tables::{DIGIT, LETTER, PRINT};

pub const RUNE_ERROR: char = '\u{FFFD}';

/// utf8.DecodeRune: the rune (U+FFFD for an invalid encoding), its width,
/// and whether it was valid. Width is 0 only for empty input.
pub fn decode_rune(s: &[u8]) -> (char, usize, bool) {
    if s.is_empty() {
        return (RUNE_ERROR, 0, false);
    }
    let b0 = s[0];
    if b0 < 0x80 {
        return (b0 as char, 1, true);
    }
    let (n, min, init) = match b0 {
        0xC2..=0xDF => (2, 0x80, (b0 & 0x1F) as u32),
        0xE0..=0xEF => (3, 0x800, (b0 & 0x0F) as u32),
        0xF0..=0xF4 => (4, 0x10000, (b0 & 0x07) as u32),
        _ => return (RUNE_ERROR, 1, false),
    };
    if s.len() < n {
        // A truncated sequence: Go still reports width 1.
        return (RUNE_ERROR, 1, false);
    }
    let mut cp = init;
    for &b in &s[1..n] {
        if b & 0xC0 != 0x80 {
            return (RUNE_ERROR, 1, false);
        }
        cp = (cp << 6) | (b & 0x3F) as u32;
    }
    if cp < min || cp > 0x10FFFF || (0xD800..=0xDFFF).contains(&cp) {
        return (RUNE_ERROR, 1, false);
    }
    (char::from_u32(cp).unwrap_or(RUNE_ERROR), n, true)
}

/// utf8.DecodeLastRune.
pub fn decode_last_rune(s: &[u8]) -> (char, usize) {
    let end = s.len() as isize;
    if end == 0 {
        return (RUNE_ERROR, 0);
    }
    let mut start = end - 1;
    if s[start as usize] < 0x80 {
        return (s[start as usize] as char, 1);
    }
    let lim = (end - 4).max(0);
    start -= 1;
    while start >= lim {
        if s[start as usize] & 0xC0 != 0x80 {
            break;
        }
        start -= 1;
    }
    if start < 0 {
        start = 0;
    }
    let (r, size, _) = decode_rune(&s[start as usize..]);
    if start + size as isize != end {
        return (RUNE_ERROR, 1);
    }
    (r, size)
}

fn in_table(table: &[(u32, u32)], c: char) -> bool {
    let cp = c as u32;
    table
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

/// unicode.IsLetter.
pub fn is_letter(c: char) -> bool {
    if (c as u32) < 0x80 {
        return c.is_ascii_alphabetic();
    }
    in_table(LETTER, c)
}

/// unicode.IsDigit.
pub fn is_digit(c: char) -> bool {
    if (c as u32) < 0x80 {
        return c.is_ascii_digit();
    }
    in_table(DIGIT, c)
}

/// strconv.IsPrint.
pub fn is_print(c: char) -> bool {
    in_table(PRINT, c)
}

/// unicode.IsSpace.
pub fn is_unicode_space(c: char) -> bool {
    matches!(
        c,
        '\t' | '\n'
            | '\u{0B}'
            | '\u{0C}'
            | '\r'
            | ' '
            | '\u{85}'
            | '\u{A0}'
            | '\u{1680}'
            | '\u{2000}'
            ..='\u{200A}' | '\u{2028}' | '\u{2029}' | '\u{202F}' | '\u{205F}' | '\u{3000}'
    )
}

/// bytes.TrimSpace.
pub fn trim_space(s: &[u8]) -> &[u8] {
    let mut start = 0;
    while start < s.len() {
        let (r, w, ok) = decode_rune(&s[start..]);
        if ok && is_unicode_space(r) {
            start += w;
        } else {
            break;
        }
    }
    let mut end = s.len();
    while end > start {
        let (r, w) = decode_last_rune(&s[start..end]);
        if r != RUNE_ERROR && is_unicode_space(r) {
            end -= w;
        } else {
            break;
        }
    }
    &s[start..end]
}

pub fn push_rune(buf: &mut Vec<u8>, c: char) {
    let mut tmp = [0u8; 4];
    buf.extend_from_slice(c.encode_utf8(&mut tmp).as_bytes());
}

const LOWERHEX: &[u8; 16] = b"0123456789abcdef";

/// strconv's appendEscapedRune.
fn escape_rune(buf: &mut Vec<u8>, c: char, quote: u8, ascii_only: bool) {
    if c as u32 == quote as u32 || c == '\\' {
        buf.push(b'\\');
        buf.push(c as u8);
        return;
    }
    if ascii_only {
        if (c as u32) < 0x80 && is_print(c) {
            buf.push(c as u8);
            return;
        }
    } else if is_print(c) {
        push_rune(buf, c);
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
                buf.push(LOWERHEX[((r >> 4) & 15) as usize]);
                buf.push(LOWERHEX[(r & 15) as usize]);
            } else if r < 0x10000 {
                buf.extend_from_slice(b"\\u");
                for sh in [12, 8, 4, 0] {
                    buf.push(LOWERHEX[((r >> sh) & 15) as usize]);
                }
            } else {
                buf.extend_from_slice(b"\\U");
                for sh in [28, 24, 20, 16, 12, 8, 4, 0] {
                    buf.push(LOWERHEX[((r >> sh) & 15) as usize]);
                }
            }
        }
    }
}

fn quote_with(s: &[u8], quote: u8, ascii_only: bool) -> Vec<u8> {
    let mut buf = Vec::with_capacity(s.len() + 2);
    buf.push(quote);
    let mut i = 0;
    while i < s.len() {
        let (r, w, ok) = decode_rune(&s[i..]);
        if !ok && w == 1 {
            buf.extend_from_slice(b"\\x");
            buf.push(LOWERHEX[(s[i] >> 4) as usize]);
            buf.push(LOWERHEX[(s[i] & 15) as usize]);
        } else {
            escape_rune(&mut buf, r, quote, ascii_only);
        }
        i += w;
    }
    buf.push(quote);
    buf
}

/// strconv.Quote.
pub fn quote(s: &[u8]) -> Vec<u8> {
    quote_with(s, b'"', false)
}

/// strconv.QuoteToASCII.
pub fn quote_to_ascii(s: &[u8]) -> Vec<u8> {
    quote_with(s, b'"', true)
}

/// strconv.QuoteRune / QuoteRuneToASCII for a rune value (invalid -> U+FFFD).
pub fn quote_rune(r: u32, ascii_only: bool) -> Vec<u8> {
    let c = match char::from_u32(r) {
        Some(c) => c,
        None => RUNE_ERROR,
    };
    let mut buf = vec![b'\''];
    escape_rune(&mut buf, c, b'\'', ascii_only);
    buf.push(b'\'');
    buf
}

/// strconv.CanBackquote.
pub fn can_backquote(s: &[u8]) -> bool {
    let mut i = 0;
    while i < s.len() {
        let (r, w, ok) = decode_rune(&s[i..]);
        i += w;
        if w > 1 {
            if r == '\u{FEFF}' {
                return false;
            }
            continue;
        }
        if !ok {
            return false;
        }
        if ((r as u32) < 0x20 && r != '\t') || r == '`' || r == '\u{7F}' {
            return false;
        }
    }
    true
}

fn unhex(b: u8) -> Option<u32> {
    match b {
        b'0'..=b'9' => Some((b - b'0') as u32),
        b'a'..=b'f' => Some((b - b'a' + 10) as u32),
        b'A'..=b'F' => Some((b - b'A' + 10) as u32),
        _ => None,
    }
}

/// strconv.UnquoteChar: (value, multibyte, tail), or Err for ErrSyntax.
pub fn unquote_char(s: &[u8], quote: u8) -> Result<(u32, bool, &[u8]), ()> {
    if s.is_empty() {
        return Err(());
    }
    let c = s[0];
    if c == quote && (quote == b'\'' || quote == b'"') {
        return Err(());
    }
    if c >= 0x80 {
        let (r, size, _) = decode_rune(s);
        return Ok((r as u32, true, &s[size..]));
    }
    if c != b'\\' {
        return Ok((c as u32, false, &s[1..]));
    }
    if s.len() <= 1 {
        return Err(());
    }
    let c = s[1];
    let mut s = &s[2..];
    let value: u32;
    let mut multibyte = false;
    match c {
        b'a' => value = 7,
        b'b' => value = 8,
        b'f' => value = 12,
        b'n' => value = 10,
        b'r' => value = 13,
        b't' => value = 9,
        b'v' => value = 11,
        b'x' | b'u' | b'U' => {
            let n = match c {
                b'x' => 2,
                b'u' => 4,
                _ => 8,
            };
            if s.len() < n {
                return Err(());
            }
            let mut v: u32 = 0;
            for &b in &s[..n] {
                v = (v << 4) | unhex(b).ok_or(())?;
            }
            s = &s[n..];
            if c == b'x' {
                value = v;
            } else {
                if v > 0x10FFFF || (0xD800..=0xDFFF).contains(&v) {
                    return Err(());
                }
                value = v;
                multibyte = true;
            }
        }
        b'0'..=b'7' => {
            let mut v = (c - b'0') as u32;
            if s.len() < 2 {
                return Err(());
            }
            for &b in &s[..2] {
                let x = b.wrapping_sub(b'0');
                if x > 7 {
                    return Err(());
                }
                v = (v << 3) | x as u32;
            }
            s = &s[2..];
            if v > 255 {
                return Err(());
            }
            value = v;
        }
        b'\\' => value = b'\\' as u32,
        b'\'' | b'"' => {
            if c != quote {
                return Err(());
            }
            value = c as u32;
        }
        _ => return Err(()),
    }
    Ok((value, multibyte, s))
}

fn valid_utf8(s: &[u8]) -> bool {
    let mut i = 0;
    while i < s.len() {
        let (_, w, ok) = decode_rune(&s[i..]);
        if !ok {
            return false;
        }
        i += w;
    }
    true
}

/// strconv.Unquote: the unquoted bytes, or Err for ErrSyntax.
pub fn unquote(s: &[u8]) -> Result<Vec<u8>, ()> {
    if s.len() < 2 {
        return Err(());
    }
    let quote = s[0];
    let end = match s[1..].iter().position(|&b| b == quote) {
        Some(e) => e + 2,
        None => return Err(()),
    };
    match quote {
        b'`' => {
            let body = &s[1..end - 1];
            let out: Vec<u8> = body.iter().copied().filter(|&b| b != b'\r').collect();
            if end != s.len() {
                return Err(());
            }
            Ok(out)
        }
        b'"' | b'\'' => {
            let head = &s[..end];
            if !head.contains(&b'\\') && !head.contains(&b'\n') {
                let valid = if quote == b'"' {
                    valid_utf8(&s[1..end - 1])
                } else {
                    let (_, n, ok) = decode_rune(&s[1..end - 1]);
                    1 + n + 1 == end && (ok || n != 1)
                };
                if valid {
                    if end != s.len() {
                        return Err(());
                    }
                    return Ok(s[1..end - 1].to_vec());
                }
            }
            let mut buf = Vec::new();
            let mut rest = &s[1..];
            while !rest.is_empty() && rest[0] != quote {
                if rest[0] == b'\n' {
                    return Err(());
                }
                let (r, multibyte, tail) = unquote_char(rest, quote)?;
                rest = tail;
                if r < 0x80 || !multibyte {
                    buf.push(r as u8);
                } else {
                    push_rune(&mut buf, char::from_u32(r).unwrap_or(RUNE_ERROR));
                }
                if quote == b'\'' {
                    break;
                }
            }
            if !(!rest.is_empty() && rest[0] == quote) {
                return Err(());
            }
            rest = &rest[1..];
            if !rest.is_empty() {
                return Err(());
            }
            Ok(buf)
        }
        _ => Err(()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn quoting() {
        assert_eq!(quote(b"a\"\\\n\x00\xff"), b"\"a\\\"\\\\\\n\\x00\\xff\"");
        assert_eq!(quote("\u{AD}é".as_bytes()), "\"\\u00adé\"".as_bytes());
        assert_eq!(quote_to_ascii("é".as_bytes()), b"\"\\u00e9\"");
        assert_eq!(quote_rune(0x110000, false), "'\u{FFFD}'".as_bytes());
        assert!(can_backquote(b"a\tb"));
        assert!(!can_backquote(b"a`b"));
    }

    #[test]
    fn unquoting() {
        assert_eq!(unquote(b"\"a\\tb\"").unwrap(), b"a\tb");
        assert_eq!(unquote(b"`a\r\nb`").unwrap(), b"a\nb");
        assert!(unquote(b"\"\\q\"").is_err());
        assert!(unquote(b"\"a\"b").is_err());
        assert_eq!(unquote(b"\"\xff\"").unwrap(), "\u{FFFD}".as_bytes());
        assert_eq!(unquote(b"'x'").unwrap(), b"x");
        assert!(unquote(b"'xy'").is_err());
    }

    #[test]
    fn trimming() {
        assert_eq!(trim_space(b" \t\n"), b"");
        assert_eq!(trim_space("\u{3000}x\u{A0}".as_bytes()), b"x");
        assert_eq!(trim_space(b"\xff "), b"\xff");
    }

    #[test]
    fn predicates() {
        assert!(is_letter('é') && is_letter('ǅ') && !is_letter('1'));
        assert!(is_digit('٣') && !is_digit('½'));
        assert!(is_print(' ') && !is_print('\u{AD}') && !is_print('\u{A0}'));
    }
}
