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

//! JSON as Python's `json` module reads and writes it, and the parts of
//! Python's object model the catalog's scripts lean on: dicts that keep
//! their order, `repr`, `==` (where `1 == 1.0 == True`), `<`, hashing,
//! truthiness, `in` and iteration.
//!
//! Reading uses a scanner that follows CPython's `json` module: it gives
//! the same value, or the same JSONDecodeError message, position and all.

use std::cmp::Ordering;

use crate::pyerr::{Crash, Res};
use crate::pystr;

#[derive(Clone, Debug)]
pub enum Value {
    Null,
    Bool(bool),
    Int(i128),
    Float(f64),
    Str(String),
    List(Vec<Value>),
    Dict(Dict),
}

/// A dict: keys in the order they were first set.
#[derive(Clone, Debug, Default)]
pub struct Dict(pub Vec<(String, Value)>);

impl Dict {
    pub fn new() -> Dict {
        Dict(Vec::new())
    }

    pub fn get(&self, key: &str) -> Option<&Value> {
        self.0.iter().find(|(k, _)| k == key).map(|(_, v)| v)
    }

    pub fn get_mut(&mut self, key: &str) -> Option<&mut Value> {
        self.0.iter_mut().find(|(k, _)| k == key).map(|(_, v)| v)
    }

    pub fn contains(&self, key: &str) -> bool {
        self.0.iter().any(|(k, _)| k == key)
    }

    /// `d[key] = value`: an existing key keeps its place.
    pub fn insert(&mut self, key: impl Into<String>, value: Value) {
        let key = key.into();
        match self.get_mut(&key) {
            Some(slot) => *slot = value,
            None => self.0.push((key, value)),
        }
    }

    pub fn len(&self) -> usize {
        self.0.len()
    }

    pub fn is_empty(&self) -> bool {
        self.0.is_empty()
    }

    pub fn iter(&self) -> impl Iterator<Item = &(String, Value)> {
        self.0.iter()
    }

    pub fn keys(&self) -> impl Iterator<Item = &String> {
        self.0.iter().map(|(k, _)| k)
    }

    /// `d[key]`, or the KeyError.
    pub fn at(&self, key: &str) -> Res<&Value> {
        self.get(key).ok_or_else(|| Crash::key_error(key))
    }
}

impl<'a> IntoIterator for &'a Dict {
    type Item = &'a (String, Value);
    type IntoIter = std::slice::Iter<'a, (String, Value)>;
    fn into_iter(self) -> Self::IntoIter {
        self.0.iter()
    }
}

/// Structural equality (order of keys counts), for tests; Python's `==`
/// is `py_eq`.
impl PartialEq for Value {
    fn eq(&self, other: &Value) -> bool {
        match (self, other) {
            (Value::Null, Value::Null) => true,
            (Value::Bool(a), Value::Bool(b)) => a == b,
            (Value::Int(a), Value::Int(b)) => a == b,
            (Value::Float(a), Value::Float(b)) => a.to_bits() == b.to_bits(),
            (Value::Str(a), Value::Str(b)) => a == b,
            (Value::List(a), Value::List(b)) => a == b,
            (Value::Dict(a), Value::Dict(b)) => a.0 == b.0,
            _ => false,
        }
    }
}

/// Builds a dict from pairs, in order.
pub fn dict(pairs: Vec<(&str, Value)>) -> Value {
    let mut d = Dict::new();
    for (k, v) in pairs {
        d.insert(k, v);
    }
    Value::Dict(d)
}

pub fn s(text: impl Into<String>) -> Value {
    Value::Str(text.into())
}

