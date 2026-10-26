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

//! Python-compatible JSON parser, serializer, equality, and `repr` formatting.
//! Preserves object key insertion order (with duplicate-key overwrite in place)
//! and arbitrary-precision integer text so `py_repr()` and `dumps_compact()`
//! match Python 3's `json.loads` and `json.dumps(..., separators=(",", ":"))`.

use crate::pystr;

#[derive(Clone, Debug)]
pub enum Value {
    Null,
    Bool(bool),
    Int(String),
    Float(f64),
    Str(String),
    Arr(Vec<Value>),
    Obj(Vec<(String, Value)>),
}

impl Value {
    pub fn get(&self, key: &str) -> Option<&Value> {
        match self {
            Value::Obj(items) => items.iter().find(|(k, _)| k == key).map(|(_, v)| v),
            _ => None,
        }
    }

    pub fn has(&self, key: &str) -> bool {
        self.get(key).is_some()
    }

    pub fn as_str(&self) -> Option<&str> {
        match self {
            Value::Str(s) => Some(s),
            _ => None,
        }
    }

    pub fn as_bool(&self) -> Option<bool> {
        match self {
            Value::Bool(b) => Some(*b),
            _ => None,
        }
    }

    pub fn as_arr(&self) -> Option<&[Value]> {
        match self {
            Value::Arr(items) => Some(items),
            _ => None,
        }
    }

    pub fn as_obj(&self) -> Option<&[(String, Value)]> {
        match self {
            Value::Obj(items) => Some(items),
            _ => None,
        }
    }

    pub fn is_dict(&self) -> bool {
        matches!(self, Value::Obj(_))
    }

    pub fn is_list(&self) -> bool {
        matches!(self, Value::Arr(_))
    }

    pub fn is_str(&self) -> bool {
        matches!(self, Value::Str(_))
    }

    pub fn is_bool(&self) -> bool {
        matches!(self, Value::Bool(_))
    }

    pub fn is_int(&self) -> bool {
        matches!(self, Value::Int(_))
    }

    /// `isinstance(value, (int, float)) and not isinstance(value, bool)`
    pub fn is_number(&self) -> bool {
        matches!(self, Value::Int(_) | Value::Float(_))
    }

    /// `is_number(value) and float(value).is_integer()`
    pub fn is_whole(&self) -> bool {
        match self {
            Value::Int(_) => true,
            Value::Float(f) => f.is_finite() && f.fract() == 0.0,
            _ => false,
        }
    }

    /// `value >= 0` for a number (`Int` or `Float`).
    pub fn is_non_negative(&self) -> bool {
        match self {
            Value::Int(s) => !normalize_int(s).starts_with('-'),
            Value::Float(f) => !f.is_nan() && *f >= 0.0,
            _ => false,
        }
    }

    pub fn py_str(&self) -> String {
        match self {
            Value::Str(s) => s.clone(),
            other => other.py_repr(),
        }
    }

    pub fn py_repr(&self) -> String {
        match self {
            Value::Null => "None".into(),
            Value::Bool(true) => "True".into(),
            Value::Bool(false) => "False".into(),
            Value::Int(s) => normalize_int(s),
            Value::Float(f) => pystr::repr_float(*f),
            Value::Str(s) => pystr::repr_str(s),
            Value::Arr(items) => {
                let parts: Vec<String> = items.iter().map(|v| v.py_repr()).collect();
                format!("[{}]", parts.join(", "))
            }
            Value::Obj(items) => {
                let parts: Vec<String> = items
                    .iter()
                    .map(|(k, v)| format!("{}: {}", pystr::repr_str(k), v.py_repr()))
                    .collect();
                format!("{{{}}}", parts.join(", "))
            }
        }
    }

    /// `json.dumps(self, separators=(",", ":"))` (with `ensure_ascii=True`).
    pub fn dumps_compact(&self) -> String {
        match self {
            Value::Null => "null".into(),
            Value::Bool(true) => "true".into(),
            Value::Bool(false) => "false".into(),
            Value::Int(s) => normalize_int(s),
            Value::Float(f) => {
                if f.is_nan() {
                    "NaN".into()
                } else if f.is_infinite() {
                    if *f > 0.0 {
                        "Infinity".into()
                    } else {
                        "-Infinity".into()
                    }
                } else {
                    pystr::repr_float(*f)
                }
            }
            Value::Str(s) => dumps_str_ascii(s),
            Value::Arr(items) => {
                let parts: Vec<String> = items.iter().map(|v| v.dumps_compact()).collect();
                format!("[{}]", parts.join(","))
            }
            Value::Obj(items) => {
                let parts: Vec<String> = items
                    .iter()
                    .map(|(k, v)| format!("{}:{}", dumps_str_ascii(k), v.dumps_compact()))
                    .collect();
                format!("{{{}}}", parts.join(","))
            }
        }
    }
}

