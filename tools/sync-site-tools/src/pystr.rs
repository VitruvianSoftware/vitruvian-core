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

//! A Python `str`: a sequence of code points, lone surrogates included, so
//! indexes, ordering, `repr()` and the UTF-8 encoder's errors are Python's.

use crate::pyerr::PyErr;
use crate::unicode_tables::{PRINTABLE, SPACE};

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

/// `str.isspace()` of one character, which is also `re`'s `\s`.
pub fn is_space(c: u32) -> bool {
    in_table(SPACE, c)
}

/// `str.isprintable()` of one character.
pub fn is_printable(c: u32) -> bool {
    in_table(PRINTABLE, c)
}

fn is_surrogate(c: u32) -> bool {
    (0xD800..=0xDFFF).contains(&c)
}

#[derive(Clone, Debug, Default, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct PyStr(pub Vec<u32>);

impl From<&str> for PyStr {
    fn from(s: &str) -> Self {
        PyStr(s.chars().map(|c| c as u32).collect())
    }
}

impl From<String> for PyStr {
    fn from(s: String) -> Self {
        PyStr::from(s.as_str())
    }
}

impl From<&String> for PyStr {
    fn from(s: &String) -> Self {
        PyStr::from(s.as_str())
    }
}

impl PyStr {
    pub fn new() -> Self {
        PyStr(Vec::new())
    }

    pub fn len(&self) -> usize {
        self.0.len()
    }

    pub fn is_empty(&self) -> bool {
        self.0.is_empty()
    }

    pub fn chars(&self) -> &[u32] {
        &self.0
    }

    pub fn push(&mut self, other: &PyStr) {
        self.0.extend_from_slice(&other.0);
    }

    pub fn push_str(&mut self, s: &str) {
        self.0.extend(s.chars().map(|c| c as u32));
    }

    pub fn push_char(&mut self, c: u32) {
        self.0.push(c);
    }

    /// `a + b`.
    pub fn concat(parts: &[&PyStr]) -> PyStr {
        let mut out = PyStr::new();
        for part in parts {
            out.push(part);
        }
        out
    }

    pub fn slice(&self, start: usize, end: usize) -> PyStr {
        PyStr(self.0[start.min(self.len())..end.min(self.len())].to_vec())
    }

    pub fn starts_with(&self, prefix: &str) -> bool {
        self.starts_with_s(&PyStr::from(prefix))
    }

    pub fn starts_with_s(&self, prefix: &PyStr) -> bool {
        self.0.starts_with(&prefix.0)
    }

    pub fn ends_with(&self, suffix: &str) -> bool {
        self.0.ends_with(&PyStr::from(suffix).0)
    }

    /// The first index of `needle` at or after `from`.
    pub fn find(&self, needle: &[u32], from: usize) -> Option<usize> {
        if needle.is_empty() {
            return if from <= self.len() { Some(from) } else { None };
        }
        if needle.len() > self.len() {
            return None;
        }
        (from..=self.len() - needle.len()).find(|&i| &self.0[i..i + needle.len()] == needle)
    }

    /// `needle in self`.
    pub fn contains(&self, needle: &str) -> bool {
        self.find(&PyStr::from(needle).0, 0).is_some()
    }

    pub fn contains_char(&self, c: u32) -> bool {
        self.0.contains(&c)
    }

    /// `self.split(sep)` for a one-character separator.
    pub fn split_char(&self, sep: u32) -> Vec<PyStr> {
        self.0
            .split(|&c| c == sep)
            .map(|part| PyStr(part.to_vec()))
            .collect()
    }

    /// `self.partition(sep)` for a one-character separator.
    pub fn partition_char(&self, sep: u32) -> (PyStr, bool, PyStr) {
        match self.0.iter().position(|&c| c == sep) {
            Some(i) => (self.slice(0, i), true, self.slice(i + 1, self.len())),
            None => (self.clone(), false, PyStr::new()),
        }
    }

    /// `self.strip()`: Unicode whitespace from both ends.
    pub fn strip(&self) -> PyStr {
        let mut start = 0;
        let mut end = self.len();
        while start < end && is_space(self.0[start]) {
            start += 1;
        }
        while end > start && is_space(self.0[end - 1]) {
            end -= 1;
        }
        self.slice(start, end)
    }

