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

//! Thin adapter over `vitruvian_pycompat::json::loads_codepoints` preserving
//! `tools/sync-site-tools`'s `PyStr` code points (including lone surrogates),
//! `PyErr` exceptions, CPython 3.12 4300-digit integer limit, bounded nesting,
//! and Python object semantics (`subscript`, `py_get`, `iterate`, `truthy`,
//! `py_eq`, `py_lt`, `py_str`, `py_repr`).

use vitruvian_pycompat::json::{
    loads_codepoints, CodepointLoadOptions, CodepointValue, JsonErrorKind,
    DEFAULT_INT_MAX_STR_DIGITS,
};

pub use vitruvian_pycompat::json::DumpOptions;
pub use vitruvian_pycompat::pystr::repr_float as float_repr;

use crate::pyerr::PyErr;
use crate::pyops;
use crate::pystr::PyStr;

#[derive(Debug)]
pub enum Value {
    Null,
    Bool(bool),
    Int(String),
    Float(f64),
    Str(PyStr),
    Arr(Vec<Value>),
    Obj(Vec<(PyStr, Value)>),
}

enum CloneFrame<'a> {
    Arr {
        out: Vec<Value>,
        rem: std::slice::Iter<'a, Value>,
    },
    Obj {
        out: Vec<(PyStr, Value)>,
        key: PyStr,
        rem: std::slice::Iter<'a, (PyStr, Value)>,
    },
}

impl Clone for Value {
    fn clone(&self) -> Self {
        let mut cur = self;
        let mut stack: Vec<CloneFrame<'_>> = Vec::new();
        loop {
            let mut cloned = match cur {
                Value::Null => Value::Null,
                Value::Bool(b) => Value::Bool(*b),
                Value::Int(s) => Value::Int(s.clone()),
                Value::Float(f) => Value::Float(*f),
                Value::Str(s) => Value::Str(s.clone()),
                Value::Arr(items) => {
                    let mut iter = items.iter();
                    match iter.next() {
                        None => Value::Arr(Vec::new()),
                        Some(first) => {
                            stack.push(CloneFrame::Arr {
                                out: Vec::with_capacity(items.len()),
                                rem: iter,
                            });
                            cur = first;
                            continue;
                        }
                    }
                }
                Value::Obj(pairs) => {
                    let mut iter = pairs.iter();
                    match iter.next() {
                        None => Value::Obj(Vec::new()),
                        Some((k, first)) => {
                            stack.push(CloneFrame::Obj {
                                out: Vec::with_capacity(pairs.len()),
                                key: k.clone(),
                                rem: iter,
                            });
                            cur = first;
                            continue;
                        }
                    }
                }
            };

            loop {
                match stack.last_mut() {
                    None => return cloned,
                    Some(CloneFrame::Arr { out, rem }) => {
                        out.push(cloned);
                        if let Some(next) = rem.next() {
                            cur = next;
                            break;
                        }
                        let Some(CloneFrame::Arr { out, .. }) = stack.pop() else {
                            unreachable!();
                        };
                        cloned = Value::Arr(out);
                    }
                    Some(CloneFrame::Obj { out, key, rem }) => {
                        out.push((std::mem::take(key), cloned));
                        if let Some((next_k, next_v)) = rem.next() {
                            *key = next_k.clone();
                            cur = next_v;
                            break;
                        }
                        let Some(CloneFrame::Obj { out, .. }) = stack.pop() else {
                            unreachable!();
                        };
                        cloned = Value::Obj(out);
                    }
                }
            }
        }
    }
}

impl PartialEq for Value {
    fn eq(&self, other: &Self) -> bool {
        let mut stack = vec![(self, other)];
        while let Some((a, b)) = stack.pop() {
            match (a, b) {
                (Value::Null, Value::Null) => {}
                (Value::Bool(x), Value::Bool(y)) if x == y => {}
                (Value::Int(x), Value::Int(y)) if x == y => {}
                (Value::Float(x), Value::Float(y)) if x == y => {}
                (Value::Str(x), Value::Str(y)) if x == y => {}
                (Value::Arr(x), Value::Arr(y)) if x.len() == y.len() => {
                    for (p, q) in x.iter().zip(y.iter()) {
                        stack.push((p, q));
                    }
                }
                (Value::Obj(x), Value::Obj(y)) if x.len() == y.len() => {
                    for ((kx, vx), (ky, vy)) in x.iter().zip(y.iter()) {
                        if kx != ky {
                            return false;
                        }
                        stack.push((vx, vy));
                    }
                }
                _ => return false,
            }
        }
        true
    }
}

impl Drop for Value {
    fn drop(&mut self) {
        let mut stack: Vec<Value> = Vec::new();
        match self {
            Value::Arr(items) if !items.is_empty() => stack.append(items),
            Value::Obj(pairs) if !pairs.is_empty() => {
                for (_k, v) in std::mem::take(pairs) {
                    stack.push(v);
                }
            }
            _ => return,
        }
        while let Some(mut node) = stack.pop() {
            match &mut node {
                Value::Arr(items) if !items.is_empty() => stack.append(items),
                Value::Obj(pairs) if !pairs.is_empty() => {
                    for (_k, v) in std::mem::take(pairs) {
                        stack.push(v);
                    }
                }
                _ => {}
            }
        }
    }
}

