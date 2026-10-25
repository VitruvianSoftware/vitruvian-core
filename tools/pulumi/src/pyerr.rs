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

/// `d.get(key, default)`, which needs `d` to be a dict.
pub fn get_or(v: &Value, key: &str, default: Value) -> Result<Value, Crash> {
    if !v.is_obj() {
        return Err(Crash::attribute(v, "get"));
    }
    Ok(v.get(key).cloned().unwrap_or(default))
}

/// A str for a str method call, or the AttributeError a non-str raises.
pub fn as_str<'a>(v: &'a Value, method: &str) -> Result<&'a str, Crash> {
    match v {
        Value::Str(s) => Ok(s),
        other => Err(Crash::attribute(other, method)),
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

/// `v[key]` with a str key. A missing key is the KeyError the script
/// catches (or not); anything but a dict is a TypeError.
pub fn index(v: &Value, key: &str) -> Result<Value, Crash> {
    match v {
        Value::Obj(_) => v
            .get(key)
            .cloned()
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