    /// `self.strip(chars)` for an ASCII set, as `.strip()` on an ASCII str.
    pub fn strip_set(&self, set: &[u32]) -> PyStr {
        let mut start = 0;
        let mut end = self.len();
        while start < end && set.contains(&self.0[start]) {
            start += 1;
        }
        while end > start && set.contains(&self.0[end - 1]) {
            end -= 1;
        }
        self.slice(start, end)
    }

    /// `self.lstrip(c)` for one character.
    pub fn lstrip_char(&self, c: u32) -> PyStr {
        let start = self.0.iter().position(|&d| d != c).unwrap_or(self.len());
        self.slice(start, self.len())
    }

    /// `self.rstrip(c)` for one character.
    pub fn rstrip_char(&self, c: u32) -> PyStr {
        let end = self.0.iter().rposition(|&d| d != c).map_or(0, |i| i + 1);
        self.slice(0, end)
    }

    /// `self.replace(old, new)`: every occurrence, left to right, none
    /// overlapping. `old` is never empty here.
    pub fn replace(&self, old: &PyStr, new: &PyStr) -> PyStr {
        if old.is_empty() {
            return self.clone();
        }
        let mut out = PyStr::new();
        let mut at = 0;
        while let Some(i) = self.find(&old.0, at) {
            out.0.extend_from_slice(&self.0[at..i]);
            out.push(new);
            at = i + old.len();
        }
        out.0.extend_from_slice(&self.0[at..]);
        out
    }

    /// `"\n".join(parts)`, or any separator.
    pub fn join(sep: &str, parts: &[PyStr]) -> PyStr {
        let sep = PyStr::from(sep);
        let mut out = PyStr::new();
        for (i, part) in parts.iter().enumerate() {
            if i > 0 {
                out.push(&sep);
            }
            out.push(part);
        }
        out
    }

    /// `repr(self)`.
    pub fn repr(&self) -> PyStr {
        let single = self.0.contains(&('\'' as u32));
        let double = self.0.contains(&('"' as u32));
        let quote = if single && !double {
            '"' as u32
        } else {
            '\'' as u32
        };
        let mut out = PyStr::new();
        out.push_char(quote);
        for &c in &self.0 {
            if c == quote || c == '\\' as u32 {
                out.push_char('\\' as u32);
                out.push_char(c);
            } else if c == '\t' as u32 {
                out.push_str("\\t");
            } else if c == '\n' as u32 {
                out.push_str("\\n");
            } else if c == '\r' as u32 {
                out.push_str("\\r");
            } else if c < 0x20 || c == 0x7F {
                out.push_str(&format!("\\x{:02x}", c));
            } else if c < 0x7F || is_printable(c) {
                out.push_char(c);
            } else if c <= 0xFF {
                out.push_str(&format!("\\x{:02x}", c));
            } else if c <= 0xFFFF {
                out.push_str(&format!("\\u{:04x}", c));
            } else {
                out.push_str(&format!("\\U{:08x}", c));
            }
        }
        out.push_char(quote);
        out
    }

    /// `self.encode("utf-8")`, which refuses a lone surrogate.
    pub fn encode_utf8(&self) -> Result<Vec<u8>, PyErr> {
        let mut out = Vec::with_capacity(self.len());
        let mut i = 0;
        while i < self.len() {
            let c = self.0[i];
            if is_surrogate(c) {
                let mut end = i + 1;
                while end < self.len() && is_surrogate(self.0[end]) {
                    end += 1;
                }
                let msg = if end == i + 1 {
                    let shown = if c <= 0xFF {
                        format!("\\x{:02x}", c)
                    } else if c <= 0xFFFF {
                        format!("\\u{:04x}", c)
                    } else {
                        format!("\\U{:08x}", c)
                    };
                    format!(
                        "'utf-8' codec can't encode character '{}' in position {}: surrogates not allowed",
                        shown, i
                    )
                } else {
                    format!(
                        "'utf-8' codec can't encode characters in position {}-{}: surrogates not allowed",
                        i,
                        end - 1
                    )
                };
                return Err(PyErr::exc("UnicodeEncodeError", &msg));
            }
            let ch = char::from_u32(c).unwrap_or('\u{FFFD}');
            let mut buf = [0u8; 4];
            out.extend_from_slice(ch.encode_utf8(&mut buf).as_bytes());
            i += 1;
        }
        Ok(out)
    }