fn dumps_str_ascii(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\u{08}' => out.push_str("\\b"),
            '\u{0c}' => out.push_str("\\f"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 || (c as u32) >= 0x7f => {
                let cp = c as u32;
                if cp < 0x10000 {
                    out.push_str(&format!("\\u{:04x}", cp));
                } else {
                    let n = cp - 0x10000;
                    let hi = 0xd800 | ((n >> 10) & 0x3ff);
                    let lo = 0xdc00 | (n & 0x3ff);
                    out.push_str(&format!("\\u{:04x}\\u{:04x}", hi, lo));
                }
            }
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

pub fn normalize_int(s: &str) -> String {
    let (neg, digits) = match s.strip_prefix('-') {
        Some(d) => (true, d),
        None => (false, s),
    };
    let trimmed = digits.trim_start_matches('0');
    if trimmed.is_empty() {
        "0".into()
    } else if neg {
        format!("-{}", trimmed)
    } else {
        trimmed.into()
    }
}

fn float_as_int(f: f64) -> Option<String> {
    if !f.is_finite() || f.fract() != 0.0 {
        return None;
    }
    Some(normalize_int(&format!("{:.0}", f)))
}

fn number_eq(a: &Value, b: &Value) -> bool {
    let int_text = |v: &Value| -> Option<String> {
        match v {
            Value::Bool(x) => Some(if *x { "1".into() } else { "0".into() }),
            Value::Int(s) => Some(normalize_int(s)),
            _ => None,
        }
    };
    match (a, b) {
        (Value::Float(x), Value::Float(y)) => x == y,
        (Value::Float(x), other) | (other, Value::Float(x)) => {
            match (float_as_int(*x), int_text(other)) {
                (Some(l), Some(r)) => l == r,
                _ => false,
            }
        }
        _ => int_text(a) == int_text(b),
    }
}

/// Python's `a == b`: `True == 1 == 1.0`, dicts equal regardless of key order.
pub fn py_eq(a: &Value, b: &Value) -> bool {
    let numeric = |v: &Value| matches!(v, Value::Bool(_) | Value::Int(_) | Value::Float(_));
    match (a, b) {
        (Value::Null, Value::Null) => true,
        (Value::Str(x), Value::Str(y)) => x == y,
        (Value::Arr(x), Value::Arr(y)) => {
            x.len() == y.len() && x.iter().zip(y).all(|(l, r)| py_eq(l, r))
        }
        (Value::Obj(x), Value::Obj(y)) => {
            x.len() == y.len()
                && x.iter().all(|(k, v)| match b.get(k) {
                    Some(w) => py_eq(v, w),
                    None => false,
                })
        }
        _ if numeric(a) && numeric(b) => number_eq(a, b),
        _ => false,
    }
}

pub fn loads_bytes(bytes: &[u8]) -> Result<Value, String> {
    let text = std::str::from_utf8(bytes).map_err(|e| e.to_string())?;
    loads(text)
}

pub fn loads(text: &str) -> Result<Value, String> {
    let chars: Vec<char> = text.chars().collect();
    if chars.first() == Some(&'\u{feff}') {
        return Err("Unexpected UTF-8 BOM".into());
    }
    let mut p = Parser { s: &chars };
    let start = p.ws(0);
    let (value, end) = p.scan(start)?;
    let end = p.ws(end);
    if end != chars.len() {
        return Err("Extra data".into());
    }
    Ok(value)
}

struct Parser<'a> {
    s: &'a [char],
}

fn is_ws(c: char) -> bool {
    matches!(c, ' ' | '\t' | '\n' | '\r')
}

impl<'a> Parser<'a> {
    fn ws(&self, mut i: usize) -> usize {
        while i < self.s.len() && is_ws(self.s[i]) {
            i += 1;
        }
        i
    }

    fn at(&self, i: usize) -> Option<char> {
        self.s.get(i).copied()
    }

    fn word(&self, i: usize, w: &str) -> bool {
        let w: Vec<char> = w.chars().collect();
        self.s.len() >= i + w.len() && self.s[i..i + w.len()] == w[..]
    }

    fn scan(&mut self, i: usize) -> Result<(Value, usize), String> {
        let c = self.at(i).ok_or_else(|| "Expecting value".to_string())?;
        match c {
            '"' => {
                let (s, end) = self.string(i + 1)?;
                Ok((Value::Str(s), end))
            }
            '{' => self.object(i + 1),
            '[' => self.array(i + 1),
            'n' if self.word(i, "null") => Ok((Value::Null, i + 4)),
            't' if self.word(i, "true") => Ok((Value::Bool(true), i + 4)),
            'f' if self.word(i, "false") => Ok((Value::Bool(false), i + 5)),
            'N' if self.word(i, "NaN") => Ok((Value::Float(f64::NAN), i + 3)),
            'I' if self.word(i, "Infinity") => Ok((Value::Float(f64::INFINITY), i + 8)),
            '-' if self.word(i, "-Infinity") => Ok((Value::Float(f64::NEG_INFINITY), i + 9)),
            _ => self.number(i),
        }
    }

    fn number(&self, start: usize) -> Result<(Value, usize), String> {
        let digit = |i: usize| matches!(self.at(i), Some(c) if c.is_ascii_digit());
        let mut i = start;
        if self.at(i) == Some('-') {
            i += 1;
        }
        match self.at(i) {
            Some('0') => i += 1,
            Some(c) if c.is_ascii_digit() => {
                while digit(i) {
                    i += 1;
                }
            }
            _ => return Err("Expecting value".into()),
        }
        let mut is_float = false;
        if self.at(i) == Some('.') && digit(i + 1) {
            is_float = true;
            i += 2;
            while digit(i) {
                i += 1;
            }
        }
        if matches!(self.at(i), Some('e' | 'E')) && i + 1 < self.s.len() {
            let e_start = i;
            i += 1;
            if matches!(self.at(i), Some('-' | '+')) && i + 1 < self.s.len() {
                i += 1;
            }
            while digit(i) {
                i += 1;
            }
            if digit(i - 1) {
                is_float = true;
            } else {
                i = e_start;
            }
        }
        let text: String = self.s[start..i].iter().collect();
        if is_float {
            Ok((Value::Float(text.parse::<f64>().unwrap_or(f64::NAN)), i))
        } else {
            Ok((Value::Int(text), i))
        }
    }

    fn hex(&self, from: usize, to: usize) -> Option<u32> {
        let mut c = 0u32;
        for i in from..to {
            c = (c << 4) | self.at(i)?.to_digit(16)?;
        }
        Some(c)
    }

    fn string(&self, mut end: usize) -> Result<(String, usize), String> {
        let len = self.s.len();
        let mut out = String::new();
        loop {
            let mut next = end;
            while next < len {
                let d = self.s[next];
                if d == '"' || d == '\\' {
                    break;
                }
                if (d as u32) <= 0x1f {
                    return Err("Invalid control character".into());
                }
                next += 1;
            }
            if next == len {
                return Err("Unterminated string".into());
            }
            let c = self.s[next];
            out.extend(&self.s[end..next]);
            next += 1;
            if c == '"' {
                return Ok((out, next));
            }
            if next == len {
                return Err("Unterminated string".into());
            }
            let e = self.s[next];
            if e != 'u' {
                end = next + 1;
                let ch = match e {
                    '"' => '"',
                    '\\' => '\\',
                    '/' => '/',
                    'b' => '\u{8}',
                    'f' => '\u{c}',
                    'n' => '\n',
                    'r' => '\r',
                    't' => '\t',
                    _ => return Err("Invalid \\escape".into()),
                };
                out.push(ch);
            } else {
                next += 1;
                end = next + 4;
                if end >= len {
                    return Err("Invalid \\uXXXX escape".into());
                }
                let mut cp = self
                    .hex(next, end)
                    .ok_or_else(|| "Invalid \\uXXXX escape".to_string())?;
                if (0xD800..0xDC00).contains(&cp)
                    && end + 6 < len
                    && self.s[end] == '\\'
                    && self.s[end + 1] == 'u'
                {
                    let lo = self
                        .hex(end + 2, end + 6)
                        .ok_or_else(|| "Invalid \\uXXXX escape".to_string())?;
                    if (0xDC00..0xE000).contains(&lo) {
                        cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
                        end += 6;
                    }
                }
                out.push(char::from_u32(cp).unwrap_or('\u{fffd}'));
            }
        }
    }

    fn object(&mut self, start: usize) -> Result<(Value, usize), String> {
        let mut items: Vec<(String, Value)> = Vec::new();
        let mut i = self.ws(start);
        if self.at(i) == Some('}') {
            return Ok((Value::Obj(items), i + 1));
        }
        loop {
            if self.at(i) != Some('"') {
                return Err("Expecting property name enclosed in double quotes".into());
            }
            let (key, next) = self.string(i + 1)?;
            i = self.ws(next);
            if self.at(i) != Some(':') {
                return Err("Expecting ':' delimiter".into());
            }
            i = self.ws(i + 1);
            let (value, next) = self.scan(i)?;
            if let Some(slot) = items.iter_mut().find(|(k, _)| *k == key) {
                slot.1 = value;
            } else {
                items.push((key, value));
            }
            i = self.ws(next);
            if self.at(i) == Some('}') {
                return Ok((Value::Obj(items), i + 1));
            }
            if self.at(i) != Some(',') {
                return Err("Expecting ',' delimiter".into());
            }
            i = self.ws(i + 1);
        }
    }

    fn array(&mut self, start: usize) -> Result<(Value, usize), String> {
        let mut items = Vec::new();
        let mut i = self.ws(start);
        if self.at(i) == Some(']') {
            return Ok((Value::Arr(items), i + 1));
        }
        loop {
            let (value, next) = self.scan(i)?;
            items.push(value);
            i = self.ws(next);
            if self.at(i) == Some(']') {
                return Ok((Value::Arr(items), i + 1));
            }
            if self.at(i) != Some(',') {
                return Err("Expecting ',' delimiter".into());
            }
            i = self.ws(i + 1);
        }
    }
}
