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

//! Python's `json` module, as adb_connect.py uses it.
//!
//! [`loads`] follows CPython's C scanner: what it accepts (NaN, Infinity,
//! unbounded ints, duplicate keys keeping the first position and the last
//! value) and its error messages, positions counted in characters, since
//! the tool prints those messages in its "ignoring invalid JSON" warning.
//! [`dumps`] is `json.dumps` with the default `ensure_ascii=True`, with or
//! without `indent=`. Object key order is preserved both ways.

use crate::py::{float_repr, Dict, Val};
use std::fmt::Write as _;

/// A `json.JSONDecodeError`, already rendered like `str(err)`.
#[derive(Debug, Clone, PartialEq)]
pub struct DecodeError(pub String);

impl std::fmt::Display for DecodeError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}

struct Parser<'a> {
    s: &'a [char],
}

enum Fail {
    /// StopIteration(idx): no JSON value starts here.
    Stop(usize),
    /// A raised JSONDecodeError(msg, idx).
    Err(&'static str, usize),
}

fn is_ws(c: char) -> bool {
    matches!(c, ' ' | '\t' | '\n' | '\r')
}

impl<'a> Parser<'a> {
    fn at(&self, i: usize) -> Option<char> {
        self.s.get(i).copied()
    }

    fn skip_ws(&self, mut i: usize) -> usize {
        while i < self.s.len() && is_ws(self.s[i]) {
            i += 1;
        }
        i
    }

    fn starts_with(&self, i: usize, lit: &str) -> bool {
        let mut j = i;
        for c in lit.chars() {
            if self.at(j) != Some(c) {
                return false;
            }
            j += 1;
        }
        true
    }

    fn scan_once(&self, idx: usize) -> Result<(Val, usize), Fail> {
        let c = match self.at(idx) {
            None => return Err(Fail::Stop(idx)),
            Some(c) => c,
        };
        match c {
            '"' => self
                .scan_string(idx + 1)
                .map(|(st, end)| (Val::Str(st), end)),
            '{' => self.parse_object(idx + 1),
            '[' => self.parse_array(idx + 1),
            'n' if self.starts_with(idx, "null") => Ok((Val::None, idx + 4)),
            't' if self.starts_with(idx, "true") => Ok((Val::Bool(true), idx + 4)),
            'f' if self.starts_with(idx, "false") => Ok((Val::Bool(false), idx + 5)),
            'N' if self.starts_with(idx, "NaN") => Ok((Val::Float(f64::NAN), idx + 3)),
            'I' if self.starts_with(idx, "Infinity") => Ok((Val::Float(f64::INFINITY), idx + 8)),
            '-' if self.starts_with(idx, "-Infinity") => {
                Ok((Val::Float(f64::NEG_INFINITY), idx + 9))
            }
            '-' | '0'..='9' => self.scan_number(idx),
            _ => Err(Fail::Stop(idx)),
        }
    }

    fn scan_number(&self, start: usize) -> Result<(Val, usize), Fail> {
        let digit = |i: usize| self.at(i).map_or(false, |c| c.is_ascii_digit());
        let mut i = start;
        if self.at(i) == Some('-') {
            i += 1;
        }
        // An integer part: 0, or a nonzero digit and more digits.
        if self.at(i) == Some('0') {
            i += 1;
        } else if self.at(i).map_or(false, |c| ('1'..='9').contains(&c)) {
            while digit(i) {
                i += 1;
            }
        } else {
            return Err(Fail::Stop(start));
        }
        let mut is_float = false;
        if self.at(i) == Some('.') && digit(i + 1) {
            is_float = true;
            i += 1;
            while digit(i) {
                i += 1;
            }
        }
        if matches!(self.at(i), Some('e') | Some('E')) {
            let mut j = i + 1;
            if matches!(self.at(j), Some('+') | Some('-')) {
                j += 1;
            }
            if digit(j) {
                while digit(j) {
                    j += 1;
                }
                is_float = true;
                i = j;
            }
        }
        let text: String = self.s[start..i].iter().collect();
        if is_float {
            let v: f64 = text.parse().unwrap_or(f64::NAN);
            Ok((Val::Float(v), i))
        } else {
            let neg = text.starts_with('-');
            let digits = text.trim_start_matches('-');
            let canon = if digits == "0" || !neg {
                digits.to_string()
            } else {
                format!("-{}", digits)
            };
            Ok((Val::Int(canon), i))
        }
    }

