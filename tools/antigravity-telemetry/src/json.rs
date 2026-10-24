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

//! An order-preserving JSON value with Python `json` semantics.
//!
//! The Python tool builds payloads from dicts, which keep insertion order, and
//! serialises them with `json.dumps`. `J` keeps document order and [`dumps`]
//! reproduces `json.dumps` byte for byte: separators, `indent`,
//! `ensure_ascii` and `repr(float)`.
//!
//! [`J::parse`] is a port of `json.loads` rather than `serde_json`, because
//! with the features this repository's crate universe enables, `serde_json`
//! gets two things visibly wrong:
//!
//! * Without `preserve_order`, `serde_json::Value` sorts keys.
//! * Without `float_roundtrip`, it parses some floats one ULP off. The
//!   session exporter re-reads the floats it wrote (file mtimes in its state
//!   file), so a value drifted on every scan. Python's parser is exact, and so
//!   is `str::parse::<f64>`.
//!
//! Enabling either feature would mean changing the shared `Cargo.toml`. This
//! parser needs neither, and its errors read like Python's
//! (`Expecting value: line 1 column 1 (char 0)`), which the hook prints.

/// A JSON value. Objects keep insertion order, like a Python dict.
#[derive(Clone, Debug, PartialEq)]
pub enum J {
    Null,
    Bool(bool),
    Int(i128),
    Float(f64),
    Str(String),
    Arr(Vec<J>),
    Obj(Vec<(String, J)>),
}

impl J {
    /// An object from `(key, value)` pairs, in order.
    pub fn obj<K: Into<String>>(pairs: Vec<(K, J)>) -> J {
        let mut out = J::Obj(Vec::with_capacity(pairs.len()));
        for (k, v) in pairs {
            out.set(&k.into(), v);
        }
        out
    }

    pub fn empty_obj() -> J {
        J::Obj(Vec::new())
    }

    pub fn str<S: Into<String>>(s: S) -> J {
        J::Str(s.into())
    }

    pub fn as_str(&self) -> Option<&str> {
        match self {
            J::Str(s) => Some(s),
            _ => None,
        }
    }

    pub fn is_null(&self) -> bool {
        matches!(self, J::Null)
    }

    /// `d.get(key)` for an object; `None` for a missing key or a non-object.
    pub fn get(&self, key: &str) -> Option<&J> {
        match self {
            J::Obj(pairs) => pairs.iter().find(|(k, _)| k == key).map(|(_, v)| v),
            _ => None,
        }
    }

    pub fn get_mut(&mut self, key: &str) -> Option<&mut J> {
        match self {
            J::Obj(pairs) => pairs.iter_mut().find(|(k, _)| k == key).map(|(_, v)| v),
            _ => None,
        }
    }

    pub fn contains_key(&self, key: &str) -> bool {
        self.get(key).is_some()
    }

    /// `d[key] = value`: replaces in place (keeping position) or appends.
    /// A no-op on a non-object.
    pub fn set(&mut self, key: &str, value: J) {
        if let J::Obj(pairs) = self {
            if let Some(slot) = pairs.iter_mut().find(|(k, _)| k == key) {
                slot.1 = value;
            } else {
                pairs.push((key.to_string(), value));
            }
        }
    }

    /// `d.pop(key, None)`.
    pub fn remove(&mut self, key: &str) -> Option<J> {
        if let J::Obj(pairs) = self {
            if let Some(i) = pairs.iter().position(|(k, _)| k == key) {
                return Some(pairs.remove(i).1);
            }
        }
        None
    }

    /// `json.loads(text)`, keeping key order. The error is
    /// `JSONDecodeError`'s message.
    pub fn parse(text: &str) -> Result<J, String> {
        Parser::new(text).document()
    }
}

impl From<&str> for J {
    fn from(s: &str) -> J {
        J::Str(s.to_string())
    }
}

impl From<String> for J {
    fn from(s: String) -> J {
        J::Str(s)
    }
}

impl From<bool> for J {
    fn from(b: bool) -> J {
        J::Bool(b)
    }
}

impl From<i64> for J {
    fn from(i: i64) -> J {
        J::Int(i as i128)
    }
}

impl From<f64> for J {
    fn from(f: f64) -> J {
        J::Float(f)
    }
}

const MAX_DEPTH: usize = 900;

/// A port of CPython's `json.decoder`/`json.scanner`, with positions in code
/// points, as Python reports them.
struct Parser {
    c: Vec<char>,
    depth: usize,
}

fn is_ws(c: char) -> bool {
    matches!(c, ' ' | '\t' | '\n' | '\r')
}

