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

//! The handful of Python built-in behaviours the tool leans on, applied to
//! decoded JSON: truthiness, `str()`/`repr()`, `int()`/`float()`, iteration,
//! `d.get()` on something that may not be a dict, and `+` on numbers.
//!
//! The Python modules parse untrusted JSON (hook payloads, transcripts) and
//! catch whatever exception a malformed value raises. Where that exception
//! lands decides what was already counted, so these helpers return `Err` at
//! exactly the points Python would raise, with a message in Python's words.

use crate::json::{float_repr, J};

pub type PyResult<T> = Result<T, String>;

pub fn type_name(v: &J) -> &'static str {
    match v {
        J::Null => "NoneType",
        J::Bool(_) => "bool",
        J::Int(_) => "int",
        J::Float(_) => "float",
        J::Str(_) => "str",
        J::Arr(_) => "list",
        J::Obj(_) => "dict",
    }
}

/// `bool(v)`.
pub fn truthy(v: &J) -> bool {
    match v {
        J::Null => false,
        J::Bool(b) => *b,
        J::Int(i) => *i != 0,
        J::Float(f) => *f != 0.0,
        J::Str(s) => !s.is_empty(),
        J::Arr(a) => !a.is_empty(),
        J::Obj(o) => !o.is_empty(),
    }
}

/// `d.get(key)` where `d` may not be a dict (AttributeError otherwise).
pub fn get<'a>(v: &'a J, key: &str) -> PyResult<Option<&'a J>> {
    match v {
        J::Obj(_) => Ok(v.get(key)),
        _ => Err(format!("'{}' object has no attribute 'get'", type_name(v))),
    }
}

/// `d.get(key, default)`.
pub fn get_or(v: &J, key: &str, default: J) -> PyResult<J> {
    Ok(get(v, key)?.cloned().unwrap_or(default))
}

/// `d[key]` for assignment through, e.g. `st["tokens"]["input"] += n`.
pub fn index_mut<'a>(v: &'a mut J, key: &str) -> PyResult<&'a mut J> {
    let tn = type_name(v);
    match v {
        J::Obj(_) => v.get_mut(key).ok_or_else(|| format!("'{}'", key)),
        J::Str(_) | J::Arr(_) => Err(format!(
            "{} indices must be integers or slices, not str",
            tn
        )),
        _ => Err(format!("'{}' object is not subscriptable", tn)),
    }
}

/// `iter(v)` materialised: lists yield items, strings characters, dicts keys.
pub fn py_iter(v: &J) -> PyResult<Vec<J>> {
    match v {
        J::Arr(items) => Ok(items.clone()),
        J::Str(s) => Ok(s.chars().map(|c| J::Str(c.to_string())).collect()),
        J::Obj(pairs) => Ok(pairs.iter().map(|(k, _)| J::Str(k.clone())).collect()),
        _ => Err(format!("'{}' object is not iterable", type_name(v))),
    }
}

/// `len(v)`.
pub fn py_len(v: &J) -> PyResult<usize> {
    match v {
        J::Str(s) => Ok(s.chars().count()),
        J::Arr(a) => Ok(a.len()),
        J::Obj(o) => Ok(o.len()),
        _ => Err(format!("object of type '{}' has no len()", type_name(v))),
    }
}

/// A dict key must be hashable; lists and dicts are not.
pub fn require_hashable(v: &J) -> PyResult<()> {
    match v {
        J::Arr(_) | J::Obj(_) => Err(format!("unhashable type: '{}'", type_name(v))),
        _ => Ok(()),
    }
}

/// `str.isspace()` for one character.
pub fn is_space(c: char) -> bool {
    c.is_whitespace() || ('\u{1c}'..='\u{1f}').contains(&c)
}

/// `s.strip()`.
pub fn strip(s: &str) -> &str {
    s.trim_matches(is_space)
}

/// `s.rstrip(chars)`.
pub fn rstrip_chars<'a>(s: &'a str, chars: &str) -> &'a str {
    s.trim_end_matches(|c| chars.contains(c))
}

/// `len(s.split())`.
pub fn split_ws_count(s: &str) -> usize {
    s.split(is_space).filter(|p| !p.is_empty()).count()
}

