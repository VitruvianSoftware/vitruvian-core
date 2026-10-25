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

//! Python's `str`: a sequence of code points, any of which may be a lone
//! surrogate (JSON's `"\ud800"` makes one, and so does a path that is not
//! UTF-8). Rust's `String` cannot hold those, so this keeps code points.
//! Ordering is Python's: code point by code point.

use crate::unicode_tables::{DECIMAL, PRINTABLE, SPACE, WORD};

fn in_table(table: &[(u32, u32)], c: u32) -> bool {
    table
        .binary_search_by(|&(lo, hi)| {
            if hi < c {
                std::cmp::Ordering::Less
            } else if lo > c {
                std::cmp::Ordering::Greater
            } else {
                std::cmp::Ordering::Equal
            }
        })
        .is_ok()
}

/// `chr(c).isspace()`, and re's `\s`.
pub fn is_space(c: u32) -> bool {
    in_table(SPACE, c)
}

/// re's `\w`.
pub fn is_word(c: u32) -> bool {
    in_table(WORD, c)
}

/// `chr(c).isprintable()`.
pub fn is_printable(c: u32) -> bool {
    in_table(PRINTABLE, c)
}

/// The value int() gives the digit `c`, if it is one.
pub fn decimal(c: u32) -> Option<u32> {
    DECIMAL
        .iter()
        .find(|&&(lo, hi)| lo <= c && c <= hi)
        .map(|&(lo, _)| (c - lo) % 10)
}

pub fn is_surrogate(c: u32) -> bool {
    (0xD800..=0xDFFF).contains(&c)
}

#[derive(Clone, Debug, Default, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct PyStr(pub Vec<u32>);

impl PyStr {
    pub fn new() -> PyStr {
        PyStr(Vec::new())
    }

    pub fn len(&self) -> usize {
        self.0.len()
    }

    pub fn is_empty(&self) -> bool {
        self.0.is_empty()
    }

    pub fn cps(&self) -> &[u32] {
        &self.0
    }

    pub fn push_str(&mut self, s: &str) {
        self.0.extend(s.chars().map(|c| c as u32));
    }

    pub fn push_py(&mut self, s: &PyStr) {
        self.0.extend_from_slice(&s.0);
    }

    pub fn push(&mut self, c: u32) {
        self.0.push(c);
    }

    pub fn slice(&self, start: usize, end: usize) -> PyStr {
        PyStr(self.0[start..end].to_vec())
    }

    pub fn eq_str(&self, s: &str) -> bool {
        self.0.iter().copied().eq(s.chars().map(|c| c as u32))
    }

    pub fn starts_with(&self, s: &str) -> bool {
        starts_with_at(&self.0, 0, s)
    }

    pub fn find(&self, needle: &str) -> Option<usize> {
        find_from(&self.0, &cps(needle), 0)
    }

    pub fn contains(&self, needle: &str) -> bool {
        self.find(needle).is_some()
    }

    /// `str.split(sep)`, every occurrence, `sep` not empty.
    pub fn split(&self, sep: &str) -> Vec<PyStr> {
        self.splitn(sep, usize::MAX)
    }

    /// `str.split(sep, maxsplit)`.
    pub fn splitn(&self, sep: &str, maxsplit: usize) -> Vec<PyStr> {
        let sep = cps(sep);
        let mut out = Vec::new();
        let mut start = 0;
        let mut splits = 0;
        while splits < maxsplit {
            match find_from(&self.0, &sep, start) {
                Some(at) => {
                    out.push(self.slice(start, at));
                    start = at + sep.len();
                    splits += 1;
                }
                None => break,
            }
        }
        out.push(self.slice(start, self.len()));
        out
    }

    /// `str.strip()`: Python's whitespace, both ends.
    pub fn strip(&self) -> PyStr {
        let mut lo = 0;
        let mut hi = self.len();
        while lo < hi && is_space(self.0[lo]) {
            lo += 1;
        }
        while hi > lo && is_space(self.0[hi - 1]) {
            hi -= 1;
        }
        self.slice(lo, hi)
    }