    fn hex4(&self, from: usize, err_at: usize) -> Result<u32, Fail> {
        let mut v = 0u32;
        for k in 0..4 {
            let d = self
                .at(from + k)
                .and_then(|c| c.to_digit(16))
                .ok_or(Fail::Err("Invalid \\uXXXX escape", err_at))?;
            v = (v << 4) | d;
        }
        Ok(v)
    }

    /// `scanstring(s, end)`: `end` is just past the opening quote.
    fn scan_string(&self, end: usize) -> Result<(String, usize), Fail> {
        let len = self.s.len();
        let begin = end - 1;
        let mut out = String::new();
        let mut end = end;
        loop {
            let mut next = end;
            let mut c = '\0';
            while next < len {
                c = self.s[next];
                if c == '"' || c == '\\' {
                    break;
                }
                if (c as u32) <= 0x1f {
                    return Err(Fail::Err("Invalid control character at", next));
                }
                next += 1;
            }
            if next >= len || !(c == '"' || c == '\\') {
                return Err(Fail::Err("Unterminated string starting at", begin));
            }
            out.extend(&self.s[end..next]);
            next += 1;
            if c == '"' {
                end = next;
                break;
            }
            if next == len {
                return Err(Fail::Err("Unterminated string starting at", begin));
            }
            let esc = self.s[next];
            if esc != 'u' {
                end = next + 1;
                let ch = match esc {
                    '"' => '"',
                    '\\' => '\\',
                    '/' => '/',
                    'b' => '\u{8}',
                    'f' => '\u{c}',
                    'n' => '\n',
                    'r' => '\r',
                    't' => '\t',
                    _ => return Err(Fail::Err("Invalid \\escape", end - 2)),
                };
                out.push(ch);
            } else {
                next += 1;
                end = next + 4;
                if end >= len {
                    return Err(Fail::Err("Invalid \\uXXXX escape", next - 1));
                }
                let mut cp = self.hex4(next, end - 5)?;
                next = end;
                if (0xd800..0xdc00).contains(&cp)
                    && end + 6 < len
                    && self.s[next] == '\\'
                    && self.s[next + 1] == 'u'
                {
                    let lo = self.hex4(next + 2, end + 6 - 5)?;
                    if (0xdc00..0xe000).contains(&lo) {
                        cp = 0x10000 + ((cp - 0xd800) << 10) + (lo - 0xdc00);
                        end += 6;
                    }
                }
                // A lone surrogate cannot live in a Rust string.
                out.push(char::from_u32(cp).unwrap_or('\u{fffd}'));
            }
        }
        Ok((out, end))
    }

    fn parse_object(&self, idx: usize) -> Result<(Val, usize), Fail> {
        let mut d = Dict::new();
        let mut idx = self.skip_ws(idx);
        if self.at(idx) != Some('}') {
            loop {
                if self.at(idx) != Some('"') {
                    return Err(Fail::Err(
                        "Expecting property name enclosed in double quotes",
                        idx,
                    ));
                }
                let (key, next) = self.scan_string(idx + 1)?;
                idx = self.skip_ws(next);
                if self.at(idx) != Some(':') {
                    return Err(Fail::Err("Expecting ':' delimiter", idx));
                }
                idx = self.skip_ws(idx + 1);
                let (val, next) = self.scan_once(idx)?;
                d.set(key, val);
                idx = self.skip_ws(next);
                if self.at(idx) == Some('}') {
                    break;
                }
                if self.at(idx) != Some(',') {
                    return Err(Fail::Err("Expecting ',' delimiter", idx));
                }
                idx = self.skip_ws(idx + 1);
            }
        }
        Ok((Val::Dict(d), idx + 1))
    }

