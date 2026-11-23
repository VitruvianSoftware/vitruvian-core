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

//! JSON as Python's `json` module reads and writes it, backed by
//! `vitruvian_pycompat::json` (`Value`, `py_eq`, `loads_with`, `dumps_with`),
//! keeping UTF-16/32 `loads_bytes`, `py_lt`/`py_sorted`, `schema_equal`,
//! `Key`, and catalog's `Crash`-returning object helpers.

use std::cmp::Ordering;

use vitruvian_pycompat::json as pyjson;

pub use vitruvian_pycompat::json::{py_eq, Value};

use crate::pyerr::{Crash, Res};

/// A dict: keys in the order they were first set.
pub type Dict = Vec<(String, Value)>;

pub type DictKeysIter<'a> =
    std::iter::Map<std::slice::Iter<'a, (String, Value)>, fn(&(String, Value)) -> &String>;

pub trait DictExt {
    fn dict_get(&self, key: &str) -> Option<&Value>;
    fn dict_get_mut(&mut self, key: &str) -> Option<&mut Value>;
    fn dict_contains(&self, key: &str) -> bool;
    fn dict_insert(&mut self, key: impl Into<String>, value: Value);
    fn dict_keys(&self) -> DictKeysIter<'_>;
    fn dict_at(&self, key: &str) -> Res<&Value>;
}

impl DictExt for Dict {
    fn dict_get(&self, key: &str) -> Option<&Value> {
        self.iter().find(|(k, _)| k == key).map(|(_, v)| v)
    }

    fn dict_get_mut(&mut self, key: &str) -> Option<&mut Value> {
        self.iter_mut().find(|(k, _)| k == key).map(|(_, v)| v)
    }

    fn dict_contains(&self, key: &str) -> bool {
        self.iter().any(|(k, _)| k == key)
    }

    /// `d[key] = value`: an existing key keeps its place.
    fn dict_insert(&mut self, key: impl Into<String>, value: Value) {
        let key = key.into();
        match self.dict_get_mut(&key) {
            Some(slot) => *slot = value,
            None => self.push((key, value)),
        }
    }

    fn dict_keys(&self) -> DictKeysIter<'_> {
        fn first((k, _): &(String, Value)) -> &String {
            k
        }
        self.iter().map(first as fn(&(String, Value)) -> &String)
    }

    /// `d[key]`, or the KeyError.
    fn dict_at(&self, key: &str) -> Res<&Value> {
        self.dict_get(key).ok_or_else(|| Crash::key_error(key))
    }
}

/// Builds a dict from pairs, in order.
pub fn dict(pairs: Vec<(&str, Value)>) -> Value {
    let mut d = Dict::new();
    for (k, v) in pairs {
        d.dict_insert(k, v);
    }
    Value::Obj(d)
}

pub fn s(text: impl Into<String>) -> Value {
    Value::Str(text.into())
}

pub fn int(n: i128) -> Value {
    Value::Int(n.to_string())
}

pub trait ValueExt {
    fn as_dict(&self) -> Option<&Dict>;
    fn as_list(&self) -> Option<&Vec<Value>>;
    fn is_null(&self) -> bool;
    fn py_get(&self, key: &str) -> Res<Option<&Value>>;
    fn get_or(&self, key: &str, default: Value) -> Res<Value>;
    fn get_v(&self, key: &str) -> Res<Value>;
    fn at(&self, key: &str) -> Res<&Value>;
    fn repr(&self) -> String;
    fn py_iter(&self) -> Res<Vec<Value>>;
    fn py_contains(&self, item: &Value) -> Res<bool>;
    fn contains_str(&self, text: &str) -> Res<bool>;
    fn field(&self, key: &str) -> Option<&Value>;
    fn field_mut(&mut self, key: &str) -> Option<&mut Value>;
    fn num_f64(&self) -> Option<f64>;
}