impl Value {
    pub fn type_name(&self) -> &'static str {
        match self {
            Value::Null => "NoneType",
            Value::Bool(_) => "bool",
            Value::Int(_) => "int",
            Value::Float(_) => "float",
            Value::Str(_) => "str",
            Value::List(_) => "list",
            Value::Dict(_) => "dict",
        }
    }

    pub fn as_str(&self) -> Option<&str> {
        match self {
            Value::Str(s) => Some(s),
            _ => None,
        }
    }

    pub fn as_dict(&self) -> Option<&Dict> {
        match self {
            Value::Dict(d) => Some(d),
            _ => None,
        }
    }

    pub fn as_list(&self) -> Option<&Vec<Value>> {
        match self {
            Value::List(l) => Some(l),
            _ => None,
        }
    }

    pub fn is_null(&self) -> bool {
        matches!(self, Value::Null)
    }

    /// `bool(value)`.
    pub fn truthy(&self) -> bool {
        match self {
            Value::Null => false,
            Value::Bool(b) => *b,
            Value::Int(i) => *i != 0,
            Value::Float(f) => *f != 0.0,
            Value::Str(s) => !s.is_empty(),
            Value::List(l) => !l.is_empty(),
            Value::Dict(d) => !d.is_empty(),
        }
    }

    /// `value.get(key)`: None when absent; AttributeError when `value` is
    /// not a dict.
    pub fn get(&self, key: &str) -> Res<Option<&Value>> {
        match self {
            Value::Dict(d) => Ok(d.get(key)),
            other => Err(Crash::no_get(other)),
        }
    }

    /// `value.get(key, default)`, cloned.
    pub fn get_or(&self, key: &str, default: Value) -> Res<Value> {
        Ok(self.get(key)?.cloned().unwrap_or(default))
    }

    /// `value.get(key)`, cloned, None for absent.
    pub fn get_v(&self, key: &str) -> Res<Value> {
        self.get_or(key, Value::Null)
    }

    /// `value[key]` for a str key.
    pub fn at(&self, key: &str) -> Res<&Value> {
        match self {
            Value::Dict(d) => d.at(key),
            Value::List(_) => Err(Crash::new(
                "TypeError",
                "list indices must be integers or slices, not str",
            )),
            Value::Str(_) => Err(Crash::new(
                "TypeError",
                "string indices must be integers, not 'str'",
            )),
            other => Err(Crash::not_subscriptable(other)),
        }
    }

    /// `repr(value)`.
    pub fn repr(&self) -> String {
        let mut out = String::new();
        self.repr_into(&mut out);
        out
    }

    fn repr_into(&self, out: &mut String) {
        match self {
            Value::Null => out.push_str("None"),
            Value::Bool(true) => out.push_str("True"),
            Value::Bool(false) => out.push_str("False"),
            Value::Int(i) => out.push_str(&i.to_string()),
            Value::Float(f) => out.push_str(&pystr::repr_float(*f)),
            Value::Str(s) => out.push_str(&pystr::repr_str(s)),
            Value::List(l) => {
                out.push('[');
                for (i, v) in l.iter().enumerate() {
                    if i > 0 {
                        out.push_str(", ");
                    }
                    v.repr_into(out);
                }
                out.push(']');
            }
            Value::Dict(d) => {
                out.push('{');
                for (i, (k, v)) in d.iter().enumerate() {
                    if i > 0 {
                        out.push_str(", ");
                    }
                    out.push_str(&pystr::repr_str(k));
                    out.push_str(": ");
                    v.repr_into(out);
                }
                out.push('}');
            }
        }
    }

    /// `str(value)`, as an f-string puts it.
    pub fn py_str(&self) -> String {
        match self {
            Value::Str(s) => s.clone(),
            other => other.repr(),
        }
    }

    /// `list(value)`: a list's items, a dict's keys, a str's characters.
    pub fn py_iter(&self) -> Res<Vec<Value>> {
        match self {
            Value::List(l) => Ok(l.clone()),
            Value::Dict(d) => Ok(d.keys().map(|k| Value::Str(k.clone())).collect()),
            Value::Str(t) => Ok(t.chars().map(|c| Value::Str(c.to_string())).collect()),
            other => Err(Crash::not_iterable(other)),
        }
    }

    /// `item in value`.
    pub fn py_contains(&self, item: &Value) -> Res<bool> {
        match self {
            Value::List(l) => Ok(l.iter().any(|v| py_eq(v, item))),
            Value::Dict(d) => {
                key(item)?;
                Ok(match item {
                    Value::Str(k) => d.contains(k),
                    _ => false,
                })
            }
            Value::Str(t) => match item {
                Value::Str(sub) => Ok(t.contains(sub.as_str())),
                other => Err(Crash::new(
                    "TypeError",
                    format!(
                        "'in <string>' requires string as left operand, not {}",
                        other.type_name()
                    ),
                )),
            },
            other => Err(Crash::new(
                "TypeError",
                format!("argument of type '{}' is not iterable", other.type_name()),
            )),
        }
    }

    /// `text in value`.
    pub fn contains_str(&self, text: &str) -> Res<bool> {
        self.py_contains(&Value::Str(text.to_string()))
    }

    /// A dict's value for `key`; None for an absent key or a non-dict.
    pub fn field(&self, key: &str) -> Option<&Value> {
        match self {
            Value::Dict(d) => d.get(key),
            _ => None,
        }
    }

    pub fn field_mut(&mut self, key: &str) -> Option<&mut Value> {
        match self {
            Value::Dict(d) => d.get_mut(key),
            _ => None,
        }
    }

    pub fn py_repr(&self) -> String {
        self.repr()
    }

    pub fn as_f64(&self) -> Option<f64> {
        match self {
            Value::Int(i) => Some(*i as f64),
            Value::Float(f) => Some(*f),
            _ => None,
        }
    }
}

