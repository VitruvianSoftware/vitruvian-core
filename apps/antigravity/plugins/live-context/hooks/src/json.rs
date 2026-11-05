// Copyright (c) 2026 VitruvianSoftware
//
// SPDX-License-Identifier: MIT

//! A small, dependency-free JSON value, parser and printer.
//!
//! The hooks are compiled on the user's machine with a bare `rustc` (see
//! `../rust-hook.sh`), so they cannot pull in crates such as `serde_json`.
//! This module covers what the hooks need and nothing more. It follows
//! JavaScript's `JSON.parse`/`JSON.stringify`, because the hooks replaced
//! Node.js scripts and their output must not change shape:
//!
//! - objects keep their keys in insertion order (as JavaScript objects do);
//! - every number is an `f64`, and is printed the way JavaScript prints it
//!   (`3`, not `3.0`);
//! - `stringify` escapes only what `JSON.stringify` escapes.

use std::fmt;

/// A JSON value.
#[derive(Clone, Debug, PartialEq, Default)]
pub enum Value {
    #[default]
    Null,
    Bool(bool),
    Number(f64),
    String(String),
    Array(Vec<Value>),
    Object(Map),
}

/// A JSON object that keeps its keys in insertion order.
#[derive(Clone, Debug, PartialEq, Default)]
pub struct Map {
    entries: Vec<(String, Value)>,
}

static NULL: Value = Value::Null;

impl Map {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn get(&self, key: &str) -> Option<&Value> {
        self.entries.iter().find(|(k, _)| k == key).map(|(_, v)| v)
    }

    pub fn get_mut(&mut self, key: &str) -> Option<&mut Value> {
        self.entries
            .iter_mut()
            .find(|(k, _)| k == key)
            .map(|(_, v)| v)
    }

    pub fn contains_key(&self, key: &str) -> bool {
        self.get(key).is_some()
    }

    /// Sets `key`, keeping its original position if it was already present.
    pub fn insert(&mut self, key: impl Into<String>, value: impl Into<Value>) {
        let key = key.into();
        let value = value.into();
        if let Some(slot) = self.get_mut(&key) {
            *slot = value;
        } else {
            self.entries.push((key, value));
        }
    }

    pub fn remove(&mut self, key: &str) -> Option<Value> {
        let idx = self.entries.iter().position(|(k, _)| k == key)?;
        Some(self.entries.remove(idx).1)
    }

