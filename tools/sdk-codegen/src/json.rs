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

//! What Python's `json.loads` reads, as CPython 3.12's C scanner reads it:
//! NaN and Infinity, integers of any size, an object's keys in the order they
//! came with the last of two equal keys winning, and the same JSONDecodeError
//! message at the same place for a document that does not parse. A value then
//! answers `repr`, `str`, `==` and truthiness the way the Python object would.
//!
//! One thing cannot be carried: a lone surrogate (`"\ud800"`), which a Rust
//! string cannot hold, is read as U+FFFD.

use crate::pyerr::PyErr;
use crate::pystr;

#[derive(Clone, Debug)]
pub enum Value {
    Null,
    Bool(bool),
    /// An integer, kept as its text: Python's ints have no size limit.
    Int(String),
    Float(f64),
    Str(String),
    Arr(Vec<Value>),
    /// Keys in the order the dict holds them.
    Obj(Vec<(String, Value)>),
}

impl Value {
    /// `d.get(key)` on a dict; None for a missing key or another type.
    pub fn get(&self, key: &str) -> Option<&Value> {
        match self {
            Value::Obj(items) => items.iter().find(|(k, _)| k == key).map(|(_, v)| v),
            _ => None,
        }
    }

    /// `key in d` for a dict.
    pub fn has(&self, key: &str) -> bool {
        self.get(key).is_some()
    }

    pub fn as_str(&self) -> Option<&str> {
        match self {
            Value::Str(s) => Some(s),
            _ => None,
        }
    }