// --- reading -----------------------------------------------------------------

/// `json.loads(text)` for a str.
pub fn loads(text: &str) -> Res<Value> {
    if text.starts_with('\u{feff}') {
        return Err(decode_error(
            "Unexpected UTF-8 BOM (decode using utf-8-sig)",
            &text.chars().collect::<Vec<_>>(),
            0,
        ));
    }
    let chars: Vec<char> = text.chars().collect();
    Scanner {
        s: &chars,
        depth: 0,
    }
    .decode()
}

/// `json.loads(data)` for bytes: the encoding found the way `json` finds
/// it (a BOM, or where the NUL bytes are), then as for a str.
pub fn loads_bytes(data: &[u8]) -> Res<Value> {
    let text = decode_detected(data)?;
    let chars: Vec<char> = text.chars().collect();
    Scanner {
        s: &chars,
        depth: 0,
    }
    .decode()
}

fn decode_detected(b: &[u8]) -> Res<String> {
    if b.starts_with(b"\xef\xbb\xbf") {
        return crate::pyerr::decode_utf8_py(&b[3..], true);
    }
    if b.starts_with(b"\xff\xfe\x00\x00") || b.starts_with(b"\x00\x00\xfe\xff") {
        let big = b[0] == 0;
        return decode_utf32(&b[4..], big, "utf-32");
    }
    if b.starts_with(b"\xff\xfe") || b.starts_with(b"\xfe\xff") {
        let big = b[0] == 0xfe;
        return decode_utf16(&b[2..], big, "utf-16");
    }
    if b.len() >= 4 {
        if b[0] == 0 {
            return if b[1] != 0 {
                decode_utf16(b, true, "utf-16-be")
            } else {
                decode_utf32(b, true, "utf-32-be")
            };
        }
        if b[1] == 0 {
            return if b[2] != 0 || b[3] != 0 {
                decode_utf16(b, false, "utf-16-le")
            } else {
                decode_utf32(b, false, "utf-32-le")
            };
        }
    } else if b.len() == 2 {
        if b[0] == 0 {
            return decode_utf16(b, true, "utf-16-be");
        }
        if b[1] == 0 {
            return decode_utf16(b, false, "utf-16-le");
        }
    }
    crate::pyerr::decode_utf8_py(b, true)
}

fn decode_utf16(b: &[u8], big: bool, codec: &str) -> Res<String> {
    let units: Vec<u16> = b
        .chunks(2)
        .filter(|c| c.len() == 2)
        .map(|c| {
            if big {
                u16::from_be_bytes([c[0], c[1]])
            } else {
                u16::from_le_bytes([c[0], c[1]])
            }
        })
        .collect();
    if b.len() % 2 == 1 {
        return Err(Crash::new(
            "UnicodeDecodeError",
            format!(
                "'{}' codec can't decode byte 0x{:02x} in position {}: truncated data",
                codec.replace('-', "-"),
                b[b.len() - 1],
                b.len() - 1
            ),
        ));
    }
    Ok(char::decode_utf16(units.into_iter())
        .map(|r| r.unwrap_or('\u{FFFD}'))
        .collect())
}

fn decode_utf32(b: &[u8], big: bool, codec: &str) -> Res<String> {
    if b.len() % 4 != 0 {
        let start = b.len() - b.len() % 4;
        return Err(Crash::new(
            "UnicodeDecodeError",
            format!(
                "'{}' codec can't decode bytes in position {}-{}: truncated data",
                codec,
                start,
                b.len() - 1
            ),
        ));
    }
    let mut out = String::new();
    for (i, c) in b.chunks(4).enumerate() {
        let cp = if big {
            u32::from_be_bytes([c[0], c[1], c[2], c[3]])
        } else {
            u32::from_le_bytes([c[0], c[1], c[2], c[3]])
        };
        match char::from_u32(cp) {
            Some(ch) => out.push(ch),
            None if (0xD800..0xE000).contains(&cp) => out.push('\u{FFFD}'),
            None => {
                return Err(Crash::new(
                    "UnicodeDecodeError",
                    format!(
                        "'{}' codec can't decode bytes in position {}-{}: code point not in range(0x110000)",
                        codec,
                        i * 4,
                        i * 4 + 3
                    ),
                ))
            }
        }
    }
    Ok(out)
}

