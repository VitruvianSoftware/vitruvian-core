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

//! JSON as Python's `json` module reads and writes it.
//!
//! The hook's payload, the policy and the backstop's user files are read with
//! `json.loads`, which accepts what serde_json does not (NaN, Infinity, ints of
//! any size) and keeps object order. The guard writes `json.dumps` text into
//! its log and its stdout, and searches it. Matching those byte for byte is
//! what makes the two guards decide alike, so this is its own small parser.

use crate::pyutil::{py_float_repr, py_repr_str};

#[derive(Clone, Debug)]
pub enum PyVal {
    None,
    Bool(bool),
    /// An int, as canonical decimal digits (Python ints have no size limit).
    Int(String),
    Float(f64),
    Str(String),
    List(Vec<PyVal>),
    /// Insertion order, as a Python dict keeps it.
    Dict(Vec<(String, PyVal)>),
}

#[derive(Debug, PartialEq, Eq)]
pub enum JsonErr {
    /// json.JSONDecodeError (a ValueError).
    Value,
    /// RecursionError: nesting deeper than Python's limit.
    Recursion,
}

/// Python's recursion limit, approximately: nesting deeper than this makes
/// `json.loads` raise RecursionError rather than ValueError.
const MAX_DEPTH: usize = 990;

impl PyVal {
    pub fn get(&self, key: &str) -> Option<&PyVal> {
        match self {
            PyVal::Dict(items) => items.iter().find(|(k, _)| k == key).map(|(_, v)| v),
            _ => None,
        }
    }

    pub fn has(&self, key: &str) -> bool {
        self.get(key).is_some()
    }

    pub fn is_dict(&self) -> bool {
        matches!(self, PyVal::Dict(_))
    }

    pub fn as_str(&self) -> Option<&str> {
        match self {
            PyVal::Str(s) => Some(s),
            _ => None,
        }
    }

    /// Python truthiness.
    pub fn truthy(&self) -> bool {
        match self {
            PyVal::None => false,
            PyVal::Bool(b) => *b,
            PyVal::Int(d) => d != "0",
            PyVal::Float(f) => *f != 0.0,
            PyVal::Str(s) => !s.is_empty(),
            PyVal::List(l) => !l.is_empty(),
            PyVal::Dict(d) => !d.is_empty(),
        }
    }

    /// `str(value)`.
    pub fn py_str(&self) -> String {
        match self {
            PyVal::Str(s) => s.clone(),
            other => other.py_repr(),
        }
    }

    /// `repr(value)`.
    pub fn py_repr(&self) -> String {
        match self {
            PyVal::None => "None".into(),
            PyVal::Bool(true) => "True".into(),
            PyVal::Bool(false) => "False".into(),
            PyVal::Int(d) => d.clone(),
            PyVal::Float(f) => py_float_repr(*f),
            PyVal::Str(s) => py_repr_str(s),
            PyVal::List(l) => {
                let items: Vec<String> = l.iter().map(|v| v.py_repr()).collect();
                format!("[{}]", items.join(", "))
            }
            PyVal::Dict(d) => {
                let items: Vec<String> = d
                    .iter()
                    .map(|(k, v)| format!("{}: {}", py_repr_str(k), v.py_repr()))
                    .collect();
                format!("{{{}}}", items.join(", "))
            }
        }
    }

    /// `dict.get(key)` on a dict, or None for anything else.
    pub fn get_or_none(&self, key: &str) -> PyVal {
        self.get(key).cloned().unwrap_or(PyVal::None)
    }
}

/// Python `==`.
pub fn py_eq(a: &PyVal, b: &PyVal) -> bool {
    use PyVal::*;
    match (a, b) {
        (None, None) => true,
        (Str(x), Str(y)) => x == y,
        (List(x), List(y)) => x.len() == y.len() && x.iter().zip(y).all(|(p, q)| py_eq(p, q)),
        (Dict(x), Dict(y)) => {
            x.len() == y.len()
                && x.iter().all(|(k, v)| match b.get(k) {
                    Some(w) => py_eq(v, w),
                    Option::None => false,
                })
        }
        _ => match (num(a), num(b)) {
            (Some(p), Some(q)) => num_eq(&p, &q),
            _ => false,
        },
    }
}

