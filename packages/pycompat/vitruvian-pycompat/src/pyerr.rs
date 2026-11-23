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

//! Where the Python script would die with an uncaught exception, the port
//! stops the same way: a traceback header, the exception's class and
//! message, exit 1. Only the last line can match Python's, since the port
//! has no Python frames to show.

use crate::json::Value;
use crate::pystr;

#[derive(Debug, Clone, PartialEq)]
pub struct Crash {
    pub class: String,
    pub msg: String,
}

impl Crash {
    pub fn new(class: &str, msg: impl Into<String>) -> Crash {
        Crash {
            class: class.into(),
            msg: msg.into(),
        }
    }

    /// The traceback Python prints for this exception.
    pub fn traceback(&self) -> String {
        format!(
            "Traceback (most recent call last):\n  File \"<rust port>\", line 0, in <module>\n{}: {}\n",
            self.class, self.msg
        )
    }

    pub fn attribute(v: &Value, attr: &str) -> Crash {
        Crash::new(
            "AttributeError",
            format!("'{}' object has no attribute '{}'", v.type_name(), attr),
        )
    }

    /// An OSError from the operating system, named the way Python names it.
    pub fn os(err: &std::io::Error, filename: Option<&str>) -> Crash {
        let code = err.raw_os_error().unwrap_or(0);
        let class = match err.kind() {
            std::io::ErrorKind::NotFound => "FileNotFoundError",
            std::io::ErrorKind::PermissionDenied => "PermissionError",
            _ => match code {
                21 => "IsADirectoryError",
                20 => "NotADirectoryError",
                _ => "OSError",
            },
        };
        let text = err.to_string();
        let text = match text.rfind(" (os error ") {
            Some(i) => text[..i].to_string(),
            None => text,
        };
        let msg = match filename {
            Some(f) => format!("[Errno {}] {}: {}", code, text, pystr::repr_str(f)),
            None => format!("[Errno {}] {}", code, text),
        };
        Crash::new(class, msg)
    }
}

/// `d.get(key)`: `None` for a missing key, `AttributeError` if `v` is not a dict.
pub fn get_ref<'a>(v: &'a Value, key: &str) -> Result<Option<&'a Value>, Crash> {
    if !v.is_obj() {
        return Err(Crash::attribute(v, "get"));
    }
    Ok(v.get(key))
}

/// `d.get(key, default)`, which needs `d` to be a dict.
pub fn get_or(v: &Value, key: &str, default: Value) -> Result<Value, Crash> {
    Ok(get_ref(v, key)?.cloned().unwrap_or(default))
}

/// A str for a str method call, or the AttributeError a non-str raises.
pub fn as_str<'a>(v: &'a Value, method: &str) -> Result<&'a str, Crash> {
    match v {
        Value::Str(s) => Ok(s),
        other => Err(Crash::attribute(other, method)),
    }
}

/// `needle in container`.
pub fn contains(container: &Value, needle: &str) -> Result<bool, Crash> {
    match container {
        Value::Str(s) => Ok(s.contains(needle)),
        Value::Arr(items) => Ok(items
            .iter()
            .any(|v| matches!(v, Value::Str(s) if s == needle))),
        Value::Obj(items) => Ok(items.iter().any(|(k, _)| k == needle)),
        other => Err(Crash::new(
            "TypeError",
            format!("argument of type '{}' is not iterable", other.type_name()),
        )),
    }
}

/// `for x in value`.
pub fn iterate(v: &Value) -> Result<Vec<Value>, Crash> {
    match v {
        Value::Arr(items) => Ok(items.clone()),
        Value::Obj(items) => Ok(crate::json::dedup(items)
            .into_iter()
            .map(|(k, _)| Value::Str(k))
            .collect()),
        Value::Str(s) => Ok(s.chars().map(|c| Value::Str(c.to_string())).collect()),
        other => Err(Crash::new(
            "TypeError",
            format!("'{}' object is not iterable", other.type_name()),
        )),
    }
}

