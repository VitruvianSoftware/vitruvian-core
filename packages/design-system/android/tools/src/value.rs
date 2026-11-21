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

//! What `json.loads` hands gen_tokens.py, and the Python operations the
//! script applies to it: `x[key]`, `key in x`, iterating, `int(x)`,
//! `str(x)`, `a, b, c, d = x`, an attribute lookup. Each fails with the
//! exception and message Python's own would.

use std::collections::HashMap;

use crate::pyerr::Exc;
use crate::pystr::{self, BigInt, IntError, PyStr};

#[derive(Clone, Debug, PartialEq)]
pub enum Value {
    Null,
    Bool(bool),
    Int(BigInt),
    Float(f64),
    Str(PyStr),
    List(Vec<Value>),
    Dict(Dict),
}

/// A JSON object as `json.loads` builds it: keys in first-seen order, a
/// repeated key keeping its first place and its last value.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Dict {
    items: Vec<(PyStr, Value)>,
    index: HashMap<PyStr, usize>,
}

impl Dict {
    pub fn new() -> Dict {
        Dict::default()
    }

    pub fn insert(&mut self, key: PyStr, value: Value) {
        match self.index.get(&key) {
            Some(&i) => self.items[i].1 = value,
            None => {
                self.index.insert(key.clone(), self.items.len());
                self.items.push((key, value));
            }
        }
    }

    pub fn get(&self, key: &[u32]) -> Option<&Value> {
        self.index.get(key).map(|&i| &self.items[i].1)
    }

    pub fn items(&self) -> &[(PyStr, Value)] {
        &self.items
    }
}

/// Python's `__repr__` dispatch, one level of nesting at a time.
///
/// repr has a recursion guard in Python too, but no token tree reaches it:
/// json.loads's guard, lower in the same budget, refuses anything nested
/// deep enough first. So there is none here.
fn repr_into(v: &Value, out: &mut String) {
    match v {
        Value::Null => out.push_str("None"),
        Value::Bool(true) => out.push_str("True"),
        Value::Bool(false) => out.push_str("False"),
        Value::Int(i) => out.push_str(&i.to_string_py()),
        Value::Float(f) => out.push_str(&pystr::repr_float(*f)),
        Value::Str(s) => out.push_str(&pystr::repr(s)),
        Value::List(items) => {
            out.push('[');
            for (i, item) in items.iter().enumerate() {
                if i > 0 {
                    out.push_str(", ");
                }
                repr_into(item, out);
            }
            out.push(']');
        }
        Value::Dict(d) => {
            out.push('{');
            for (i, (k, item)) in d.items().iter().enumerate() {
                if i > 0 {
                    out.push_str(", ");
                }
                out.push_str(&pystr::repr(k));
                out.push_str(": ");
                repr_into(item, out);
            }
            out.push('}');
        }
    }
}

impl Value {
    /// `type(x).__name__`.
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

    /// `repr(x)`. Lists and dicts hold no unescaped surrogate, so this is a
    /// Rust string.
    pub fn repr(&self) -> String {
        let mut out = String::new();
        repr_into(self, &mut out);
        out
    }

    /// `str(x)`, which is `repr(x)` for everything but a str.
    pub fn py_str(&self) -> PyStr {
        match self {
            Value::Str(s) => s.clone(),
            other => pystr::ps(&other.repr()),
        }
    }

    /// The str an attribute is looked up on (`x.lstrip`, `x.removesuffix`),
    /// or the AttributeError a non-str raises.
    pub fn str_attr(&self, attr: &str) -> Result<&PyStr, Exc> {
        match self {
            Value::Str(s) => Ok(s),
            other => Err(other.no_attribute(attr)),
        }
    }

    pub fn no_attribute(&self, attr: &str) -> Exc {
        Exc::new(
            "AttributeError",
            format!("'{}' object has no attribute '{}'", self.type_name(), attr),
        )
    }

    /// `x.items()`.
    pub fn dict_items(&self) -> Result<&[(PyStr, Value)], Exc> {
        match self {
            Value::Dict(d) => Ok(d.items()),
            other => Err(other.no_attribute("items")),
        }
    }

    /// `x[key]` for a str key.
    pub fn index_str(&self, key: &[u32]) -> Result<&Value, Exc> {
        match self {
            Value::Dict(d) => d.get(key).ok_or_else(|| Exc::key_error(pystr::repr(key))),
            _ => self.index(&Value::Str(key.to_vec())).map(|v| match v {
                std::borrow::Cow::Borrowed(v) => v,
                // Only a str container hands back a new value, and it
                // refuses a str key before getting there.
                std::borrow::Cow::Owned(_) => unreachable!(),
            }),
        }
    }

