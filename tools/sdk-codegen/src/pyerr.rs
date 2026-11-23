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

//! The ways sdk_codegen.py stops: an exception nothing catches, which Python
//! prints as a traceback ending in `Class: message`, and `SystemExit` with a
//! message, which it prints alone. Each is built here with the words Python
//! would use, from the operation on a JSON value that raised it.

use crate::json::Value;
use crate::pystr;

/// An exception: its class as the traceback names it, and `str()` of it.
#[derive(Clone, Debug, PartialEq)]
pub struct PyErr {
    pub class: String,
    pub message: String,
    /// `SystemExit(message)`: printed alone, exit status 1.
    pub exit: bool,
    /// The exception this one was raised from (`raise ... from cause`).
    pub cause: Option<Box<PyErr>>,
}

pub type PyResult<T> = Result<T, PyErr>;

impl PyErr {
    pub fn new(class: &str, message: impl Into<String>) -> PyErr {
        PyErr {
            class: class.to_string(),
            message: message.into(),
            exit: false,
            cause: None,
        }
    }

    /// `raise SystemExit(message)`.
    pub fn exit(message: impl Into<String>) -> PyErr {
        PyErr {
            class: "SystemExit".into(),
            message: message.into(),
            exit: true,
            cause: None,
        }
    }

    /// The last line(s) of the traceback: `Class: message`, or `Class`
    /// alone when the message is empty.
    pub fn render(&self) -> String {
        if self.message.is_empty() {
            self.class.clone()
        } else {
            format!("{}: {}", self.class, self.message)
        }
    }
}

/// `model.SchemaProblem(message)`.
pub fn schema_problem(message: impl Into<String>) -> PyErr {
    PyErr::new("model.SchemaProblem", message)
}

/// `KeyError(key)` for a str key.
pub fn key_error(key: &str) -> PyErr {
    PyErr::new("KeyError", pystr::repr_str(key))
}

/// `TypeError(...)`.
pub fn type_error(message: impl Into<String>) -> PyErr {
    PyErr::new("TypeError", message)
}

/// `AttributeError: 'T' object has no attribute 'name'`.
pub fn no_attribute(value: &Value, name: &str) -> PyErr {
    PyErr::new(
        "AttributeError",
        format!("'{}' object has no attribute '{}'", value.type_name(), name),
    )
}

/// `value[key]` with a str key.
pub fn getitem<'a>(value: &'a Value, key: &str) -> PyResult<&'a Value> {
    match value {
        Value::Obj(_) => value.get(key).ok_or_else(|| key_error(key)),
        Value::Str(_) => Err(type_error("string indices must be integers, not 'str'")),
        Value::Arr(_) => Err(type_error(
            "list indices must be integers or slices, not str",
        )),
        other => Err(type_error(format!(
            "'{}' object is not subscriptable",
            other.type_name()
        ))),
    }
}

/// `key in value` with a str key.
pub fn contains(value: &Value, key: &str) -> PyResult<bool> {
    match value {
        Value::Obj(_) => Ok(value.has(key)),
        Value::Str(s) => Ok(s.contains(key)),
        Value::Arr(items) => Ok(items.iter().any(|v| matches!(v, Value::Str(s) if s == key))),
        other => Err(type_error(format!(
            "argument of type '{}' is not iterable",
            other.type_name()
        ))),
    }
}

/// `value.get(key, default)`: only a dict has `get`.
pub fn get<'a>(value: &'a Value, key: &str) -> PyResult<Option<&'a Value>> {
    match value {
        Value::Obj(_) => Ok(value.get(key)),
        other => Err(no_attribute(other, "get")),
    }
}

/// `for item in value`: a dict gives its keys, a str its characters.
pub fn iterate(value: &Value) -> PyResult<Vec<Value>> {
    match value {
        Value::Arr(items) => Ok(items.clone()),
        Value::Obj(items) => Ok(items.iter().map(|(k, _)| Value::Str(k.clone())).collect()),
        Value::Str(s) => Ok(s.chars().map(|c| Value::Str(c.to_string())).collect()),
        other => Err(type_error(format!(
            "'{}' object is not iterable",
            other.type_name()
        ))),
    }
}

/// `value.items()`: only a dict has it.
pub fn items(value: &Value) -> PyResult<&Vec<(String, Value)>> {
    match value {
        Value::Obj(items) => Ok(items),
        other => Err(no_attribute(other, "items")),
    }
}

/// `hash(value)` for a set or dict lookup: only lists and dicts refuse.
pub fn hashable(value: &Value) -> PyResult<()> {
    match value {
        Value::Arr(_) | Value::Obj(_) => Err(type_error(format!(
            "unhashable type: '{}'",
            value.type_name()
        ))),
        _ => Ok(()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::json::loads;

    #[test]
    fn messages_are_pythons() {
        let list = loads("[1]").unwrap();
        let flag = loads("true").unwrap();
        let text = loads("\"x\"").unwrap();
        let obj = loads("{\"a\": 1}").unwrap();
        assert_eq!(
            getitem(&list, "a").unwrap_err().render(),
            "TypeError: list indices must be integers or slices, not str"
        );
        assert_eq!(
            getitem(&flag, "a").unwrap_err().render(),
            "TypeError: 'bool' object is not subscriptable"
        );
        assert_eq!(getitem(&obj, "b").unwrap_err().render(), "KeyError: 'b'");
        assert_eq!(
            contains(&flag, "a").unwrap_err().render(),
            "TypeError: argument of type 'bool' is not iterable"
        );
        assert!(contains(&text, "x").unwrap());
        assert_eq!(
            get(&flag, "a").unwrap_err().render(),
            "AttributeError: 'bool' object has no attribute 'get'"
        );
        assert_eq!(
            iterate(&loads("3").unwrap()).unwrap_err().render(),
            "TypeError: 'int' object is not iterable"
        );
        assert_eq!(iterate(&obj).unwrap().len(), 1);
        assert_eq!(PyErr::new("StopIteration", "").render(), "StopIteration");
        assert!(hashable(&list).is_err());
    }
}
