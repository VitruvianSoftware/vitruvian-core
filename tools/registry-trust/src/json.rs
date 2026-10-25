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

//! JSON as Python 3.12's `json` module reads and writes it: values keep
//! their key order (a repeated key keeps its first place and its last
//! value), and text that is not JSON is reported with the C decoder's
//! message at the same line, column and character, because the tool prints
//! it. Also the Python view of a value: its truthiness, `str()` and `repr()`.

use std::collections::HashMap;

use crate::py;

#[derive(Clone, Debug, Default, PartialEq)]
pub struct Dict {
    entries: Vec<(String, Value)>,
    index: HashMap<String, usize>,
}

impl Dict {
    pub fn new() -> Dict {
        Dict::default()
    }

    pub fn get(&self, key: &str) -> Option<&Value> {
        self.index.get(key).map(|&i| &self.entries[i].1)
    }

    pub fn get_mut(&mut self, key: &str) -> Option<&mut Value> {
        match self.index.get(key) {
            Some(&i) => Some(&mut self.entries[i].1),
            None => None,
        }
    }

    pub fn contains(&self, key: &str) -> bool {
        self.index.contains_key(key)
    }

    /// `d[key] = value`: a key already there keeps its place.
    pub fn insert(&mut self, key: String, value: Value) {
        if let Some(&i) = self.index.get(&key) {
            self.entries[i].1 = value;
        } else {
            self.index.insert(key.clone(), self.entries.len());
            self.entries.push((key, value));
        }
    }

    pub fn iter(&self) -> impl Iterator<Item = (&String, &Value)> {
        self.entries.iter().map(|entry| (&entry.0, &entry.1))
    }

    pub fn keys(&self) -> impl Iterator<Item = &String> {
        self.entries.iter().map(|(k, _)| k)
    }

    pub fn len(&self) -> usize {
        self.entries.len()
    }

    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }
}

#[derive(Clone, Debug, Default, PartialEq)]
pub enum Value {
    #[default]
    Null,
    Bool(bool),
    /// An integer, as its decimal digits: Python's are unbounded.
    Int(String),
    Float(f64),
    Str(String),
    List(Vec<Value>),
    Dict(Dict),
    /// A TOML date or time: its `str()`, and its type's name
    /// (`datetime.datetime`, `datetime.date` or `datetime.time`).
    Date(String, &'static str),
}

impl Value {
    /// `value.get(key)` when the value is a dict; None otherwise.
    pub fn get(&self, key: &str) -> Option<&Value> {
        match self {
            Value::Dict(d) => d.get(key),
            _ => None,
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

    /// `bool(value)`.
    pub fn truthy(&self) -> bool {
        match self {
            Value::Null => false,
            Value::Bool(b) => *b,
            Value::Int(digits) => digits.trim_start_matches('-').trim_start_matches('0') != "",
            Value::Float(f) => *f != 0.0,
            Value::Str(s) => !s.is_empty(),
            Value::List(l) => !l.is_empty(),
            Value::Dict(d) => !d.is_empty(),
            Value::Date(..) => true,
        }
    }

    /// `str(value)`.
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
            Value::Int(digits) => digits.clone(),
            Value::Float(f) => py::repr_float(*f),
            Value::Str(s) => py::repr_str(s),
            Value::Date(s, _) => s.clone(),
            Value::List(items) => {
                let inner: Vec<String> = items.iter().map(Value::py_repr).collect();
                format!("[{}]", inner.join(", "))
            }
            Value::Dict(d) => {
                let inner: Vec<String> = d
                    .iter()
                    .map(|(k, v)| format!("{}: {}", py::repr_str(k), v.py_repr()))
                    .collect();
                format!("{{{}}}", inner.join(", "))
            }
        }
    }
}

/// What `json.loads` raised: `str(error)` in .0. A JSONDecodeError unless
/// `decode` says the bytes were not UTF-8 (a UnicodeDecodeError).
#[derive(Debug, Clone, PartialEq)]
pub struct JsonError(pub String, pub bool);

impl JsonError {
    /// The exception's name as a traceback's last line shows it.
    pub fn class(&self) -> &'static str {
        if self.1 {
            "UnicodeDecodeError"
        } else if self.0.starts_with("maximum recursion") {
            "RecursionError"
        } else {
            "json.decoder.JSONDecodeError"
        }
    }