enum Num {
    I(String),
    F(f64),
}

fn num(v: &PyVal) -> Option<Num> {
    match v {
        PyVal::Bool(b) => Some(Num::I(if *b { "1".into() } else { "0".into() })),
        PyVal::Int(d) => Some(Num::I(d.clone())),
        PyVal::Float(f) => Some(Num::F(*f)),
        _ => None,
    }
}

fn num_eq(a: &Num, b: &Num) -> bool {
    match (a, b) {
        (Num::I(x), Num::I(y)) => x == y,
        (Num::F(x), Num::F(y)) => x == y,
        (Num::I(i), Num::F(f)) | (Num::F(f), Num::I(i)) => {
            if !f.is_finite() || f.fract() != 0.0 {
                return false;
            }
            // An integral float equals the int with the same exact digits.
            format!("{:.0}", f) == *i || (*f == 0.0 && i == "0")
        }
    }
}

/// `json.loads(text)`.
pub fn loads(text: &str) -> Result<PyVal, JsonErr> {
    let t: Vec<char> = text.chars().collect();
    if t.first() == Some(&'\u{feff}') {
        return Err(JsonErr::Value);
    }
    let mut p = Parser { t: &t, i: 0 };
    p.ws();
    let v = p.value(0)?;
    p.ws();
    if p.i != t.len() {
        return Err(JsonErr::Value);
    }
    Ok(v)
}

struct Parser<'a> {
    t: &'a [char],
    i: usize,
}

impl<'a> Parser<'a> {
    fn ws(&mut self) {
        while self.i < self.t.len() && matches!(self.t[self.i], ' ' | '\t' | '\n' | '\r') {
            self.i += 1;
        }
    }

    fn peek(&self) -> Option<char> {
        self.t.get(self.i).copied()
    }

    fn lit(&mut self, s: &str) -> bool {
        if crate::pyutil::starts_at(self.t, self.i, s) {
            self.i += s.chars().count();
            true
        } else {
            false
        }
    }

    fn value(&mut self, depth: usize) -> Result<PyVal, JsonErr> {
        match self.peek() {
            Some('"') => {
                self.i += 1;
                Ok(PyVal::Str(self.string()?))
            }
            Some('{') => {
                if depth >= MAX_DEPTH {
                    return Err(JsonErr::Recursion);
                }
                self.i += 1;
                self.object(depth + 1)
            }
            Some('[') => {
                if depth >= MAX_DEPTH {
                    return Err(JsonErr::Recursion);
                }
                self.i += 1;
                self.array(depth + 1)
            }
            Some('n') if self.lit("null") => Ok(PyVal::None),
            Some('t') if self.lit("true") => Ok(PyVal::Bool(true)),
            Some('f') if self.lit("false") => Ok(PyVal::Bool(false)),
            Some('N') if self.lit("NaN") => Ok(PyVal::Float(f64::NAN)),
            Some('I') if self.lit("Infinity") => Ok(PyVal::Float(f64::INFINITY)),
            Some('-') if crate::pyutil::starts_at(self.t, self.i, "-Infinity") => {
                self.i += 9;
                Ok(PyVal::Float(f64::NEG_INFINITY))
            }
            Some(c) if c == '-' || c.is_ascii_digit() => self.number(),
            _ => Err(JsonErr::Value),
        }
    }