/// `json.JSONDecodeError(msg, doc, pos)`, as str() shows it.
fn decode_error(msg: &str, s: &[char], pos: usize) -> Crash {
    let lineno = s[..pos].iter().filter(|c| **c == '\n').count() + 1;
    let colno = match s[..pos].iter().rposition(|c| *c == '\n') {
        Some(nl) => pos - nl,
        None => pos + 1,
    };
    Crash::new(
        "json.decoder.JSONDecodeError",
        format!("{}: line {} column {} (char {})", msg, lineno, colno, pos),
    )
}

/// CPython's `_json` scanner.
struct Scanner<'a> {
    s: &'a [char],
    depth: usize,
}

enum Scan {
    Value(Value, usize),
    /// StopIteration(idx): no value starts here.
    Stop(usize),
}

impl<'a> Scanner<'a> {
    fn ws(&self, mut i: usize) -> usize {
        while i < self.s.len() && matches!(self.s[i], ' ' | '\t' | '\n' | '\r') {
            i += 1;
        }
        i
    }

    fn decode(&mut self) -> Res<Value> {
        let start = self.ws(0);
        match self.scan_once(start)? {
            Scan::Stop(at) => Err(decode_error("Expecting value", self.s, at)),
            Scan::Value(v, end) => {
                let end = self.ws(end);
                if end != self.s.len() {
                    return Err(decode_error("Extra data", self.s, end));
                }
                Ok(v)
            }
        }
    }

    fn starts(&self, i: usize, word: &str) -> bool {
        let w: Vec<char> = word.chars().collect();
        i + w.len() <= self.s.len() && self.s[i..i + w.len()] == w[..]
    }

    fn scan_once(&mut self, i: usize) -> Res<Scan> {
        if i >= self.s.len() {
            return Ok(Scan::Stop(i));
        }
        match self.s[i] {
            '"' => {
                let (text, end) = self.scanstring(i + 1)?;
                Ok(Scan::Value(Value::Str(text), end))
            }
            '{' => self.nested(i, true),
            '[' => self.nested(i, false),
            'n' if self.starts(i, "null") => Ok(Scan::Value(Value::Null, i + 4)),
            't' if self.starts(i, "true") => Ok(Scan::Value(Value::Bool(true), i + 4)),
            'f' if self.starts(i, "false") => Ok(Scan::Value(Value::Bool(false), i + 5)),
            'N' if self.starts(i, "NaN") => Ok(Scan::Value(Value::Float(f64::NAN), i + 3)),
            'I' if self.starts(i, "Infinity") => {
                Ok(Scan::Value(Value::Float(f64::INFINITY), i + 8))
            }
            '-' if self.starts(i, "-Infinity") => {
                Ok(Scan::Value(Value::Float(f64::NEG_INFINITY), i + 9))
            }
            _ => Ok(self.number(i)),
        }
    }

    fn nested(&mut self, i: usize, object: bool) -> Res<Scan> {
        self.depth += 1;
        if self.depth > 990 {
            return Err(Crash::new(
                "RecursionError",
                "maximum recursion depth exceeded while decoding a JSON document",
            ));
        }
        let r = if object {
            self.object(i + 1)
        } else {
            self.array(i + 1)
        };
        self.depth -= 1;
        r
    }

    fn number(&self, start: usize) -> Scan {
        let s = self.s;
        let digit = |i: usize| i < s.len() && s[i].is_ascii_digit();
        let mut i = start;
        if i < s.len() && s[i] == '-' {
            i += 1;
        }
        if i < s.len() && ('1'..='9').contains(&s[i]) {
            i += 1;
            while digit(i) {
                i += 1;
            }
        } else if i < s.len() && s[i] == '0' {
            i += 1;
        } else {
            return Scan::Stop(start);
        }
        let mut is_float = false;
        if i + 1 < s.len() && s[i] == '.' && digit(i + 1) {
            is_float = true;
            i += 2;
            while digit(i) {
                i += 1;
            }
        }
        if i < s.len() && (s[i] == 'e' || s[i] == 'E') {
            let mut e = i + 1;
            if e < s.len() && (s[e] == '-' || s[e] == '+') {
                e += 1;
            }
            if digit(e) {
                while digit(e) {
                    e += 1;
                }
                is_float = true;
                i = e;
            }
        }
        let text: String = s[start..i].iter().collect();
        if is_float {
            return Scan::Value(Value::Float(text.parse().unwrap_or(f64::NAN)), i);
        }
        match text.parse::<i128>() {
            Ok(n) => Scan::Value(Value::Int(n), i),
            // Past i128: Python keeps every digit; this keeps a float.
            Err(_) => Scan::Value(Value::Float(text.parse().unwrap_or(f64::NAN)), i),
        }
    }