    pub fn iter(&self) -> impl Iterator<Item = (&String, &Value)> {
        self.entries.iter().map(|(k, v)| (k, v))
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

impl<K: Into<String>, V: Into<Value>> FromIterator<(K, V)> for Map {
    fn from_iter<I: IntoIterator<Item = (K, V)>>(iter: I) -> Self {
        let mut map = Map::new();
        for (k, v) in iter {
            map.insert(k, v);
        }
        map
    }
}

impl Value {
    /// The member `key` of an object; `None` for a missing key or a non-object.
    pub fn get(&self, key: &str) -> Option<&Value> {
        match self {
            Value::Object(m) => m.get(key),
            _ => None,
        }
    }

    pub fn as_str(&self) -> Option<&str> {
        match self {
            Value::String(s) => Some(s),
            _ => None,
        }
    }

    pub fn as_bool(&self) -> Option<bool> {
        match self {
            Value::Bool(b) => Some(*b),
            _ => None,
        }
    }

    pub fn as_f64(&self) -> Option<f64> {
        match self {
            Value::Number(n) => Some(*n),
            _ => None,
        }
    }

    pub fn as_array(&self) -> Option<&Vec<Value>> {
        match self {
            Value::Array(a) => Some(a),
            _ => None,
        }
    }

    pub fn as_object(&self) -> Option<&Map> {
        match self {
            Value::Object(m) => Some(m),
            _ => None,
        }
    }

    pub fn as_object_mut(&mut self) -> Option<&mut Map> {
        match self {
            Value::Object(m) => Some(m),
            _ => None,
        }
    }

    pub fn is_null(&self) -> bool {
        matches!(self, Value::Null)
    }

    pub fn is_object(&self) -> bool {
        matches!(self, Value::Object(_))
    }

    /// Pretty-prints like `JSON.stringify(value, null, 2)`.
    pub fn to_string_pretty(&self) -> String {
        let mut out = String::new();
        write_value(&mut out, self, Some(0));
        out
    }
}

impl std::ops::Index<&str> for Value {
    type Output = Value;
    fn index(&self, key: &str) -> &Value {
        self.get(key).unwrap_or(&NULL)
    }
}

impl std::ops::Index<&str> for Map {
    type Output = Value;
    fn index(&self, key: &str) -> &Value {
        self.get(key).unwrap_or(&NULL)
    }
}

impl std::ops::Index<usize> for Value {
    type Output = Value;
    fn index(&self, idx: usize) -> &Value {
        match self {
            Value::Array(a) => a.get(idx).unwrap_or(&NULL),
            _ => &NULL,
        }
    }
}

impl PartialEq<&str> for Value {
    fn eq(&self, other: &&str) -> bool {
        self.as_str() == Some(*other)
    }
}

impl PartialEq<bool> for Value {
    fn eq(&self, other: &bool) -> bool {
        self.as_bool() == Some(*other)
    }
}

impl PartialEq<f64> for Value {
    fn eq(&self, other: &f64) -> bool {
        self.as_f64() == Some(*other)
    }
}

impl From<&str> for Value {
    fn from(s: &str) -> Self {
        Value::String(s.to_string())
    }
}

impl From<String> for Value {
    fn from(s: String) -> Self {
        Value::String(s)
    }
}

impl From<&String> for Value {
    fn from(s: &String) -> Self {
        Value::String(s.clone())
    }
}

impl From<bool> for Value {
    fn from(b: bool) -> Self {
        Value::Bool(b)
    }
}

impl From<f64> for Value {
    fn from(n: f64) -> Self {
        Value::Number(n)
    }
}

macro_rules! from_int {
    ($($t:ty),*) => {$(
        impl From<$t> for Value {
            fn from(n: $t) -> Self {
                Value::Number(n as f64)
            }
        }
    )*};
}
from_int!(i32, i64, u32, u64, usize);

impl From<Vec<Value>> for Value {
    fn from(a: Vec<Value>) -> Self {
        Value::Array(a)
    }
}

impl From<Map> for Value {
    fn from(m: Map) -> Self {
        Value::Object(m)
    }
}

impl<T: Into<Value>> From<Option<T>> for Value {
    fn from(o: Option<T>) -> Self {
        o.map(Into::into).unwrap_or(Value::Null)
    }
}

/// Compact output, like `JSON.stringify(value)`.
impl fmt::Display for Value {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let mut out = String::new();
        write_value(&mut out, self, None);
        f.write_str(&out)
    }
}

/// Builds an object from `(key, value)` pairs, in order.
pub fn obj<const N: usize>(pairs: [(&str, Value); N]) -> Value {
    Value::Object(pairs.into_iter().collect())
}

fn write_value(out: &mut String, v: &Value, indent: Option<usize>) {
    match v {
        Value::Null => out.push_str("null"),
        Value::Bool(b) => out.push_str(if *b { "true" } else { "false" }),
        Value::Number(n) => write_number(out, *n),
        Value::String(s) => write_string(out, s),
        Value::Array(a) => {
            if a.is_empty() {
                out.push_str("[]");
                return;
            }
            out.push('[');
            for (i, item) in a.iter().enumerate() {
                if i > 0 {
                    out.push(',');
                }
                newline(out, indent.map(|d| d + 1));
                write_value(out, item, indent.map(|d| d + 1));
            }
            newline(out, indent);
            out.push(']');
        }
        Value::Object(m) => {
            if m.is_empty() {
                out.push_str("{}");
                return;
            }
            out.push('{');
            for (i, (k, item)) in m.iter().enumerate() {
                if i > 0 {
                    out.push(',');
                }
                newline(out, indent.map(|d| d + 1));
                write_string(out, k);
                out.push(':');
                if indent.is_some() {
                    out.push(' ');
                }
                write_value(out, item, indent.map(|d| d + 1));
            }
            newline(out, indent);
            out.push('}');
        }
    }
}

fn newline(out: &mut String, indent: Option<usize>) {
    if let Some(depth) = indent {
        out.push('\n');
        for _ in 0..depth {
            out.push_str("  ");
        }
    }
}

fn write_number(out: &mut String, n: f64) {
    if !n.is_finite() {
        out.push_str("null");
    } else if n == 0.0 {
        out.push('0');
    } else if n.abs() >= 1e21 || n.abs() < 1e-6 {
        // JavaScript switches to exponent notation outside this range.
        let s = format!("{n:e}");
        match s.split_once('e') {
            Some((mant, exp)) if !exp.starts_with('-') => {
                out.push_str(mant);
                out.push_str("e+");
                out.push_str(exp);
            }
            _ => out.push_str(&s),
        }
    } else {
        out.push_str(&format!("{n}"));
    }
}

fn write_string(out: &mut String, s: &str) {
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
            c => out.push(c),
        }
    }
    out.push('"');
}