    /// `x[key]` for any key. A str yields a new one-character str, so the
    /// result may be owned.
    pub fn index(&self, key: &Value) -> Result<std::borrow::Cow<'_, Value>, Exc> {
        use std::borrow::Cow;
        let position = |len: usize| -> Result<Option<usize>, Exc> {
            let i = match key {
                Value::Bool(b) => *b as isize,
                Value::Int(n) => n.to_isize().ok_or_else(|| {
                    Exc::new("IndexError", "cannot fit 'int' into an index-sized integer")
                })?,
                _ => return Ok(None),
            };
            let i = if i < 0 { i + len as isize } else { i };
            if i < 0 || i >= len as isize {
                return Ok(Some(usize::MAX));
            }
            Ok(Some(i as usize))
        };
        match self {
            Value::Dict(d) => match key {
                Value::Str(k) => d
                    .get(k)
                    .map(Cow::Borrowed)
                    .ok_or_else(|| Exc::key_error(pystr::repr(k))),
                Value::List(_) | Value::Dict(_) => Err(Exc::type_error(format!(
                    "unhashable type: '{}'",
                    key.type_name()
                ))),
                // A JSON object's keys are all strs; nothing else is in it.
                other => Err(Exc::key_error(other.repr())),
            },
            Value::List(items) => match position(items.len())? {
                Some(usize::MAX) => Err(Exc::new("IndexError", "list index out of range")),
                Some(i) => Ok(Cow::Borrowed(&items[i])),
                None => Err(Exc::type_error(format!(
                    "list indices must be integers or slices, not {}",
                    key.type_name()
                ))),
            },
            Value::Str(s) => match position(s.len())? {
                Some(usize::MAX) => Err(Exc::new("IndexError", "string index out of range")),
                Some(i) => Ok(Cow::Owned(Value::Str(vec![s[i]]))),
                None => Err(Exc::type_error(format!(
                    "string indices must be integers, not '{}'",
                    key.type_name()
                ))),
            },
            other => Err(Exc::type_error(format!(
                "'{}' object is not subscriptable",
                other.type_name()
            ))),
        }
    }

    /// `needle in x` for a str needle.
    pub fn contains_str(&self, needle: &[u32]) -> Result<bool, Exc> {
        match self {
            Value::Dict(d) => Ok(d.get(needle).is_some()),
            Value::List(items) => Ok(items
                .iter()
                .any(|v| matches!(v, Value::Str(s) if s[..] == needle[..]))),
            Value::Str(s) => Ok(pystr::contains(s, needle)),
            other => Err(Exc::type_error(format!(
                "argument of type '{}' is not iterable",
                other.type_name()
            ))),
        }
    }

    /// `list(x)`: a dict's keys, a list's items, a str's characters.
    pub fn iterate(&self) -> Result<Vec<Value>, Exc> {
        match self {
            Value::Dict(d) => Ok(d
                .items()
                .iter()
                .map(|(k, _)| Value::Str(k.clone()))
                .collect()),
            Value::List(items) => Ok(items.clone()),
            Value::Str(s) => Ok(s.iter().map(|&c| Value::Str(vec![c])).collect()),
            other => Err(Exc::type_error(format!(
                "'{}' object is not iterable",
                other.type_name()
            ))),
        }
    }

    /// `int(x)`.
    pub fn to_int(&self) -> Result<BigInt, Exc> {
        match self {
            Value::Bool(b) => Ok(BigInt::small(*b as i64)),
            Value::Int(n) => Ok(n.clone()),
            Value::Float(f) if f.is_nan() => {
                Err(Exc::value_error("cannot convert float NaN to integer"))
            }
            Value::Float(f) if f.is_infinite() => Err(Exc::new(
                "OverflowError",
                "cannot convert float infinity to integer",
            )),
            Value::Float(f) => Ok(BigInt::from_f64(*f)),
            Value::Str(s) => pystr::parse_int(s).map_err(|e| match e {
                IntError::Invalid => {
                    let r: String = pystr::repr(s).chars().take(200).collect();
                    Exc::value_error(format!("invalid literal for int() with base 10: {}", r))
                }
                IntError::TooLong(n) => Exc::value_error(format!(
                    "Exceeds the limit ({} digits) for integer string conversion: value has {} digits; use sys.set_int_max_str_digits() to increase the limit",
                    pystr::MAX_STR_DIGITS, n
                )),
            }),
            other => Err(Exc::type_error(format!(
                "int() argument must be a string, a bytes-like object or a real number, not '{}'",
                other.type_name()
            ))),
        }
    }

    /// `a, b, c, d = x`.
    pub fn unpack4(&self) -> Result<[Value; 4], Exc> {
        let items = match self {
            Value::List(_) | Value::Dict(_) | Value::Str(_) => self.iterate()?,
            other => {
                return Err(Exc::type_error(format!(
                    "cannot unpack non-iterable {} object",
                    other.type_name()
                )))
            }
        };
        match items.len() {
            4 => {
                let mut it = items.into_iter();
                Ok([
                    it.next().unwrap(),
                    it.next().unwrap(),
                    it.next().unwrap(),
                    it.next().unwrap(),
                ])
            }
            n if n < 4 => Err(Exc::value_error(format!(
                "not enough values to unpack (expected 4, got {})",
                n
            ))),
            _ => Err(Exc::value_error("too many values to unpack (expected 4)")),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::pystr::ps;

    fn msg(e: Exc) -> String {
        format!("{}: {}", e.class, pystr::backslashreplace(&e.msg))
    }

    #[test]
    fn subscripts_fail_as_python() {
        let list = Value::List(vec![Value::Null]);
        assert_eq!(
            msg(list.index_str(&ps("a")).unwrap_err()),
            "TypeError: list indices must be integers or slices, not str"
        );
        assert_eq!(
            msg(Value::Str(ps("ab")).index_str(&ps("a")).unwrap_err()),
            "TypeError: string indices must be integers, not 'str'"
        );
        assert_eq!(
            msg(Value::Null.index_str(&ps("a")).unwrap_err()),
            "TypeError: 'NoneType' object is not subscriptable"
        );
        assert_eq!(
            msg(Value::Dict(Dict::new()).index_str(&ps("it's")).unwrap_err()),
            "KeyError: \"it's\""
        );
        let big = Value::Int(pystr::parse_int(&ps(&"9".repeat(30))).unwrap());
        assert_eq!(
            msg(list.index(&big).unwrap_err()),
            "IndexError: cannot fit 'int' into an index-sized integer"
        );
        assert_eq!(
            msg(list.index(&Value::Bool(true)).unwrap_err()),
            "IndexError: list index out of range"
        );
        assert!(list.index(&Value::Int(BigInt::small(-1))).is_ok());
    }

    #[test]
    fn repeated_keys_keep_first_place_last_value() {
        let mut d = Dict::new();
        d.insert(ps("a"), Value::Null);
        d.insert(ps("b"), Value::Null);
        d.insert(ps("a"), Value::Bool(true));
        assert_eq!(Value::Dict(d).repr(), "{'a': True, 'b': None}");
    }

    #[test]
    fn unpacking_counts_as_python() {
        let l = |n: usize| Value::List(vec![Value::Null; n]);
        assert!(l(4).unpack4().is_ok());
        assert_eq!(
            msg(l(2).unpack4().unwrap_err()),
            "ValueError: not enough values to unpack (expected 4, got 2)"
        );
        assert_eq!(
            msg(l(5).unpack4().unwrap_err()),
            "ValueError: too many values to unpack (expected 4)"
        );
        assert_eq!(
            msg(Value::Float(1.0).unpack4().unwrap_err()),
            "TypeError: cannot unpack non-iterable float object"
        );
        let [a, ..] = Value::Str(ps("abcd")).unpack4().unwrap();
        assert_eq!(a, Value::Str(ps("a")));
    }

    #[test]
    fn int_of_values() {
        assert_eq!(Value::Bool(true).to_int().unwrap(), BigInt::small(1));
        assert_eq!(
            msg(Value::Float(f64::INFINITY).to_int().unwrap_err()),
            "OverflowError: cannot convert float infinity to integer"
        );
        assert_eq!(
            msg(Value::Null.to_int().unwrap_err()),
            "TypeError: int() argument must be a string, a bytes-like object or a real number, not 'NoneType'"
        );
        let long = msg(Value::Str(ps(&"1x".repeat(300))).to_int().unwrap_err());
        assert_eq!(
            long.len(),
            "ValueError: invalid literal for int() with base 10: ".len() + 200
        );
    }

    #[test]
    fn membership() {
        assert!(Value::Str(ps("xcolorx"))
            .contains_str(&ps("color"))
            .unwrap());
        assert!(!Value::List(vec![Value::Int(BigInt::small(1))])
            .contains_str(&ps("1"))
            .unwrap());
        assert_eq!(
            msg(Value::Null.contains_str(&ps("color")).unwrap_err()),
            "TypeError: argument of type 'NoneType' is not iterable"
        );
    }
}