impl Value {
    /// `d.get(key)` on an object; `None` for a missing key or a non-object.
    pub fn get(&self, key: &str) -> Option<&Value> {
        let key_cp = PyStr::from(key);
        match self {
            Value::Obj(pairs) => pairs
                .iter()
                .rev()
                .find(|(k, _)| *k == key_cp)
                .map(|(_, v)| v),
            _ => None,
        }
    }

    pub fn is_obj(&self) -> bool {
        matches!(self, Value::Obj(_))
    }

    /// Python truthiness.
    pub fn truthy(&self) -> bool {
        match self {
            Value::Null => false,
            Value::Bool(b) => *b,
            Value::Int(s) => s.trim_start_matches('-').chars().any(|c| c != '0'),
            Value::Float(f) => *f != 0.0,
            Value::Str(s) => !s.is_empty(),
            Value::Arr(a) => !a.is_empty(),
            Value::Obj(o) => !o.is_empty(),
        }
    }

    /// The Python type name, for error messages.
    pub fn type_name(&self) -> &'static str {
        match self {
            Value::Null => "NoneType",
            Value::Bool(_) => "bool",
            Value::Int(_) => "int",
            Value::Float(_) => "float",
            Value::Str(_) => "str",
            Value::Arr(_) => "list",
            Value::Obj(_) => "dict",
        }
    }

    /// `str(value)`, preserving lone surrogates.
    pub fn py_str(&self) -> PyStr {
        match self {
            Value::Str(text) => text.clone(),
            other => other.py_repr(),
        }
    }

    /// `repr(value)`, escaping lone surrogates as `\ud800`..`\udfff`.
    pub fn py_repr(&self) -> PyStr {
        let mut out = PyStr::new();
        format_iter(self, FormatMode::Repr, &mut out);
        out
    }
}

/// `f"{value:.1f}"` of a float.
pub fn format_fixed1(f: f64) -> String {
    vitruvian_pycompat::pystr::format_fixed(f, 1)
}

pub fn s(text: &str) -> Value {
    Value::Str(PyStr::from(text))
}

pub fn s_py(text: &PyStr) -> Value {
    Value::Str(text.clone())
}

pub fn int(value: i64) -> Value {
    Value::Int(value.to_string())
}

pub fn obj(pairs: Vec<(&str, Value)>) -> Value {
    let mut out: Vec<(PyStr, Value)> = Vec::with_capacity(pairs.len());
    for (k, v) in pairs {
        let key = PyStr::from(k);
        if let Some(slot) = out.iter_mut().find(|(ek, _)| *ek == key) {
            slot.1 = v;
        } else {
            out.push((key, v));
        }
    }
    Value::Obj(out)
}

pub fn list_of_str(items: &[&str]) -> Value {
    Value::Arr(items.iter().map(|item| s(item)).collect())
}

/// `int_str / 2**power`, correctly rounded, as Python's true division gives it;
/// `None` where Python raises `OverflowError`.
pub fn int_div_pow2(text: &str, power: u32) -> Option<f64> {
    let (negative, rest) = match text.strip_prefix('-') {
        Some(d) => (true, d),
        None => (false, text),
    };
    let trimmed = rest.trim_start_matches('0');
    if trimmed.is_empty() {
        return Some(0.0);
    }
    // n / 2**p == n * 5**p / 10**p, and both are exact decimals.
    let mut product: Vec<u32> = trimmed.bytes().rev().map(|b| (b - b'0') as u32).collect();
    for _ in 0..power {
        let mut carry = 0u32;
        for digit in product.iter_mut() {
            let v = *digit * 5 + carry;
            *digit = v % 10;
            carry = v / 10;
        }
        while carry > 0 {
            product.push(carry % 10);
            carry /= 10;
        }
    }
    let digits: String = product
        .iter()
        .rev()
        .map(|&d| char::from(b'0' + d as u8))
        .collect();
    let decimal = format!(
        "{}e-{}",
        if negative {
            format!("-{digits}")
        } else {
            digits
        },
        power
    );
    let value: f64 = decimal.parse().ok()?;
    if value.is_infinite() {
        None
    } else {
        Some(value)
    }
}

enum ConvertFrame {
    Arr {
        out: Vec<Value>,
        rem: std::vec::IntoIter<CodepointValue>,
    },
    Obj {
        out: Vec<(PyStr, Value)>,
        key: PyStr,
        rem: std::vec::IntoIter<(Vec<u32>, CodepointValue)>,
    },
}