/// Why a document could not be parsed.
#[derive(Debug, Clone, PartialEq)]
pub struct Error {
    pub offset: usize,
    pub message: &'static str,
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{} at byte {}", self.message, self.offset)
    }
}

const MAX_DEPTH: usize = 512;

/// Parses a complete JSON document, like `JSON.parse`.
pub fn parse(src: &str) -> Result<Value, Error> {
    let mut p = Parser {
        bytes: src.as_bytes(),
        src,
        pos: 0,
    };
    p.skip_ws();
    let v = p.value(0)?;
    p.skip_ws();
    if p.pos != p.bytes.len() {
        return Err(p.err("trailing characters"));
    }
    Ok(v)
}

/// Parses `src` and returns its top-level object, or `None` for anything else.
pub fn parse_object(src: &str) -> Option<Map> {
    match parse(src) {
        Ok(Value::Object(m)) => Some(m),
        _ => None,
    }
}

struct Parser<'a> {
    bytes: &'a [u8],
    src: &'a str,
    pos: usize,
}

impl Parser<'_> {
    fn err(&self, message: &'static str) -> Error {
        Error {
            offset: self.pos,
            message,
        }
    }

    fn skip_ws(&mut self) {
        while let Some(b' ' | b'\t' | b'\n' | b'\r') = self.bytes.get(self.pos) {
            self.pos += 1;
        }
    }

    fn eat(&mut self, lit: &str) -> Result<(), Error> {
        if self.src[self.pos..].starts_with(lit) {
            self.pos += lit.len();
            Ok(())
        } else {
            Err(self.err("unexpected token"))
        }
    }

    fn value(&mut self, depth: usize) -> Result<Value, Error> {
        if depth > MAX_DEPTH {
            return Err(self.err("nesting too deep"));
        }
        match self.bytes.get(self.pos) {
            None => Err(self.err("unexpected end of input")),
            Some(b'n') => self.eat("null").map(|_| Value::Null),
            Some(b't') => self.eat("true").map(|_| Value::Bool(true)),
            Some(b'f') => self.eat("false").map(|_| Value::Bool(false)),
            Some(b'"') => self.string().map(Value::String),
            Some(b'[') => self.array(depth),
            Some(b'{') => self.object(depth),
            Some(b'-' | b'0'..=b'9') => self.number(),
            Some(_) => Err(self.err("unexpected token")),
        }
    }

    fn array(&mut self, depth: usize) -> Result<Value, Error> {
        self.pos += 1;
        let mut items = Vec::new();
        self.skip_ws();
        if self.bytes.get(self.pos) == Some(&b']') {
            self.pos += 1;
            return Ok(Value::Array(items));
        }
        loop {
            self.skip_ws();
            items.push(self.value(depth + 1)?);
            self.skip_ws();
            match self.bytes.get(self.pos) {
                Some(b',') => self.pos += 1,
                Some(b']') => {
                    self.pos += 1;
                    return Ok(Value::Array(items));
                }
                _ => return Err(self.err("expected , or ]")),
            }
        }
    }

    fn object(&mut self, depth: usize) -> Result<Value, Error> {
        self.pos += 1;
        let mut map = Map::new();
        self.skip_ws();
        if self.bytes.get(self.pos) == Some(&b'}') {
            self.pos += 1;
            return Ok(Value::Object(map));
        }
        loop {
            self.skip_ws();
            if self.bytes.get(self.pos) != Some(&b'"') {
                return Err(self.err("expected a key"));
            }
            let key = self.string()?;
            self.skip_ws();
            if self.bytes.get(self.pos) != Some(&b':') {
                return Err(self.err("expected :"));
            }
            self.pos += 1;
            self.skip_ws();
            let v = self.value(depth + 1)?;
            // JSON.parse keeps the last duplicate, at the first one's position.
            map.insert(key, v);
            self.skip_ws();
            match self.bytes.get(self.pos) {
                Some(b',') => self.pos += 1,
                Some(b'}') => {
                    self.pos += 1;
                    return Ok(Value::Object(map));
                }
                _ => return Err(self.err("expected , or }")),
            }
        }
    }

    fn number(&mut self) -> Result<Value, Error> {
        let start = self.pos;
        if self.bytes.get(self.pos) == Some(&b'-') {
            self.pos += 1;
        }
        match self.bytes.get(self.pos) {
            Some(b'0') => self.pos += 1,
            Some(b'1'..=b'9') => self.digits(),
            _ => return Err(self.err("invalid number")),
        }
        if self.bytes.get(self.pos) == Some(&b'.') {
            self.pos += 1;
            if !matches!(self.bytes.get(self.pos), Some(b'0'..=b'9')) {
                return Err(self.err("invalid number"));
            }
            self.digits();
        }
        if let Some(b'e' | b'E') = self.bytes.get(self.pos) {
            self.pos += 1;
            if let Some(b'+' | b'-') = self.bytes.get(self.pos) {
                self.pos += 1;
            }
            if !matches!(self.bytes.get(self.pos), Some(b'0'..=b'9')) {
                return Err(self.err("invalid number"));
            }
            self.digits();
        }
        self.src[start..self.pos]
            .parse::<f64>()
            .map(Value::Number)
            .map_err(|_| self.err("invalid number"))
    }

    fn digits(&mut self) {
        while let Some(b'0'..=b'9') = self.bytes.get(self.pos) {
            self.pos += 1;
        }
    }

    fn hex4(&mut self) -> Result<u32, Error> {
        let hex = self
            .src
            .get(self.pos..self.pos + 4)
            .ok_or_else(|| self.err("bad \\u escape"))?;
        let n = u32::from_str_radix(hex, 16).map_err(|_| self.err("bad \\u escape"))?;
        self.pos += 4;
        Ok(n)
    }

    fn string(&mut self) -> Result<String, Error> {
        self.pos += 1;
        let mut out = String::new();
        loop {
            let run_start = self.pos;
            while let Some(&b) = self.bytes.get(self.pos) {
                if b == b'"' || b == b'\\' || b < 0x20 {
                    break;
                }
                self.pos += 1;
            }
            out.push_str(&self.src[run_start..self.pos]);
            match self.bytes.get(self.pos) {
                None => return Err(self.err("unterminated string")),
                Some(b'"') => {
                    self.pos += 1;
                    return Ok(out);
                }
                Some(b'\\') => {
                    self.pos += 1;
                    let esc = *self
                        .bytes
                        .get(self.pos)
                        .ok_or_else(|| self.err("unterminated string"))?;
                    self.pos += 1;
                    match esc {
                        b'"' => out.push('"'),
                        b'\\' => out.push('\\'),
                        b'/' => out.push('/'),
                        b'b' => out.push('\u{08}'),
                        b'f' => out.push('\u{0c}'),
                        b'n' => out.push('\n'),
                        b'r' => out.push('\r'),
                        b't' => out.push('\t'),
                        b'u' => {
                            let hi = self.hex4()?;
                            let c = if (0xD800..0xDC00).contains(&hi)
                                && self.src[self.pos..].starts_with("\\u")
                            {
                                let save = self.pos;
                                self.pos += 2;
                                let lo = self.hex4()?;
                                if (0xDC00..0xE000).contains(&lo) {
                                    char::from_u32(0x10000 + ((hi - 0xD800) << 10) + (lo - 0xDC00))
                                } else {
                                    self.pos = save;
                                    None
                                }
                            } else {
                                char::from_u32(hi)
                            };
                            // A lone surrogate cannot live in a Rust string.
                            out.push(c.unwrap_or('\u{FFFD}'));
                        }
                        _ => return Err(self.err("bad escape")),
                    }
                }
                Some(_) => return Err(self.err("control character in string")),
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trips_in_insertion_order() {
        let src = r#"{"z":1,"a":[true,false,null],"m":{"k":"v"},"n":-2.5e3}"#;
        let v = parse(src).unwrap();
        assert_eq!(
            v.to_string(),
            r#"{"z":1,"a":[true,false,null],"m":{"k":"v"},"n":-2500}"#
        );
        assert_eq!(v["m"]["k"], "v");
        assert!(v["missing"].is_null());
        assert_eq!(v["a"][0], true);
    }

    #[test]
    fn prints_numbers_like_javascript() {
        let cases = [
            (3.0, "3"),
            (0.1, "0.1"),
            (-0.0, "0"),
            (1793521123810.0, "1793521123810"),
            (1e21, "1e+21"),
            (1.5e-7, "1.5e-7"),
            (f64::NAN, "null"),
        ];
        for (n, want) in cases {
            assert_eq!(Value::Number(n).to_string(), want, "{n}");
        }
    }

    #[test]
    fn escapes_like_json_stringify() {
        let v = Value::from("a\"b\\c\nd\u{1}é/😀");
        assert_eq!(v.to_string(), "\"a\\\"b\\\\c\\nd\\u0001é/😀\"");
        let back = parse(&v.to_string()).unwrap();
        assert_eq!(back, v);
    }

    #[test]
    fn decodes_unicode_escapes_and_surrogate_pairs() {
        assert_eq!(parse(r#""é😀""#).unwrap(), "é😀");
        assert_eq!(parse(r#""\ud83d""#).unwrap(), "\u{FFFD}");
    }

    #[test]
    fn rejects_malformed_documents() {
        for bad in [
            "",
            "{",
            "[1,]",
            "{\"a\" 1}",
            "01",
            "1.",
            "\"\u{1}\"",
            "nul",
            "{} x",
            "'a'",
        ] {
            assert!(parse(bad).is_err(), "{bad:?} should not parse");
        }
        let deep = "[".repeat(MAX_DEPTH + 2);
        assert!(parse(&deep).is_err());
    }

    #[test]
    fn duplicate_keys_keep_the_last_value() {
        let v = parse(r#"{"a":1,"b":2,"a":3}"#).unwrap();
        assert_eq!(v.to_string(), r#"{"a":3,"b":2}"#);
    }

    #[test]
    fn pretty_prints_like_json_stringify_with_two_spaces() {
        let v = parse(r#"{"a":[1,{"b":null}],"c":{},"d":[]}"#).unwrap();
        assert_eq!(
            v.to_string_pretty(),
            "{\n  \"a\": [\n    1,\n    {\n      \"b\": null\n    }\n  ],\n  \"c\": {},\n  \"d\": []\n}"
        );
    }
}