fn repr_str(s: &str) -> String {
    let quote = if s.contains('\'') && !s.contains('"') {
        '"'
    } else {
        '\''
    };
    let mut out = String::new();
    out.push(quote);
    for c in s.chars() {
        match c {
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if c == quote => {
                out.push('\\');
                out.push(c);
            }
            c if (c as u32) < 0x20 || (c as u32) == 0x7f => {
                out.push_str(&format!("\\x{:02x}", c as u32))
            }
            c if c.is_control() => {
                let n = c as u32;
                if n <= 0xff {
                    out.push_str(&format!("\\x{:02x}", n));
                } else if n <= 0xffff {
                    out.push_str(&format!("\\u{:04x}", n));
                } else {
                    out.push_str(&format!("\\U{:08x}", n));
                }
            }
            c => out.push(c),
        }
    }
    out.push(quote);
    out
}

/// `repr(v)`.
pub fn py_repr(v: &J) -> String {
    match v {
        J::Null => "None".to_string(),
        J::Bool(b) => if *b { "True" } else { "False" }.to_string(),
        J::Int(i) => i.to_string(),
        J::Float(f) => float_repr(*f),
        J::Str(s) => repr_str(s),
        J::Arr(items) => {
            let inner: Vec<String> = items.iter().map(py_repr).collect();
            format!("[{}]", inner.join(", "))
        }
        J::Obj(pairs) => {
            let inner: Vec<String> = pairs
                .iter()
                .map(|(k, v)| format!("{}: {}", repr_str(k), py_repr(v)))
                .collect();
            format!("{{{}}}", inner.join(", "))
        }
    }
}

/// `str(v)`.
pub fn py_str(v: &J) -> String {
    match v {
        J::Str(s) => s.clone(),
        other => py_repr(other),
    }
}

fn strip_digit_underscores(s: &str) -> Option<String> {
    // Python allows single underscores between digits only.
    let chars: Vec<char> = s.chars().collect();
    for (i, c) in chars.iter().enumerate() {
        if *c == '_' {
            let before = i > 0 && chars[i - 1].is_ascii_digit();
            let after = i + 1 < chars.len() && chars[i + 1].is_ascii_digit();
            if !before || !after {
                return None;
            }
        }
    }
    Some(chars.into_iter().filter(|c| *c != '_').collect())
}

/// `int(v)`.
pub fn py_int(v: &J) -> PyResult<i128> {
    match v {
        J::Bool(b) => Ok(*b as i128),
        J::Int(i) => Ok(*i),
        J::Float(f) => {
            if f.is_nan() {
                Err("cannot convert float NaN to integer".to_string())
            } else if f.is_infinite() {
                Err("cannot convert float infinity to integer".to_string())
            } else {
                Ok(f.trunc() as i128)
            }
        }
        J::Str(s) => {
            let invalid = || format!("invalid literal for int() with base 10: {}", repr_str(s));
            let t = strip(s);
            let (neg, digits) = match t.strip_prefix('-') {
                Some(rest) => (true, rest),
                None => (false, t.strip_prefix('+').unwrap_or(t)),
            };
            let digits = strip_digit_underscores(digits).ok_or_else(invalid)?;
            if digits.is_empty() || !digits.chars().all(|c| c.is_ascii_digit()) {
                return Err(invalid());
            }
            let n: i128 = digits.parse().map_err(|_| invalid())?;
            Ok(if neg { -n } else { n })
        }
        other => Err(format!(
            "int() argument must be a string, a bytes-like object or a real number, not '{}'",
            type_name(other)
        )),
    }
}

/// `float(v)`.
pub fn py_float(v: &J) -> PyResult<f64> {
    match v {
        J::Bool(b) => Ok(if *b { 1.0 } else { 0.0 }),
        J::Int(i) => Ok(*i as f64),
        J::Float(f) => Ok(*f),
        J::Str(s) => parse_py_float(s)
            .ok_or_else(|| format!("could not convert string to float: {}", repr_str(s))),
        other => Err(format!(
            "float() argument must be a string or a real number, not '{}'",
            type_name(other)
        )),
    }
}