    /// `str.strip(chars)` for a set of ASCII characters.
    pub fn strip_chars(&self, chars: &str) -> PyStr {
        let set = cps(chars);
        let mut lo = 0;
        let mut hi = self.len();
        while lo < hi && set.contains(&self.0[lo]) {
            lo += 1;
        }
        while hi > lo && set.contains(&self.0[hi - 1]) {
            hi -= 1;
        }
        self.slice(lo, hi)
    }

    /// `"".join(...)` with a separator.
    pub fn join(sep: &str, parts: &[PyStr]) -> PyStr {
        let mut out = PyStr::new();
        for (i, part) in parts.iter().enumerate() {
            if i > 0 {
                out.push_str(sep);
            }
            out.push_py(part);
        }
        out
    }

    /// `str.replace(old, new)` for a non-empty `old`.
    pub fn replace(&self, old: &str, new: &str) -> PyStr {
        PyStr::join(new, &self.split(old))
    }

    /// `repr(s)`, quotes and escapes as Python writes them.
    pub fn repr(&self) -> PyStr {
        let quote = if self.0.contains(&('\'' as u32)) && !self.0.contains(&('"' as u32)) {
            '"' as u32
        } else {
            '\'' as u32
        };
        let mut out = PyStr::new();
        out.push(quote);
        for &c in &self.0 {
            if c == quote || c == '\\' as u32 {
                out.push('\\' as u32);
                out.push(c);
            } else if c == '\t' as u32 {
                out.push_str("\\t");
            } else if c == '\n' as u32 {
                out.push_str("\\n");
            } else if c == '\r' as u32 {
                out.push_str("\\r");
            } else if c < 0x20 || c == 0x7F {
                out.push_str(&format!("\\x{:02x}", c));
            } else if c < 0x7F || is_printable(c) {
                out.push(c);
            } else {
                out.push_str(&escape(c));
            }
        }
        out.push(quote);
        out
    }

    /// The text, with each lone surrogate written `\udXXX`: what Python's
    /// backslashreplace (stderr's handler) writes. Only for messages.
    pub fn lossy(&self) -> String {
        let mut out = String::new();
        for &c in &self.0 {
            match char::from_u32(c) {
                Some(ch) => out.push(ch),
                None => out.push_str(&escape(c)),
            }
        }
        out
    }
}

/// `\xNN`, `\uNNNN` or `\UNNNNNNNN`, as repr() and backslashreplace write a
/// character.
pub fn escape(c: u32) -> String {
    if c < 0x100 {
        format!("\\x{:02x}", c)
    } else if c < 0x10000 {
        format!("\\u{:04x}", c)
    } else {
        format!("\\U{:08x}", c)
    }
}

impl From<&str> for PyStr {
    fn from(s: &str) -> PyStr {
        PyStr(cps(s))
    }
}

pub fn cps(s: &str) -> Vec<u32> {
    s.chars().map(|c| c as u32).collect()
}

pub fn starts_with_at(hay: &[u32], at: usize, s: &str) -> bool {
    let mut i = at;
    for c in s.chars() {
        if i >= hay.len() || hay[i] != c as u32 {
            return false;
        }
        i += 1;
    }
    true
}

pub fn find_from(hay: &[u32], needle: &[u32], from: usize) -> Option<usize> {
    if needle.is_empty() {
        return if from <= hay.len() { Some(from) } else { None };
    }
    if hay.len() < needle.len() {
        return None;
    }
    (from..=hay.len() - needle.len()).find(|&i| hay[i..i + needle.len()] == *needle)
}

/// Python's own UTF-8 decoder, strict: the error it raises, or the text.
/// `final_` is false while more input may follow; then an incomplete
/// sequence at the end is not an error, and its bytes are left over.
pub struct Utf8Error {
    pub start: usize,
    pub end: usize,
    pub reason: &'static str,
    pub byte: u8,
}