    pub fn crash(&self) -> Crash {
        Crash(format!("{}: {}", self.class(), self.0))
    }
}

impl std::fmt::Display for JsonError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}

struct Parser {
    s: Vec<char>,
    depth: usize,
}

enum Fail {
    /// The scanner's StopIteration: "Expecting value" at that place.
    Stop(usize),
    Error(&'static str, usize),
}

fn is_ws(c: char) -> bool {
    matches!(c, ' ' | '\t' | '\n' | '\r')
}

impl Parser {
    fn at(&self, i: usize) -> Option<char> {
        self.s.get(i).copied()
    }

    fn skip_ws(&self, mut i: usize) -> usize {
        while i < self.s.len() && is_ws(self.s[i]) {
            i += 1;
        }
        i
    }

    fn starts(&self, i: usize, word: &str) -> bool {
        let w: Vec<char> = word.chars().collect();
        self.s.len() >= i + w.len() && self.s[i..i + w.len()] == w[..]
    }

    fn scan(&mut self, i: usize) -> Result<(Value, usize), Fail> {
        let Some(c) = self.at(i) else {
            return Err(Fail::Stop(i));
        };
        match c {
            '"' => self.string(i + 1).map(|(s, e)| (Value::Str(s), e)),
            '{' => self.nested(|p| p.object(i + 1)),
            '[' => self.nested(|p| p.array(i + 1)),
            'n' if self.starts(i, "null") => Ok((Value::Null, i + 4)),
            't' if self.starts(i, "true") => Ok((Value::Bool(true), i + 4)),
            'f' if self.starts(i, "false") => Ok((Value::Bool(false), i + 5)),
            'N' if self.starts(i, "NaN") => Ok((Value::Float(f64::NAN), i + 3)),
            'I' if self.starts(i, "Infinity") => Ok((Value::Float(f64::INFINITY), i + 8)),
            '-' if self.starts(i, "-Infinity") => Ok((Value::Float(f64::NEG_INFINITY), i + 9)),
            _ => self.number(i),
        }
    }

    fn nested(
        &mut self,
        parse: impl FnOnce(&mut Parser) -> Result<(Value, usize), Fail>,
    ) -> Result<(Value, usize), Fail> {
        self.depth += 1;
        if self.depth > 2000 {
            return Err(Fail::Error(
                "maximum recursion depth exceeded while decoding a JSON document",
                0,
            ));
        }
        let result = parse(self);
        self.depth -= 1;
        result
    }

    fn number(&self, start: usize) -> Result<(Value, usize), Fail> {
        let digit = |i: usize| self.at(i).is_some_and(|c| c.is_ascii_digit());
        let mut i = start;
        if self.at(i) == Some('-') {
            i += 1;
        }
        match self.at(i) {
            Some('0') => i += 1,
            Some('1'..='9') => {
                while digit(i) {
                    i += 1;
                }
            }
            _ => return Err(Fail::Stop(start)),
        }
        let mut float = false;
        if self.at(i) == Some('.') && digit(i + 1) {
            float = true;
            i += 1;
            while digit(i) {
                i += 1;
            }
        }
        if matches!(self.at(i), Some('e' | 'E')) {
            let mut j = i + 1;
            if matches!(self.at(j), Some('+' | '-')) {
                j += 1;
            }
            if digit(j) {
                while digit(j) {
                    j += 1;
                }
                float = true;
                i = j;
            }
        }
        let text: String = self.s[start..i].iter().collect();
        if float {
            Ok((Value::Float(text.parse().unwrap_or(f64::NAN)), i))
        } else {
            let normal = match text.strip_prefix('-') {
                Some("0") => "0".to_string(),
                _ => text,
            };
            Ok((Value::Int(normal), i))
        }
    }