    fn number(&mut self) -> Result<PyVal, JsonErr> {
        let t = self.t;
        let start = self.i;
        let mut i = self.i;
        if t.get(i) == Some(&'-') {
            i += 1;
        }
        match t.get(i) {
            Some('0') => i += 1,
            Some(c) if c.is_ascii_digit() => {
                while i < t.len() && t[i].is_ascii_digit() {
                    i += 1;
                }
            }
            _ => return Err(JsonErr::Value),
        }
        let int_end = i;
        let mut is_float = false;
        if t.get(i) == Some(&'.') && t.get(i + 1).map_or(false, |c| c.is_ascii_digit()) {
            i += 1;
            while i < t.len() && t[i].is_ascii_digit() {
                i += 1;
            }
            is_float = true;
        }
        if matches!(t.get(i), Some('e') | Some('E')) {
            let mut j = i + 1;
            if matches!(t.get(j), Some('+') | Some('-')) {
                j += 1;
            }
            if t.get(j).map_or(false, |c| c.is_ascii_digit()) {
                while j < t.len() && t[j].is_ascii_digit() {
                    j += 1;
                }
                i = j;
                is_float = true;
            }
        }
        self.i = i;
        let text: String = t[start..i].iter().collect();
        if is_float {
            return Ok(PyVal::Float(
                text.parse::<f64>().map_err(|_| JsonErr::Value)?,
            ));
        }
        let digits: String = t[start..int_end].iter().collect();
        Ok(PyVal::Int(if digits == "-0" { "0".into() } else { digits }))
    }

    fn hex4(&mut self) -> Result<u32, JsonErr> {
        if self.i + 4 > self.t.len() {
            return Err(JsonErr::Value);
        }
        let s: String = self.t[self.i..self.i + 4].iter().collect();
        if !s.chars().all(|c| c.is_ascii_hexdigit()) {
            return Err(JsonErr::Value);
        }
        self.i += 4;
        Ok(u32::from_str_radix(&s, 16).unwrap())
    }

    fn string(&mut self) -> Result<String, JsonErr> {
        let mut out = String::new();
        loop {
            let c = self.peek().ok_or(JsonErr::Value)?;
            self.i += 1;
            match c {
                '"' => return Ok(out),
                '\\' => {
                    let e = self.peek().ok_or(JsonErr::Value)?;
                    self.i += 1;
                    match e {
                        '"' => out.push('"'),
                        '\\' => out.push('\\'),
                        '/' => out.push('/'),
                        'b' => out.push('\x08'),
                        'f' => out.push('\x0c'),
                        'n' => out.push('\n'),
                        'r' => out.push('\r'),
                        't' => out.push('\t'),
                        'u' => {
                            let mut cp = self.hex4()?;
                            if (0xD800..0xDC00).contains(&cp)
                                && crate::pyutil::starts_at(self.t, self.i, "\\u")
                            {
                                let save = self.i;
                                self.i += 2;
                                match self.hex4() {
                                    Ok(lo) if (0xDC00..0xE000).contains(&lo) => {
                                        cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
                                    }
                                    _ => self.i = save,
                                }
                            }
                            // A lone surrogate cannot live in a Rust string.
                            out.push(char::from_u32(cp).unwrap_or('\u{fffd}'));
                        }
                        _ => return Err(JsonErr::Value),
                    }
                }
                c if (c as u32) < 0x20 => return Err(JsonErr::Value),
                c => out.push(c),
            }
        }
    }

    fn object(&mut self, depth: usize) -> Result<PyVal, JsonErr> {
        let mut items: Vec<(String, PyVal)> = Vec::new();
        self.ws();
        if self.peek() == Some('}') {
            self.i += 1;
            return Ok(PyVal::Dict(items));
        }
        loop {
            if self.peek() != Some('"') {
                return Err(JsonErr::Value);
            }
            self.i += 1;
            let key = self.string()?;
            self.ws();
            if self.peek() != Some(':') {
                return Err(JsonErr::Value);
            }
            self.i += 1;
            self.ws();
            let v = self.value(depth)?;
            match items.iter_mut().find(|(k, _)| *k == key) {
                Some(slot) => slot.1 = v,
                None => items.push((key, v)),
            }
            self.ws();
            match self.peek() {
                Some('}') => {
                    self.i += 1;
                    return Ok(PyVal::Dict(items));
                }
                Some(',') => {
                    self.i += 1;
                    self.ws();
                }
                _ => return Err(JsonErr::Value),
            }
        }
    }