impl Utf8Error {
    /// str(UnicodeDecodeError).
    pub fn message(&self) -> String {
        if self.end == self.start + 1 {
            format!(
                "'utf-8' codec can't decode byte 0x{:02x} in position {}: {}",
                self.byte, self.start, self.reason
            )
        } else {
            format!(
                "'utf-8' codec can't decode bytes in position {}-{}: {}",
                self.start,
                self.end - 1,
                self.reason
            )
        }
    }
}

fn cont(b: u8) -> bool {
    (0x80..=0xBF).contains(&b)
}

/// Decodes `data`; returns the code points and how many bytes it consumed.
pub fn decode_utf8(data: &[u8], final_: bool) -> Result<(Vec<u32>, usize), Utf8Error> {
    let mut out = Vec::with_capacity(data.len());
    let mut i = 0;
    let n = data.len();
    let invalid = |start: usize, len: usize, reason: &'static str| Utf8Error {
        start,
        end: start + len,
        reason,
        byte: data[start],
    };
    while i < n {
        let ch = data[i];
        if ch < 0x80 {
            out.push(ch as u32);
            i += 1;
            continue;
        }
        let left = n - i;
        // CPython's stringlib utf8_decode: which error, and how many bytes it
        // covers (1 for an invalid start or a bad second byte, and so on).
        if ch < 0xC2 {
            return Err(invalid(i, 1, "invalid start byte"));
        }
        if ch < 0xE0 {
            if left < 2 {
                return truncated(data, i, final_, out);
            }
            if !cont(data[i + 1]) {
                return Err(invalid(i, 1, "invalid continuation byte"));
            }
            out.push(((ch as u32 & 0x1F) << 6) | (data[i + 1] as u32 & 0x3F));
            i += 2;
            continue;
        }
        if ch < 0xF0 {
            if left < 3 {
                if left < 2 {
                    return truncated(data, i, final_, out);
                }
                let ch2 = data[i + 1];
                if !cont(ch2) || (if ch2 < 0xA0 { ch == 0xE0 } else { ch == 0xED }) {
                    return Err(invalid(i, 1, "invalid continuation byte"));
                }
                return truncated(data, i, final_, out);
            }
            let (ch2, ch3) = (data[i + 1], data[i + 2]);
            if !cont(ch2) || (ch == 0xE0 && ch2 < 0xA0) || (ch == 0xED && ch2 >= 0xA0) {
                return Err(invalid(i, 1, "invalid continuation byte"));
            }
            if !cont(ch3) {
                return Err(invalid(i, 2, "invalid continuation byte"));
            }
            out.push(((ch as u32 & 0x0F) << 12) | ((ch2 as u32 & 0x3F) << 6) | (ch3 as u32 & 0x3F));
            i += 3;
            continue;
        }
        if ch < 0xF5 {
            if left < 4 {
                if left < 2 {
                    return truncated(data, i, final_, out);
                }
                let ch2 = data[i + 1];
                if !cont(ch2) || (if ch2 < 0x90 { ch == 0xF0 } else { ch == 0xF4 }) {
                    return Err(invalid(i, 1, "invalid continuation byte"));
                }
                if left < 3 {
                    return truncated(data, i, final_, out);
                }
                if !cont(data[i + 2]) {
                    return Err(invalid(i, 2, "invalid continuation byte"));
                }
                return truncated(data, i, final_, out);
            }
            let (ch2, ch3, ch4) = (data[i + 1], data[i + 2], data[i + 3]);
            if !cont(ch2) || (ch == 0xF0 && ch2 < 0x90) || (ch == 0xF4 && ch2 >= 0x90) {
                return Err(invalid(i, 1, "invalid continuation byte"));
            }
            if !cont(ch3) {
                return Err(invalid(i, 2, "invalid continuation byte"));
            }
            if !cont(ch4) {
                return Err(invalid(i, 3, "invalid continuation byte"));
            }
            out.push(
                ((ch as u32 & 0x07) << 18)
                    | ((ch2 as u32 & 0x3F) << 12)
                    | ((ch3 as u32 & 0x3F) << 6)
                    | (ch4 as u32 & 0x3F),
            );
            i += 4;
            continue;
        }
        return Err(invalid(i, 1, "invalid start byte"));
    }
    Ok((out, n))
}