    /// The bytes as Python writes them to a stream that is UTF-8 with
    /// `backslashreplace`: stderr's.
    pub fn to_utf8_backslashreplace(&self) -> Vec<u8> {
        let mut out = Vec::with_capacity(self.len());
        for &c in &self.0 {
            match char::from_u32(c) {
                Some(ch) => {
                    let mut buf = [0u8; 4];
                    out.extend_from_slice(ch.encode_utf8(&mut buf).as_bytes());
                }
                None => out.extend_from_slice(format!("\\u{:04x}", c).as_bytes()),
            }
        }
        out
    }

    /// `os.fsdecode`: UTF-8, each byte that is not part of a character
    /// becoming U+DC80..U+DCFF (`surrogateescape`).
    pub fn from_surrogateescape(bytes: &[u8]) -> PyStr {
        let mut out = PyStr::new();
        let mut rest = bytes;
        loop {
            match std::str::from_utf8(rest) {
                Ok(text) => {
                    out.push_str(text);
                    return out;
                }
                Err(error) => {
                    let good = error.valid_up_to();
                    out.push_str(std::str::from_utf8(&rest[..good]).unwrap_or(""));
                    let bad = error.error_len().unwrap_or(rest.len() - good);
                    for &b in &rest[good..good + bad] {
                        out.push_char(0xDC00 + b as u32);
                    }
                    rest = &rest[good + bad..];
                }
            }
        }
    }

    /// `os.fsencode`: the inverse of `from_surrogateescape`.
    pub fn to_surrogateescape(&self) -> Vec<u8> {
        let mut out = Vec::with_capacity(self.len());
        for &c in &self.0 {
            if (0xDC80..=0xDCFF).contains(&c) {
                out.push((c - 0xDC00) as u8);
            } else {
                match char::from_u32(c) {
                    Some(ch) => {
                        let mut buf = [0u8; 4];
                        out.extend_from_slice(ch.encode_utf8(&mut buf).as_bytes());
                    }
                    None => {
                        // A surrogate Python could not encode either: never
                        // reached, as paths only come from the file system.
                        out.extend_from_slice(&[
                            0xE0 | (c >> 12) as u8,
                            0x80 | ((c >> 6) & 0x3F) as u8,
                            0x80 | (c & 0x3F) as u8,
                        ]);
                    }
                }
            }
        }
        out
    }

    /// For tests and messages that are known to be valid.
    pub fn to_string_lossy(&self) -> String {
        self.0
            .iter()
            .map(|&c| char::from_u32(c).unwrap_or('\u{FFFD}'))
            .collect()
    }
}

/// Python's strict UTF-8 decoder over a whole file, with its error message.
pub fn decode_utf8(bytes: &[u8]) -> Result<PyStr, PyErr> {
    match std::str::from_utf8(bytes) {
        Ok(text) => Ok(PyStr::from(text)),
        Err(error) => {
            let start = error.valid_up_to();
            let lead = bytes[start];
            let (end, reason) = match error.error_len() {
                None => (bytes.len(), "unexpected end of data"),
                Some(1) if !(0xC2..=0xF4).contains(&lead) => (start + 1, "invalid start byte"),
                Some(n) => (start + n, "invalid continuation byte"),
            };
            Err(decode_error("utf-8", bytes, start, end, reason))
        }
    }
}

/// Python's ASCII decoder over a whole file, with its error message.
pub fn decode_ascii(bytes: &[u8]) -> Result<PyStr, PyErr> {
    match bytes.iter().position(|&b| b >= 0x80) {
        None => Ok(PyStr(bytes.iter().map(|&b| b as u32).collect())),
        Some(start) => Err(decode_error(
            "ascii",
            bytes,
            start,
            start + 1,
            "ordinal not in range(128)",
        )),
    }
}

fn decode_error(codec: &str, bytes: &[u8], start: usize, end: usize, reason: &str) -> PyErr {
    let msg = if end == start + 1 {
        format!(
            "'{}' codec can't decode byte 0x{:02x} in position {}: {}",
            codec, bytes[start], start, reason
        )
    } else {
        format!(
            "'{}' codec can't decode bytes in position {}-{}: {}",
            codec,
            start,
            end - 1,
            reason
        )
    };
    PyErr::exc("UnicodeDecodeError", &msg)
}