impl Parser {
    fn new(text: &str) -> Self {
        Parser {
            c: text.chars().collect(),
            depth: 0,
        }
    }

    /// `JSONDecodeError`'s message.
    fn err(&self, msg: &str, pos: usize) -> String {
        let before = &self.c[..pos.min(self.c.len())];
        let lineno = before.iter().filter(|c| **c == '\n').count() + 1;
        let colno = match before.iter().rposition(|c| *c == '\n') {
            Some(nl) => pos - nl,
            None => pos + 1,
        };
        format!("{}: line {} column {} (char {})", msg, lineno, colno, pos)
    }

    fn at(&self, i: usize) -> Option<char> {
        self.c.get(i).copied()
    }

    fn skip_ws(&self, mut i: usize) -> usize {
        while self.at(i).map(is_ws).unwrap_or(false) {
            i += 1;
        }
        i
    }

    fn lit(&self, i: usize, word: &str) -> bool {
        let w: Vec<char> = word.chars().collect();
        i + w.len() <= self.c.len() && self.c[i..i + w.len()] == w[..]
    }

    fn document(&mut self) -> Result<J, String> {
        let start = self.skip_ws(0);
        let Some((value, end)) = self.value(start)? else {
            return Err(self.err("Expecting value", start));
        };
        let end = self.skip_ws(end);
        if end != self.c.len() {
            return Err(self.err("Extra data", end));
        }
        Ok(value)
    }

    /// `scan_once`: `Ok(None)` is Python's `StopIteration` (no value here).
    fn value(&mut self, i: usize) -> Result<Option<(J, usize)>, String> {
        let Some(ch) = self.at(i) else {
            return Ok(None);
        };
        match ch {
            '"' => self.string(i + 1).map(|(s, e)| Some((J::Str(s), e))),
            '{' => {
                self.enter(i)?;
                let r = self.object(i + 1).map(Some);
                self.depth -= 1;
                r
            }
            '[' => {
                self.enter(i)?;
                let r = self.array(i + 1).map(Some);
                self.depth -= 1;
                r
            }
            'n' if self.lit(i, "null") => Ok(Some((J::Null, i + 4))),
            't' if self.lit(i, "true") => Ok(Some((J::Bool(true), i + 4))),
            'f' if self.lit(i, "false") => Ok(Some((J::Bool(false), i + 5))),
            'N' if self.lit(i, "NaN") => Ok(Some((J::Float(f64::NAN), i + 3))),
            'I' if self.lit(i, "Infinity") => Ok(Some((J::Float(f64::INFINITY), i + 8))),
            '-' if self.lit(i, "-Infinity") => Ok(Some((J::Float(f64::NEG_INFINITY), i + 9))),
            '-' | '0'..='9' => Ok(self.number(i)),
            _ => Ok(None),
        }
    }

    fn enter(&mut self, i: usize) -> Result<(), String> {
        if self.depth >= MAX_DEPTH {
            return Err(self.err("maximum recursion depth exceeded", i));
        }
        self.depth += 1;
        Ok(())
    }

    /// `-?(0|[1-9]\d*)(\.\d+)?([eE][-+]?\d+)?`: an int unless it has a
    /// fraction or an exponent.
    fn number(&self, i: usize) -> Option<(J, usize)> {
        let digit = |k: usize| self.at(k).map(|c| c.is_ascii_digit()).unwrap_or(false);
        let mut j = i;
        if self.at(j) == Some('-') {
            j += 1;
        }
        match self.at(j) {
            Some('0') => j += 1,
            Some('1'..='9') => {
                while digit(j) {
                    j += 1;
                }
            }
            _ => return None,
        }
        let mut is_float = false;
        if self.at(j) == Some('.') && digit(j + 1) {
            j += 1;
            while digit(j) {
                j += 1;
            }
            is_float = true;
        }
        if matches!(self.at(j), Some('e') | Some('E')) {
            let mut k = j + 1;
            if matches!(self.at(k), Some('+') | Some('-')) {
                k += 1;
            }
            if digit(k) {
                while digit(k) {
                    k += 1;
                }
                j = k;
                is_float = true;
            }
        }
        let text: String = self.c[i..j].iter().collect();
        if !is_float {
            if let Ok(n) = text.parse::<i128>() {
                return Some((J::Int(n), j));
            }
        }
        // Correctly rounded, as CPython's float() is; overflow gives inf.
        text.parse::<f64>().ok().map(|f| (J::Float(f), j))
    }

