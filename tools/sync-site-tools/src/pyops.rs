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

//! Python value operations (`subscript`, `get`, `iterate`, `check_hashable`,
//! `==`, `<`) over `crate::json::Value` with CPython 3.12 error messages.

use std::cmp::Ordering;

use crate::json::Value;
use crate::pyerr::PyErr;
use crate::pystr::PyStr;

/// Object entries as a Python dict holds them: first key position, last value.
pub(crate) fn dedup_obj<'a>(pairs: &'a [(PyStr, Value)]) -> Vec<(&'a PyStr, &'a Value)> {
    let mut out: Vec<(&'a PyStr, &'a Value)> = Vec::with_capacity(pairs.len());
    for (k, v) in pairs {
        if let Some(slot) = out.iter_mut().find(|(ek, _)| *ek == k) {
            slot.1 = v;
        } else {
            out.push((k, v));
        }
    }
    out
}

/// `d.get(key)`: `None` for a missing key, `AttributeError` if `v` is not a dict.
pub(crate) fn get_ref<'a>(v: &'a Value, key: &str) -> Result<Option<&'a Value>, PyErr> {
    if !v.is_obj() {
        return Err(PyErr::exc(
            "AttributeError",
            &format!("'{}' object has no attribute 'get'", v.type_name()),
        ));
    }
    Ok(v.get(key))
}

/// `d.get(key, default)`, which needs `d` to be a dict.
pub(crate) fn get_or(v: &Value, key: &str, default: Value) -> Result<Value, PyErr> {
    Ok(get_ref(v, key)?.cloned().unwrap_or(default))
}

/// `v[key]` with a str key, returning a borrowed reference. A missing key is
/// `KeyError`; anything but a dict is `TypeError`.
pub(crate) fn index_ref<'a>(v: &'a Value, key: &str) -> Result<&'a Value, PyErr> {
    match v {
        Value::Obj(_) => v
            .get(key)
            .ok_or_else(|| PyErr::key_error(&PyStr::from(key))),
        Value::Arr(_) => Err(PyErr::type_error(
            "list indices must be integers or slices, not str",
        )),
        Value::Str(_) => Err(PyErr::type_error(
            "string indices must be integers, not 'str'",
        )),
        other => Err(PyErr::type_error(&format!(
            "'{}' object is not subscriptable",
            other.type_name()
        ))),
    }
}

/// `for x in value`.
pub(crate) fn iterate(v: &Value) -> Result<Vec<Value>, PyErr> {
    match v {
        Value::Arr(items) => Ok(items.clone()),
        Value::Obj(pairs) => Ok(dedup_obj(pairs)
            .into_iter()
            .map(|(k, _)| Value::Str(k.clone()))
            .collect()),
        Value::Str(text) => Ok(text
            .chars()
            .iter()
            .map(|&c| Value::Str(PyStr(vec![c])))
            .collect()),
        other => Err(PyErr::type_error(&format!(
            "'{}' object is not iterable",
            other.type_name()
        ))),
    }
}

/// Raises what `hash(v)` raises for unhashable JSON containers (`list`, `dict`).
pub(crate) fn check_hashable(v: &Value) -> Result<(), PyErr> {
    match v {
        Value::Arr(_) | Value::Obj(_) => Err(PyErr::type_error(&format!(
            "unhashable type: '{}'",
            v.type_name()
        ))),
        _ => Ok(()),
    }
}

pub(crate) fn normalize_int(s: &str) -> (bool, &str) {
    let (neg, digits) = match s.strip_prefix('-') {
        Some(d) => (true, d),
        None => (false, s),
    };
    let trimmed = digits.trim_start_matches('0');
    if trimmed.is_empty() {
        (false, "0")
    } else {
        (neg, trimmed)
    }
}

pub(crate) fn format_normalized_int(s: &str) -> String {
    let (neg, digits) = normalize_int(s);
    if neg {
        format!("-{digits}")
    } else {
        digits.to_string()
    }
}