    fn hex4(&self, at: usize) -> Option<u32> {
        let mut v = 0u32;
        for k in 0..4 {
            v = v * 16 + self.s.get(at + k)?.to_digit(16)?;
        }
        Some(v)
    }

    /// `scanstring(s, end)`: the text and the index after its closing quote.
    fn scanstring(&self, end: usize) -> Res<(String, usize)> {
        let s = self.s;
        let len = s.len();
        let begin = end - 1;
        let mut out = String::new();
        let mut next = end;
        loop {
            // Find the end of the run of plain characters.
            let mut c = '\0';
            while next < len {
                c = s[next];
                if c == '"' || c == '\\' {
                    break;
                }
                if (c as u32) <= 0x1f {
                    return Err(decode_error("Invalid control character at", s, next));
                }
                out.push(c);
                next += 1;
            }
            if next >= len {
                return Err(decode_error("Unterminated string starting at", s, begin));
            }
            if c == '"' {
                return Ok((out, next + 1));
            }
            // A backslash.
            next += 1;
            if next == len {
                return Err(decode_error("Unterminated string starting at", s, begin));
            }
            let c = s[next];
            if c != 'u' {
                let end = next + 1;
                let ch = match c {
                    '"' => '"',
                    '\\' => '\\',
                    '/' => '/',
                    'b' => '\u{8}',
                    'f' => '\u{c}',
                    'n' => '\n',
                    'r' => '\r',
                    't' => '\t',
                    _ => return Err(decode_error("Invalid \\escape", s, end - 2)),
                };
                out.push(ch);
                next = end;
            } else {
                next += 1;
                let end = next + 4;
                if end >= len {
                    return Err(decode_error("Invalid \\uXXXX escape", s, next - 1));
                }
                let mut cp = match self.hex4(next) {
                    Some(v) => v,
                    None => return Err(decode_error("Invalid \\uXXXX escape", s, end - 5)),
                };
                let mut after = end;
                if (0xD800..0xDC00).contains(&cp)
                    && end + 6 < len
                    && s[end] == '\\'
                    && s[end + 1] == 'u'
                {
                    let low = match self.hex4(end + 2) {
                        Some(v) => v,
                        None => return Err(decode_error("Invalid \\uXXXX escape", s, end + 6 - 5)),
                    };
                    if (0xDC00..0xE000).contains(&low) {
                        cp = 0x10000 + (((cp - 0xD800) << 10) | (low - 0xDC00));
                        after = end + 6;
                    }
                }
                out.push(char::from_u32(cp).unwrap_or('\u{FFFD}'));
                next = after;
            }
        }
    }

    fn object(&mut self, start: usize) -> Res<Scan> {
        let s = self.s;
        let mut d = Dict::new();
        let mut i = self.ws(start);
        if i < s.len() && s[i] == '}' {
            return Ok(Scan::Value(Value::Dict(d), i + 1));
        }
        loop {
            if i >= s.len() || s[i] != '"' {
                return Err(decode_error(
                    "Expecting property name enclosed in double quotes",
                    s,
                    i,
                ));
            }
            let (k, after) = self.scanstring(i + 1)?;
            i = self.ws(after);
            if i >= s.len() || s[i] != ':' {
                return Err(decode_error("Expecting ':' delimiter", s, i));
            }
            i = self.ws(i + 1);
            match self.scan_once(i)? {
                Scan::Stop(at) => return Ok(Scan::Stop(at)),
                Scan::Value(v, end) => {
                    d.insert(k, v);
                    i = self.ws(end);
                }
            }
            if i < s.len() && s[i] == '}' {
                return Ok(Scan::Value(Value::Dict(d), i + 1));
            }
            if i >= s.len() || s[i] != ',' {
                return Err(decode_error("Expecting ',' delimiter", s, i));
            }
            i = self.ws(i + 1);
        }
    }