    fn hex4(&self, i: usize) -> Option<u32> {
        if i + 4 > self.c.len() {
            return None;
        }
        let s: String = self.c[i..i + 4].iter().collect();
        if s.chars().all(|c| c.is_ascii_hexdigit()) {
            u32::from_str_radix(&s, 16).ok()
        } else {
            None
        }
    }

    /// `scanstring`, from just after the opening quote.
    fn string(&self, start: usize) -> Result<(String, usize), String> {
        let mut out = String::new();
        let mut i = start;
        loop {
            let Some(ch) = self.at(i) else {
                return Err(self.err("Unterminated string starting at", start - 1));
            };
            match ch {
                '"' => return Ok((out, i + 1)),
                '\\' => {
                    let Some(esc) = self.at(i + 1) else {
                        return Err(self.err("Unterminated string starting at", start - 1));
                    };
                    let simple = match esc {
                        '"' => Some('"'),
                        '\\' => Some('\\'),
                        '/' => Some('/'),
                        'b' => Some('\u{08}'),
                        'f' => Some('\u{0c}'),
                        'n' => Some('\n'),
                        'r' => Some('\r'),
                        't' => Some('\t'),
                        _ => None,
                    };
                    if let Some(c) = simple {
                        out.push(c);
                        i += 2;
                        continue;
                    }
                    if esc != 'u' {
                        // CPython's C scanner names no character here.
                        return Err(self.err("Invalid \\escape", i));
                    }
                    let Some(mut cp) = self.hex4(i + 2) else {
                        return Err(self.err("Invalid \\uXXXX escape", i + 1));
                    };
                    let mut next = i + 6;
                    if (0xD800..0xDC00).contains(&cp)
                        && self.at(next) == Some('\\')
                        && self.at(next + 1) == Some('u')
                    {
                        if let Some(lo) = self.hex4(next + 2) {
                            if (0xDC00..0xE000).contains(&lo) {
                                cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
                                next += 6;
                            }
                        }
                    }
                    // A lone surrogate is legal in a Python str, not a Rust one.
                    out.push(char::from_u32(cp).unwrap_or('\u{FFFD}'));
                    i = next;
                }
                c if (c as u32) < 0x20 => return Err(self.err("Invalid control character at", i)),
                c => {
                    out.push(c);
                    i += 1;
                }
            }
        }
    }

    /// `JSONObject`, from just after `{`.
    fn object(&mut self, mut end: usize) -> Result<(J, usize), String> {
        let mut out = J::Obj(Vec::new());
        let mut next = self.at(end);
        if next != Some('"') {
            if next.map(is_ws).unwrap_or(false) {
                end = self.skip_ws(end);
                next = self.at(end);
            }
            if next == Some('}') {
                return Ok((out, end + 1));
            } else if next != Some('"') {
                return Err(self.err("Expecting property name enclosed in double quotes", end));
            }
        }
        end += 1;
        loop {
            let (key, e) = self.string(end)?;
            end = e;
            if self.at(end) != Some(':') {
                end = self.skip_ws(end);
                if self.at(end) != Some(':') {
                    return Err(self.err("Expecting ':' delimiter", end));
                }
            }
            end = self.skip_ws(end + 1);
            let Some((value, e)) = self.value(end)? else {
                return Err(self.err("Expecting value", end));
            };
            // Python dict semantics: the last value wins, the first position
            // is kept.
            out.set(&key, value);
            end = self.skip_ws(e);
            let next = self.at(end);
            end += 1;
            match next {
                Some('}') => return Ok((out, end)),
                Some(',') => {}
                _ => return Err(self.err("Expecting ',' delimiter", end - 1)),
            }
            end = self.skip_ws(end);
            let next = self.at(end);
            end += 1;
            if next != Some('"') {
                return Err(self.err("Expecting property name enclosed in double quotes", end - 1));
            }
        }
    }

    /// `JSONArray`, from just after `[`.
    fn array(&mut self, mut end: usize) -> Result<(J, usize), String> {
        let mut items = Vec::new();
        end = self.skip_ws(end);
        if self.at(end) == Some(']') {
            return Ok((J::Arr(items), end + 1));
        }
        loop {
            let Some((value, e)) = self.value(end)? else {
                return Err(self.err("Expecting value", end));
            };
            items.push(value);
            end = self.skip_ws(e);
            let next = self.at(end);
            end += 1;
            match next {
                Some(']') => return Ok((J::Arr(items), end)),
                Some(',') => {}
                _ => return Err(self.err("Expecting ',' delimiter", end - 1)),
            }
            end = self.skip_ws(end);
        }
    }
}