fn truncated(
    data: &[u8],
    at: usize,
    final_: bool,
    out: Vec<u32>,
) -> Result<(Vec<u32>, usize), Utf8Error> {
    if final_ {
        Err(Utf8Error {
            start: at,
            end: data.len(),
            reason: "unexpected end of data",
            byte: data[at],
        })
    } else {
        Ok((out, at))
    }
}

/// Bytes from the operating system (a path, an argument, an environment
/// variable) as Python sees them: UTF-8, each byte that is not written as a
/// lone surrogate U+DC80..U+DCFF (surrogateescape).
pub fn decode_os(data: &[u8]) -> PyStr {
    let mut out = Vec::new();
    let mut i = 0;
    while i < data.len() {
        match decode_utf8(&data[i..], true) {
            Ok((cps, _)) => {
                out.extend(cps);
                break;
            }
            Err(e) => {
                let (good, _) = decode_utf8(&data[i..i + e.start], true).unwrap_or_default();
                out.extend(good);
                out.push(0xDC00 + data[i + e.start] as u32);
                i += e.start + 1;
            }
        }
    }
    PyStr(out)
}

/// The inverse of `decode_os`, for handing a path back to the system.
pub fn encode_os(s: &PyStr) -> Option<Vec<u8>> {
    let mut out = Vec::new();
    for &c in &s.0 {
        if (0xDC80..=0xDCFF).contains(&c) {
            out.push((c - 0xDC00) as u8);
        } else if let Some(ch) = char::from_u32(c) {
            let mut buf = [0u8; 4];
            out.extend_from_slice(ch.encode_utf8(&mut buf).as_bytes());
        } else {
            return None;
        }
    }
    Some(out)
}

/// How Python writes a str to a stream that cannot hold a lone surrogate.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Errors {
    Strict,
    SurrogateEscape,
    BackslashReplace,
    Replace,
    Ignore,
    SurrogatePass,
    XmlCharRefReplace,
}

impl Errors {
    pub fn parse(name: &str) -> Option<Errors> {
        Some(match name {
            "strict" => Errors::Strict,
            "surrogateescape" => Errors::SurrogateEscape,
            "backslashreplace" | "namereplace" => Errors::BackslashReplace,
            "replace" => Errors::Replace,
            "ignore" => Errors::Ignore,
            "surrogatepass" => Errors::SurrogatePass,
            "xmlcharrefreplace" => Errors::XmlCharRefReplace,
            _ => return None,
        })
    }
}

/// str(UnicodeEncodeError) for the code points [start, end) of `s`.
pub fn encode_error(s: &[u32], start: usize, end: usize) -> String {
    if end == start + 1 {
        format!(
            "'utf-8' codec can't encode character '{}' in position {}: surrogates not allowed",
            escape(s[start]),
            start
        )
    } else {
        format!(
            "'utf-8' codec can't encode characters in position {}-{}: surrogates not allowed",
            start,
            end - 1
        )
    }
}