    fn array(&mut self, start: usize) -> Res<Scan> {
        let s = self.s;
        let mut out = Vec::new();
        let mut i = self.ws(start);
        if i < s.len() && s[i] == ']' {
            return Ok(Scan::Value(Value::List(out), i + 1));
        }
        loop {
            match self.scan_once(i)? {
                Scan::Stop(at) => return Ok(Scan::Stop(at)),
                Scan::Value(v, end) => {
                    out.push(v);
                    i = self.ws(end);
                }
            }
            if i < s.len() && s[i] == ']' {
                return Ok(Scan::Value(Value::List(out), i + 1));
            }
            if i >= s.len() || s[i] != ',' {
                return Err(decode_error("Expecting ',' delimiter", s, i));
            }
            i = self.ws(i + 1);
        }
    }
}

// --- writing -----------------------------------------------------------------

/// `json.dumps(value, ensure_ascii=..., indent=...)` with the default
/// separators for that indent.
pub fn dumps(v: &Value, indent: Option<usize>, ensure_ascii: bool) -> String {
    let mut out = String::new();
    write_value(v, indent, ensure_ascii, 0, &mut out);
    out
}

/// `json.dumps(value, ensure_ascii=False)`.
pub fn dumps_unicode(v: &Value) -> String {
    dumps(v, None, false)
}

/// `json.dumps(value)`.
pub fn dumps_plain(v: &Value) -> String {
    dumps(v, None, true)
}

fn newline(indent: Option<usize>, level: usize, out: &mut String) {
    if let Some(n) = indent {
        out.push('\n');
        for _ in 0..n * level {
            out.push(' ');
        }
    }
}

fn write_value(v: &Value, indent: Option<usize>, ascii: bool, level: usize, out: &mut String) {
    let item_sep = if indent.is_some() { "," } else { ", " };
    match v {
        Value::Null => out.push_str("null"),
        Value::Bool(true) => out.push_str("true"),
        Value::Bool(false) => out.push_str("false"),
        Value::Int(i) => out.push_str(&i.to_string()),
        Value::Float(f) => out.push_str(&float_json(*f)),
        Value::Str(s) => out.push_str(&quote(s, ascii)),
        Value::List(l) => {
            if l.is_empty() {
                out.push_str("[]");
                return;
            }
            out.push('[');
            for (i, x) in l.iter().enumerate() {
                if i > 0 {
                    out.push_str(item_sep);
                }
                newline(indent, level + 1, out);
                write_value(x, indent, ascii, level + 1, out);
            }
            newline(indent, level, out);
            out.push(']');
        }
        Value::Dict(d) => {
            if d.is_empty() {
                out.push_str("{}");
                return;
            }
            out.push('{');
            for (i, (k, x)) in d.iter().enumerate() {
                if i > 0 {
                    out.push_str(item_sep);
                }
                newline(indent, level + 1, out);
                out.push_str(&quote(k, ascii));
                out.push_str(": ");
                write_value(x, indent, ascii, level + 1, out);
            }
            newline(indent, level, out);
            out.push('}');
        }
    }
}

/// `float.__repr__` as `json` writes it, with its names for the
/// non-finite.
pub fn float_json(f: f64) -> String {
    if f.is_nan() {
        "NaN".into()
    } else if f.is_infinite() {
        if f > 0.0 {
            "Infinity".into()
        } else {
            "-Infinity".into()
        }
    } else {
        pystr::repr_float(f)
    }
}