/// `repr(float)` for a finite value: the shortest round-trip digits, laid out
/// the way CPython does (scientific below 1e-4 and from 1e16).
pub fn float_repr(f: f64) -> String {
    if f.is_nan() {
        return "nan".to_string();
    }
    if f.is_infinite() {
        return if f > 0.0 { "inf" } else { "-inf" }.to_string();
    }
    // `{:e}` yields the shortest round-trip digits, e.g. "-1.45e2", "1e-5".
    let sci = format!("{:e}", f);
    let (mantissa, exp) = sci
        .split_once('e')
        .expect("LowerExp always has an exponent");
    let exp: i32 = exp.parse().expect("LowerExp exponent is an integer");
    let (neg, mantissa) = match mantissa.strip_prefix('-') {
        Some(m) => (true, m),
        None => (false, mantissa),
    };
    let digits: String = mantissa.chars().filter(|c| *c != '.').collect();
    let mut out = String::new();
    if neg {
        out.push('-');
    }
    if (-4..16).contains(&exp) {
        if exp >= 0 {
            let int_len = (exp + 1) as usize;
            if digits.len() <= int_len {
                out.push_str(&digits);
                out.push_str(&"0".repeat(int_len - digits.len()));
                out.push_str(".0");
            } else {
                out.push_str(&digits[..int_len]);
                out.push('.');
                out.push_str(&digits[int_len..]);
            }
        } else {
            out.push_str("0.");
            out.push_str(&"0".repeat((-exp - 1) as usize));
            out.push_str(&digits);
        }
    } else {
        out.push_str(&digits[..1]);
        if digits.len() > 1 {
            out.push('.');
            out.push_str(&digits[1..]);
        }
        out.push('e');
        out.push(if exp < 0 { '-' } else { '+' });
        out.push_str(&format!("{:02}", exp.abs()));
    }
    out
}

/// How `json.dumps` writes a float (`NaN`/`Infinity` rather than `nan`/`inf`).
fn float_json(f: f64) -> String {
    if f.is_nan() {
        "NaN".to_string()
    } else if f.is_infinite() {
        if f > 0.0 { "Infinity" } else { "-Infinity" }.to_string()
    } else {
        float_repr(f)
    }
}

fn write_str(out: &mut String, s: &str, ensure_ascii: bool) {
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            '\u{08}' => out.push_str("\\b"),
            '\u{0c}' => out.push_str("\\f"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c if ensure_ascii && (c as u32) > 0x7e => {
                let mut buf = [0u16; 2];
                for unit in c.encode_utf16(&mut buf) {
                    out.push_str(&format!("\\u{:04x}", unit));
                }
            }
            c => out.push(c),
        }
    }
    out.push('"');
}

fn newline_indent(out: &mut String, indent: usize, level: usize) {
    out.push('\n');
    out.push_str(&" ".repeat(indent * level));
}

fn write_value(out: &mut String, v: &J, indent: Option<usize>, ensure_ascii: bool, level: usize) {
    match v {
        J::Null => out.push_str("null"),
        J::Bool(b) => out.push_str(if *b { "true" } else { "false" }),
        J::Int(i) => out.push_str(&i.to_string()),
        J::Float(f) => out.push_str(&float_json(*f)),
        J::Str(s) => write_str(out, s, ensure_ascii),
        J::Arr(items) => {
            if items.is_empty() {
                out.push_str("[]");
                return;
            }
            out.push('[');
            for (i, item) in items.iter().enumerate() {
                if i > 0 {
                    out.push(',');
                    if indent.is_none() {
                        out.push(' ');
                    }
                }
                if let Some(n) = indent {
                    newline_indent(out, n, level + 1);
                }
                write_value(out, item, indent, ensure_ascii, level + 1);
            }
            if let Some(n) = indent {
                newline_indent(out, n, level);
            }
            out.push(']');
        }
        J::Obj(pairs) => {
            if pairs.is_empty() {
                out.push_str("{}");
                return;
            }
            out.push('{');
            for (i, (k, item)) in pairs.iter().enumerate() {
                if i > 0 {
                    out.push(',');
                    if indent.is_none() {
                        out.push(' ');
                    }
                }
                if let Some(n) = indent {
                    newline_indent(out, n, level + 1);
                }
                write_str(out, k, ensure_ascii);
                out.push_str(": ");
                write_value(out, item, indent, ensure_ascii, level + 1);
            }
            if let Some(n) = indent {
                newline_indent(out, n, level);
            }
            out.push('}');
        }
    }
}