    /// The C scanstring: `begin` is just past the opening quote.
    fn string(&self, begin: usize) -> Result<(String, usize), Fail> {
        let len = self.s.len();
        let mut out = String::new();
        let mut end = begin;
        loop {
            let mut next = end;
            let mut c = '\0';
            while next < len {
                c = self.s[next];
                if c == '"' || c == '\\' {
                    break;
                }
                if (c as u32) <= 0x1f {
                    return Err(Fail::Error("Invalid control character at", next));
                }
                next += 1;
            }
            if next >= len || !(c == '"' || c == '\\') {
                return Err(Fail::Error("Unterminated string starting at", begin - 1));
            }
            out.extend(&self.s[end..next]);
            next += 1;
            if c == '"' {
                return Ok((out, next));
            }
            if next == len {
                return Err(Fail::Error("Unterminated string starting at", begin - 1));
            }
            let c = self.s[next];
            if c != 'u' {
                end = next + 1;
                let decoded = match c {
                    '"' => '"',
                    '\\' => '\\',
                    '/' => '/',
                    'b' => '\u{8}',
                    'f' => '\u{c}',
                    'n' => '\n',
                    'r' => '\r',
                    't' => '\t',
                    _ => return Err(Fail::Error("Invalid \\escape", end - 2)),
                };
                out.push(decoded);
                continue;
            }
            next += 1;
            end = next + 4;
            if end >= len {
                return Err(Fail::Error("Invalid \\uXXXX escape", next - 1));
            }
            let hex = |from: usize| -> Option<u32> {
                let text: String = self.s[from..from + 4].iter().collect();
                if text.chars().all(|c| c.is_ascii_hexdigit()) {
                    u32::from_str_radix(&text, 16).ok()
                } else {
                    None
                }
            };
            let Some(mut code) = hex(next) else {
                return Err(Fail::Error("Invalid \\uXXXX escape", end - 5));
            };
            if (0xd800..0xdc00).contains(&code)
                && end + 6 < len
                && self.s[end] == '\\'
                && self.s[end + 1] == 'u'
            {
                let Some(low) = hex(end + 2) else {
                    return Err(Fail::Error("Invalid \\uXXXX escape", end + 1));
                };
                if (0xdc00..0xe000).contains(&low) {
                    code = 0x10000 + (((code - 0xd800) << 10) | (low - 0xdc00));
                    end += 6;
                }
            }
            // A lone surrogate cannot be a Rust char; it reads as U+FFFD.
            out.push(char::from_u32(code).unwrap_or('\u{fffd}'));
        }
    }

    fn object(&mut self, start: usize) -> Result<(Value, usize), Fail> {
        let mut dict = Dict::new();
        let mut i = self.skip_ws(start);
        if self.at(i) == Some('}') {
            return Ok((Value::Dict(dict), i + 1));
        }
        loop {
            if self.at(i) != Some('"') {
                return Err(Fail::Error(
                    "Expecting property name enclosed in double quotes",
                    i,
                ));
            }
            let (key, after) = self.string(i + 1)?;
            i = self.skip_ws(after);
            if self.at(i) != Some(':') {
                return Err(Fail::Error("Expecting ':' delimiter", i));
            }
            i = self.skip_ws(i + 1);
            let (value, after) = self.scan(i)?;
            dict.insert(key, value);
            i = self.skip_ws(after);
            if self.at(i) == Some('}') {
                return Ok((Value::Dict(dict), i + 1));
            }
            if self.at(i) != Some(',') {
                return Err(Fail::Error("Expecting ',' delimiter", i));
            }
            i = self.skip_ws(i + 1);
        }
    }