/// `s.encode("utf-8", errors)`, as CPython's encoder does it: a run of
/// surrogates goes to the handler at once.
pub fn encode_utf8(s: &[u32], errors: Errors) -> Result<Vec<u8>, String> {
    let mut out = Vec::with_capacity(s.len());
    let mut i = 0;
    while i < s.len() {
        let c = s[i];
        if !is_surrogate(c) {
            let ch = char::from_u32(c).expect("not a surrogate");
            let mut buf = [0u8; 4];
            out.extend_from_slice(ch.encode_utf8(&mut buf).as_bytes());
            i += 1;
            continue;
        }
        let start = i;
        let mut end = i + 1;
        while end < s.len() && is_surrogate(s[end]) {
            end += 1;
        }
        match errors {
            Errors::Strict => return Err(encode_error(s, start, end)),
            Errors::SurrogateEscape => {
                let mut k = start;
                while k < end && (0xDC80..=0xDCFF).contains(&s[k]) {
                    out.push((s[k] - 0xDC00) as u8);
                    k += 1;
                }
                if k < end {
                    return Err(encode_error(s, k, end));
                }
            }
            Errors::BackslashReplace => {
                for &c in &s[start..end] {
                    out.extend_from_slice(escape(c).as_bytes());
                }
            }
            Errors::Replace => out.extend(std::iter::repeat(b'?').take(end - start)),
            Errors::Ignore => {}
            Errors::SurrogatePass => {
                for &c in &s[start..end] {
                    out.push(0xE0 | (c >> 12) as u8);
                    out.push(0x80 | ((c >> 6) & 0x3F) as u8);
                    out.push(0x80 | (c & 0x3F) as u8);
                }
            }
            Errors::XmlCharRefReplace => {
                for &c in &s[start..end] {
                    out.extend_from_slice(format!("&#{};", c).as_bytes());
                }
            }
        }
        i = end;
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn strip_takes_pythons_whitespace() {
        let s = PyStr::from("\u{3000} a b\u{85}\u{1c}");
        assert_eq!(s.strip(), PyStr::from("a b"));
        assert_eq!(PyStr::from("\u{feff}a").strip(), PyStr::from("\u{feff}a"));
    }

    #[test]
    fn repr_picks_quotes_like_python() {
        assert_eq!(PyStr::from("a'b").repr().lossy(), "\"a'b\"");
        assert_eq!(PyStr::from("a'b\"").repr().lossy(), "'a\\'b\"'");
        assert_eq!(
            PyStr::from("\u{7f}\n\u{a0}é").repr().lossy(),
            "'\\x7f\\n\\xa0é'"
        );
        assert_eq!(PyStr(vec![0xD800]).repr().lossy(), "'\\ud800'");
    }

    #[test]
    fn utf8_errors_read_like_cpythons() {
        let e = decode_utf8(b"ab\xff", true).err().unwrap();
        assert_eq!(
            e.message(),
            "'utf-8' codec can't decode byte 0xff in position 2: invalid start byte"
        );
        let e = decode_utf8(b"\xe2\x82A", true).err().unwrap();
        assert_eq!(
            e.message(),
            "'utf-8' codec can't decode bytes in position 0-1: invalid continuation byte"
        );
        let e = decode_utf8(b"\xe2\x82", true).err().unwrap();
        assert_eq!(
            e.message(),
            "'utf-8' codec can't decode bytes in position 0-1: unexpected end of data"
        );
        assert_eq!(decode_utf8(b"a\xe2\x82", false).ok().unwrap().1, 1);
        let e = decode_utf8(b"\xed\xa0\x80", true).err().unwrap();
        assert_eq!(
            e.message(),
            "'utf-8' codec can't decode byte 0xed in position 0: invalid continuation byte"
        );
    }

    #[test]
    fn surrogates_fail_strict_and_survive_surrogateescape() {
        let s = [0x61, 0xDCFF, 0xD800, 0xD801];
        assert_eq!(
            encode_utf8(&s, Errors::Strict).err().unwrap(),
            "'utf-8' codec can't encode characters in position 1-3: surrogates not allowed"
        );
        assert_eq!(
            encode_utf8(&s, Errors::SurrogateEscape).err().unwrap(),
            "'utf-8' codec can't encode characters in position 2-3: surrogates not allowed"
        );
        assert_eq!(
            encode_utf8(&[0xDCFF], Errors::SurrogateEscape).unwrap(),
            vec![0xFF]
        );
        assert_eq!(decode_os(b"a\xffb"), PyStr(vec![0x61, 0xDCFF, 0x62]));
    }
}