/// `v[key]` with a str key, returning a borrowed reference. A missing key is
/// `KeyError`; anything but a dict is `TypeError`.
pub fn index_ref<'a>(v: &'a Value, key: &str) -> Result<&'a Value, Crash> {
    match v {
        Value::Obj(_) => v
            .get(key)
            .ok_or_else(|| Crash::new("KeyError", pystr::repr_str(key))),
        Value::Arr(_) => Err(Crash::new(
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

/// `v[key]` with a str key. A missing key is the KeyError the script
/// catches (or not); anything but a dict is a TypeError.
pub fn index(v: &Value, key: &str) -> Result<Value, Crash> {
    index_ref(v, key).cloned()
}

/// Raises what `hash(v)` raises for unhashable JSON containers (`list`, `dict`).
pub fn check_hashable(v: &Value) -> Result<(), Crash> {
    match v {
        Value::Arr(_) | Value::Obj(_) => Err(Crash::new(
            "TypeError",
            format!("unhashable type: '{}'", v.type_name()),
        )),
        _ => Ok(()),
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

fn normalize_int(s: &str) -> (bool, &str) {
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

fn cmp_int_str(a: &str, b: &str) -> std::cmp::Ordering {
    let (aneg, adig) = normalize_int(a);
    let (bneg, bdig) = normalize_int(b);
    match (aneg, bneg) {
        (false, true) => std::cmp::Ordering::Greater,
        (true, false) => std::cmp::Ordering::Less,
        (false, false) => adig.len().cmp(&bdig.len()).then_with(|| adig.cmp(bdig)),
        (true, true) => bdig.len().cmp(&adig.len()).then_with(|| bdig.cmp(adig)),
    }
}

/// Compare a decimal integer string against an `f64` by exact mathematical
/// value, as Python compares `int` and `float`; returns `None` for `NaN`.
fn cmp_int_float(int_str: &str, f: f64) -> Option<std::cmp::Ordering> {
    if f.is_nan() {
        return None;
    }
    if f.is_infinite() {
        return Some(if f > 0.0 {
            std::cmp::Ordering::Less
        } else {
            std::cmp::Ordering::Greater
        });
    }
    let whole = f.trunc();
    let exact = format!("{:.0}", whole);
    match cmp_int_str(int_str, &exact) {
        std::cmp::Ordering::Equal => {
            let frac = f - whole;
            Some(if frac > 0.0 {
                std::cmp::Ordering::Less
            } else if frac < 0.0 {
                std::cmp::Ordering::Greater
            } else {
                std::cmp::Ordering::Equal
            })
        }
        other => Some(other),
    }
}

/// Python's `a < b`.
pub fn lt(a: &Value, b: &Value) -> Result<bool, Crash> {
    use std::cmp::Ordering;
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
        (Value::Arr(x), Value::Arr(y)) => {
            for (p, q) in x.iter().zip(y) {
                if !crate::json::py_eq(p, q) {
                    return lt(p, q);
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

/// `len(v)`.
pub fn len(v: &Value) -> Result<usize, Crash> {
    match v {
        Value::Arr(items) => Ok(items.len()),
        Value::Obj(items) => Ok(crate::json::dedup(items).len()),
        Value::Str(s) => Ok(s.chars().count()),
        other => Err(Crash::new(
            "TypeError",
            format!("object of type '{}' has no len()", other.type_name()),
        )),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::json::loads;

    #[test]
    fn traceback_and_attribute_match_cpython() {
        let c = Crash::new("KeyError", pystr::repr_str("x"));
        assert_eq!(
            c.traceback(),
            "Traceback (most recent call last):\n  File \"<rust port>\", line 0, in <module>\nKeyError: 'x'\n"
        );
        let cases = [
            (Value::Null, "'NoneType' object has no attribute 'get'"),
            (Value::Bool(true), "'bool' object has no attribute 'get'"),
            (
                Value::Int("1".into()),
                "'int' object has no attribute 'get'",
            ),
            (Value::Float(1.5), "'float' object has no attribute 'get'"),
            (
                Value::Str("s".into()),
                "'str' object has no attribute 'get'",
            ),
            (Value::Arr(vec![]), "'list' object has no attribute 'get'"),
            (Value::Obj(vec![]), "'dict' object has no attribute 'get'"),
        ];
        for (val, expected) in cases {
            let err = Crash::attribute(&val, "get");
            assert_eq!(err.class, "AttributeError");
            assert_eq!(err.msg, expected);
        }
    }

    #[test]
    fn os_errors_classify_and_format() {
        let not_found = std::fs::read("/definitely/not/here").unwrap_err();
        let c_named = Crash::os(&not_found, Some("/definitely/not/here"));
        assert_eq!(c_named.class, "FileNotFoundError");
        assert_eq!(
            c_named.msg,
            "[Errno 2] No such file or directory: '/definitely/not/here'"
        );
        let c_plain = Crash::os(&not_found, None);
        assert_eq!(c_plain.class, "FileNotFoundError");
        assert_eq!(c_plain.msg, "[Errno 2] No such file or directory");

        let perm = std::io::Error::new(std::io::ErrorKind::PermissionDenied, "denied");
        assert_eq!(Crash::os(&perm, None).class, "PermissionError");

        let is_dir = std::io::Error::from_raw_os_error(21);
        assert_eq!(Crash::os(&is_dir, Some("dir")).class, "IsADirectoryError");

        let not_dir = std::io::Error::from_raw_os_error(20);
        assert_eq!(Crash::os(&not_dir, None).class, "NotADirectoryError");

        let generic = std::io::Error::other("custom failure");
        assert_eq!(
            Crash::os(&generic, None),
            Crash::new("OSError", "[Errno 0] custom failure")
        );
    }

    #[test]
    fn value_operations_and_errors_match_cpython() {
        let obj = loads(r#"{"a": 1, "a": 2, "b": "hi"}"#).unwrap();
        let arr = loads(r#"["x", 3]"#).unwrap();
        let text = Value::Str("café".into());
        let flag = Value::Bool(false);

        assert_eq!(
            get_or(&obj, "b", Value::Null).unwrap(),
            Value::Str("hi".into())
        );
        assert_eq!(
            get_or(&obj, "missing", Value::Bool(true)).unwrap(),
            Value::Bool(true)
        );
        assert_eq!(
            get_or(&arr, "a", Value::Null).unwrap_err(),
            Crash::new("AttributeError", "'list' object has no attribute 'get'")
        );

        assert_eq!(as_str(&text, "strip").unwrap(), "café");
        assert_eq!(
            as_str(&flag, "strip").unwrap_err(),
            Crash::new("AttributeError", "'bool' object has no attribute 'strip'")
        );

        assert!(contains(&text, "fé").unwrap());
        assert!(contains(&arr, "x").unwrap());
        assert!(!contains(&arr, "3").unwrap());
        assert!(contains(&obj, "a").unwrap());
        assert_eq!(
            contains(&flag, "a").unwrap_err(),
            Crash::new("TypeError", "argument of type 'bool' is not iterable")
        );

        assert_eq!(iterate(&arr).unwrap().len(), 2);
        assert_eq!(
            iterate(&obj).unwrap(),
            vec![Value::Str("a".into()), Value::Str("b".into())]
        );
        assert_eq!(iterate(&text).unwrap().len(), 4);
        assert_eq!(
            iterate(&flag).unwrap_err(),
            Crash::new("TypeError", "'bool' object is not iterable")
        );

        assert_eq!(index(&obj, "b").unwrap(), Value::Str("hi".into()));
        assert_eq!(index(&obj, "k").unwrap_err(), Crash::new("KeyError", "'k'"));
        assert_eq!(
            index(&obj, "it's").unwrap_err(),
            Crash::new("KeyError", "\"it's\"")
        );
        assert_eq!(
            index(&arr, "a").unwrap_err(),
            Crash::new(
                "TypeError",
                "list indices must be integers or slices, not str"
            )
        );
        assert_eq!(
            index(&text, "a").unwrap_err(),
            Crash::new("TypeError", "string indices must be integers, not 'str'")
        );
        assert_eq!(
            index(&flag, "a").unwrap_err(),
            Crash::new("TypeError", "'bool' object is not subscriptable")
        );

        assert_eq!(len(&arr).unwrap(), 2);
        assert_eq!(len(&obj).unwrap(), 2);
        assert_eq!(len(&text).unwrap(), 4);
        assert_eq!(
            len(&flag).unwrap_err(),
            Crash::new("TypeError", "object of type 'bool' has no len()")
        );

        assert_eq!(get_ref(&obj, "b").unwrap(), Some(&Value::Str("hi".into())));
        assert_eq!(get_ref(&obj, "missing").unwrap(), None);
        assert_eq!(
            get_ref(&arr, "a").unwrap_err(),
            Crash::new("AttributeError", "'list' object has no attribute 'get'")
        );

        assert_eq!(index_ref(&obj, "b").unwrap(), &Value::Str("hi".into()));
        assert_eq!(
            index_ref(&obj, "missing").unwrap_err(),
            Crash::new("KeyError", "'missing'")
        );

        assert!(check_hashable(&Value::Null).is_ok());
        assert!(check_hashable(&Value::Str("a".into())).is_ok());
        assert_eq!(
            check_hashable(&arr).unwrap_err(),
            Crash::new("TypeError", "unhashable type: 'list'")
        );
        assert_eq!(
            check_hashable(&obj).unwrap_err(),
            Crash::new("TypeError", "unhashable type: 'dict'")
        );

        assert!(lt(&Value::Int("1".into()), &Value::Float(1.5)).unwrap());
        assert!(!lt(
            &Value::Int("9007199254740993".into()),
            &Value::Float(9007199254740992.0)
        )
        .unwrap());
        assert!(lt(&Value::Bool(false), &Value::Int("1".into())).unwrap());
        assert!(!lt(&Value::Float(f64::NAN), &Value::Int("1".into())).unwrap());
        assert!(!lt(&Value::Int("1".into()), &Value::Float(f64::NAN)).unwrap());
        assert!(lt(&Value::Str("a".into()), &Value::Str("b".into())).unwrap());
        assert!(lt(
            &Value::Arr(vec![Value::Int("1".into()), Value::Str("a".into())]),
            &Value::Arr(vec![Value::Float(1.0), Value::Str("b".into())])
        )
        .unwrap());
        assert_eq!(
            lt(&Value::Str("a".into()), &Value::Int("1".into())).unwrap_err(),
            Crash::new(
                "TypeError",
                "'<' not supported between instances of 'str' and 'int'"
            )
        );
    }

    #[test]
    fn cmp_int_str_and_float_exact() {
        use std::cmp::Ordering;

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