/// Python's `float(str)` grammar: optional sign, decimal or exponent form,
/// `inf`/`infinity`/`nan` in any case, underscores between digits.
pub fn parse_py_float(s: &str) -> Option<f64> {
    let t = strip(s);
    let lower = t.to_ascii_lowercase();
    let body = lower.trim_start_matches(['+', '-']);
    if matches!(body, "inf" | "infinity" | "nan") {
        return lower.parse::<f64>().ok();
    }
    let cleaned = strip_digit_underscores(t)?;
    let ok_chars = cleaned
        .chars()
        .all(|c| c.is_ascii_digit() || matches!(c, '.' | 'e' | 'E' | '+' | '-'));
    if !ok_chars || cleaned.is_empty() {
        return None;
    }
    cleaned.parse::<f64>().ok()
}

/// `a + b` for the numeric types JSON can hold (bool counts as int).
pub fn num_add(a: &J, b: &J) -> PyResult<J> {
    let as_int = |v: &J| match v {
        J::Bool(b) => Some(*b as i128),
        J::Int(i) => Some(*i),
        _ => None,
    };
    let as_float = |v: &J| match v {
        J::Float(f) => Some(*f),
        other => as_int(other).map(|i| i as f64),
    };
    if let (Some(x), Some(y)) = (as_int(a), as_int(b)) {
        return Ok(J::Int(x + y));
    }
    if let (Some(x), Some(y)) = (as_float(a), as_float(b)) {
        return Ok(J::Float(x + y));
    }
    if let (J::Str(x), J::Str(y)) = (a, b) {
        return Ok(J::Str(format!("{}{}", x, y)));
    }
    Err(format!(
        "unsupported operand type(s) for +: '{}' and '{}'",
        type_name(a),
        type_name(b)
    ))
}

/// `target += inc`.
pub fn add_assign(target: &mut J, inc: &J) -> PyResult<()> {
    *target = num_add(target, inc)?;
    Ok(())
}

/// A numeric value as f64, for comparisons (`count > 0`, `mtime > now - 900`).
/// Non-numbers compare as absent: Python would raise TypeError there, which
/// only a hand-corrupted state file can trigger.
pub fn as_number(v: &J) -> Option<f64> {
    match v {
        J::Bool(b) => Some(if *b { 1.0 } else { 0.0 }),
        J::Int(i) => Some(*i as f64),
        J::Float(f) => Some(*f),
        _ => None,
    }
}

pub fn gt_zero(v: &J) -> bool {
    as_number(v).map(|n| n > 0.0).unwrap_or(false)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn int_and_float_conversions() {
        assert_eq!(py_int(&J::str(" 1_000 ")).unwrap(), 1000);
        assert_eq!(py_int(&J::Float(12.9)).unwrap(), 12);
        assert_eq!(py_int(&J::Bool(true)).unwrap(), 1);
        assert!(py_int(&J::str("12.5")).is_err());
        assert!(py_int(&J::Null).is_err());
        assert_eq!(py_float(&J::str("1e3")).unwrap(), 1000.0);
        assert!(py_float(&J::str("inf")).unwrap().is_infinite());
        assert!(py_float(&J::str("abc")).is_err());
    }

    #[test]
    fn repr_and_str() {
        assert_eq!(py_str(&J::Null), "None");
        assert_eq!(py_str(&J::Bool(false)), "False");
        let v = J::parse(r#"{"a": [1, "it's", null]}"#).unwrap();
        assert_eq!(py_str(&v), r#"{'a': [1, "it's", None]}"#);
    }

    #[test]
    fn get_on_non_dict_errors_like_python() {
        assert_eq!(
            get(&J::Arr(vec![]), "x").unwrap_err(),
            "'list' object has no attribute 'get'"
        );
    }

    #[test]
    fn numeric_add() {
        assert_eq!(num_add(&J::Int(1), &J::Bool(true)).unwrap(), J::Int(2));
        assert_eq!(num_add(&J::Int(1), &J::Float(0.5)).unwrap(), J::Float(1.5));
        assert!(num_add(&J::Int(1), &J::Null).is_err());
    }

    #[test]
    fn whitespace_split_count() {
        assert_eq!(split_ws_count("  a b\tc\n"), 3);
        assert_eq!(split_ws_count(""), 0);
    }
}
