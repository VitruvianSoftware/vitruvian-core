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

//! Python value semantics the advisory comparison relies on: hashing and
//! equality (`1 == 1.0 == True` collapse in a set or dict key), `<` for
//! `sorted()` (and the TypeError it raises across types), and iteration
//! (`for x in value`: a dict yields its keys, a str its characters).

use crate::pyjson::Py;
use std::cmp::Ordering;

/// What Python would raise; the message is the TypeError's text.
#[derive(Debug, PartialEq)]
pub struct TypeError(pub String);

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub enum HKey {
    None,
    Int(i128),
    Float(u64),
    Str(String),
}

pub fn type_name(v: &Py) -> &'static str {
    match v {
        Py::None => "NoneType",
        Py::Bool(_) => "bool",
        Py::Int(_) => "int",
        Py::Float(_) => "float",
        Py::Str(_) => "str",
        Py::List(_) => "list",
        Py::Dict(_) => "dict",
    }
}

/// `hash(v)`'s equivalence class; lists and dicts are unhashable.
pub fn hkey(v: &Py) -> Result<HKey, TypeError> {
    Ok(match v {
        Py::None => HKey::None,
        Py::Bool(b) => HKey::Int(*b as i128),
        Py::Int(i) => HKey::Int(*i),
        Py::Float(f) => {
            if f.fract() == 0.0 && f.abs() < 1e38 {
                HKey::Int(*f as i128)
            } else {
                HKey::Float(f.to_bits())
            }
        }
        Py::Str(s) => HKey::Str(s.clone()),
        other => {
            return Err(TypeError(format!(
                "unhashable type: '{}'",
                type_name(other)
            )))
        }
    })
}

/// `for x in v`.
pub fn iterate(v: &Py) -> Result<Vec<Py>, TypeError> {
    match v {
        Py::List(items) => Ok(items.clone()),
        Py::Dict(items) => Ok(items.iter().map(|(k, _)| Py::Str(k.clone())).collect()),
        Py::Str(s) => Ok(s.chars().map(|c| Py::Str(c.to_string())).collect()),
        other => Err(TypeError(format!(
            "'{}' object is not iterable",
            type_name(other)
        ))),
    }
}

fn num(v: &Py) -> Option<f64> {
    match v {
        Py::Bool(b) => Some(*b as i64 as f64),
        Py::Int(i) => Some(*i as f64),
        Py::Float(f) => Some(*f),
        _ => None,
    }
}

fn int(v: &Py) -> Option<i128> {
    match v {
        Py::Bool(b) => Some(*b as i128),
        Py::Int(i) => Some(*i),
        _ => None,
    }
}

/// `a < b`.
pub fn lt(a: &Py, b: &Py) -> Result<bool, TypeError> {
    match (a, b) {
        (Py::Str(x), Py::Str(y)) => Ok(x < y),
        _ => {
            if let (Some(x), Some(y)) = (int(a), int(b)) {
                return Ok(x < y);
            }
            match (num(a), num(b)) {
                (Some(x), Some(y)) => Ok(x < y),
                _ => Err(TypeError(format!(
                    "'<' not supported between instances of '{}' and '{}'",
                    type_name(a),
                    type_name(b)
                ))),
            }
        }
    }
}

fn eq(a: &Py, b: &Py) -> bool {
    match (hkey(a), hkey(b)) {
        (Ok(x), Ok(y)) => x == y,
        _ => a == b,
    }
}

/// Tuple comparison, as `sorted()` makes it.
pub fn cmp_tuple(a: &[Py], b: &[Py]) -> Result<Ordering, TypeError> {
    for (x, y) in a.iter().zip(b.iter()) {
        if eq(x, y) {
            continue;
        }
        if lt(x, y)? {
            return Ok(Ordering::Less);
        }
        if lt(y, x)? {
            return Ok(Ordering::Greater);
        }
        return Ok(Ordering::Equal);
    }
    Ok(a.len().cmp(&b.len()))
}

/// `sorted(items)` with a comparison that can raise. Any comparison raising
/// makes the whole sort raise (CPython may compare fewer pairs; only inputs
/// that mix types in one position can tell the difference).
pub fn sorted_by<T: Clone>(
    items: &[T],
    cmp: impl Fn(&T, &T) -> Result<Ordering, TypeError>,
) -> Result<Vec<T>, TypeError> {
    let mut err: Option<TypeError> = None;
    let mut v = items.to_vec();
    v.sort_by(|a, b| match cmp(a, b) {
        Ok(o) => o,
        Err(e) => {
            if err.is_none() {
                err = Some(e);
            }
            Ordering::Equal
        }
    });
    match err {
        Some(e) => Err(e),
        None => Ok(v),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn numbers_collapse_like_python() {
        assert_eq!(hkey(&Py::Bool(true)).unwrap(), hkey(&Py::Int(1)).unwrap());
        assert_eq!(hkey(&Py::Float(1.0)).unwrap(), hkey(&Py::Int(1)).unwrap());
        assert_eq!(hkey(&Py::Float(-0.0)).unwrap(), hkey(&Py::Int(0)).unwrap());
        assert_ne!(
            hkey(&Py::Str("1".into())).unwrap(),
            hkey(&Py::Int(1)).unwrap()
        );
        assert!(hkey(&Py::List(vec![])).is_err());
    }

    #[test]
    fn mixed_types_do_not_sort() {
        let a = vec![Py::Str("x".into()), Py::None];
        let b = vec![Py::Str("x".into()), Py::Str("npm".into())];
        assert!(cmp_tuple(&a, &b).is_err());
        let c = vec![Py::Str("w".into()), Py::None];
        assert_eq!(cmp_tuple(&c, &b).unwrap(), Ordering::Less);
        assert!(iterate(&Py::Int(3)).is_err());
        assert_eq!(iterate(&Py::Str("ab".into())).unwrap().len(), 2);
    }
}