    pub fn as_obj(&self) -> Option<&Vec<(String, Value)>> {
        match self {
            Value::Obj(items) => Some(items),
            _ => None,
        }
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

    /// The Python type's name, as error messages give it.
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

    /// `str(value)`, as an f-string formats it.
    pub fn py_str(&self) -> String {
        match self {
            Value::Str(s) => s.clone(),
            other => other.py_repr(),
        }
    }

    /// `repr(value)`.
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

    /// Whether this is a JSON number that is not a bool.
    pub fn is_number(&self) -> bool {
        matches!(self, Value::Int(_) | Value::Float(_))
    }

    /// The sign of a number: -1, 0 or 1; None for NaN or a non-number.
    pub fn sign(&self) -> Option<i32> {
        match self {
            Value::Int(s) => {
                let n = normalize_int(s);
                Some(if n == "0" {
                    0
                } else if n.starts_with('-') {
                    -1
                } else {
                    1
                })
            }
            Value::Float(f) => {
                if f.is_nan() {
                    None
                } else if *f == 0.0 {
                    Some(0)
                } else if *f < 0.0 {
                    Some(-1)
                } else {
                    Some(1)
                }
            }
            Value::Bool(b) => Some(if *b { 1 } else { 0 }),
            _ => None,
        }
    }
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

/// An integral float as the exact integer text it is, for comparing with an int.
fn float_as_int(f: f64) -> Option<String> {
    if !f.is_finite() || f.fract() != 0.0 {
        return None;
    }
    Some(normalize_int(&format!("{:.0}", f)))
}

/// Python's `a == b` on two numbers (bools are 0 and 1).
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

/// Python's `a == b`: True == 1 == 1.0, a dict equal whatever its order.
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

/// jsonschema's `_utils.equal`: as `==`, except that a bool equals only a bool.
pub fn schema_eq(a: &Value, b: &Value) -> bool {
    match (a, b) {
        (Value::Str(x), Value::Str(y)) => x == y,
        (Value::Str(_), _) | (_, Value::Str(_)) => false,
        (Value::Arr(x), Value::Arr(y)) => {
            x.len() == y.len() && x.iter().zip(y).all(|(l, r)| schema_eq(l, r))
        }
        (Value::Obj(x), Value::Obj(y)) => {
            x.len() == y.len()
                && x.iter().all(|(k, v)| match b.get(k) {
                    Some(w) => schema_eq(v, w),
                    None => false,
                })
        }
        (Value::Bool(x), Value::Bool(y)) => x == y,
        (Value::Bool(_), _) | (_, Value::Bool(_)) => false,
        (Value::Null, Value::Null) => true,
        (Value::Int(_) | Value::Float(_), Value::Int(_) | Value::Float(_)) => number_eq(a, b),
        _ => false,
    }
}

/// `json.loads(text)`, or the JSONDecodeError it raises.
pub fn loads(text: &str) -> Result<Value, PyErr> {
    let chars: Vec<char> = text.chars().collect();
    let fail = |msg: &str, pos: usize| decode_error(&chars, msg, pos);
    if chars.first() == Some(&'\u{feff}') {
        return Err(fail("Unexpected UTF-8 BOM (decode using utf-8-sig)", 0));
    }
    let mut p = Parser { s: &chars };
    let start = p.ws(0);
    let (value, end) = match p.scan(start) {
        Ok(found) => found,
        Err(Stop::At(pos)) => return Err(fail("Expecting value", pos)),
        Err(Stop::Error(msg, pos)) => return Err(fail(&msg, pos)),
    };
    let end = p.ws(end);
    if end != chars.len() {
        return Err(fail("Extra data", end));
    }
    Ok(value)
}

fn decode_error(doc: &[char], msg: &str, pos: usize) -> PyErr {
    let before = &doc[..pos.min(doc.len())];
    let lineno = before.iter().filter(|&&c| c == '\n').count() + 1;
    let colno = match before.iter().rposition(|&c| c == '\n') {
        Some(nl) => pos - nl,
        None => pos + 1,
    };
    PyErr::new(
        "json.decoder.JSONDecodeError",
        format!("{}: line {} column {} (char {})", msg, lineno, colno, pos),
    )
}

enum Stop {
    /// StopIteration: no value starts here.
    At(usize),
    /// A JSONDecodeError raised inside.
    Error(String, usize),
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

    fn scan(&mut self, i: usize) -> Result<(Value, usize), Stop> {
        let c = match self.at(i) {
            None => return Err(Stop::At(i)),
            Some(c) => c,
        };
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

    fn number(&self, start: usize) -> Result<(Value, usize), Stop> {
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
            _ => return Err(Stop::At(start)),
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

    /// CPython's scanstring_unicode, from just after the opening quote.
    fn string(&self, mut end: usize) -> Result<(String, usize), Stop> {
        let len = self.s.len();
        let begin = end - 1;
        let err = |msg: &str, pos: usize| Stop::Error(msg.to_string(), pos);
        let mut out = String::new();
        loop {
            let mut next = end;
            while next < len {
                let d = self.s[next];
                if d == '"' || d == '\\' {
                    break;
                }
                if (d as u32) <= 0x1f {
                    return Err(err("Invalid control character at", next));
                }
                next += 1;
            }
            if next == len {
                return Err(err("Unterminated string starting at", begin));
            }
            let c = self.s[next];
            out.extend(&self.s[end..next]);
            next += 1;
            if c == '"' {
                return Ok((out, next));
            }
            if next == len {
                return Err(err("Unterminated string starting at", begin));
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
                    _ => return Err(err("Invalid \\escape", end - 2)),
                };
                out.push(ch);
            } else {
                next += 1;
                end = next + 4;
                if end >= len {
                    return Err(err("Invalid \\uXXXX escape", next - 1));
                }
                let mut cp = match self.hex(next, end) {
                    Some(v) => v,
                    None => return Err(err("Invalid \\uXXXX escape", end - 5)),
                };
                if (0xD800..0xDC00).contains(&cp)
                    && end + 6 < len
                    && self.s[end] == '\\'
                    && self.s[end + 1] == 'u'
                {
                    let lo = match self.hex(end + 2, end + 6) {
                        Some(v) => v,
                        None => return Err(err("Invalid \\uXXXX escape", end + 1)),
                    };
                    if (0xDC00..0xE000).contains(&lo) {
                        cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
                        end += 6;
                    }
                }
                out.push(char::from_u32(cp).unwrap_or('\u{fffd}'));
            }
        }
    }

    fn object(&mut self, start: usize) -> Result<(Value, usize), Stop> {
        let err = |msg: &str, pos: usize| Stop::Error(msg.to_string(), pos);
        let mut items: Vec<(String, Value)> = Vec::new();
        let mut i = self.ws(start);
        if self.at(i) == Some('}') {
            return Ok((Value::Obj(items), i + 1));
        }
        loop {
            if self.at(i) != Some('"') {
                return Err(err("Expecting property name enclosed in double quotes", i));
            }
            let (key, next) = self.string(i + 1)?;
            i = self.ws(next);
            if self.at(i) != Some(':') {
                return Err(err("Expecting ':' delimiter", i));
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
                return Err(err("Expecting ',' delimiter", i));
            }
            i = self.ws(i + 1);
        }
    }

    fn array(&mut self, start: usize) -> Result<(Value, usize), Stop> {
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
                return Err(Stop::Error("Expecting ',' delimiter".into(), i));
            }
            i = self.ws(i + 1);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn msg(text: &str) -> String {
        loads(text).unwrap_err().message
    }

    #[test]
    fn reads_python_extensions() {
        let v = loads(r#"{"a": NaN, "b": -Infinity, "a": 2, "n": 123456789012345678901234567890}"#)
            .unwrap();
        assert_eq!(v.get("a").unwrap().py_repr(), "2");
        let keys: Vec<&str> = v
            .as_obj()
            .unwrap()
            .iter()
            .map(|(k, _)| k.as_str())
            .collect();
        assert_eq!(keys, ["a", "b", "n"]);
        assert_eq!(
            v.get("n").unwrap().py_repr(),
            "123456789012345678901234567890"
        );
        assert_eq!(v.get("b").unwrap().py_repr(), "-inf");
    }

    #[test]
    fn errors_name_the_place_as_python_does() {
        assert_eq!(msg(""), "Expecting value: line 1 column 1 (char 0)");
        assert_eq!(msg("[1,]"), "Expecting value: line 1 column 4 (char 3)");
        assert_eq!(
            msg("{\"a\":1,}"),
            "Expecting property name enclosed in double quotes: line 1 column 8 (char 7)"
        );
        assert_eq!(msg("{} x"), "Extra data: line 1 column 4 (char 3)");
        assert_eq!(
            msg("\n\"ab"),
            "Unterminated string starting at: line 2 column 1 (char 1)"
        );
        assert_eq!(
            msg("\"a\\q\""),
            "Invalid \\escape: line 1 column 3 (char 2)"
        );
        assert_eq!(
            msg("\"\\u12\""),
            "Invalid \\uXXXX escape: line 1 column 3 (char 2)"
        );
        assert_eq!(
            msg("\"a\nb\""),
            "Invalid control character at: line 1 column 3 (char 2)"
        );
        assert_eq!(
            msg("\u{feff}{}"),
            "Unexpected UTF-8 BOM (decode using utf-8-sig): line 1 column 1 (char 0)"
        );
        assert_eq!(
            msg("{\"a\" 1}"),
            "Expecting ':' delimiter: line 1 column 6 (char 5)"
        );
        assert_eq!(
            msg("[1 2]"),
            "Expecting ',' delimiter: line 1 column 4 (char 3)"
        );
        assert_eq!(msg("-"), "Expecting value: line 1 column 1 (char 0)");
        assert_eq!(msg("01"), "Extra data: line 1 column 2 (char 1)");
    }

    #[test]
    fn numbers_and_strings() {
        assert_eq!(loads("1e5").unwrap().py_repr(), "100000.0");
        assert_eq!(loads("-0").unwrap().py_repr(), "0");
        assert_eq!(loads("1.5E-7").unwrap().py_repr(), "1.5e-07");
        assert!(loads("1e").is_err());
        let v = loads(r#""\ud83d\ude00 \u00e9 \/""#).unwrap();
        assert_eq!(v.py_str(), "\u{1F600} \u{e9} /");
    }

    #[test]
    fn equality() {
        let t = Value::Bool(true);
        let one = Value::Int("1".into());
        let onef = Value::Float(1.0);
        assert!(py_eq(&t, &one));
        assert!(py_eq(&one, &onef));
        assert!(!schema_eq(&t, &one));
        assert!(schema_eq(&one, &onef));
        assert!(!py_eq(&Value::Float(f64::NAN), &Value::Float(f64::NAN)));
        let a = loads(r#"{"x": 1, "y": [true]}"#).unwrap();
        let b = loads(r#"{"y": [1], "x": 1.0}"#).unwrap();
        assert!(py_eq(&a, &b));
        assert!(!schema_eq(&a, &b));
        assert!(!Value::Int("-0".into()).truthy());
        assert_eq!(
            loads("[1, \"it's\", null, {}]").unwrap().py_repr(),
            "[1, \"it's\", None, {}]"
        );
    }
}
