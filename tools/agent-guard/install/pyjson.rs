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

//! Python's semantics for the JSON the installer reads and writes.
//!
//! `json.dumps(indent=2)` as install.py's dump() writes a user file (so a
//! rewrite changes only agent-guard's entries), `json.loads`' error messages
//! (the "not valid JSON (...)" refusal quotes them), and the handful of dict
//! and list operations install.py performs, with the AttributeError or
//! TypeError Python would raise on a value of the wrong type.

use agent_guard::pyutil::{is_space, py_float_repr};
use agent_guard::pyval::{dumps_str, PyVal};

/// An exception install.py could raise, by what catches it.
#[derive(Clone, Debug, PartialEq)]
pub enum PyErr {
    /// SystemExit(message): printed to stderr, exit 1.
    Exit(String),
    /// AttributeError(message).
    Attr(String),
    /// TypeError(message).
    Type(String),
    /// Any other exception nothing in install.py catches: (type, message).
    Other(&'static str, String),
}

impl PyErr {
    /// `str(exc)`.
    pub fn text(&self) -> String {
        match self {
            PyErr::Exit(m) | PyErr::Attr(m) | PyErr::Type(m) | PyErr::Other(_, m) => m.clone(),
        }
    }

    /// The last line of the traceback Python would print for it.
    pub fn last_line(&self) -> String {
        match self {
            PyErr::Exit(m) => m.clone(),
            PyErr::Attr(m) => format!("AttributeError: {}", m),
            PyErr::Type(m) => format!("TypeError: {}", m),
            PyErr::Other(kind, m) => format!("{}: {}", kind, m),
        }
    }
}

pub type R<T> = Result<T, PyErr>;

pub fn type_name(v: &PyVal) -> &'static str {
    match v {
        PyVal::None => "NoneType",
        PyVal::Bool(_) => "bool",
        PyVal::Int(_) => "int",
        PyVal::Float(_) => "float",
        PyVal::Str(_) => "str",
        PyVal::List(_) => "list",
        PyVal::Dict(_) => "dict",
    }
}

/// `v.get(key)`: AttributeError unless v is a dict.
pub fn get<'a>(v: &'a PyVal, key: &str) -> R<Option<&'a PyVal>> {
    match v {
        PyVal::Dict(_) => Ok(v.get(key)),
        other => Err(no_attr(other, "get")),
    }
}

pub fn no_attr(v: &PyVal, attr: &str) -> PyErr {
    PyErr::Attr(format!(
        "'{}' object has no attribute '{}'",
        type_name(v),
        attr
    ))
}

/// `iter(v)`, collected: a dict's keys, a string's characters, a list's items.
pub fn iter(v: &PyVal) -> R<Vec<PyVal>> {
    match v {
        PyVal::List(l) => Ok(l.clone()),
        PyVal::Dict(d) => Ok(d.iter().map(|(k, _)| PyVal::Str(k.clone())).collect()),
        PyVal::Str(s) => Ok(s.chars().map(|c| PyVal::Str(c.to_string())).collect()),
        other => Err(PyErr::Type(format!(
            "'{}' object is not iterable",
            type_name(other)
        ))),
    }
}

/// `d[key] = value` on a dict (an existing key keeps its place).
pub fn set(d: &mut PyVal, key: &str, value: PyVal) {
    if let PyVal::Dict(items) = d {
        if let Some(slot) = items.iter_mut().find(|(k, _)| k == key) {
            slot.1 = value;
        } else {
            items.push((key.to_string(), value));
        }
    }
}

/// `del d[key]`.
pub fn del(d: &mut PyVal, key: &str) {
    if let PyVal::Dict(items) = d {
        items.retain(|(k, _)| k != key);
    }
}

pub fn get_mut<'a>(d: &'a mut PyVal, key: &str) -> Option<&'a mut PyVal> {
    match d {
        PyVal::Dict(items) => items.iter_mut().find(|(k, _)| k == key).map(|(_, v)| v),
        _ => None,
    }
}

pub fn keys(d: &PyVal) -> Vec<String> {
    match d {
        PyVal::Dict(items) => items.iter().map(|(k, _)| k.clone()).collect(),
        _ => Vec::new(),
    }
}

pub fn empty_dict() -> PyVal {
    PyVal::Dict(Vec::new())
}

/// `json.dumps(v, indent=2, ensure_ascii=ensure_ascii, separators=(",", key_sep))`.
pub fn dumps_indent(v: &PyVal, key_sep: &str, ensure_ascii: bool) -> String {
    let mut out = String::new();
    write_value(v, key_sep, ensure_ascii, 0, &mut out);
    out
}

