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

//! Just enough of jq to run pipeline-status.sh's three filters the way jq
//! runs them: a stream of JSON values in, one result (or one error) per value,
//! jq's ordering for `group_by`/`sort_by`, and jq's string interpolation.
//!
//! Values are parsed with serde_json into an order-keeping tree, because jq
//! keeps an object's keys in the order they came (a repeated key keeps its
//! first place and its last value) and prints them that way.

use serde::de::{Deserialize, Deserializer, MapAccess, SeqAccess, Visitor};
use std::cmp::Ordering;
use std::collections::HashMap;
use std::fmt;

#[derive(Clone, Debug)]
pub enum Value {
    Null,
    Bool(bool),
    /// The number as jq compares it, and its integer form when it has one.
    Number(f64, Option<i128>),
    String(String),
    Array(Vec<Value>),
    Object(Vec<(String, Value)>),
}

impl Value {
    /// jq's name for the kind, as its error messages use it.
    pub fn kind(&self) -> &'static str {
        match self {
            Value::Null => "null",
            Value::Bool(_) => "boolean",
            Value::Number(..) => "number",
            Value::String(_) => "string",
            Value::Array(_) => "array",
            Value::Object(_) => "object",
        }
    }

    /// jq truthiness: everything but `null` and `false`.
    pub fn truthy(&self) -> bool {
        !matches!(self, Value::Null | Value::Bool(false))
    }

    /// `.key`: an object's field (null when absent), null on null, and an
    /// error on anything else.
    pub fn index(&self, key: &str) -> Result<Value, String> {
        match self {
            Value::Object(entries) => Ok(entries
                .iter()
                .find(|(k, _)| k == key)
                .map(|(_, v)| v.clone())
                .unwrap_or(Value::Null)),
            Value::Null => Ok(Value::Null),
            other => Err(format!(
                "Cannot index {} with string \"{}\"",
                other.kind(),
                key
            )),
        }
    }

    /// `.[]?`: an array's elements or an object's values; nothing otherwise.
    pub fn iterate_quiet(&self) -> Vec<Value> {
        match self {
            Value::Array(items) => items.clone(),
            Value::Object(entries) => entries.iter().map(|(_, v)| v.clone()).collect(),
            _ => Vec::new(),
        }
    }

    pub fn is_str(&self, s: &str) -> bool {
        matches!(self, Value::String(v) if v == s)
    }

    pub fn is_null(&self) -> bool {
        matches!(self, Value::Null)
    }
}

struct ValueVisitor;

impl<'de> Visitor<'de> for ValueVisitor {
    type Value = Value;

    fn expecting(&self, f: &mut fmt::Formatter) -> fmt::Result {
        f.write_str("a JSON value")
    }

    fn visit_unit<E>(self) -> Result<Value, E> {
        Ok(Value::Null)
    }

    fn visit_bool<E>(self, v: bool) -> Result<Value, E> {
        Ok(Value::Bool(v))
    }

    fn visit_i64<E>(self, v: i64) -> Result<Value, E> {
        Ok(Value::Number(v as f64, Some(v as i128)))
    }

    fn visit_u64<E>(self, v: u64) -> Result<Value, E> {
        Ok(Value::Number(v as f64, Some(v as i128)))
    }

    fn visit_f64<E>(self, v: f64) -> Result<Value, E> {
        Ok(Value::Number(v, None))
    }

    fn visit_str<E>(self, v: &str) -> Result<Value, E> {
        Ok(Value::String(v.to_string()))
    }

    fn visit_string<E>(self, v: String) -> Result<Value, E> {
        Ok(Value::String(v))
    }

    fn visit_seq<A: SeqAccess<'de>>(self, mut seq: A) -> Result<Value, A::Error> {
        let mut items = Vec::new();
        while let Some(item) = seq.next_element::<Value>()? {
            items.push(item);
        }
        Ok(Value::Array(items))
    }

    fn visit_map<A: MapAccess<'de>>(self, mut map: A) -> Result<Value, A::Error> {
        let mut entries: Vec<(String, Value)> = Vec::new();
        let mut seen: HashMap<String, usize> = HashMap::new();
        while let Some(key) = map.next_key::<String>()? {
            let value = map.next_value::<Value>()?;
            match seen.get(&key) {
                Some(&at) => entries[at].1 = value,
                None => {
                    seen.insert(key.clone(), entries.len());
                    entries.push((key, value));
                }
            }
        }
        Ok(Value::Object(entries))
    }
}