    fn array(&mut self, start: usize) -> Result<(Value, usize), Fail> {
        let mut items = Vec::new();
        let mut i = self.skip_ws(start);
        if self.at(i) == Some(']') {
            return Ok((Value::List(items), i + 1));
        }
        loop {
            let (value, after) = self.scan(i)?;
            items.push(value);
            i = self.skip_ws(after);
            if self.at(i) == Some(']') {
                return Ok((Value::List(items), i + 1));
            }
            if self.at(i) != Some(',') {
                return Err(Fail::Error("Expecting ',' delimiter", i));
            }
            i = self.skip_ws(i + 1);
        }
    }
}

fn located(s: &[char], message: &str, pos: usize) -> JsonError {
    let before = &s[..pos.min(s.len())];
    let line = before.iter().filter(|&&c| c == '\n').count() + 1;
    let column = match before.iter().rposition(|&c| c == '\n') {
        Some(nl) => pos - nl,
        None => pos + 1,
    };
    JsonError(
        format!("{message}: line {line} column {column} (char {pos})"),
        false,
    )
}

/// `json.loads(text)` for a `str`.
pub fn loads(text: &str) -> Result<Value, JsonError> {
    let s: Vec<char> = text.chars().collect();
    if s.first() == Some(&'\u{feff}') {
        return Err(located(
            &s,
            "Unexpected UTF-8 BOM (decode using utf-8-sig)",
            0,
        ));
    }
    let mut parser = Parser { s, depth: 0 };
    let start = parser.skip_ws(0);
    let (value, end) = match parser.scan(start) {
        Ok(found) => found,
        Err(Fail::Stop(at)) => return Err(located(&parser.s, "Expecting value", at)),
        Err(Fail::Error(message, at)) => {
            if message.starts_with("maximum recursion") {
                return Err(JsonError(message.to_string(), false));
            }
            return Err(located(&parser.s, message, at));
        }
    };
    let end = parser.skip_ws(end);
    if end != parser.s.len() {
        return Err(located(&parser.s, "Extra data", end));
    }
    Ok(value)
}

/// `json.loads(body)` for `bytes`: a UTF-8 BOM is dropped, and bytes that
/// are not UTF-8 are the codec's error.
pub fn loads_bytes(body: &[u8]) -> Result<Value, JsonError> {
    let body = body.strip_prefix(b"\xef\xbb\xbf").unwrap_or(body);
    if let Some(message) = py::utf8_error(body) {
        return Err(JsonError(message, true));
    }
    loads(std::str::from_utf8(body).unwrap())
}

// --- what Python does with a value, crashes included ---------------------------

/// An exception the scripts do not catch: the last line of its traceback,
/// `AttributeError: 'list' object has no attribute 'get'`. The port stops
/// where the script would, with exit 1, and prints that line.
#[derive(Debug, Clone, PartialEq)]
pub struct Crash(pub String);

impl Crash {
    pub fn new(class: &str, message: impl std::fmt::Display) -> Crash {
        Crash(format!("{class}: {message}"))
    }

    /// What Python prints for it. The frames are Python's own, which the
    /// port cannot have, so only the first and last lines are written.
    pub fn traceback(&self) -> String {
        format!("Traceback (most recent call last):\n{}\n", self.0)
    }
}

impl Value {
    /// `type(value)`'s tp_name, as Python's messages name it.
    pub fn type_name(&self) -> &'static str {
        match self {
            Value::Null => "NoneType",
            Value::Bool(_) => "bool",
            Value::Int(_) => "int",
            Value::Float(_) => "float",
            Value::Str(_) => "str",
            Value::List(_) => "list",
            Value::Dict(_) => "dict",
            Value::Date(_, kind) => kind,
        }
    }

    pub fn no_attribute(&self, attr: &str) -> Crash {
        Crash::new(
            "AttributeError",
            format!("'{}' object has no attribute '{attr}'", self.type_name()),
        )
    }

    /// `value.get(key)`: a dict's, or the AttributeError anything else raises.
    pub fn pget(&self, key: &str) -> Result<Option<&Value>, Crash> {
        match self {
            Value::Dict(d) => Ok(d.get(key)),
            other => Err(other.no_attribute("get")),
        }
    }

    /// `value[key]` with a str key.
    pub fn index(&self, key: &str) -> Result<&Value, Crash> {
        match self {
            Value::Dict(d) => d
                .get(key)
                .ok_or_else(|| Crash::new("KeyError", py::repr_str(key))),
            Value::List(_) => Err(Crash::new(
                "TypeError",
                "list indices must be integers or slices, not str",
            )),
            Value::Str(_) => Err(Crash::new(
                "TypeError",
                "string indices must be integers, not 'str'",
            )),
            other => Err(Crash::new(
                "TypeError",
                format!("'{}' object is not subscriptable", other.type_name()),
            )),
        }
    }

    /// `value.items()`.
    pub fn items(&self) -> Result<Vec<(&String, &Value)>, Crash> {
        match self {
            Value::Dict(d) => Ok(d.iter().collect()),
            other => Err(other.no_attribute("items")),
        }
    }