fn write_str(s: &str, ensure_ascii: bool, out: &mut String) {
    if ensure_ascii {
        dumps_str(s, out);
        return;
    }
    // ensure_ascii=False: only '"', '\\' and the C0 controls are escaped.
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            '\x08' => out.push_str("\\b"),
            '\x0c' => out.push_str("\\f"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
}

fn newline_indent(level: usize, out: &mut String) {
    out.push('\n');
    for _ in 0..level * 2 {
        out.push(' ');
    }
}

fn write_value(v: &PyVal, key_sep: &str, ascii: bool, level: usize, out: &mut String) {
    match v {
        PyVal::None => out.push_str("null"),
        PyVal::Bool(true) => out.push_str("true"),
        PyVal::Bool(false) => out.push_str("false"),
        PyVal::Int(d) => out.push_str(d),
        PyVal::Float(f) => {
            if f.is_nan() {
                out.push_str("NaN")
            } else if f.is_infinite() {
                out.push_str(if *f > 0.0 { "Infinity" } else { "-Infinity" })
            } else {
                out.push_str(&py_float_repr(*f))
            }
        }
        PyVal::Str(s) => write_str(s, ascii, out),
        PyVal::List(l) => {
            if l.is_empty() {
                out.push_str("[]");
                return;
            }
            out.push('[');
            for (i, item) in l.iter().enumerate() {
                if i > 0 {
                    out.push(',');
                }
                newline_indent(level + 1, out);
                write_value(item, key_sep, ascii, level + 1, out);
            }
            newline_indent(level, out);
            out.push(']');
        }
        PyVal::Dict(d) => {
            if d.is_empty() {
                out.push_str("{}");
                return;
            }
            out.push('{');
            for (i, (k, val)) in d.iter().enumerate() {
                if i > 0 {
                    out.push(',');
                }
                newline_indent(level + 1, out);
                write_str(k, ascii, out);
                out.push_str(key_sep);
                write_value(val, key_sep, ascii, level + 1, out);
            }
            newline_indent(level, out);
            out.push('}');
        }
    }
}

/// `str(exc)` for the JSONDecodeError `json.loads(text)` raises, for text it rejects.
///
/// A port of CPython's C scanner (Modules/_json.c, 3.12): the same message
/// at the same character position.
pub fn decode_error(text: &str) -> String {
    let s: Vec<char> = text.chars().collect();
    let (msg, pos) = if s.first() == Some(&'\u{feff}') {
        ("Unexpected UTF-8 BOM (decode using utf-8-sig)", 0)
    } else {
        let start = skip_ws(&s, 0);
        match scan_once(&s, start) {
            Err(Scan::Stop(p)) => ("Expecting value", p),
            Err(Scan::Msg(m, p)) => (m, p),
            Ok(end) => {
                let end = skip_ws(&s, end);
                // Valid JSON should not get here; say what Python would of trailing text.
                ("Extra data", end)
            }
        }
    };
    let lineno = s[..pos.min(s.len())].iter().filter(|&&c| c == '\n').count() + 1;
    let colno = match s[..pos.min(s.len())].iter().rposition(|&c| c == '\n') {
        Some(nl) => pos - nl,
        None => pos + 1,
    };
    format!("{}: line {} column {} (char {})", msg, lineno, colno, pos)
}

enum Scan {
    /// StopIteration(pos): no value starts here ("Expecting value" at the top).
    Stop(usize),
    Msg(&'static str, usize),
}

fn is_json_ws(c: char) -> bool {
    matches!(c, ' ' | '\t' | '\n' | '\r')
}

fn skip_ws(s: &[char], mut i: usize) -> usize {
    while i < s.len() && is_json_ws(s[i]) {
        i += 1;
    }
    i
}

fn lit(s: &[char], i: usize, word: &str) -> bool {
    let w: Vec<char> = word.chars().collect();
    i + w.len() <= s.len() && s[i..i + w.len()] == w[..]
}

fn scan_once(s: &[char], idx: usize) -> Result<usize, Scan> {
    if idx >= s.len() {
        return Err(Scan::Stop(idx));
    }
    match s[idx] {
        '"' => return scan_string(s, idx + 1),
        '{' => return scan_object(s, idx + 1),
        '[' => return scan_array(s, idx + 1),
        'n' if lit(s, idx, "null") => return Ok(idx + 4),
        't' if lit(s, idx, "true") => return Ok(idx + 4),
        'f' if lit(s, idx, "false") => return Ok(idx + 5),
        'N' if lit(s, idx, "NaN") => return Ok(idx + 3),
        'I' if lit(s, idx, "Infinity") => return Ok(idx + 8),
        '-' if lit(s, idx, "-Infinity") => return Ok(idx + 9),
        _ => {}
    }
    match_number(s, idx)
}

fn match_number(s: &[char], start: usize) -> Result<usize, Scan> {
    let len = s.len();
    let digit = |i: usize| i < len && s[i].is_ascii_digit();
    let mut idx = start;
    if idx < len && s[idx] == '-' {
        idx += 1;
        if idx >= len {
            return Err(Scan::Stop(start));
        }
    }
    if idx < len && ('1'..='9').contains(&s[idx]) {
        idx += 1;
        while digit(idx) {
            idx += 1;
        }
    } else if idx < len && s[idx] == '0' {
        idx += 1;
    } else {
        return Err(Scan::Stop(start));
    }
    if idx + 1 < len && s[idx] == '.' && digit(idx + 1) {
        idx += 2;
        while digit(idx) {
            idx += 1;
        }
    }
    if idx + 1 < len && (s[idx] == 'e' || s[idx] == 'E') {
        let e_start = idx;
        idx += 1;
        if idx + 1 < len && (s[idx] == '-' || s[idx] == '+') {
            idx += 1;
        }
        while digit(idx) {
            idx += 1;
        }
        if !s[idx - 1].is_ascii_digit() {
            idx = e_start;
        }
    }
    Ok(idx)
}

fn hex4(s: &[char], from: usize) -> Option<u32> {
    let mut v = 0u32;
    for &c in &s[from..from + 4] {
        v = (v << 4) | c.to_digit(16)?;
    }
    Some(v)
}

fn scan_string(s: &[char], mut end: usize) -> Result<usize, Scan> {
    let len = s.len();
    let begin = end - 1;
    loop {
        let mut next = end;
        while next < len {
            let c = s[next];
            if c == '"' || c == '\\' {
                break;
            }
            if (c as u32) <= 0x1f {
                return Err(Scan::Msg("Invalid control character at", next));
            }
            next += 1;
        }
        if next >= len {
            return Err(Scan::Msg("Unterminated string starting at", begin));
        }
        let c = s[next];
        next += 1;
        if c == '"' {
            return Ok(next);
        }
        if next == len {
            return Err(Scan::Msg("Unterminated string starting at", begin));
        }
        let c = s[next];
        if c != 'u' {
            end = next + 1;
            if !matches!(c, '"' | '\\' | '/' | 'b' | 'f' | 'n' | 'r' | 't') {
                return Err(Scan::Msg("Invalid \\escape", end - 2));
            }
            continue;
        }
        next += 1;
        end = next + 4;
        if end >= len {
            return Err(Scan::Msg("Invalid \\uXXXX escape", next - 1));
        }
        let Some(cp) = hex4(s, next) else {
            return Err(Scan::Msg("Invalid \\uXXXX escape", end - 5));
        };
        if (0xD800..0xDC00).contains(&cp) && end + 6 < len && s[end] == '\\' && s[end + 1] == 'u' {
            end += 6;
            let Some(lo) = hex4(s, end - 4) else {
                return Err(Scan::Msg("Invalid \\uXXXX escape", end - 5));
            };
            if !(0xDC00..0xE000).contains(&lo) {
                end -= 6;
            }
        }
    }
}

fn scan_object(s: &[char], idx: usize) -> Result<usize, Scan> {
    let len = s.len();
    let mut idx = skip_ws(s, idx);
    if idx < len && s[idx] == '}' {
        return Ok(idx + 1);
    }
    loop {
        if idx >= len || s[idx] != '"' {
            return Err(Scan::Msg(
                "Expecting property name enclosed in double quotes",
                idx,
            ));
        }
        idx = scan_string(s, idx + 1)?;
        idx = skip_ws(s, idx);
        if idx >= len || s[idx] != ':' {
            return Err(Scan::Msg("Expecting ':' delimiter", idx));
        }
        idx = skip_ws(s, idx + 1);
        idx = scan_once(s, idx)?;
        idx = skip_ws(s, idx);
        if idx < len && s[idx] == '}' {
            return Ok(idx + 1);
        }
        if idx >= len || s[idx] != ',' {
            return Err(Scan::Msg("Expecting ',' delimiter", idx));
        }
        idx = skip_ws(s, idx + 1);
    }
}

fn scan_array(s: &[char], idx: usize) -> Result<usize, Scan> {
    let len = s.len();
    let mut idx = skip_ws(s, idx);
    if idx < len && s[idx] == ']' {
        return Ok(idx + 1);
    }
    loop {
        idx = scan_once(s, idx)?;
        idx = skip_ws(s, idx);
        if idx < len && s[idx] == ']' {
            return Ok(idx + 1);
        }
        if idx >= len || s[idx] != ',' {
            return Err(Scan::Msg("Expecting ',' delimiter", idx));
        }
        idx = skip_ws(s, idx + 1);
    }
}

/// `s.splitlines(True)`.
pub fn splitlines_keepends(s: &str) -> Vec<String> {
    let t: Vec<char> = s.chars().collect();
    let mut out = Vec::new();
    let mut start = 0;
    let mut i = 0;
    while i < t.len() {
        let c = t[i];
        let is_break = matches!(
            c,
            '\n' | '\r'
                | '\x0b'
                | '\x0c'
                | '\x1c'
                | '\x1d'
                | '\x1e'
                | '\u{85}'
                | '\u{2028}'
                | '\u{2029}'
        );
        if is_break {
            let mut end = i + 1;
            if c == '\r' && end < t.len() && t[end] == '\n' {
                end += 1;
            }
            out.push(t[start..end].iter().collect());
            start = end;
            i = end;
        } else {
            i += 1;
        }
    }
    if start < t.len() {
        out.push(t[start..].iter().collect());
    }
    out
}

/// `re.search(r'"\s:\s', text)`.
pub fn has_spaced_colon(text: &str) -> bool {
    let t: Vec<char> = text.chars().collect();
    t.windows(4)
        .any(|w| w[0] == '"' && is_space(w[1]) && w[2] == ':' && is_space(w[3]))
}

#[cfg(test)]
mod tests {
    use super::*;
    use agent_guard::pyval::loads;

    #[test]
    fn indent_dump_matches_python() {
        let v = loads(r#"{"a": [], "b": {}, "c": [1, {"d": "é/\u0001"}], "e": 1.5, "f": null}"#)
            .unwrap();
        assert_eq!(
            dumps_indent(&v, ": ", false),
            "{\n  \"a\": [],\n  \"b\": {},\n  \"c\": [\n    1,\n    {\n      \"d\": \"é/\\u0001\"\n    }\n  ],\n  \"e\": 1.5,\n  \"f\": null\n}"
        );
        assert!(dumps_indent(&v, " : ", true).contains("\"d\" : \"\\u00e9/\\u0001\""));
    }

    #[test]
    fn decode_errors_match_python() {
        // Each message was produced by CPython 3.12's json.loads.
        for (text, want) in [
            (
                "{\"a\":1,}",
                "Expecting property name enclosed in double quotes: line 1 column 8 (char 7)",
            ),
            ("[1,]", "Expecting value: line 1 column 4 (char 3)"),
            (
                "{\"a\" 1}",
                "Expecting ':' delimiter: line 1 column 6 (char 5)",
            ),
            (
                "{",
                "Expecting property name enclosed in double quotes: line 1 column 2 (char 1)",
            ),
            ("", "Expecting value: line 1 column 1 (char 0)"),
            ("  x", "Expecting value: line 1 column 3 (char 2)"),
            (
                "\"ab",
                "Unterminated string starting at: line 1 column 1 (char 0)",
            ),
            ("\"a\\q\"", "Invalid \\escape: line 1 column 3 (char 2)"),
            (
                "\"\\ud800\\u12\"",
                "Invalid \\uXXXX escape: line 1 column 9 (char 8)",
            ),
            ("{\"a\":1}x", "Extra data: line 1 column 8 (char 7)"),
            ("[01]", "Expecting ',' delimiter: line 1 column 3 (char 2)"),
            ("1.e5", "Extra data: line 1 column 2 (char 1)"),
            ("-", "Expecting value: line 1 column 1 (char 0)"),
            (
                "\u{feff}{}",
                "Unexpected UTF-8 BOM (decode using utf-8-sig): line 1 column 1 (char 0)",
            ),
            (
                "\"a\tb\"",
                "Invalid control character at: line 1 column 3 (char 2)",
            ),
            (
                "{\"a\":[1,2",
                "Expecting ',' delimiter: line 1 column 10 (char 9)",
            ),
            (
                "{broken",
                "Expecting property name enclosed in double quotes: line 1 column 2 (char 1)",
            ),
            (
                "{\n  \"a\": x\n}",
                "Expecting value: line 2 column 8 (char 9)",
            ),
        ] {
            assert_eq!(decode_error(text), want, "{:?}", text);
        }
    }

    #[test]
    fn splitlines_like_python() {
        assert_eq!(
            splitlines_keepends("a\nb\r\nc\u{2028}d"),
            vec!["a\n", "b\r\n", "c\u{2028}", "d"]
        );
        assert!(splitlines_keepends("").is_empty());
    }
}