    fn parse_array(&self, idx: usize) -> Result<(Val, usize), Fail> {
        let mut items = Vec::new();
        let mut idx = self.skip_ws(idx);
        if self.at(idx) != Some(']') {
            loop {
                let (val, next) = self.scan_once(idx)?;
                items.push(val);
                idx = self.skip_ws(next);
                if self.at(idx) == Some(']') {
                    break;
                }
                if self.at(idx) != Some(',') {
                    return Err(Fail::Err("Expecting ',' delimiter", idx));
                }
                idx = self.skip_ws(idx + 1);
            }
        }
        Ok((Val::List(items), idx + 1))
    }
}

fn render(doc: &[char], msg: &str, pos: usize) -> DecodeError {
    let before = &doc[..pos.min(doc.len())];
    let lineno = before.iter().filter(|&&c| c == '\n').count() + 1;
    let colno = match before.iter().rposition(|&c| c == '\n') {
        Some(nl) => pos - nl,
        None => pos + 1,
    };
    DecodeError(format!(
        "{}: line {} column {} (char {})",
        msg, lineno, colno, pos
    ))
}

/// `json.loads(text)`.
pub fn loads(text: &str) -> Result<Val, DecodeError> {
    let doc: Vec<char> = text.chars().collect();
    if doc.first() == Some(&'\u{feff}') {
        return Err(render(
            &doc,
            "Unexpected UTF-8 BOM (decode using utf-8-sig)",
            0,
        ));
    }
    let p = Parser { s: &doc };
    let start = p.skip_ws(0);
    let (val, end) = match p.scan_once(start) {
        Ok(v) => v,
        Err(Fail::Stop(i)) => return Err(render(&doc, "Expecting value", i)),
        Err(Fail::Err(msg, i)) => return Err(render(&doc, msg, i)),
    };
    let end = p.skip_ws(end);
    if end != doc.len() {
        return Err(render(&doc, "Extra data", end));
    }
    Ok(val)
}

fn dump_str(st: &str, out: &mut String) {
    out.push('"');
    for c in st.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            '\u{8}' => out.push_str("\\b"),
            '\u{c}' => out.push_str("\\f"),
            ' '..='~' => out.push(c),
            _ => {
                let mut buf = [0u16; 2];
                for unit in c.encode_utf16(&mut buf) {
                    let _ = write!(out, "\\u{:04x}", unit);
                }
            }
        }
    }
    out.push('"');
}

fn dump_val(v: &Val, indent: Option<usize>, level: usize, out: &mut String) {
    match v {
        Val::None => out.push_str("null"),
        Val::Bool(true) => out.push_str("true"),
        Val::Bool(false) => out.push_str("false"),
        Val::Int(d) => out.push_str(d),
        Val::Float(f) => {
            if f.is_nan() {
                out.push_str("NaN");
            } else if f.is_infinite() {
                out.push_str(if *f > 0.0 { "Infinity" } else { "-Infinity" });
            } else {
                out.push_str(&float_repr(*f));
            }
        }
        Val::Str(st) => dump_str(st, out),
        Val::List(items) => {
            if items.is_empty() {
                out.push_str("[]");
                return;
            }
            out.push('[');
            for (i, item) in items.iter().enumerate() {
                separator(i, indent, level + 1, out);
                dump_val(item, indent, level + 1, out);
            }
            closing(indent, level, out);
            out.push(']');
        }
        Val::Dict(d) => {
            if d.is_empty() {
                out.push_str("{}");
                return;
            }
            out.push('{');
            for (i, (k, item)) in d.0.iter().enumerate() {
                separator(i, indent, level + 1, out);
                dump_str(k, out);
                out.push_str(": ");
                dump_val(item, indent, level + 1, out);
            }
            closing(indent, level, out);
            out.push('}');
        }
    }
}

fn separator(i: usize, indent: Option<usize>, level: usize, out: &mut String) {
    match indent {
        Some(n) => {
            if i > 0 {
                out.push(',');
            }
            out.push('\n');
            out.push_str(&" ".repeat(n * level));
        }
        None => {
            if i > 0 {
                out.push_str(", ");
            }
        }
    }
}

fn closing(indent: Option<usize>, level: usize, out: &mut String) {
    if let Some(n) = indent {
        out.push('\n');
        out.push_str(&" ".repeat(n * level));
    }
}