/// `json.dumps(v, indent=indent, ensure_ascii=ensure_ascii)`.
pub fn dumps(v: &J, indent: Option<usize>, ensure_ascii: bool) -> String {
    let mut out = String::new();
    write_value(&mut out, v, indent, ensure_ascii, 0);
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn float_repr_matches_python() {
        let cases = [
            (145.0, "145.0"),
            (0.1, "0.1"),
            (1e-05, "1e-05"),
            (0.0001, "0.0001"),
            (1e16, "1e+16"),
            (123456789012345678.0, "1.2345678901234568e+17"),
            (1e15, "1000000000000000.0"),
            (-0.0, "-0.0"),
            (2.5e-7, "2.5e-07"),
            (12.5, "12.5"),
        ];
        for (f, want) in cases {
            assert_eq!(float_repr(f), want, "{f}");
        }
    }

    #[test]
    fn dumps_matches_python_layout() {
        let v = J::parse(r#"{"b": [1, 2.0, {"x": null}], "a": {}, "c": [], "d": "é\n"}"#).unwrap();
        assert_eq!(
            dumps(&v, None, true),
            r#"{"b": [1, 2.0, {"x": null}], "a": {}, "c": [], "d": "\u00e9\n"}"#
        );
        assert_eq!(
            dumps(&v, None, false),
            "{\"b\": [1, 2.0, {\"x\": null}], \"a\": {}, \"c\": [], \"d\": \"é\\n\"}"
        );
        assert_eq!(
            dumps(&v, Some(2), true),
            "{\n  \"b\": [\n    1,\n    2.0,\n    {\n      \"x\": null\n    }\n  ],\n  \"a\": {},\n  \"c\": [],\n  \"d\": \"\\u00e9\\n\"\n}"
        );
    }

    #[test]
    fn parse_keeps_order_and_last_duplicate() {
        let v = J::parse(r#"{"z": 1, "a": 2, "z": 3}"#).unwrap();
        assert_eq!(dumps(&v, None, true), r#"{"z": 3, "a": 2}"#);
    }

    #[test]
    fn parse_matches_python_json() {
        // Exact float parsing: these round-trip through repr unchanged.
        for text in [
            "1792885118.2732465",
            "1792712318.3030279",
            "0.1",
            "1e-05",
            "1.2345678901234568e+17",
        ] {
            assert_eq!(
                float_repr(match J::parse(text).unwrap() {
                    J::Float(f) => f,
                    other => panic!("{:?}", other),
                }),
                text
            );
        }
        assert_eq!(J::parse("12").unwrap(), J::Int(12));
        assert_eq!(J::parse("-0").unwrap(), J::Int(0));
        assert_eq!(J::parse("1E2").unwrap(), J::Float(100.0));
        assert!(matches!(J::parse("NaN").unwrap(), J::Float(f) if f.is_nan()));
        assert_eq!(
            J::parse(" [1, \"a\\u00e9\\ud83d\\ude00\\n\"] ").unwrap(),
            J::Arr(vec![J::Int(1), J::str("a\u{e9}\u{1F600}\n")])
        );
        let errors = [
            ("", "Expecting value: line 1 column 1 (char 0)"),
            ("not json", "Expecting value: line 1 column 1 (char 0)"),
            ("{\"a\": ", "Expecting value: line 1 column 7 (char 6)"),
            (
                "{\"a\" 1}",
                "Expecting ':' delimiter: line 1 column 6 (char 5)",
            ),
            ("[1 2]", "Expecting ',' delimiter: line 1 column 4 (char 3)"),
            (
                "{1: 2}",
                "Expecting property name enclosed in double quotes: line 1 column 2 (char 1)",
            ),
            (
                "\"abc",
                "Unterminated string starting at: line 1 column 1 (char 0)",
            ),
            ("[1]\n x", "Extra data: line 2 column 2 (char 5)"),
            ("\"\\q\"", "Invalid \\escape: line 1 column 2 (char 1)"),
            (
                "\"\\u12\"",
                "Invalid \\uXXXX escape: line 1 column 3 (char 2)",
            ),
            (
                "\"a\tb\"",
                "Invalid control character at: line 1 column 3 (char 2)",
            ),
        ];
        for (text, want) in errors {
            assert_eq!(J::parse(text).unwrap_err(), want, "{:?}", text);
        }
    }

    #[test]
    fn astral_escapes_as_surrogate_pair() {
        assert_eq!(dumps(&J::str("😀"), None, true), r#""\ud83d\ude00""#);
    }
}