    /// `for x in value`: a list's items, a dict's keys, a str's characters.
    pub fn iterate(&self) -> Result<Vec<Value>, Crash> {
        match self {
            Value::List(items) => Ok(items.clone()),
            Value::Dict(d) => Ok(d.keys().map(|k| Value::Str(k.clone())).collect()),
            Value::Str(text) => Ok(text.chars().map(|c| Value::Str(c.to_string())).collect()),
            other => Err(Crash::new(
                "TypeError",
                format!("'{}' object is not iterable", other.type_name()),
            )),
        }
    }

    /// The str a str method is called on, or the AttributeError.
    pub fn str_for(&self, method: &str) -> Result<&str, Crash> {
        match self {
            Value::Str(text) => Ok(text),
            other => Err(other.no_attribute(method)),
        }
    }
}

/// `value or {}`.
pub fn or_empty(value: Option<&Value>) -> Value {
    match value {
        Some(v) if v.truthy() => v.clone(),
        _ => Value::Dict(Dict::new()),
    }
}

/// `value.get(key, default)` with the default taken when the key is absent.
pub fn get_or(value: &Value, key: &str, default: Value) -> Result<Value, Crash> {
    Ok(value.pget(key)?.cloned().unwrap_or(default))
}

// --- writing --------------------------------------------------------------------

/// A string as `json.dumps` writes it, with `ensure_ascii`.
pub fn quote(s: &str) -> String {
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
            ' '..='~' => out.push(c),
            c => {
                let mut units = [0u16; 2];
                for unit in c.encode_utf16(&mut units) {
                    out.push_str(&format!("\\u{unit:04x}"));
                }
            }
        }
    }
    out.push('"');
    out
}

fn scalar(value: &Value) -> Option<String> {
    Some(match value {
        Value::Null => "null".into(),
        Value::Bool(true) => "true".into(),
        Value::Bool(false) => "false".into(),
        Value::Int(digits) => digits.clone(),
        Value::Float(f) if f.is_nan() => "NaN".into(),
        Value::Float(f) if f.is_infinite() => {
            if *f > 0.0 {
                "Infinity".into()
            } else {
                "-Infinity".into()
            }
        }
        Value::Float(f) => py::repr_float(*f),
        Value::Str(s) | Value::Date(s, _) => quote(s),
        _ => return None,
    })
}

/// `json.dumps(value)`: separators `", "` and `": "`, on one line.
pub fn dumps(value: &Value) -> String {
    if let Some(text) = scalar(value) {
        return text;
    }
    match value {
        Value::List(items) => {
            let inner: Vec<String> = items.iter().map(dumps).collect();
            format!("[{}]", inner.join(", "))
        }
        Value::Dict(d) => {
            let inner: Vec<String> = d
                .iter()
                .map(|(k, v)| format!("{}: {}", quote(k), dumps(v)))
                .collect();
            format!("{{{}}}", inner.join(", "))
        }
        _ => unreachable!(),
    }
}

/// `json.dump(value, out, indent=indent)`.
pub fn dumps_indented(value: &Value, indent: usize) -> String {
    fn walk(value: &Value, indent: usize, level: usize, out: &mut String) {
        if let Some(text) = scalar(value) {
            out.push_str(&text);
            return;
        }
        let inner = " ".repeat(indent * (level + 1));
        let outer = " ".repeat(indent * level);
        match value {
            Value::List(items) if items.is_empty() => out.push_str("[]"),
            Value::Dict(d) if d.is_empty() => out.push_str("{}"),
            Value::List(items) => {
                out.push('[');
                for (i, item) in items.iter().enumerate() {
                    out.push_str(if i == 0 { "\n" } else { ",\n" });
                    out.push_str(&inner);
                    walk(item, indent, level + 1, out);
                }
                out.push('\n');
                out.push_str(&outer);
                out.push(']');
            }
            Value::Dict(d) => {
                out.push('{');
                for (i, (k, v)) in d.iter().enumerate() {
                    out.push_str(if i == 0 { "\n" } else { ",\n" });
                    out.push_str(&inner);
                    out.push_str(&quote(k));
                    out.push_str(": ");
                    walk(v, indent, level + 1, out);
                }
                out.push('\n');
                out.push_str(&outer);
                out.push('}');
            }
            _ => unreachable!(),
        }
    }
    let mut out = String::new();
    walk(value, indent, 0, &mut out);
    out
}

