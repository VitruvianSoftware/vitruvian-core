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

//! Python's operations on the values `json.loads` makes, named as the
//! scripts use them (`d.get`, `d[k]`, `==`, `in`, `sorted`, `set`), over
//! json.rs's object model.

use crate::json::{self, Value};
use crate::pyerr::{Crash, Res};

/// `v.get(key)`.
pub fn get<'a>(v: &'a Value, key: &str) -> Res<Option<&'a Value>> {
    v.get(key)
}

/// `v.get(key, default)`.
pub fn get_or(v: &Value, key: &str, default: Value) -> Res<Value> {
    v.get_or(key, default)
}

/// `v.get(key)` with None as `Value::Null`.
pub fn get_null(v: &Value, key: &str) -> Res<Value> {
    v.get_v(key)
}

/// `v[key]` with a str key.
pub fn index<'a>(v: &'a Value, key: &str) -> Res<&'a Value> {
    v.at(key)
}

/// `v[a][b]...`.
pub fn path<'a>(v: &'a Value, keys: &[&str]) -> Res<&'a Value> {
    let mut at = v;
    for k in keys {
        at = at.at(k)?;
    }
    Ok(at)
}

/// `str(v)`.
pub fn str_of(v: &Value) -> String {
    v.py_str()
}

/// `a == b`.
pub fn eq(a: &Value, b: &Value) -> bool {
    json::py_eq(a, b)
}

/// `TypeError: unhashable type: 'list'` for a list or dict.
pub fn hashable(v: &Value) -> Res<()> {
    json::key(v).map(|_| ())
}

/// `len(set(values))`.
pub fn set_len(values: &[Value]) -> Res<usize> {
    let mut seen = std::collections::HashSet::new();
    for v in values {
        seen.insert(json::key(v)?);
    }
    Ok(seen.len())
}

/// `a < b`.
pub fn lt(a: &Value, b: &Value) -> Res<bool> {
    json::py_lt(a, b)
}

/// `sorted(values)`.
pub fn sorted(values: &[Value]) -> Res<Vec<Value>> {
    json::py_sorted(values)
}

/// `list(v)` / `for x in v`.
pub fn iterate(v: &Value) -> Res<Vec<Value>> {
    v.py_iter()
}

/// `needle in container`.
pub fn contains(container: &Value, needle: &Value) -> Res<bool> {
    container.py_contains(needle)
}

/// `d[key] = value`: a key already there keeps its place.
pub fn set_item(d: &mut Value, key: &str, value: Value) {
    if let Value::Dict(items) = d {
        items.insert(key, value);
    }
}

/// A value a str method is called on: the str, or the AttributeError.
pub fn want_str<'a>(v: &'a Value, method: &str) -> Res<&'a str> {
    match v {
        Value::Str(s) => Ok(s),
        other => Err(Crash::no_attr(other, method)),
    }
}

pub fn obj(items: Vec<(&str, Value)>) -> Value {
    json::dict(items)
}

pub fn s(text: impl Into<String>) -> Value {
    Value::Str(text.into())
}

pub fn int(n: i128) -> Value {
    Value::Int(n)
}