impl<'de> Deserialize<'de> for Value {
    fn deserialize<D: Deserializer<'de>>(d: D) -> Result<Value, D::Error> {
        d.deserialize_any(ValueVisitor)
    }
}

/// One item of jq's input stream: a value, with the line jq would name if a
/// filter fails on it, or the parse error that ends the stream.
pub enum Input {
    Value(Value, usize),
    ParseError(String),
}

/// Read `text` the way jq reads stdin: value after value until the end or a
/// syntax error, which stops the stream after the values before it.
pub fn parse_stream(text: &str) -> Vec<Input> {
    let mut items = Vec::new();
    let mut stream = serde_json::Deserializer::from_str(text).into_iter::<Value>();
    loop {
        match stream.next() {
            None => break,
            Some(Ok(value)) => {
                let line = line_after(text, stream.byte_offset());
                items.push(Input::Value(value, line));
            }
            Some(Err(err)) => {
                items.push(Input::ParseError(err.to_string()));
                break;
            }
        }
    }
    items
}

/// jq reads its input a line at a time, so a value's errors name the count of
/// whole lines read once the line holding the value's last byte is in.
fn line_after(text: &str, end: usize) -> usize {
    let bytes = text.as_bytes();
    let from = end.saturating_sub(1);
    match bytes[from.min(bytes.len())..]
        .iter()
        .position(|&b| b == b'\n')
    {
        Some(at) => bytes[..from + at + 1]
            .iter()
            .filter(|&&b| b == b'\n')
            .count(),
        None => bytes.iter().filter(|&&b| b == b'\n').count(),
    }
}

fn rank(v: &Value) -> u8 {
    match v {
        Value::Null => 0,
        Value::Bool(false) => 1,
        Value::Bool(true) => 2,
        Value::Number(..) => 3,
        Value::String(_) => 4,
        Value::Array(_) => 5,
        Value::Object(_) => 6,
    }
}

fn sorted_keys(entries: &[(String, Value)]) -> Vec<&str> {
    let mut keys: Vec<&str> = entries.iter().map(|(k, _)| k.as_str()).collect();
    keys.sort_by(|a, b| a.as_bytes().cmp(b.as_bytes()));
    keys
}

fn field<'a>(entries: &'a [(String, Value)], key: &str) -> &'a Value {
    entries
        .iter()
        .find(|(k, _)| k == key)
        .map(|(_, v)| v)
        .unwrap_or(&Value::Null)
}

/// jq's total order: null < false < true < numbers < strings < arrays <
/// objects; objects compare their sorted keys first, then values key by key.
pub fn compare(a: &Value, b: &Value) -> Ordering {
    let (ra, rb) = (rank(a), rank(b));
    if ra != rb {
        return ra.cmp(&rb);
    }
    match (a, b) {
        (Value::Number(x, _), Value::Number(y, _)) => {
            if x < y {
                Ordering::Less
            } else if x == y {
                Ordering::Equal
            } else {
                Ordering::Greater
            }
        }
        (Value::String(x), Value::String(y)) => x.as_bytes().cmp(y.as_bytes()),
        (Value::Array(x), Value::Array(y)) => {
            for (p, q) in x.iter().zip(y.iter()) {
                let r = compare(p, q);
                if r != Ordering::Equal {
                    return r;
                }
            }
            x.len().cmp(&y.len())
        }
        (Value::Object(x), Value::Object(y)) => {
            let (kx, ky) = (sorted_keys(x), sorted_keys(y));
            for (p, q) in kx.iter().zip(ky.iter()) {
                let r = p.as_bytes().cmp(q.as_bytes());
                if r != Ordering::Equal {
                    return r;
                }
            }
            let r = kx.len().cmp(&ky.len());
            if r != Ordering::Equal {
                return r;
            }
            for key in kx {
                let r = compare(field(x, key), field(y, key));
                if r != Ordering::Equal {
                    return r;
                }
            }
            Ordering::Equal
        }
        _ => Ordering::Equal,
    }
}

/// `"\(x)"`: strings as they are, anything else as compact JSON.
pub fn interpolate(v: &Value) -> String {
    match v {
        Value::String(s) => s.clone(),
        other => to_json(other),
    }
}

pub fn to_json(v: &Value) -> String {
    let mut out = String::new();
    write_json(v, &mut out);
    out
}