fn from_codepoints(mut current: CodepointValue) -> Value {
    let mut stack: Vec<ConvertFrame> = Vec::new();
    loop {
        let mut produced = match &mut current {
            CodepointValue::Null => Value::Null,
            CodepointValue::Bool(b) => Value::Bool(*b),
            CodepointValue::Int(text) => Value::Int(std::mem::take(text)),
            CodepointValue::Float(x) => Value::Float(*x),
            CodepointValue::Str(cps) => Value::Str(PyStr(std::mem::take(cps))),
            CodepointValue::Arr(items) => {
                let mut iter = std::mem::take(items).into_iter();
                match iter.next() {
                    None => Value::Arr(Vec::new()),
                    Some(first) => {
                        stack.push(ConvertFrame::Arr {
                            out: Vec::with_capacity(iter.len() + 1),
                            rem: iter,
                        });
                        current = first;
                        continue;
                    }
                }
            }
            CodepointValue::Obj(entries) => {
                let mut iter = std::mem::take(entries).into_iter();
                match iter.next() {
                    None => Value::Obj(Vec::new()),
                    Some((key, first)) => {
                        stack.push(ConvertFrame::Obj {
                            out: Vec::with_capacity(iter.len() + 1),
                            key: PyStr(key),
                            rem: iter,
                        });
                        current = first;
                        continue;
                    }
                }
            }
        };

        loop {
            match stack.last_mut() {
                None => return produced,
                Some(ConvertFrame::Arr { out, rem }) => {
                    out.push(produced);
                    if let Some(next) = rem.next() {
                        current = next;
                        break;
                    }
                    let Some(ConvertFrame::Arr { out, .. }) = stack.pop() else {
                        unreachable!();
                    };
                    produced = Value::Arr(out);
                }
                Some(ConvertFrame::Obj { out, key, rem }) => {
                    out.push((std::mem::take(key), produced));
                    if let Some((next_key, next_val)) = rem.next() {
                        *key = PyStr(next_key);
                        current = next_val;
                        break;
                    }
                    let Some(ConvertFrame::Obj { out, .. }) = stack.pop() else {
                        unreachable!();
                    };
                    produced = Value::Obj(out);
                }
            }
        }
    }
}

/// `json.loads(text)`.
pub fn loads(text: &PyStr) -> Result<Value, PyErr> {
    loads_codepoints(
        text.chars(),
        &CodepointLoadOptions {
            max_depth: None,
            max_int_digits: Some(DEFAULT_INT_MAX_STR_DIGITS),
        },
    )
    .map(from_codepoints)
    .map_err(|e| match e.kind() {
        JsonErrorKind::Recursion => {
            PyErr::exc("RecursionError", e.recursion_message().unwrap_or(&e.msg))
        }
        JsonErrorKind::IntDigitLimit => PyErr::exc("ValueError", &e.msg),
        JsonErrorKind::Decode => PyErr::exc("json.decoder.JSONDecodeError", &e.python_str()),
    })
}

fn encode_string(text: &PyStr, ensure_ascii: bool, out: &mut PyStr) {
    out.push_char('"' as u32);
    for &c in text.chars() {
        match c {
            0x22 => out.push_str("\\\""),
            0x5C => out.push_str("\\\\"),
            0x0A => out.push_str("\\n"),
            0x0D => out.push_str("\\r"),
            0x09 => out.push_str("\\t"),
            0x08 => out.push_str("\\b"),
            0x0C => out.push_str("\\f"),
            _ if c < 0x20 => out.push_str(&format!("\\u{:04x}", c)),
            _ if ensure_ascii && c > 0x7E => {
                if c > 0xFFFF {
                    let v = c - 0x10000;
                    out.push_str(&format!(
                        "\\u{:04x}\\u{:04x}",
                        0xD800 | ((v >> 10) & 0x3FF),
                        0xDC00 | (v & 0x3FF)
                    ));
                } else {
                    out.push_str(&format!("\\u{:04x}", c));
                }
            }
            _ => out.push_char(c),
        }
    }
    out.push_char('"' as u32);
}

fn float_json(f: f64) -> String {
    if f.is_nan() {
        "NaN".to_string()
    } else if f.is_infinite() {
        if f > 0.0 { "Infinity" } else { "-Infinity" }.to_string()
    } else {
        float_repr(f)
    }
}

#[derive(Copy, Clone)]
enum FormatMode {
    Repr,
    Json {
        ensure_ascii: bool,
        indent: Option<usize>,
    },
}

enum FormatFrame<'a> {
    Arr {
        items: &'a [Value],
        next: usize,
    },
    Obj {
        entries: Vec<(&'a PyStr, &'a Value)>,
        next: usize,
    },
}

fn push_spaces(count: usize, out: &mut PyStr) {
    for _ in 0..count {
        out.push_char(' ' as u32);
    }
}

fn write_sep(i: usize, indent: Option<usize>, level: usize, out: &mut PyStr) {
    match indent {
        None => {
            if i > 0 {
                out.push_str(", ");
            }
        }
        Some(width) => {
            if i > 0 {
                out.push_str(",");
            }
            out.push_str("\n");
            push_spaces(width * level, out);
        }
    }
}

fn write_close_indent(indent: Option<usize>, level: usize, out: &mut PyStr) {
    if let Some(width) = indent {
        out.push_str("\n");
        push_spaces(width * level, out);
    }
}

fn write_key(k: &PyStr, mode: FormatMode, out: &mut PyStr) {
    match mode {
        FormatMode::Repr => out.push(&k.repr()),
        FormatMode::Json { ensure_ascii, .. } => encode_string(k, ensure_ascii, out),
    }
}