/// A JSON string, escaped as `json.dumps` escapes it.
pub fn quote(s: &str, ascii: bool) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            '\u{8}' => out.push_str("\\b"),
            '\u{c}' => out.push_str("\\f"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c if ascii && (c as u32) > 0x7e => {
                let cp = c as u32;
                if cp == 0x7f {
                    out.push(c);
                } else if cp < 0x10000 {
                    out.push_str(&format!("\\u{:04x}", cp));
                } else {
                    let v = cp - 0x10000;
                    out.push_str(&format!(
                        "\\u{:04x}\\u{:04x}",
                        0xD800 | (v >> 10),
                        0xDC00 | (v & 0x3FF)
                    ));
                }
            }
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

// --- Python's comparisons ----------------------------------------------------

enum Num {
    I(i128),
    F(f64),
}

fn num(v: &Value) -> Option<Num> {
    match v {
        Value::Bool(b) => Some(Num::I(*b as i128)),
        Value::Int(i) => Some(Num::I(*i)),
        Value::Float(f) => Some(Num::F(*f)),
        _ => None,
    }
}

fn num_cmp(a: &Num, b: &Num) -> Option<Ordering> {
    match (a, b) {
        (Num::I(x), Num::I(y)) => Some(x.cmp(y)),
        (Num::I(x), Num::F(y)) => int_float_cmp(*x, *y),
        (Num::F(x), Num::I(y)) => int_float_cmp(*y, *x).map(Ordering::reverse),
        (Num::F(x), Num::F(y)) => x.partial_cmp(y),
    }
}

fn int_float_cmp(i: i128, f: f64) -> Option<Ordering> {
    if f.is_nan() {
        return None;
    }
    if f.is_infinite() {
        return Some(if f > 0.0 {
            Ordering::Less
        } else {
            Ordering::Greater
        });
    }
    // Exact: compare the integer with the float's floor, then its fraction.
    let fl = f.floor();
    if fl >= 1.7e38 {
        return Some(Ordering::Less);
    }
    if fl <= -1.7e38 {
        return Some(Ordering::Greater);
    }
    let fi = fl as i128;
    match i.cmp(&fi) {
        Ordering::Equal => {
            if f > fl {
                Some(Ordering::Less)
            } else {
                Some(Ordering::Equal)
            }
        }
        o => Some(o),
    }
}

/// Python's `a == b` for JSON values.
pub fn py_eq(a: &Value, b: &Value) -> bool {
    if let (Some(x), Some(y)) = (num(a), num(b)) {
        return num_cmp(&x, &y) == Some(Ordering::Equal);
    }
    match (a, b) {
        (Value::Null, Value::Null) => true,
        (Value::Str(x), Value::Str(y)) => x == y,
        (Value::List(x), Value::List(y)) => {
            x.len() == y.len() && x.iter().zip(y).all(|(p, q)| py_eq(p, q))
        }
        (Value::Dict(x), Value::Dict(y)) => {
            x.len() == y.len()
                && x.iter()
                    .all(|(k, v)| y.get(k).map_or(false, |w| py_eq(v, w)))
        }
        _ => false,
    }
}

/// jsonschema's `equal`: as `==`, except that a bool is never a number.
pub fn schema_equal(a: &Value, b: &Value) -> bool {
    match (a, b) {
        (Value::Str(x), Value::Str(y)) => x == y,
        (Value::Str(_), _) | (_, Value::Str(_)) => false,
        (Value::List(x), Value::List(y)) => {
            x.len() == y.len() && x.iter().zip(y).all(|(p, q)| schema_equal(p, q))
        }
        (Value::Dict(x), Value::Dict(y)) => {
            x.len() == y.len()
                && x.iter()
                    .all(|(k, v)| y.get(k).map_or(false, |w| schema_equal(v, w)))
        }
        (Value::Bool(x), Value::Bool(y)) => x == y,
        (Value::Bool(_), _) | (_, Value::Bool(_)) => false,
        _ => py_eq(a, b),
    }
}

/// Python's `a < b`, or the TypeError it raises.
pub fn py_lt(a: &Value, b: &Value) -> Res<bool> {
    if let (Some(x), Some(y)) = (num(a), num(b)) {
        return Ok(num_cmp(&x, &y) == Some(Ordering::Less));
    }
    match (a, b) {
        (Value::Str(x), Value::Str(y)) => Ok(x < y),
        (Value::List(x), Value::List(y)) => {
            for (p, q) in x.iter().zip(y) {
                if !py_eq(p, q) {
                    return py_lt(p, q);
                }
            }
            Ok(x.len() < y.len())
        }
        _ => Err(Crash::new(
            "TypeError",
            format!(
                "'<' not supported between instances of '{}' and '{}'",
                a.type_name(),
                b.type_name()
            ),
        )),
    }
}

/// `sorted(values)`: stable, by `<`, failing as Python does when two items
/// cannot be compared.
pub fn py_sorted(values: &[Value]) -> Res<Vec<Value>> {
    let mut out: Vec<Value> = Vec::with_capacity(values.len());
    // Insertion sort with Python's `<` keeps it stable and surfaces the
    // TypeError; the lists sorted here are short.
    for v in values {
        let mut at = out.len();
        while at > 0 && py_lt(v, &out[at - 1])? {
            at -= 1;
        }
        out.insert(at, v.clone());
    }
    if values.len() >= 2 && out.len() == values.len() {
        // Python compares neighbours even when already in order.
        for w in values.windows(2) {
            py_lt(&w[1], &w[0])?;
        }
    }
    Ok(out)
}

/// A hashable value as a dict key or set member: `1`, `1.0` and `True` are
/// one key.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub enum Key {
    None,
    Int(i128),
    Float(u64),
    Str(String),
}