fn write_json(v: &Value, out: &mut String) {
    match v {
        Value::Null => out.push_str("null"),
        Value::Bool(b) => out.push_str(if *b { "true" } else { "false" }),
        Value::Number(f, int) => out.push_str(&format_number(*f, *int)),
        Value::String(s) => write_json_string(s, out),
        Value::Array(items) => {
            out.push('[');
            for (i, item) in items.iter().enumerate() {
                if i > 0 {
                    out.push(',');
                }
                write_json(item, out);
            }
            out.push(']');
        }
        Value::Object(entries) => {
            out.push('{');
            for (i, (k, item)) in entries.iter().enumerate() {
                if i > 0 {
                    out.push(',');
                }
                write_json_string(k, out);
                out.push(':');
                write_json(item, out);
            }
            out.push('}');
        }
    }
}

/// Integers print as integers. jq 1.7 prints any other number as the literal
/// it read; serde_json keeps no literal, so this prints the shortest form.
fn format_number(f: f64, int: Option<i128>) -> String {
    if let Some(i) = int {
        return i.to_string();
    }
    let text = format!("{f}");
    if f.is_finite() && f.fract() == 0.0 && f.abs() < 1e17 {
        format!("{}", f as i128)
    } else {
        text
    }
}

fn write_json_string(s: &str, out: &mut String) {
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\u{08}' => out.push_str("\\b"),
            '\t' => out.push_str("\\t"),
            '\n' => out.push_str("\\n"),
            '\u{0c}' => out.push_str("\\f"),
            '\r' => out.push_str("\\r"),
            c if (c as u32) < 0x20 || c as u32 == 0x7f => {
                out.push_str(&format!("\\u{:04x}", c as u32));
            }
            c => out.push(c),
        }
    }
    out.push('"');
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parse(text: &str) -> Value {
        match parse_stream(text).into_iter().next() {
            Some(Input::Value(v, _)) => v,
            _ => panic!("no value in {text}"),
        }
    }

    #[test]
    fn objects_keep_first_place_and_last_value() {
        assert_eq!(
            to_json(&parse(r#"{"a":1,"b":2,"a":3}"#)),
            r#"{"a":3,"b":2}"#
        );
    }

    #[test]
    fn order_follows_jq() {
        let items = [
            "null", "false", "true", "-1", "2.5", "\"A\"", "\"a\"", "[]", "[1]", "{}",
        ];
        for pair in items.windows(2) {
            assert_eq!(
                compare(&parse(pair[0]), &parse(pair[1])),
                Ordering::Less,
                "{pair:?}"
            );
        }
        assert_eq!(compare(&parse("1"), &parse("1.0")), Ordering::Equal);
        assert_eq!(
            compare(&parse(r#"{"b":1}"#), &parse(r#"{"a":1,"b":1}"#)),
            Ordering::Greater
        );
    }

    #[test]
    fn interpolation_escapes_like_jq() {
        assert_eq!(interpolate(&parse(r#""x\ny""#)), "x\ny");
        assert_eq!(
            interpolate(&parse(r#"["\u007f\u0001\b"]"#)),
            r#"["\u007f\u0001\b"]"#
        );
        assert_eq!(interpolate(&parse("null")), "null");
        assert_eq!(interpolate(&parse("12")), "12");
    }

    #[test]
    fn stream_stops_at_a_syntax_error() {
        let items = parse_stream("{\"a\":1}\ngarbage\n{\"a\":2}\n");
        assert_eq!(items.len(), 2);
        assert!(matches!(items[0], Input::Value(_, 1)));
        assert!(matches!(items[1], Input::ParseError(_)));
    }

    #[test]
    fn line_numbers_count_whole_lines() {
        let items = parse_stream("5 [1] 6");
        assert!(items.iter().all(|i| matches!(i, Input::Value(_, 0))));
        let items = parse_stream("{}\n[1]\n5\n");
        let lines: Vec<usize> = items
            .iter()
            .map(|i| match i {
                Input::Value(_, l) => *l,
                _ => 99,
            })
            .collect();
        assert_eq!(lines, vec![1, 2, 3]);
    }

    #[test]
    fn indexing_errors_name_the_kind() {
        assert_eq!(
            parse("5").index("workflow_runs").unwrap_err(),
            "Cannot index number with string \"workflow_runs\""
        );
        assert!(parse("null").index("x").unwrap().is_null());
    }
}