fn as_int_str(v: &Value) -> Option<&str> {
    match v {
        Value::Bool(true) => Some("1"),
        Value::Bool(false) => Some("0"),
        Value::Int(s) => Some(s.as_str()),
        _ => None,
    }
}

fn cmp_int_str(a: &str, b: &str) -> Ordering {
    let (aneg, adig) = normalize_int(a);
    let (bneg, bdig) = normalize_int(b);
    match (aneg, bneg) {
        (false, true) => Ordering::Greater,
        (true, false) => Ordering::Less,
        (false, false) => adig.len().cmp(&bdig.len()).then_with(|| adig.cmp(bdig)),
        (true, true) => bdig.len().cmp(&adig.len()).then_with(|| bdig.cmp(adig)),
    }
}

/// Compare a decimal integer string against an `f64` by exact mathematical
/// value, as Python compares `int` and `float`; returns `None` for `NaN`.
fn cmp_int_float(int_str: &str, f: f64) -> Option<Ordering> {
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
    let whole = f.trunc();
    let exact = format!("{:.0}", whole);
    match cmp_int_str(int_str, &exact) {
        Ordering::Equal => {
            let frac = f - whole;
            Some(if frac > 0.0 {
                Ordering::Less
            } else if frac < 0.0 {
                Ordering::Greater
            } else {
                Ordering::Equal
            })
        }
        other => Some(other),
    }
}

fn py_eq_scalar(a: &Value, b: &Value) -> Option<bool> {
    let is_num = |v: &Value| matches!(v, Value::Bool(_) | Value::Int(_) | Value::Float(_));
    if is_num(a) && is_num(b) {
        return Some(match (as_int_str(a), as_int_str(b)) {
            (Some(x), Some(y)) => cmp_int_str(x, y) == Ordering::Equal,
            (Some(x), None) => match b {
                Value::Float(y) => cmp_int_float(x, *y) == Some(Ordering::Equal),
                _ => unreachable!(),
            },
            (None, Some(y)) => match a {
                Value::Float(x) => cmp_int_float(y, *x) == Some(Ordering::Equal),
                _ => unreachable!(),
            },
            (None, None) => match (a, b) {
                (Value::Float(x), Value::Float(y)) => (x.is_nan() && y.is_nan()) || x == y,
                _ => unreachable!(),
            },
        });
    }
    match (a, b) {
        (Value::Null, Value::Null) => Some(true),
        (Value::Str(x), Value::Str(y)) => Some(x == y),
        (Value::Arr(x), Value::Arr(y)) => {
            if x.len() != y.len() {
                Some(false)
            } else if x.is_empty() {
                Some(true)
            } else {
                None
            }
        }
        (Value::Obj(x), Value::Obj(y)) => {
            if x.is_empty() && y.is_empty() {
                Some(true)
            } else if x.is_empty() || y.is_empty() {
                Some(false)
            } else {
                None
            }
        }
        _ => Some(false),
    }
}

/// `PyObject_RichCompareBool(self, other, Py_EQ)`. `json.loads` returns one
/// singleton `NaN` object, so `NaN` compares equal to `NaN` here.
pub(crate) fn py_eq(a: &Value, b: &Value) -> bool {
    if let Some(res) = py_eq_scalar(a, b) {
        return res;
    }
    let mut stack = vec![(a, b)];
    while let Some((lhs, rhs)) = stack.pop() {
        match (lhs, rhs) {
            (Value::Arr(x), Value::Arr(y)) => {
                if x.len() != y.len() {
                    return false;
                }
                for (p, q) in x.iter().zip(y.iter()) {
                    match py_eq_scalar(p, q) {
                        Some(true) => {}
                        Some(false) => return false,
                        None => stack.push((p, q)),
                    }
                }
            }
            (Value::Obj(x), Value::Obj(y)) => {
                let ox = dedup_obj(x);
                let oy = dedup_obj(y);
                if ox.len() != oy.len() {
                    return false;
                }
                for (k, v) in ox {
                    let Some((_, v2)) = oy.iter().find(|(k2, _)| k == *k2) else {
                        return false;
                    };
                    match py_eq_scalar(v, v2) {
                        Some(true) => {}
                        Some(false) => return false,
                        None => stack.push((v, v2)),
                    }
                }
            }
            _ => unreachable!(),
        }
    }
    true
}