pub fn key(v: &Value) -> Res<Key> {
    match v {
        Value::Null => Ok(Key::None),
        Value::Bool(b) => Ok(Key::Int(*b as i128)),
        Value::Int(i) => Ok(Key::Int(*i)),
        Value::Float(f) => {
            if f.fract() == 0.0 && f.abs() < 1.7e38 {
                Ok(Key::Int(*f as i128))
            } else {
                Ok(Key::Float(f.to_bits()))
            }
        }
        Value::Str(s) => Ok(Key::Str(s.clone())),
        other => Err(Crash::unhashable(other)),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn err(text: &str) -> String {
        loads(text).unwrap_err().msg
    }

    #[test]
    fn reads_in_order_and_last_value_wins() {
        let v = loads(r#"{"b": 1, "a": [true, null, "x"], "b": 2}"#).unwrap();
        assert_eq!(v.repr(), "{'b': 2, 'a': [True, None, 'x']}");
        assert_eq!(loads("1.5").unwrap().repr(), "1.5");
        assert_eq!(loads("[NaN, -Infinity]").unwrap().repr(), "[nan, -inf]");
        assert_eq!(
            loads("100000000000000000000").unwrap().repr(),
            "100000000000000000000"
        );
    }

    #[test]
    fn decode_errors_match_python() {
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
            err("[1 2]"),
            "Expecting ',' delimiter: line 1 column 4 (char 3)"
        );
        assert_eq!(err("[1,]"), "Expecting value: line 1 column 4 (char 3)");
        assert_eq!(err("{} x"), "Extra data: line 1 column 4 (char 3)");
        assert_eq!(
            err("\n\"abc"),
            "Unterminated string starting at: line 2 column 1 (char 1)"
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
            err("\"\\ud800\\uZZZZ\""),
            "Invalid \\uXXXX escape: line 1 column 9 (char 8)"
        );
        assert_eq!(
            err("{\"a\":1,}"),
            "Expecting property name enclosed in double quotes: line 1 column 8 (char 7)"
        );
        assert_eq!(err("[-]"), "Expecting value: line 1 column 2 (char 1)");
        assert_eq!(
            err("\"a\tb\""),
            "Invalid control character at: line 1 column 3 (char 2)"
        );
        assert_eq!(err("01"), "Extra data: line 1 column 2 (char 1)");
        assert_eq!(
            err("\u{feff}{}"),
            "Unexpected UTF-8 BOM (decode using utf-8-sig): line 1 column 1 (char 0)"
        );
        assert!(loads_bytes(b"\xef\xbb\xbf{}").is_ok());
        assert_eq!(
            loads_bytes(b"\xff").unwrap_err().msg,
            "'utf-8' codec can't decode byte 0xff in position 0: invalid start byte"
        );
    }

    #[test]
    fn writes_as_python_does() {
        let v = loads(r#"{"a": [1, 2.0, "é"], "b": {}, "c": []}"#).unwrap();
        assert_eq!(
            dumps_plain(&v),
            r#"{"a": [1, 2.0, "\u00e9"], "b": {}, "c": []}"#
        );
        assert_eq!(
            dumps(&v, Some(2), false),
            "{\n  \"a\": [\n    1,\n    2.0,\n    \"é\"\n  ],\n  \"b\": {},\n  \"c\": []\n}"
        );
        assert_eq!(quote("\u{1F600}\u{7f}", true), "\"\\ud83d\\ude00\u{7f}\"");
    }

    #[test]
    fn python_equality_and_order() {
        assert!(py_eq(&Value::Int(1), &Value::Float(1.0)));
        assert!(py_eq(&Value::Bool(true), &Value::Int(1)));
        assert!(!schema_equal(&Value::Bool(true), &Value::Int(1)));
        assert!(py_lt(&s("a"), &s("b")).unwrap());
        assert!(py_lt(&s("a"), &Value::Int(1)).is_err());
        let sorted = py_sorted(&[s("b"), s("a"), s("c")]).unwrap();
        assert_eq!(Value::List(sorted).repr(), "['a', 'b', 'c']");
        assert_eq!(
            key(&Value::Float(2.0)).unwrap(),
            key(&Value::Int(2)).unwrap()
        );
    }
}