/// A dict from pairs, for building values by hand.
pub fn dict<K: Into<String>>(pairs: impl IntoIterator<Item = (K, Value)>) -> Value {
    let mut d = Dict::new();
    for (k, v) in pairs {
        d.insert(k.into(), v);
    }
    Value::Dict(d)
}

pub fn s(text: &str) -> Value {
    Value::Str(text.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn err(text: &str) -> String {
        loads(text).unwrap_err().0
    }

    #[test]
    fn values_keep_their_order_and_a_repeated_key_its_place() {
        let v = loads(r#"{"b": 1, "a": [true, null, 2.5, "x"], "b": 3}"#).unwrap();
        let d = v.as_dict().unwrap();
        assert_eq!(d.keys().cloned().collect::<Vec<_>>(), ["b", "a"]);
        assert_eq!(d.get("b"), Some(&Value::Int("3".into())));
        assert_eq!(v.get("a").unwrap().py_repr(), "[True, None, 2.5, 'x']");
    }

    #[test]
    fn escapes_and_surrogate_pairs_decode() {
        let v = loads(r#""a\n\u00e9\ud83d\ude00\/""#).unwrap();
        assert_eq!(v, Value::Str("a\né😀/".into()));
    }

    #[test]
    fn errors_name_python_s_message_and_place() {
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
            err("{\"a\": 1,}"),
            "Expecting property name enclosed in double quotes: line 1 column 9 (char 8)"
        );
        assert_eq!(err("[1,]"), "Expecting value: line 1 column 4 (char 3)");
        assert_eq!(
            err("[1 2]"),
            "Expecting ',' delimiter: line 1 column 4 (char 3)"
        );
        assert_eq!(err("{}\n x"), "Extra data: line 2 column 2 (char 4)");
        assert_eq!(
            err("\"abc"),
            "Unterminated string starting at: line 1 column 1 (char 0)"
        );
        assert_eq!(
            err("\"a\u{1}\""),
            "Invalid control character at: line 1 column 3 (char 2)"
        );
        assert_eq!(err("\"\\x\""), "Invalid \\escape: line 1 column 2 (char 1)");
        assert_eq!(
            err("\"\\u12\""),
            "Invalid \\uXXXX escape: line 1 column 3 (char 2)"
        );
        assert_eq!(
            err("\u{feff}{}"),
            "Unexpected UTF-8 BOM (decode using utf-8-sig): line 1 column 1 (char 0)"
        );
        assert_eq!(err("01"), "Extra data: line 1 column 2 (char 1)");
        assert_eq!(err("-"), "Expecting value: line 1 column 1 (char 0)");
    }

    #[test]
    fn bytes_drop_a_bom_and_report_bad_utf8() {
        assert_eq!(loads_bytes(b"\xef\xbb\xbf{}").unwrap(), dict::<String>([]));
        assert!(loads_bytes(b"\xff")
            .unwrap_err()
            .0
            .contains("invalid start byte"));
    }

    #[test]
    fn dumping_is_python_s_json_dump() {
        let v = dict([
            ("a", s("é\"")),
            ("b", Value::List(vec![])),
            ("c", Value::Null),
        ]);
        assert_eq!(dumps(&v), r#"{"a": "\u00e9\"", "b": [], "c": null}"#);
        let list = Value::List(vec![dict([("x", s("1"))])]);
        assert_eq!(dumps_indented(&list, 2), "[\n  {\n    \"x\": \"1\"\n  }\n]");
        assert_eq!(dumps_indented(&Value::List(vec![]), 2), "[]");
        assert_eq!(quote("😀"), "\"\\ud83d\\ude00\"");
    }

    #[test]
    fn truthiness_is_python_s() {
        assert!(!Value::Int("0".into()).truthy());
        assert!(Value::Int("-1".into()).truthy());
        assert!(!s("").truthy());
        assert!(!Value::List(vec![]).truthy());
        assert!(Value::Bool(true).truthy());
    }
}