impl ValueExt for Value {
    fn as_dict(&self) -> Option<&Dict> {
        match self {
            Value::Obj(d) => Some(d),
            _ => None,
        }
    }

    fn as_list(&self) -> Option<&Vec<Value>> {
        match self {
            Value::Arr(l) => Some(l),
            _ => None,
        }
    }

    fn is_null(&self) -> bool {
        matches!(self, Value::Null)
    }

    /// `value.get(key)`: None when absent; AttributeError when `value` is
    /// not a dict.
    fn py_get(&self, key: &str) -> Res<Option<&Value>> {
        match self {
            Value::Obj(d) => Ok(d.dict_get(key)),
            other => Err(Crash::no_get(other)),
        }
    }

    /// `value.get(key, default)`, cloned.
    fn get_or(&self, key: &str, default: Value) -> Res<Value> {
        Ok(self.py_get(key)?.cloned().unwrap_or(default))
    }

    /// `value.get(key)`, cloned, None for absent.
    fn get_v(&self, key: &str) -> Res<Value> {
        self.get_or(key, Value::Null)
    }

    /// `value[key]` for a str key.
    fn at(&self, key: &str) -> Res<&Value> {
        match self {
            Value::Obj(d) => d.dict_at(key),
            Value::Arr(_) => Err(Crash::new(
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

    fn repr(&self) -> String {
        self.py_repr()
    }

    /// `list(value)`: a list's items, a dict's keys, a str's characters.
    fn py_iter(&self) -> Res<Vec<Value>> {
        match self {
            Value::Arr(l) => Ok(l.clone()),
            Value::Obj(d) => Ok(d.dict_keys().map(|k| Value::Str(k.clone())).collect()),
            Value::Str(t) => Ok(t.chars().map(|c| Value::Str(c.to_string())).collect()),
            other => Err(Crash::not_iterable(other)),
        }
    }

    /// `item in value`.
    fn py_contains(&self, item: &Value) -> Res<bool> {
        match self {
            Value::Arr(l) => Ok(l.iter().any(|v| py_eq(v, item))),
            Value::Obj(d) => {
                key(item)?;
                Ok(match item {
                    Value::Str(k) => d.dict_contains(k),
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
    fn contains_str(&self, text: &str) -> Res<bool> {
        self.py_contains(&Value::Str(text.to_string()))
    }

    fn field(&self, key: &str) -> Option<&Value> {
        self.get(key)
    }

    fn field_mut(&mut self, key: &str) -> Option<&mut Value> {
        match self {
            Value::Obj(d) => d.dict_get_mut(key),
            _ => None,
        }
    }

    /// Numeric value as `f64` for `Int`/`Float` only (not `Bool`).
    fn num_f64(&self) -> Option<f64> {
        match self {
            Value::Int(s) => s.parse::<f64>().ok(),
            Value::Float(f) => Some(*f),
            _ => None,
        }
    }
}

// --- reading -----------------------------------------------------------------

fn json_error_to_crash(err: pyjson::JsonError) -> Crash {
    match err.kind() {
        pyjson::JsonErrorKind::Recursion => Crash::new(
            "RecursionError",
            err.recursion_message().unwrap_or(&err.msg),
        ),
        pyjson::JsonErrorKind::IntDigitLimit => Crash::new("ValueError", err.msg),
        pyjson::JsonErrorKind::Decode => {
            Crash::new("json.decoder.JSONDecodeError", err.python_str())
        }
    }
}

/// Maximum JSON/plist nesting depth accepted by `catalog`.
///
/// Cap is 50 (a deliberate change from CPython 3.12's 9,997,
/// `vitruvian_pycompat::json::CPYTHON_312_MAX_DEPTH`) so recursive walkers in
/// `catalog` cannot overflow a 2 MiB thread stack in an unoptimised build.
///
/// Measured 2026-11-23:
/// - Real input maximum depth is 8 (`catalog/catalog.schema.json`: 8,
///   `catalog/tools.json`: 6, `catalog/testdata/tools.json`: 6,
///   `catalog/sources.json`: 3, `catalog/testdata/sources.json`: 3,
///   `catalog/android/vitruvian-remote.json`: 2,
///   `apps/desktop/vitruvian-atrium/Resources/Info.plist`: 2,
///   `catalog/testdata/Info.plist`: 1).
/// - Lowest measured walker stack limit on a 2 MiB thread (unoptimised):
///   `schema::Validator::descend` with combinator + `$ref` is safe at 85 and
///   overflows at 86 (simple `$ref` safe at 129, overflows at 130;
///   `plist::load` safe at 590, overflows at 591; `bump::dumps` safe at
///   1,094 for objects and 1,163 for arrays).
pub const MAX_DEPTH: usize = 50;

/// `json.loads(text)` for a str.
pub fn loads(text: &str) -> Res<Value> {
    pyjson::loads_with(
        text,
        &pyjson::LoadOptions {
            max_depth: Some(MAX_DEPTH),
        },
    )
    .map_err(json_error_to_crash)
}

/// `json.loads(data)` for bytes: the encoding found the way `json` finds
/// it (a BOM, or where the NUL bytes are), then as for a str.
pub fn loads_bytes(data: &[u8]) -> Res<Value> {
    let text = decode_detected(data)?;
    if text.starts_with('\u{feff}') {
        return Err(Crash::new(
            "json.decoder.JSONDecodeError",
            "Expecting value: line 1 column 1 (char 0)",
        ));
    }
    loads(&text)
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
                codec,
                b[b.len() - 1],
                b.len() - 1
            ),
        ));
    }
    Ok(char::decode_utf16(units)
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

// --- writing -----------------------------------------------------------------

/// `json.dumps(value, ensure_ascii=..., indent=...)` with the default
/// separators for that indent.
pub fn dumps(v: &Value, indent: Option<usize>, ensure_ascii: bool) -> String {
    pyjson::dumps_with(
        v,
        &pyjson::DumpOptions {
            indent,
            ensure_ascii,
            ..pyjson::DumpOptions::default()
        },
    )
}

/// `json.dumps(value, ensure_ascii=False)`.
pub fn dumps_unicode(v: &Value) -> String {
    dumps(v, None, false)
}

/// `json.dumps(value)`.
pub fn dumps_plain(v: &Value) -> String {
    dumps(v, None, true)
}

/// `float.__repr__` as `json` writes it, with its names for the
/// non-finite.
pub fn float_json(f: f64) -> String {
    dumps(&Value::Float(f), None, true)
}

/// A JSON string, escaped as `json.dumps` escapes it.
pub fn quote(s: &str, ascii: bool) -> String {
    dumps(&Value::Str(s.to_string()), None, ascii)
}

// --- Python's comparisons ----------------------------------------------------

enum Num {
    I(String),
    F(f64),
}

fn num(v: &Value) -> Option<Num> {
    match v {
        Value::Bool(b) => Some(Num::I(if *b { "1" } else { "0" }.into())),
        Value::Int(s) => Some(Num::I(pyjson::normalize_int(s))),
        Value::Float(f) => Some(Num::F(*f)),
        _ => None,
    }
}

fn cmp_int_str(a: &str, b: &str) -> Ordering {
    let neg_a = a.starts_with('-');
    let neg_b = b.starts_with('-');
    if neg_a != neg_b {
        return if neg_a {
            Ordering::Less
        } else {
            Ordering::Greater
        };
    }
    let da = a.strip_prefix('-').unwrap_or(a);
    let db = b.strip_prefix('-').unwrap_or(b);
    let mag = da.len().cmp(&db.len()).then_with(|| da.cmp(db));
    if neg_a {
        mag.reverse()
    } else {
        mag
    }
}

fn int_str_float_cmp(i: &str, f: f64) -> Option<Ordering> {
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
    let fl = f.floor();
    let fi = pyjson::normalize_int(&format!("{:.0}", fl));
    match cmp_int_str(i, &fi) {
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

fn num_cmp(a: &Num, b: &Num) -> Option<Ordering> {
    match (a, b) {
        (Num::I(x), Num::I(y)) => Some(cmp_int_str(x, y)),
        (Num::I(x), Num::F(y)) => int_str_float_cmp(x, *y),
        (Num::F(x), Num::I(y)) => int_str_float_cmp(y, *x).map(Ordering::reverse),
        (Num::F(x), Num::F(y)) => x.partial_cmp(y),
    }
}

/// jsonschema's `equal`: as `==`, except that a bool is never a number.
pub fn schema_equal(a: &Value, b: &Value) -> bool {
    let mut stack = vec![(a, b)];
    while let Some((ca, cb)) = stack.pop() {
        match (ca, cb) {
            (Value::Str(x), Value::Str(y)) => {
                if x != y {
                    return false;
                }
            }
            (Value::Str(_), _) | (_, Value::Str(_)) => return false,
            (Value::Bool(x), Value::Bool(y)) => {
                if x != y {
                    return false;
                }
            }
            (Value::Bool(_), _) | (_, Value::Bool(_)) => return false,
            (Value::Arr(x), Value::Arr(y)) => {
                if x.len() != y.len() {
                    return false;
                }
                stack.extend(x.iter().zip(y));
            }
            (Value::Obj(x), Value::Obj(y)) => {
                if x.len() != y.len() {
                    return false;
                }
                for (k, v) in x {
                    match y.dict_get(k) {
                        Some(w) => stack.push((v, w)),
                        None => return false,
                    }
                }
            }
            _ => {
                if !py_eq(ca, cb) {
                    return false;
                }
            }
        }
    }
    true
}

/// Python's `a < b`, or the TypeError it raises.
pub fn py_lt(mut a: &Value, mut b: &Value) -> Res<bool> {
    loop {
        if let (Some(x), Some(y)) = (num(a), num(b)) {
            return Ok(num_cmp(&x, &y) == Some(Ordering::Less));
        }
        match (a, b) {
            (Value::Str(x), Value::Str(y)) => return Ok(x < y),
            (Value::Arr(x), Value::Arr(y)) => {
                let mut diff = None;
                for (p, q) in x.iter().zip(y) {
                    if !py_eq(p, q) {
                        diff = Some((p, q));
                        break;
                    }
                }
                match diff {
                    Some((p, q)) => {
                        a = p;
                        b = q;
                    }
                    None => return Ok(x.len() < y.len()),
                }
            }
            _ => {
                return Err(Crash::new(
                    "TypeError",
                    format!(
                        "'<' not supported between instances of '{}' and '{}'",
                        a.type_name(),
                        b.type_name()
                    ),
                ))
            }
        }
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
    Int(String),
    Float(u64),
    Str(String),
}

pub fn key(v: &Value) -> Res<Key> {
    match v {
        Value::Null => Ok(Key::None),
        Value::Bool(b) => Ok(Key::Int(if *b { "1" } else { "0" }.into())),
        Value::Int(s) => Ok(Key::Int(pyjson::normalize_int(s))),
        Value::Float(f) => {
            if f.is_finite() && f.fract() == 0.0 {
                Ok(Key::Int(pyjson::normalize_int(&format!("{:.0}", f))))
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
        assert!(loads_bytes(b"\xef\xbb\xbf\xef\xbb\xbf{}").is_err());
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
        // CPython 3.12 escapes 0x7f as \u007f when ensure_ascii=True.
        assert_eq!(quote("\u{1F600}\u{7f}", true), "\"\\ud83d\\ude00\\u007f\"");
    }

    #[test]
    fn python_equality_and_order() {
        assert!(py_eq(&int(1), &Value::Float(1.0)));
        assert!(py_eq(&Value::Bool(true), &int(1)));
        assert!(!schema_equal(&Value::Bool(true), &int(1)));
        assert!(py_lt(&s("a"), &s("b")).unwrap());
        assert!(py_lt(&s("a"), &int(1)).is_err());
        let sorted = py_sorted(&[s("b"), s("a"), s("c")]).unwrap();
        assert_eq!(Value::Arr(sorted).repr(), "['a', 'b', 'c']");
        assert_eq!(key(&Value::Float(2.0)).unwrap(), key(&int(2)).unwrap());
    }

    #[test]
    fn depth_cap_is_safe_on_2mb_thread_and_cap_plus_one_errors() {
        let handle = std::thread::Builder::new()
            .stack_size(2 * 1024 * 1024)
            .spawn(|| {
                let d = MAX_DEPTH;
                for (open, close, leaf, step) in [
                    ("[", "]", "1", 1),
                    ("{\"a\":", "}", "1", 1),
                    ("[{\"a\":", "}]", "1", 2),
                ] {
                    let reps = d / step;
                    let doc = format!("{}{}{}", open.repeat(reps), leaf, close.repeat(reps));
                    let v = loads(&doc).unwrap();
                    let v2 = v.clone();
                    assert!(py_eq(&v, &v2));
                    assert!(schema_equal(&v, &v2));
                    if matches!(v, Value::Arr(_)) {
                        assert!(!py_lt(&v, &v2).unwrap());
                    } else {
                        assert!(py_lt(&v, &v2).is_err());
                    }
                    assert!(!v.repr().is_empty());
                    assert!(!dumps(&v, None, true).is_empty());
                    drop(v2);
                    drop(v);
                }
                let arr_over = format!("{}1{}", "[".repeat(d + 1), "]".repeat(d + 1));
                let err = loads(&arr_over).unwrap_err();
                assert_eq!(err.class, "RecursionError");
                assert!(err.msg.contains("maximum recursion depth exceeded"));
                let obj_over = format!("{}1{}", "{\"a\":".repeat(d + 1), "}".repeat(d + 1));
                let err = loads(&obj_over).unwrap_err();
                assert_eq!(err.class, "RecursionError");
                assert!(err.msg.contains("maximum recursion depth exceeded"));
            })
            .unwrap();
        handle.join().unwrap();
    }

    #[test]
    fn loads_bytes_depth_cap_on_2mb_thread() {
        let handle = std::thread::Builder::new()
            .stack_size(2 * 1024 * 1024)
            .spawn(|| {
                let d = MAX_DEPTH;
                let ok_arr = format!("{}1{}", "[".repeat(d), "]".repeat(d));
                assert!(loads_bytes(ok_arr.as_bytes()).is_ok());
                let mut bom_arr = b"\xef\xbb\xbf".to_vec();
                bom_arr.extend_from_slice(ok_arr.as_bytes());
                assert!(loads_bytes(&bom_arr).is_ok());
                let ok_obj = format!("{}1{}", "{\"a\":".repeat(d), "}".repeat(d));
                let utf16le: Vec<u8> = ok_obj
                    .encode_utf16()
                    .flat_map(|u| u.to_le_bytes())
                    .collect();
                assert!(loads_bytes(&utf16le).is_ok());

                let over_arr = format!("{}1{}", "[".repeat(d + 1), "]".repeat(d + 1));
                let err = loads_bytes(over_arr.as_bytes()).unwrap_err();
                assert_eq!(err.class, "RecursionError");
                assert!(err.msg.contains("maximum recursion depth exceeded"));

                let over_obj = format!("{}1{}", "{\"a\":".repeat(d + 1), "}".repeat(d + 1));
                let err = loads_bytes(over_obj.as_bytes()).unwrap_err();
                assert_eq!(err.class, "RecursionError");
                assert!(err.msg.contains("maximum recursion depth exceeded"));
            })
            .unwrap();
        handle.join().unwrap();
    }
}