/// `json.dumps(v)` (`indent=None`) or `json.dumps(v, indent=n)`.
pub fn dumps(v: &Val, indent: Option<usize>) -> String {
    let mut out = String::new();
    dump_val(v, indent, 0, &mut out);
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::py::{int, s};

    fn err(text: &str) -> String {
        loads(text).unwrap_err().0
    }

    #[test]
    fn loads_keeps_order_and_types() {
        let v = loads(r#"{"b": 1, "a": [true, null, 1.5, "x\u00e9"], "b": 2}"#).unwrap();
        let d = v.as_dict().unwrap();
        let keys: Vec<&str> = d.0.iter().map(|(k, _)| k.as_str()).collect();
        assert_eq!(keys, vec!["b", "a"]);
        assert_eq!(d.get("b"), Some(&int(2)));
        assert_eq!(
            d.get("a"),
            Some(&Val::List(vec![
                Val::Bool(true),
                Val::None,
                Val::Float(1.5),
                s("xé")
            ]))
        );
        assert_eq!(
            loads("123456789012345678901234567890").unwrap(),
            Val::Int("123456789012345678901234567890".into())
        );
        assert!(matches!(loads("NaN").unwrap(), Val::Float(f) if f.is_nan()));
        assert_eq!(loads("\"\\ud83d\\ude00\"").unwrap(), s("😀"));
        assert_eq!(loads("-0").unwrap(), int(0));
    }

    #[test]
    fn loads_errors_match_cpython() {
        assert_eq!(err(""), "Expecting value: line 1 column 1 (char 0)");
        assert_eq!(
            err("{"),
            "Expecting property name enclosed in double quotes: line 1 column 2 (char 1)"
        );
        assert_eq!(
            err("{\"a\" 1}"),
            "Expecting ':' delimiter: line 1 column 6 (char 5)"
        );
        assert_eq!(
            err("{\"a\": 1 \"b\"}"),
            "Expecting ',' delimiter: line 1 column 9 (char 8)"
        );
        assert_eq!(err("[1,]"), "Expecting value: line 1 column 4 (char 3)");
        assert_eq!(
            err("{\"a\": 1,}"),
            "Expecting property name enclosed in double quotes: line 1 column 9 (char 8)"
        );
        assert_eq!(
            err("\"abc"),
            "Unterminated string starting at: line 1 column 1 (char 0)"
        );
        assert_eq!(
            err("\"a\\x\""),
            "Invalid \\escape: line 1 column 3 (char 2)"
        );
        assert_eq!(
            err("\"\\u12\""),
            "Invalid \\uXXXX escape: line 1 column 3 (char 2)"
        );
        assert_eq!(
            err("\"\\ud800\\uzzzz\""),
            "Invalid \\uXXXX escape: line 1 column 9 (char 8)"
        );
        assert_eq!(
            err("[1 2]"),
            "Expecting ',' delimiter: line 1 column 4 (char 3)"
        );
        assert_eq!(err("-"), "Expecting value: line 1 column 1 (char 0)");
        assert_eq!(
            err("\"a\tb\""),
            "Invalid control character at: line 1 column 3 (char 2)"
        );
        assert_eq!(err("{}\n x"), "Extra data: line 2 column 2 (char 4)");
        assert_eq!(err("01"), "Extra data: line 1 column 2 (char 1)");
        assert_eq!(
            err("\u{feff}{}"),
            "Unexpected UTF-8 BOM (decode using utf-8-sig): line 1 column 1 (char 0)"
        );
    }

    #[test]
    fn dumps_matches_python() {
        let mut d = Dict::new();
        d.set("success", Val::Bool(false));
        d.set("error", s("caf\u{e9} \"q\" \u{1f600}\n"));
        d.set("results", Val::List(vec![]));
        let v = Val::Dict(d);
        assert_eq!(
            dumps(&v, None),
            r#"{"success": false, "error": "caf\u00e9 \"q\" \ud83d\ude00\n", "results": []}"#
        );
        let mut inner = Dict::new();
        inner.set("port", int(5555));
        inner.set("aliases", Val::List(vec![s("tv"), s("sony")]));
        inner.set("empty", Val::Dict(Dict::new()));
        assert_eq!(
            dumps(&Val::Dict(inner), Some(2)),
            "{\n  \"port\": 5555,\n  \"aliases\": [\n    \"tv\",\n    \"sony\"\n  ],\n  \"empty\": {}\n}"
        );
        assert_eq!(dumps(&Val::Float(f64::NEG_INFINITY), None), "-Infinity");
        assert_eq!(dumps(&s("\u{7f}"), None), "\"\\u007f\"");
    }
}