fn format_iter(root: &Value, mode: FormatMode, out: &mut PyStr) {
    let indent = match mode {
        FormatMode::Repr => None,
        FormatMode::Json { indent, .. } => indent,
    };
    let mut stack: Vec<FormatFrame<'_>> = Vec::new();
    let mut cur = root;
    loop {
        loop {
            match cur {
                Value::Null => {
                    out.push_str(match mode {
                        FormatMode::Repr => "None",
                        FormatMode::Json { .. } => "null",
                    });
                    break;
                }
                Value::Bool(true) => {
                    out.push_str(match mode {
                        FormatMode::Repr => "True",
                        FormatMode::Json { .. } => "true",
                    });
                    break;
                }
                Value::Bool(false) => {
                    out.push_str(match mode {
                        FormatMode::Repr => "False",
                        FormatMode::Json { .. } => "false",
                    });
                    break;
                }
                Value::Int(s) => {
                    out.push_str(&pyops::format_normalized_int(s));
                    break;
                }
                Value::Float(f) => {
                    match mode {
                        FormatMode::Repr => out.push_str(&float_repr(*f)),
                        FormatMode::Json { .. } => out.push_str(&float_json(*f)),
                    }
                    break;
                }
                Value::Str(text) => {
                    write_key(text, mode, out);
                    break;
                }
                Value::Arr(items) => {
                    if items.is_empty() {
                        out.push_str("[]");
                        break;
                    }
                    out.push_str("[");
                    stack.push(FormatFrame::Arr { items, next: 1 });
                    write_sep(0, indent, stack.len(), out);
                    cur = &items[0];
                }
                Value::Obj(pairs) => {
                    let entries = pyops::dedup_obj(pairs);
                    if entries.is_empty() {
                        out.push_str("{}");
                        break;
                    }
                    out.push_str("{");
                    let (k, v) = entries[0];
                    stack.push(FormatFrame::Obj { entries, next: 1 });
                    write_sep(0, indent, stack.len(), out);
                    write_key(k, mode, out);
                    out.push_str(": ");
                    cur = v;
                }
            }
        }

        loop {
            let level = stack.len();
            let Some(top) = stack.last_mut() else {
                return;
            };
            match top {
                FormatFrame::Arr { items, next } => {
                    if *next < items.len() {
                        let i = *next;
                        *next += 1;
                        write_sep(i, indent, level, out);
                        cur = &items[i];
                        break;
                    }
                    stack.pop();
                    write_close_indent(indent, stack.len(), out);
                    out.push_str("]");
                }
                FormatFrame::Obj { entries, next } => {
                    if *next < entries.len() {
                        let i = *next;
                        *next += 1;
                        write_sep(i, indent, level, out);
                        let (k, v) = entries[i];
                        write_key(k, mode, out);
                        out.push_str(": ");
                        cur = v;
                        break;
                    }
                    stack.pop();
                    write_close_indent(indent, stack.len(), out);
                    out.push_str("}");
                }
            }
        }
    }
}

/// `json.dumps(value, ensure_ascii=..., indent=...)`.
pub fn dumps(value: &Value, ensure_ascii: bool, indent: Option<usize>) -> PyStr {
    let mut out = PyStr::new();
    format_iter(
        value,
        FormatMode::Json {
            ensure_ascii,
            indent,
        },
        &mut out,
    );
    out
}

/// Python-object operations expected by `tools/sync-site-tools` over `Value`.
pub trait ValueExt {
    fn subscript(&self, key: &str) -> Result<&Value, PyErr>;
    /// Named `py_get` so `Value::get(&self, &str) -> Option<&Value>` does not shadow it.
    fn py_get(&self, key: &str) -> Result<Option<&Value>, PyErr>;
    fn get_or(&self, key: &str, default: Value) -> Result<Value, PyErr>;
    fn get_value(&self, key: &str) -> Result<Value, PyErr>;
    fn iterate(&self) -> Result<Vec<Value>, PyErr>;
    fn check_hashable(&self) -> Result<(), PyErr>;
    fn eq_str(&self, text: &str) -> bool;
    fn py_eq(&self, other: &Value) -> bool;
    fn py_lt(&self, other: &Value) -> Result<bool, PyErr>;
    fn to_pystr(&self) -> PyStr;
    fn to_pyrepr(&self) -> PyStr;
}

impl ValueExt for Value {
    fn subscript(&self, key: &str) -> Result<&Value, PyErr> {
        pyops::index_ref(self, key)
    }

    fn py_get(&self, key: &str) -> Result<Option<&Value>, PyErr> {
        pyops::get_ref(self, key)
    }

    fn get_or(&self, key: &str, default: Value) -> Result<Value, PyErr> {
        pyops::get_or(self, key, default)
    }

    fn get_value(&self, key: &str) -> Result<Value, PyErr> {
        self.get_or(key, Value::Null)
    }

    fn iterate(&self) -> Result<Vec<Value>, PyErr> {
        pyops::iterate(self)
    }

    fn check_hashable(&self) -> Result<(), PyErr> {
        pyops::check_hashable(self)
    }

    fn eq_str(&self, text: &str) -> bool {
        matches!(self, Value::Str(own) if *own == PyStr::from(text))
    }

    fn py_eq(&self, other: &Value) -> bool {
        pyops::py_eq(self, other)
    }

    fn py_lt(&self, other: &Value) -> Result<bool, PyErr> {
        pyops::lt(self, other)
    }

    fn to_pystr(&self) -> PyStr {
        self.py_str()
    }