/// What a file opened in text mode reads as: `\r\n` and a lone `\r`
/// become `\n` (universal newlines).
pub fn universal_newlines(text: PyStr) -> PyStr {
    if !text.0.contains(&('\r' as u32)) {
        return text;
    }
    let mut out = Vec::with_capacity(text.len());
    let mut i = 0;
    while i < text.len() {
        let c = text.0[i];
        if c == '\r' as u32 {
            out.push('\n' as u32);
            if i + 1 < text.len() && text.0[i + 1] == '\n' as u32 {
                i += 1;
            }
        } else {
            out.push(c);
        }
        i += 1;
    }
    PyStr(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn s(text: &str) -> PyStr {
        PyStr::from(text)
    }

    #[test]
    fn repr_picks_quotes_and_escapes_as_python() {
        assert_eq!(s("it's").repr().to_string_lossy(), "\"it's\"");
        assert_eq!(s("a'b\"c").repr().to_string_lossy(), "'a\\'b\"c'");
        assert_eq!(
            s("\u{85}\u{2028}\u{a0}é\t\x7f").repr().to_string_lossy(),
            "'\\x85\\u2028\\xa0é\\t\\x7f'"
        );
        assert_eq!(
            PyStr(vec![0x61, 0xDCFF]).repr().to_string_lossy(),
            "'a\\udcff'"
        );
        assert_eq!(s("\u{e0000}").repr().to_string_lossy(), "'\\U000e0000'");
    }

    #[test]
    fn strip_uses_unicode_whitespace() {
        assert_eq!(s("\u{3000} a \x1c").strip(), s("a"));
        assert_eq!(s("\n\nx\n").lstrip_char('\n' as u32), s("x\n"));
        assert_eq!(s("x\n\n").rstrip_char('\n' as u32), s("x"));
        assert_eq!(s("\n\n").rstrip_char('\n' as u32), s(""));
    }

    #[test]
    fn encode_reports_surrogates_like_python() {
        let one = PyStr(vec![0x61, 0xDCFF]).encode_utf8().unwrap_err();
        assert_eq!(
            one.last_line(),
            "UnicodeEncodeError: 'utf-8' codec can't encode character '\\udcff' in position 1: surrogates not allowed"
        );
        let run = PyStr(vec![0x61, 0x62, 0x63, 0xDCFF, 0xDCFE])
            .encode_utf8()
            .unwrap_err();
        assert_eq!(
            run.last_line(),
            "UnicodeEncodeError: 'utf-8' codec can't encode characters in position 3-4: surrogates not allowed"
        );
    }

    #[test]
    fn decode_reports_like_python() {
        let cases: &[(&[u8], &str)] = &[
            (
                b"ab\xe2\x82",
                "'utf-8' codec can't decode bytes in position 2-3: unexpected end of data",
            ),
            (
                b"ab\xe2\x28x",
                "'utf-8' codec can't decode byte 0xe2 in position 2: invalid continuation byte",
            ),
            (
                b"ab\xf0\x9f\x98x",
                "'utf-8' codec can't decode bytes in position 2-4: invalid continuation byte",
            ),
            (
                b"ab\xed\xa0\x80",
                "'utf-8' codec can't decode byte 0xed in position 2: invalid continuation byte",
            ),
            (
                b"\xff",
                "'utf-8' codec can't decode byte 0xff in position 0: invalid start byte",
            ),
        ];
        for (bytes, want) in cases {
            let got = decode_utf8(bytes).unwrap_err();
            assert_eq!(got.last_line(), format!("UnicodeDecodeError: {}", want));
        }
        assert_eq!(
            decode_ascii(b"ab\xe2").unwrap_err().last_line(),
            "UnicodeDecodeError: 'ascii' codec can't decode byte 0xe2 in position 2: ordinal not in range(128)"
        );
    }

    #[test]
    fn surrogateescape_round_trips() {
        let bytes = b"a\xffb\xe2\x82";
        let text = PyStr::from_surrogateescape(bytes);
        assert_eq!(text.0, vec![0x61, 0xDCFF, 0x62, 0xDCE2, 0xDC82]);
        assert_eq!(text.to_surrogateescape(), bytes.to_vec());
    }

    #[test]
    fn newlines_are_universal() {
        assert_eq!(universal_newlines(s("a\r\nb\rc\n")), s("a\nb\nc\n"));
    }

    #[test]
    fn replace_and_partition() {
        assert_eq!(s("aXbXc").replace(&s("X"), &s("--")), s("a--b--c"));
        assert_eq!(
            s("abc").partition_char('\n' as u32),
            (s("abc"), false, s(""))
        );
        assert_eq!(
            s("a\nb\nc").partition_char('\n' as u32),
            (s("a"), true, s("b\nc"))
        );
    }
}