fn lt_non_arr(a: &Value, b: &Value) -> Result<bool, PyErr> {
    let is_num = |v: &Value| matches!(v, Value::Bool(_) | Value::Int(_) | Value::Float(_));
    if is_num(a) && is_num(b) {
        return Ok(match (as_int_str(a), as_int_str(b)) {
            (Some(x), Some(y)) => cmp_int_str(x, y) == Ordering::Less,
            (Some(x), None) => match b {
                Value::Float(y) => cmp_int_float(x, *y) == Some(Ordering::Less),
                _ => unreachable!(),
            },
            (None, Some(y)) => match a {
                Value::Float(x) => cmp_int_float(y, *x) == Some(Ordering::Greater),
                _ => unreachable!(),
            },
            (None, None) => match (a, b) {
                (Value::Float(x), Value::Float(y)) => x.partial_cmp(y) == Some(Ordering::Less),
                _ => unreachable!(),
            },
        });
    }
    match (a, b) {
        (Value::Str(x), Value::Str(y)) => Ok(x < y),
        _ => Err(PyErr::type_error(&format!(
            "'<' not supported between instances of '{}' and '{}'",
            a.type_name(),
            b.type_name()
        ))),
    }
}

/// Python's `a < b`.
pub(crate) fn lt(a: &Value, b: &Value) -> Result<bool, PyErr> {
    let (Value::Arr(xs_vec), Value::Arr(ys_vec)) = (a, b) else {
        return lt_non_arr(a, b);
    };
    let mut xs: &[Value] = xs_vec;
    let mut ys: &[Value] = ys_vec;
    let mut stack: Vec<(&[Value], &[Value], usize)> = Vec::new();
    let mut idx = 0usize;
    loop {
        let common = xs.len().min(ys.len());
        let mut descended = false;
        while idx < common {
            match (&xs[idx], &ys[idx]) {
                (Value::Arr(px), Value::Arr(py)) => {
                    stack.push((xs, ys, idx + 1));
                    xs = px;
                    ys = py;
                    idx = 0;
                    descended = true;
                    break;
                }
                (p, q) => {
                    if !py_eq(p, q) {
                        return lt_non_arr(p, q);
                    }
                    idx += 1;
                }
            }
        }
        if descended {
            continue;
        }
        if xs.len() != ys.len() {
            return Ok(xs.len() < ys.len());
        }
        match stack.pop() {
            Some((px, py, next_idx)) => {
                xs = px;
                ys = py;
                idx = next_idx;
            }
            None => return Ok(false),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::json::{self, loads};

    #[test]
    fn value_ops_match_cpython() {
        let obj = loads(&PyStr::from(r#"{"a": 1, "a": 2, "b": "hi"}"#)).unwrap();
        let arr = loads(&PyStr::from(r#"["x", 3]"#)).unwrap();

        assert_eq!(get_ref(&obj, "b").unwrap(), Some(&json::s("hi")));
        assert_eq!(get_ref(&obj, "missing").unwrap(), None);
        assert_eq!(
            get_ref(&arr, "a").unwrap_err().last_line(),
            "AttributeError: 'list' object has no attribute 'get'"
        );

        assert_eq!(index_ref(&obj, "b").unwrap(), &json::s("hi"));
        assert_eq!(
            index_ref(&obj, "missing").unwrap_err().last_line(),
            "KeyError: 'missing'"
        );

        assert!(check_hashable(&Value::Null).is_ok());
        assert!(check_hashable(&json::s("a")).is_ok());
        assert_eq!(
            check_hashable(&arr).unwrap_err().last_line(),
            "TypeError: unhashable type: 'list'"
        );
        assert_eq!(
            check_hashable(&obj).unwrap_err().last_line(),
            "TypeError: unhashable type: 'dict'"
        );

        assert!(lt(&json::int(1), &Value::Float(1.5)).unwrap());
        assert!(!lt(
            &Value::Int("9007199254740993".into()),
            &Value::Float(9007199254740992.0)
        )
        .unwrap());
        assert!(lt(&Value::Bool(false), &json::int(1)).unwrap());
        assert!(!lt(&Value::Float(f64::NAN), &json::int(1)).unwrap());
        assert!(!lt(&json::int(1), &Value::Float(f64::NAN)).unwrap());
        assert!(lt(&json::s("a"), &json::s("b")).unwrap());
        assert!(lt(
            &Value::Arr(vec![json::int(1), json::s("a")]),
            &Value::Arr(vec![Value::Float(1.0), json::s("b")])
        )
        .unwrap());
        assert_eq!(
            lt(&json::s("a"), &json::int(1)).unwrap_err().last_line(),
            "TypeError: '<' not supported between instances of 'str' and 'int'"
        );

        // Lone surrogates compare by exact code point.
        let s1 = Value::Str(PyStr(vec![0xD800]));
        let s2 = Value::Str(PyStr(vec![0xD801]));
        assert!(lt(&s1, &s2).unwrap());
        assert!(!py_eq(&s1, &s2));
        assert!(py_eq(&s1, &s1));

        // Nested list comparison edge cases matching CPython 3.12.
        let nan_lhs = Value::Arr(vec![Value::Arr(vec![Value::Float(f64::NAN)]), json::int(1)]);
        let nan_rhs = Value::Arr(vec![Value::Arr(vec![Value::Float(f64::NAN)]), json::int(2)]);
        assert!(lt(&nan_lhs, &nan_rhs).unwrap());

        let short_lhs = Value::Arr(vec![
            Value::Arr(vec![json::int(1), json::int(2)]),
            json::s("bad"),
        ]);
        let short_rhs = Value::Arr(vec![
            Value::Arr(vec![json::int(1), json::int(3)]),
            json::int(0),
        ]);
        assert!(lt(&short_lhs, &short_rhs).unwrap());

        let len_lhs = Value::Arr(vec![Value::Arr(vec![json::int(1)]), json::int(2)]);
        let len_rhs = Value::Arr(vec![
            Value::Arr(vec![json::int(1), json::int(0)]),
            json::int(0),
        ]);
        assert!(lt(&len_lhs, &len_rhs).unwrap());
        assert!(!lt(&len_rhs, &len_lhs).unwrap());

        let obj_eq_lhs = Value::Arr(vec![json::obj(vec![("a", json::int(1))]), json::int(0)]);
        let obj_eq_rhs = Value::Arr(vec![json::obj(vec![("a", json::int(1))]), json::int(1)]);
        assert!(lt(&obj_eq_lhs, &obj_eq_rhs).unwrap());

        let obj_ne_rhs = Value::Arr(vec![json::obj(vec![("a", json::int(2))]), json::int(1)]);
        assert_eq!(
            lt(&obj_eq_lhs, &obj_ne_rhs).unwrap_err().last_line(),
            "TypeError: '<' not supported between instances of 'dict' and 'dict'"
        );
    }

    fn deep_arr(depth: usize, mut leaf: Value) -> Value {
        for _ in 0..depth {
            leaf = Value::Arr(vec![leaf]);
        }
        leaf
    }

    fn deep_obj(depth: usize, mut leaf: Value) -> Value {
        for _ in 0..depth {
            leaf = Value::Obj(vec![(PyStr::from("a"), leaf)]);
        }
        leaf
    }

    fn deep_mixed(depth: usize, mut leaf: Value) -> Value {
        for k in (0..depth).rev() {
            if k % 2 == 0 {
                leaf = Value::Obj(vec![(PyStr::from("a"), leaf)]);
            } else {
                leaf = Value::Arr(vec![leaf]);
            }
        }
        leaf
    }

    #[test]
    fn deep_py_eq_2mib_stack() {
        let handle = std::thread::Builder::new()
            .stack_size(2 << 20)
            .spawn(|| {
                const DEPTH: usize = vitruvian_pycompat::json::CPYTHON_312_MAX_DEPTH;
                let a1 = deep_arr(DEPTH, json::int(1));
                let a2 = deep_arr(DEPTH, json::int(1));
                let a3 = deep_arr(DEPTH, json::int(2));
                assert!(py_eq(&a1, &a2));
                assert!(!py_eq(&a1, &a3));

                let o1 = deep_obj(DEPTH, json::int(1));
                let o2 = deep_obj(DEPTH, json::int(1));
                let o3 = deep_obj(DEPTH, json::int(2));
                assert!(py_eq(&o1, &o2));
                assert!(!py_eq(&o1, &o3));

                let m1 = deep_mixed(DEPTH, json::int(1));
                let m2 = deep_mixed(DEPTH, json::int(1));
                let m3 = deep_mixed(DEPTH, json::int(2));
                assert!(py_eq(&m1, &m2));
                assert!(!py_eq(&m1, &m3));
            })
            .unwrap();
        handle.join().unwrap();
    }

    #[test]
    fn deep_lt_2mib_stack() {
        let handle = std::thread::Builder::new()
            .stack_size(2 << 20)
            .spawn(|| {
                const DEPTH: usize = vitruvian_pycompat::json::CPYTHON_312_MAX_DEPTH;
                let a0 = deep_arr(DEPTH, json::int(0));
                let a1 = deep_arr(DEPTH, json::int(1));
                assert!(lt(&a0, &a1).unwrap());
                assert!(!lt(&a1, &a0).unwrap());
                assert!(!lt(&a0, &a0).unwrap());

                let o0 = Value::Arr(vec![deep_obj(DEPTH - 1, json::int(1)), json::int(0)]);
                let o1 = Value::Arr(vec![deep_obj(DEPTH - 1, json::int(1)), json::int(1)]);
                assert!(lt(&o0, &o1).unwrap());
            })
            .unwrap();
        handle.join().unwrap();
    }

    #[test]
    fn cmp_int_str_and_float_exact() {
        assert_eq!(cmp_int_str("-0", "0"), Ordering::Equal);
        assert_eq!(cmp_int_str("-10", "2"), Ordering::Less);
        assert_eq!(cmp_int_str("-2", "-10"), Ordering::Greater);
        assert_eq!(
            cmp_int_str(
                "1000000000000000000000000000001",
                "1000000000000000000000000000000"
            ),
            Ordering::Greater
        );

        assert_eq!(cmp_int_float("3", 3.5), Some(Ordering::Less));
        assert_eq!(cmp_int_float("-3", -3.5), Some(Ordering::Greater));
        assert_eq!(cmp_int_float("0", -0.0), Some(Ordering::Equal));
        assert_eq!(cmp_int_float("0", -0.5), Some(Ordering::Greater));
        assert_eq!(cmp_int_float("0", 0.5), Some(Ordering::Less));
        assert_eq!(
            cmp_int_float("9007199254740993", 9007199254740992.0),
            Some(Ordering::Greater)
        );
        assert_eq!(cmp_int_float("1", f64::INFINITY), Some(Ordering::Less));
        assert_eq!(
            cmp_int_float("1", f64::NEG_INFINITY),
            Some(Ordering::Greater)
        );
        assert_eq!(cmp_int_float("1", f64::NAN), None);
    }
}