    fn to_pyrepr(&self) -> PyStr {
        self.py_repr()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn load(text: &str) -> Result<Value, String> {
        loads(&PyStr::from(text)).map_err(|e| e.last_line())
    }

    fn err(text: &str) -> String {
        load(text)
            .unwrap_err()
            .trim_start_matches("json.decoder.JSONDecodeError: ")
            .to_string()
    }

    #[test]
    fn errors_are_the_c_scanners() {
        let cases = [
            (
                "\"\\ud83d\\ude00",
                "Invalid \\uXXXX escape: line 1 column 9 (char 8)",
            ),
            (
                "\"\\ud83d\\u12\"",
                "Invalid \\uXXXX escape: line 1 column 9 (char 8)",
            ),
            (
                "\"\\ud83d\\uzzzz\"x",
                "Invalid \\uXXXX escape: line 1 column 9 (char 8)",
            ),
            (
                "\"abc\\u12\"",
                "Invalid \\uXXXX escape: line 1 column 6 (char 5)",
            ),
            (
                "\"\\u1234",
                "Invalid \\uXXXX escape: line 1 column 3 (char 2)",
            ),
            (
                "\"\\",
                "Unterminated string starting at: line 1 column 1 (char 0)",
            ),
            ("\"a\\q\"", "Invalid \\escape: line 1 column 3 (char 2)"),
            (
                "{\"a\":1,}",
                "Expecting property name enclosed in double quotes: line 1 column 8 (char 7)",
            ),
            ("[1,]", "Expecting value: line 1 column 4 (char 3)"),
            ("[", "Expecting value: line 1 column 2 (char 1)"),
            (
                "{",
                "Expecting property name enclosed in double quotes: line 1 column 2 (char 1)",
            ),
            ("1.", "Extra data: line 1 column 2 (char 1)"),
            ("1e+", "Extra data: line 1 column 2 (char 1)"),
            ("-", "Expecting value: line 1 column 1 (char 0)"),
            ("nul", "Expecting value: line 1 column 1 (char 0)"),
            ("  ", "Expecting value: line 1 column 3 (char 2)"),
            (
                "\u{feff}1",
                "Unexpected UTF-8 BOM (decode using utf-8-sig): line 1 column 1 (char 0)",
            ),
            ("[1 2]", "Expecting ',' delimiter: line 1 column 4 (char 3)"),
            (
                "{\"a\" 1}",
                "Expecting ':' delimiter: line 1 column 6 (char 5)",
            ),
            (
                "{\"a\":1 \"b\"}",
                "Expecting ',' delimiter: line 1 column 8 (char 7)",
            ),
            (
                "\"a\u{1}\"",
                "Invalid control character at: line 1 column 3 (char 2)",
            ),
            ("1 x", "Extra data: line 1 column 3 (char 2)"),
            ("{\"a\":[}", "Expecting value: line 1 column 7 (char 6)"),
            ("\n\n  x", "Expecting value: line 3 column 3 (char 4)"),
            ("\r\r  x", "Expecting value: line 1 column 5 (char 4)"),
            ("\r\n  x", "Expecting value: line 2 column 3 (char 4)"),
        ];
        for (text, want) in cases {
            assert_eq!(err(text), want, "{:?}", text);
        }
    }

    #[test]
    fn values_and_dumps_round_trip_as_python() {
        let v = load("{\"a\": [1, 2.50, -0, -0.0, 1e400, NaN, true, null], \"b\": {}, \"a\": \"\\ud83d\\ude00\\u00e9\"}").unwrap();
        assert_eq!(
            dumps(&v, false, None).to_string_lossy(),
            "{\"a\": \"😀é\", \"b\": {}}"
        );
        assert_eq!(
            dumps(&v, true, None).to_string_lossy(),
            "{\"a\": \"\\ud83d\\ude00\\u00e9\", \"b\": {}}"
        );
        let w =
            load("[1, 2.50, -0, -0.0, 1e400, -Infinity, NaN, true, null, [], {\"k\": [\"x\"]}]")
                .unwrap();
        assert_eq!(
            dumps(&w, false, Some(2)).to_string_lossy(),
            "[\n  1,\n  2.5,\n  0,\n  -0.0,\n  Infinity,\n  -Infinity,\n  NaN,\n  true,\n  null,\n  [],\n  {\n    \"k\": [\n      \"x\"\n    ]\n  }\n]"
        );
        assert_eq!(
            w.to_pyrepr().to_string_lossy(),
            "[1, 2.5, 0, -0.0, inf, -inf, nan, True, None, [], {'k': ['x']}]"
        );
    }

    #[test]
    fn lone_surrogates_round_trip_without_replacement() {
        let v = load(r#"["\ud800", "x\udfffy"]"#).unwrap();
        assert_eq!(
            v,
            Value::Arr(vec![
                Value::Str(PyStr(vec![0xD800])),
                Value::Str(PyStr(vec!['x' as u32, 0xDFFF, 'y' as u32])),
            ])
        );
        assert_eq!(v.to_pyrepr().to_string_lossy(), r"['\ud800', 'x\udfffy']");
        assert_eq!(
            dumps(&v, true, None).to_string_lossy(),
            r#"["\ud800", "x\udfffy"]"#
        );
        let dumped = dumps(&v, false, None);
        assert_eq!(
            dumped.chars(),
            &[
                '[' as u32, '"' as u32, 0xD800, '"' as u32, ',' as u32, ' ' as u32, '"' as u32,
                'x' as u32, 0xDFFF, 'y' as u32, '"' as u32, ']' as u32,
            ]
        );
        let err = dumped.encode_utf8().unwrap_err();
        assert_eq!(
            err.last_line(),
            "UnicodeEncodeError: 'utf-8' codec can't encode character '\\ud800' in position 2: surrogates not allowed"
        );

        let raw_py = PyStr(vec!['a' as u32, 0xD800, 'b' as u32]);
        let wrapped = s_py(&raw_py);
        assert_eq!(wrapped.to_pystr(), raw_py);
        assert_eq!(wrapped.to_pyrepr().to_string_lossy(), r"'a\ud800b'");
    }

    #[test]
    fn float_repr_is_pythons() {
        let cases = [
            (1e16, "1e+16"),
            (1234567890123456.0, "1234567890123456.0"),
            (0.0001, "0.0001"),
            (1e-5, "1e-05"),
            (-0.0, "-0.0"),
            (0.0, "0.0"),
            (1.5e300, "1.5e+300"),
            (0.1, "0.1"),
            (123.456, "123.456"),
            (5e-324, "5e-324"),
        ];
        for (f, want) in cases {
            assert_eq!(float_repr(f), want);
        }
        assert_eq!(format_fixed1(0.25), "0.2");
        assert_eq!(format_fixed1(0.35), "0.3");
        assert_eq!(format_fixed1(2.25), "2.2");
        assert_eq!(format_fixed1(f64::NAN), "nan");
    }

    #[test]
    fn big_ints_compare_and_divide_exactly() {
        let big = format!("1{}", "0".repeat(309));
        assert_eq!(
            int_div_pow2(&big, 20).map(float_repr),
            Some("9.5367431640625e+302".to_string())
        );
        assert_eq!(int_div_pow2(&format!("1{}", "0".repeat(400)), 10), None);
        assert_eq!(int_div_pow2("4000", 10), Some(3.90625));
        assert_eq!(int_div_pow2("-0", 10), Some(0.0));
        assert!(int(3).py_lt(&Value::Float(3.5)).unwrap());
        assert!(!int(-3).py_lt(&Value::Float(-3.5)).unwrap());
        assert!(!int(9007199254740993)
            .py_lt(&Value::Float(9007199254740992.0))
            .unwrap());
        assert!(load(&"1".repeat(4301))
            .unwrap_err()
            .starts_with("ValueError: Exceeds the limit (4300 digits)"));
    }

    #[test]
    fn python_type_errors() {
        let v = load("[1]").unwrap();
        assert_eq!(
            v.subscript("a").unwrap_err().last_line(),
            "TypeError: list indices must be integers or slices, not str"
        );
        assert_eq!(
            load("\"x\"")
                .unwrap()
                .subscript("a")
                .unwrap_err()
                .last_line(),
            "TypeError: string indices must be integers, not 'str'"
        );
        assert_eq!(
            load("null")
                .unwrap()
                .subscript("a")
                .unwrap_err()
                .last_line(),
            "TypeError: 'NoneType' object is not subscriptable"
        );
        assert_eq!(
            load("{}").unwrap().subscript("a").unwrap_err().last_line(),
            "KeyError: 'a'"
        );
        assert_eq!(
            load("5").unwrap().iterate().unwrap_err().last_line(),
            "TypeError: 'int' object is not iterable"
        );
        assert_eq!(
            v.py_get("a").unwrap_err().last_line(),
            "AttributeError: 'list' object has no attribute 'get'"
        );
        assert_eq!(
            s("a").py_lt(&int(1)).unwrap_err().last_line(),
            "TypeError: '<' not supported between instances of 'str' and 'int'"
        );
        assert!(Value::Float(f64::NAN).py_eq(&Value::Float(f64::NAN)));
        assert!(Value::Bool(true).py_eq(&Value::Float(1.0)));
    }

    #[test]
    fn truthiness_and_adapter_helpers() {
        assert!(!Value::Null.truthy());
        assert!(!Value::Bool(false).truthy());
        assert!(Value::Bool(true).truthy());
        assert!(!Value::Int("-0".into()).truthy());
        assert!(int(1).truthy());
        assert!(!Value::Float(-0.0).truthy());
        assert!(Value::Float(0.1).truthy());
        assert!(!s("").truthy());
        assert!(s("x").truthy());
        assert!(!Value::Arr(vec![]).truthy());
        assert!(list_of_str(&["a"]).truthy());
        assert!(!obj(vec![]).truthy());
        assert!(obj(vec![("a", int(1)), ("a", int(2))]).truthy());

        let d = obj(vec![("k", s("v")), ("k", s("v2"))]);
        assert!(d.subscript("k").unwrap().eq_str("v2"));
        assert!(!d.subscript("k").unwrap().eq_str("v"));
        assert_eq!(d.py_get("missing").unwrap(), None);
        assert_eq!(d.get_value("missing").unwrap(), Value::Null);
        assert_eq!(d.get_or("missing", int(7)).unwrap(), int(7));
        assert!(s("a").check_hashable().is_ok());
        assert_eq!(
            d.check_hashable().unwrap_err().last_line(),
            "TypeError: unhashable type: 'dict'"
        );
    }

    #[test]
    fn deep_nesting_returns_recursion_error_without_crashing() {
        // Test CPython 3.12's 9,997 accepted / 9,998 rejected depth boundary on a 32 MiB thread.
        let handle = std::thread::Builder::new()
            .stack_size(32 << 20)
            .spawn(|| {
                fn obj_chain(depth: usize, leaf: &str) -> String {
                    format!("{}{}{}", r#"{"a":"#.repeat(depth), leaf, "}".repeat(depth))
                }
                fn mixed_chain(depth: usize, start_obj: bool, leaf: &str) -> String {
                    let mut out = String::new();
                    for k in 0..depth {
                        if (k % 2 == 0) == start_obj {
                            out.push_str(r#"{"a":"#);
                        } else {
                            out.push('[');
                        }
                    }
                    out.push_str(leaf);
                    for k in (0..depth).rev() {
                        if (k % 2 == 0) == start_obj {
                            out.push('}');
                        } else {
                            out.push(']');
                        }
                    }
                    out
                }

                const ACCEPTED_DEPTH: usize = vitruvian_pycompat::json::CPYTHON_312_MAX_DEPTH;
                assert_eq!(ACCEPTED_DEPTH, 9_997);
                // Exact accepted depth: 9,997 across arrays, objects, and mixed chains.
                let ok_cases = [
                    format!("{}{}", "[".repeat(ACCEPTED_DEPTH), "]".repeat(ACCEPTED_DEPTH)),
                    format!("{}1{}", "[".repeat(ACCEPTED_DEPTH), "]".repeat(ACCEPTED_DEPTH)),
                    obj_chain(ACCEPTED_DEPTH, "1"),
                    mixed_chain(ACCEPTED_DEPTH, false, "0"),
                    mixed_chain(ACCEPTED_DEPTH, true, "0"),
                ];
                for doc in &ok_cases {
                    let v = load(doc);
                    assert!(v.is_ok(), "depth {} should succeed: {:?}", ACCEPTED_DEPTH, v);
                }

                // Exact rejected depth: 9,998 and deeper (50,000), never aborting.
                let arr_err = "RecursionError: maximum recursion depth exceeded while decoding a JSON array from a unicode string";
                let obj_err = "RecursionError: maximum recursion depth exceeded while decoding a JSON object from a unicode string";

                for doc in [
                    "[".repeat(ACCEPTED_DEPTH + 1),
                    format!(
                        "{}{}",
                        "[".repeat(ACCEPTED_DEPTH + 1),
                        "]".repeat(ACCEPTED_DEPTH + 1)
                    ),
                    "[".repeat(50_000),
                    format!("{}{}", "[".repeat(50_000), "]".repeat(50_000)),
                    // k=0..9997 -> 9,998th opener is k=9997 (odd); start_obj=true alternates {'a':[... -> '[' at k=9997.
                    mixed_chain(ACCEPTED_DEPTH + 1, true, "0"),
                ] {
                    assert_eq!(load(&doc).unwrap_err(), arr_err);
                }

                for doc in [
                    r#"{"a":"#.repeat(ACCEPTED_DEPTH + 1),
                    obj_chain(ACCEPTED_DEPTH + 1, "1"),
                    r#"{"a":"#.repeat(50_000),
                    obj_chain(50_000, "1"),
                    // k=0..9997 -> 9,998th opener is k=9997 (odd); start_obj=false alternates [{"a":... -> '{' at k=9997.
                    mixed_chain(ACCEPTED_DEPTH + 1, false, "0"),
                ] {
                    assert_eq!(load(&doc).unwrap_err(), obj_err);
                }

                let err = loads(&PyStr::from("[".repeat(ACCEPTED_DEPTH + 1))).unwrap_err();
                let stderr = String::from_utf8(err.stderr_bytes()).unwrap();
                assert!(
                    stderr.ends_with(&format!("{arr_err}\n")),
                    "unexpected stderr: {stderr:?}"
                );
            })
            .unwrap();
        handle.join().unwrap();
    }

    fn build_deep_arr(depth: usize, mut leaf: Value) -> Value {
        for _ in 0..depth {
            leaf = Value::Arr(vec![leaf]);
        }
        leaf
    }

    fn build_deep_obj(depth: usize, mut leaf: Value) -> Value {
        for _ in 0..depth {
            leaf = Value::Obj(vec![(PyStr::from("a"), leaf)]);
        }
        leaf
    }

    fn build_deep_mixed(depth: usize, mut leaf: Value) -> Value {
        for k in (0..depth).rev() {
            if k % 2 == 0 {
                leaf = Value::Obj(vec![(PyStr::from("a"), leaf)]);
            } else {
                leaf = Value::Arr(vec![leaf]);
            }
        }
        leaf
    }

    fn build_deep_mixed_json(depth: usize, leaf: &str) -> String {
        let mut out = String::new();
        for k in 0..depth {
            if k % 2 == 0 {
                out.push_str(r#"{"a":"#);
            } else {
                out.push('[');
            }
        }
        out.push_str(leaf);
        for k in (0..depth).rev() {
            if k % 2 == 0 {
                out.push('}');
            } else {
                out.push(']');
            }
        }
        out
    }

    #[test]
    fn deep_loads_and_from_codepoints_2mib_stack() {
        let handle = std::thread::Builder::new()
            .stack_size(2 << 20)
            .spawn(|| {
                const DEPTH: usize = vitruvian_pycompat::json::CPYTHON_312_MAX_DEPTH;
                let arr_doc = format!("{}1{}", "[".repeat(DEPTH), "]".repeat(DEPTH));
                let obj_doc = format!("{}{}{}", r#"{"a":"#.repeat(DEPTH), "1", "}".repeat(DEPTH));
                let mixed_doc = build_deep_mixed_json(DEPTH, "1");

                let a = loads(&PyStr::from(arr_doc)).unwrap();
                assert_eq!(a, build_deep_arr(DEPTH, int(1)));
                let o = loads(&PyStr::from(obj_doc)).unwrap();
                assert_eq!(o, build_deep_obj(DEPTH, int(1)));
                let m = loads(&PyStr::from(mixed_doc)).unwrap();
                assert_eq!(m, build_deep_mixed(DEPTH, int(1)));
            })
            .unwrap();
        handle.join().unwrap();
    }

    #[test]
    fn deep_py_repr_and_py_str_2mib_stack() {
        let handle = std::thread::Builder::new()
            .stack_size(2 << 20)
            .spawn(|| {
                const DEPTH: usize = vitruvian_pycompat::json::CPYTHON_312_MAX_DEPTH;
                let a = build_deep_arr(DEPTH, int(1));
                let r_a = a.py_repr().to_string_lossy();
                assert_eq!(r_a, format!("{}1{}", "[".repeat(DEPTH), "]".repeat(DEPTH)));
                assert_eq!(a.py_str(), a.to_pyrepr());
                assert_eq!(a.to_pystr(), a.py_repr());

                let o = build_deep_obj(DEPTH, s_py(&PyStr(vec![0xD800])));
                let r_o = o.to_pyrepr().to_string_lossy();
                assert!(r_o.starts_with(&"{'a': ".repeat(16)));
                assert!(r_o.contains(r"'\ud800'"));
                assert_eq!(o.to_pystr().to_string_lossy(), r_o);

                let m = build_deep_mixed(DEPTH, int(1));
                let r_m = m.py_repr().to_string_lossy();
                assert!(r_m.starts_with("{'a': [{'a': ["));
                assert_eq!(m.py_str().to_string_lossy(), r_m);
            })
            .unwrap();
        handle.join().unwrap();
    }

    #[test]
    fn deep_dumps_2mib_stack() {
        let handle = std::thread::Builder::new()
            .stack_size(2 << 20)
            .spawn(|| {
                const DEPTH: usize = vitruvian_pycompat::json::CPYTHON_312_MAX_DEPTH;
                let a = build_deep_arr(DEPTH, int(1));
                let d_a = dumps(&a, false, None).to_string_lossy();
                assert_eq!(d_a, format!("{}1{}", "[".repeat(DEPTH), "]".repeat(DEPTH)));

                let o = build_deep_obj(DEPTH, int(1));
                let want_o = format!("{}{}{}", r#"{"a": "#.repeat(DEPTH), "1", "}".repeat(DEPTH));
                assert_eq!(dumps(&o, true, None).to_string_lossy(), want_o);

                let m = build_deep_mixed(DEPTH, s_py(&PyStr(vec![0xD800])));
                let d_m = dumps(&m, true, None).to_string_lossy();
                assert!(d_m.starts_with(r#"{"a": [{"a": ["#));
                assert!(d_m.contains(r#""\ud800""#));
            })
            .unwrap();
        handle.join().unwrap();
    }

    #[test]
    fn deep_clone_and_eq_2mib_stack() {
        let handle = std::thread::Builder::new()
            .stack_size(2 << 20)
            .spawn(|| {
                const DEPTH: usize = vitruvian_pycompat::json::CPYTHON_312_MAX_DEPTH;
                for (same, diff) in [
                    (build_deep_arr(DEPTH, int(1)), build_deep_arr(DEPTH, int(2))),
                    (build_deep_obj(DEPTH, int(1)), build_deep_obj(DEPTH, int(2))),
                    (
                        build_deep_mixed(DEPTH, int(1)),
                        build_deep_mixed(DEPTH, int(2)),
                    ),
                ] {
                    let cloned = same.clone();
                    assert_eq!(same, cloned);
                    assert_ne!(same, diff);
                }
            })
            .unwrap();
        handle.join().unwrap();
    }

    #[test]
    fn deep_truthy_and_accessors_2mib_stack() {
        let handle = std::thread::Builder::new()
            .stack_size(2 << 20)
            .spawn(|| {
                const DEPTH: usize = vitruvian_pycompat::json::CPYTHON_312_MAX_DEPTH;
                let a = build_deep_arr(DEPTH, int(1));
                assert!(a.truthy());
                assert_eq!(a.iterate().unwrap().len(), 1);

                let o = build_deep_obj(DEPTH, int(1));
                assert!(o.truthy());
                assert!(o.get("a").is_some());
                assert!(o.get_or("a", Value::Null).unwrap().truthy());
                assert_eq!(o.iterate().unwrap(), vec![s("a")]);
            })
            .unwrap();
        handle.join().unwrap();
    }
}