    fn array(&mut self, depth: usize) -> Result<PyVal, JsonErr> {
        let mut items = Vec::new();
        self.ws();
        if self.peek() == Some(']') {
            self.i += 1;
            return Ok(PyVal::List(items));
        }
        loop {
            items.push(self.value(depth)?);
            self.ws();
            match self.peek() {
                Some(']') => {
                    self.i += 1;
                    return Ok(PyVal::List(items));
                }
                Some(',') => {
                    self.i += 1;
                    self.ws();
                }
                _ => return Err(JsonErr::Value),
            }
        }
    }
}

/// A JSON string as `json.dumps` writes it (ensure_ascii).
pub fn dumps_str(s: &str, out: &mut String) {
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
            ' '..='~' => out.push(c),
            c => {
                let cp = c as u32;
                if cp >= 0x10000 {
                    let v = cp - 0x10000;
                    out.push_str(&format!(
                        "\\u{:04x}\\u{:04x}",
                        0xD800 + (v >> 10),
                        0xDC00 + (v & 0x3FF)
                    ));
                } else {
                    out.push_str(&format!("\\u{:04x}", cp));
                }
            }
        }
    }
    out.push('"');
}

/// `json.dumps(value, sort_keys=sort_keys)`.
pub fn dumps(v: &PyVal, sort_keys: bool) -> String {
    let mut out = String::new();
    dump(v, sort_keys, &mut out);
    out
}

fn dump(v: &PyVal, sort_keys: bool, out: &mut String) {
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
        PyVal::Str(s) => dumps_str(s, out),
        PyVal::List(l) => {
            out.push('[');
            for (i, item) in l.iter().enumerate() {
                if i > 0 {
                    out.push_str(", ");
                }
                dump(item, sort_keys, out);
            }
            out.push(']');
        }
        PyVal::Dict(d) => {
            let mut items: Vec<&(String, PyVal)> = d.iter().collect();
            if sort_keys {
                items.sort_by(|a, b| a.0.cmp(&b.0));
            }
            out.push('{');
            for (i, (k, val)) in items.into_iter().enumerate() {
                if i > 0 {
                    out.push_str(", ");
                }
                dumps_str(k, out);
                out.push_str(": ");
                dump(val, sort_keys, out);
            }
            out.push('}');
        }
    }
}

/// A dict from string pairs, in order.
pub fn dict(items: Vec<(&str, PyVal)>) -> PyVal {
    PyVal::Dict(items.into_iter().map(|(k, v)| (k.to_string(), v)).collect())
}

pub fn s(v: &str) -> PyVal {
    PyVal::Str(v.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trips_like_python() {
        let v = loads(r#" {"b": [1, 2.50, -0, NaN, "é😀\u0001"], "a": {"x": true}, "b": null} "#)
            .unwrap();
        assert_eq!(dumps(&v, false), r#"{"b": null, "a": {"x": true}}"#);
        let v =
            loads(r#"[1, 2.50, -0, NaN, "é😀\u0001\/", 1e400, 12345678901234567890123]"#).unwrap();
        assert_eq!(
            dumps(&v, true),
            r#"[1, 2.5, 0, NaN, "\u00e9\ud83d\ude00\u0001/", Infinity, 12345678901234567890123]"#
        );
        assert_eq!(
            v.py_str(),
            "[1, 2.5, 0, nan, 'é😀\\x01/', inf, 12345678901234567890123]"
        );
    }

    #[test]
    fn rejects_what_python_rejects() {
        for bad in [
            "",
            "[1,]",
            "{'a': 1}",
            "01",
            "\"\x01\"",
            "\u{feff}{}",
            "[1] x",
            "tru",
        ] {
            assert_eq!(loads(bad).unwrap_err(), JsonErr::Value, "{:?}", bad);
        }
        let deep = "[".repeat(5000);
        assert_eq!(loads(&deep).unwrap_err(), JsonErr::Recursion);
    }

    #[test]
    fn equality_is_pythons() {
        let a = loads(r#"{"x": [1, true, 2.0]}"#).unwrap();
        let b = loads(r#"{"x": [1.0, 1, 2]}"#).unwrap();
        assert!(py_eq(&a, &b));
        assert!(!py_eq(&loads("NaN").unwrap(), &loads("NaN").unwrap()));
    }
}
